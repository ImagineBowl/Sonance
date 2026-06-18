//
//  MetronomeEngine.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

@preconcurrency import AVFoundation
import os
#if canImport(UIKit)
import UIKit
#endif

private final class MetronomeRenderState: @unchecked Sendable {
    let lock = NSLock()

    var isActive = false
    var bpm: Double = MetronomeConfig.defaultBPM
    var beatsPerBar = MetronomeConfig.defaultTimeSignature.beatsPerBar
    var noteValue = MetronomeConfig.defaultTimeSignature.noteValue
    var sampleRate: Double = 44_100

    var accentSamples: [Float] = []
    var tickSamples: [Float] = []

    var timelineSample: Int64 = 0
    var nextClickSample: Int64 = 0
    var clickSampleIndex = 0
    var currentClickSamples: [Float] = []
    var beatInBar = 0

    func resetTimeline(leadTime: TimeInterval) {
        timelineSample = 0
        nextClickSample = Int64(leadTime * sampleRate)
        clickSampleIndex = 0
        currentClickSamples = []
        beatInBar = 0
    }

    func framesPerBeat() -> Int64 {
        let beatUnitScale = Double(MetronomeConfig.referenceBeatNoteValue) / Double(noteValue)
        let interval = (60.0 / bpm) * beatUnitScale
        return max(1, Int64(interval * sampleRate))
    }

    func beginClick(isAccent: Bool) {
        currentClickSamples = isAccent ? accentSamples : tickSamples
        clickSampleIndex = 0
    }

    func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard isActive else {
            buffer.initialize(repeating: 0, count: frameCount)
            return
        }

        for frame in 0..<frameCount {
            if clickSampleIndex == 0,
               currentClickSamples.isEmpty,
               timelineSample >= nextClickSample {
                let isAccent = beatInBar == 0
                beginClick(isAccent: isAccent)
                nextClickSample = timelineSample + framesPerBeat()
                let finishedBeat = beatInBar
                beatInBar = (beatInBar + 1) % max(beatsPerBar, 1)
                notifyBeat(beatInBar: finishedBeat, isAccent: isAccent)
            }

            if clickSampleIndex < currentClickSamples.count {
                buffer[frame] = currentClickSamples[clickSampleIndex]
                clickSampleIndex += 1
            } else {
                buffer[frame] = 0
                currentClickSamples = []
                clickSampleIndex = 0
            }

            timelineSample += 1
        }
    }

    private func notifyBeat(beatInBar: Int, isAccent: Bool) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .metronomeBeatDidFire,
                object: nil,
                userInfo: [
                    MetronomeBeatNotificationKey.beatInBar: beatInBar,
                    MetronomeBeatNotificationKey.isAccent: isAccent
                ]
            )
        }
    }
}

private enum MetronomeBeatNotificationKey {
    static let beatInBar = "beatInBar"
    static let isAccent = "isAccent"
}

extension Notification.Name {
    fileprivate static let metronomeBeatDidFire = Notification.Name("metronomeBeatDidFire")
}

@MainActor
final class MetronomeEngine: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Sonance",
        category: "MetronomeEngine"
    )

    @Published var bpm: Double = MetronomeConfig.defaultBPM {
        didSet {
            let clamped = min(max(bpm, MetronomeConfig.minBPM), MetronomeConfig.maxBPM)
            if clamped != bpm {
                bpm = clamped
                return
            }
            MetronomeConfig.saveBPM(clamped)
            syncRenderState()
            syncNowPlayingIfNeeded()
        }
    }

    @Published var timeSignature: TimeSignature = MetronomeConfig.defaultTimeSignature {
        didSet {
            guard timeSignature != oldValue else { return }
            MetronomeConfig.saveTimeSignature(timeSignature)
            beatIndex = 0
            syncRenderState()
            if wantsToPlay {
                renderState.resetTimeline(leadTime: MetronomeConfig.startLeadTime)
            }
            syncNowPlayingIfNeeded()
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var beatIndex = 0
    @Published private(set) var isAccentBeat = false
    @Published private(set) var pulseGeneration: UInt = 0

    private nonisolated(unsafe) var audioEngine: AVAudioEngine?
    private nonisolated(unsafe) var sourceNode: AVAudioSourceNode?
    private nonisolated(unsafe) var dialPlayerNode: AVAudioPlayerNode?
    private nonisolated(unsafe) var dialTickBuffer: AVAudioPCMBuffer?
    private nonisolated(unsafe) var sampleRate: Double = 44_100

    private let renderState = MetronomeRenderState()
    private var wantsToPlay = false
    private var beatObserver: NSObjectProtocol?

    private var tapTimestamps: [TimeInterval] = []
    private let nowPlayingController = MetronomeNowPlayingController()
    private var isNowPlayingSessionActive = false

    #if canImport(UIKit)
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private var audioSessionObservers: [NSObjectProtocol] = []
    #endif

    init() {
        bpm = MetronomeConfig.savedBPM()
        timeSignature = MetronomeConfig.savedTimeSignature()
        nowPlayingController.configure(with: self)
        beatObserver = NotificationCenter.default.addObserver(
            forName: .metronomeBeatDidFire,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleBeatNotification(notification)
            }
        }
        #if canImport(UIKit)
        hapticGenerator.prepare()
        registerForAudioSessionNotifications()
        #endif
    }

    deinit {
        if let beatObserver {
            NotificationCenter.default.removeObserver(beatObserver)
        }
        #if canImport(UIKit)
        for observer in audioSessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    func warmUp() {
        do {
            try prepareEngineIfNeeded()
        } catch {
            Self.logger.error("Failed to warm up metronome engine: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Control

    func start() {
        guard !isRunning else { return }

        do {
            try AudioSessionCoordinator.activate(.metronome)
            try prepareEngineIfNeeded()
            guard let audioEngine else { return }

            wantsToPlay = true
            syncRenderState()
            renderState.resetTimeline(leadTime: MetronomeConfig.startLeadTime)

            renderState.lock.lock()
            renderState.isActive = true
            renderState.lock.unlock()

            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }

            isRunning = true
            isNowPlayingSessionActive = true
            syncNowPlayingIfNeeded()
        } catch {
            Self.logger.error("Failed to start metronome: \(error.localizedDescription)")
            wantsToPlay = false
            tearDownEngine()
            isRunning = false
        }
    }

    func stop() {
        wantsToPlay = false
        renderState.lock.lock()
        renderState.isActive = false
        renderState.lock.unlock()

        isRunning = false
        beatIndex = 0
        isAccentBeat = false
        syncNowPlayingIfNeeded()
    }

    func endSession() {
        wantsToPlay = false
        renderState.lock.lock()
        renderState.isActive = false
        renderState.lock.unlock()

        dialPlayerNode?.stop()
        audioEngine?.stop()
        isRunning = false
        beatIndex = 0
        isAccentBeat = false
        isNowPlayingSessionActive = false
        nowPlayingController.clear()
    }

    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func incrementBPM(by amount: Double = MetronomeConfig.bpmStep) {
        setBPM(bpm + amount, playTick: true)
    }

    func decrementBPM(by amount: Double = MetronomeConfig.bpmStep) {
        setBPM(bpm - amount, playTick: true)
    }

    func tapTempo() {
        let now = CACurrentMediaTime()
        tapTimestamps.append(now)
        tapTimestamps = tapTimestamps.filter { now - $0 <= MetronomeConfig.tapTempoWindow }

        guard tapTimestamps.count >= MetronomeConfig.minTapCount else { return }

        let intervals = zip(tapTimestamps.dropFirst(), tapTimestamps).map { $0.0 - $0.1 }
        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard averageInterval > 0 else { return }

        let tappedBPM = MetronomeConfig.bpm(fromBeatInterval: averageInterval, timeSignature: timeSignature)
        setBPM(tappedBPM, playTick: true)
    }

    func setBPM(_ value: Double, playTick: Bool = false) {
        let clamped = min(max(value, MetronomeConfig.minBPM), MetronomeConfig.maxBPM)
        let previous = Int(bpm.rounded())
        bpm = clamped
        if playTick, Int(clamped.rounded()) != previous {
            playDialTick()
        }
    }

    func prepareForBackground() {
        guard wantsToPlay else { return }
        resumePlaybackIfNeeded()
    }

    func recoverPlaybackIfNeeded() {
        guard wantsToPlay else { return }
        resumePlaybackIfNeeded()
    }

    func playDialTick() {
        do {
            try AudioSessionCoordinator.activate(.metronome)
            try prepareEngineIfNeeded()
            guard let audioEngine, let dialPlayerNode, let dialTickBuffer else { return }

            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }

            if !dialPlayerNode.isPlaying {
                dialPlayerNode.play()
            }

            dialPlayerNode.scheduleBuffer(dialTickBuffer, at: nil, options: [])
        } catch {
            Self.logger.error("Failed to play dial tick: \(error.localizedDescription)")
        }
    }

    // MARK: - Engine Setup

    private func prepareEngineIfNeeded() throws {
        if audioEngine != nil, sourceNode != nil, dialTickBuffer != nil {
            return
        }

        tearDownEngine()

        let engine = AVAudioEngine()
        let dialPlayer = AVAudioPlayerNode()
        let state = renderState

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard let format else {
            throw MetronomeEngineError.invalidAudioFormat
        }

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = bufferList.first,
                  let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            state.render(into: pointer, frameCount: Int(frameCount))
            return noErr
        }

        dialTickBuffer = makeClickBuffer(
            format: format,
            frequency: MetronomeConfig.dialTickFrequency,
            amplitude: MetronomeConfig.dialTickAmplitude,
            duration: MetronomeConfig.dialTickDuration
        )

        guard dialTickBuffer != nil else {
            throw MetronomeEngineError.bufferCreationFailed
        }

        engine.attach(node)
        engine.attach(dialPlayer)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.connect(dialPlayer, to: engine.mainMixerNode, format: format)

        syncClickSamples(format: format)

        audioEngine = engine
        sourceNode = node
        dialPlayerNode = dialPlayer
    }

    private func syncClickSamples(format: AVAudioFormat) {
        guard let accentBuffer = makeClickBuffer(
            format: format,
            frequency: MetronomeConfig.accentFrequency,
            amplitude: MetronomeConfig.accentAmplitude,
            duration: MetronomeConfig.clickDuration
        ),
        let tickBuffer = makeClickBuffer(
            format: format,
            frequency: MetronomeConfig.tickFrequency,
            amplitude: MetronomeConfig.tickAmplitude,
            duration: MetronomeConfig.clickDuration
        ),
        let accentData = accentBuffer.floatChannelData?[0],
        let tickData = tickBuffer.floatChannelData?[0] else {
            return
        }

        renderState.lock.lock()
        renderState.sampleRate = sampleRate
        renderState.accentSamples = Array(UnsafeBufferPointer(start: accentData, count: Int(accentBuffer.frameLength)))
        renderState.tickSamples = Array(UnsafeBufferPointer(start: tickData, count: Int(tickBuffer.frameLength)))
        renderState.lock.unlock()
    }

    private func syncRenderState() {
        renderState.lock.lock()
        renderState.bpm = bpm
        renderState.beatsPerBar = timeSignature.beatsPerBar
        renderState.noteValue = timeSignature.noteValue
        renderState.sampleRate = sampleRate
        renderState.lock.unlock()
    }

    private func tearDownEngine() {
        renderState.lock.lock()
        renderState.isActive = false
        renderState.lock.unlock()

        dialPlayerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        sourceNode = nil
        dialPlayerNode = nil
        dialTickBuffer = nil
    }

    private enum MetronomeEngineError: Error {
        case invalidAudioFormat
        case bufferCreationFailed
    }

    private func resumePlaybackIfNeeded() {
        do {
            try AudioSessionCoordinator.activate(.metronome)
            try prepareEngineIfNeeded()
            guard let audioEngine else { return }

            syncRenderState()

            renderState.lock.lock()
            renderState.isActive = true
            renderState.lock.unlock()

            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }

            isRunning = true
            isNowPlayingSessionActive = true
            syncNowPlayingIfNeeded()
        } catch {
            Self.logger.error("Failed to resume metronome playback: \(error.localizedDescription)")
        }
    }

    private func handleBeatNotification(_ notification: Notification) {
        guard isRunning, wantsToPlay else { return }

        guard let userInfo = notification.userInfo,
              let beatInBar = userInfo[MetronomeBeatNotificationKey.beatInBar] as? Int,
              let isAccent = userInfo[MetronomeBeatNotificationKey.isAccent] as? Bool else {
            return
        }

        beatIndex = beatInBar
        isAccentBeat = isAccent
        pulseGeneration &+= 1

        if isAccent {
            #if canImport(UIKit)
            hapticGenerator.impactOccurred(intensity: 0.9)
            #endif
        }
    }

    // MARK: - Audio Session

    #if canImport(UIKit)
    private func registerForAudioSessionNotifications() {
        let center = NotificationCenter.default

        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleAudioInterruption(notification)
                }
            }
        )

        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard self?.wantsToPlay == true else { return }
                    self?.tearDownEngine()
                    self?.resumePlaybackIfNeeded()
                }
            }
        )
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            break
        case .ended:
            guard wantsToPlay else { return }
            resumePlaybackIfNeeded()
        @unknown default:
            break
        }
    }
    #endif

    // MARK: - Click Synthesis

    private func makeClickBuffer(
        format: AVAudioFormat,
        frequency: Double,
        amplitude: Float,
        duration: TimeInterval = MetronomeConfig.clickDuration
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = frameCount

        for index in 0..<Int(frameCount) {
            let time = Double(index) / sampleRate
            let envelope = exp(-time * 45)
            let sample = sin(2 * Double.pi * frequency * time) * envelope
            channelData[index] = Float(sample) * amplitude
        }

        return buffer
    }

    private func syncNowPlayingIfNeeded() {
        guard isNowPlayingSessionActive else { return }
        nowPlayingController.update(
            bpm: bpm,
            timeSignature: timeSignature,
            isRunning: wantsToPlay
        )
    }
}
