//
//  MetronomeEngine.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import AVFoundation
import os
#if canImport(UIKit)
import UIKit
#endif

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
            if isRunning {
                restartScheduling()
            }
        }
    }

    @Published var timeSignature: TimeSignature = MetronomeConfig.defaultTimeSignature {
        didSet {
            guard timeSignature != oldValue else { return }
            MetronomeConfig.saveTimeSignature(timeSignature)
            beatIndex = 0
            if isRunning {
                restartScheduling()
            }
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var beatIndex = 0
    @Published private(set) var isAccentBeat = false
    @Published private(set) var pulseToken = UUID()

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var dialPlayerNode: AVAudioPlayerNode?
    private var accentBuffer: AVAudioPCMBuffer?
    private var tickBuffer: AVAudioPCMBuffer?
    private var dialTickBuffer: AVAudioPCMBuffer?
    private var sampleRate: Double = 44_100

    private var beatCounter = 0
    private var nextBeatSampleTime: AVAudioFramePosition = 0
    private var scheduledBeatCount = 0
    private var tapTimestamps: [TimeInterval] = []

    #if canImport(UIKit)
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    #endif

    init() {
        bpm = MetronomeConfig.savedBPM()
        timeSignature = MetronomeConfig.savedTimeSignature()
        #if canImport(UIKit)
        hapticGenerator.prepare()
        #endif
    }

    // MARK: - Public Control

    func start() {
        guard !isRunning else { return }

        do {
            try AudioSessionCoordinator.activate(.metronome)
            try prepareEngineIfNeeded()
            guard let audioEngine, let playerNode else { return }

            resetSchedulingState()

            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }

            playerNode.play()
            isRunning = true
            scheduleBeats(count: MetronomeConfig.beatsToScheduleAhead)
        } catch {
            Self.logger.error("Failed to start metronome: \(error.localizedDescription)")
            tearDownEngine()
            isRunning = false
        }
    }

    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        resetSchedulingState()
        isRunning = false
        beatIndex = 0
        isAccentBeat = false
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

        let tappedBPM = 60.0 / averageInterval
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

            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred(intensity: 0.55)
            #endif
        } catch {
            Self.logger.error("Failed to play dial tick: \(error.localizedDescription)")
        }
    }

    // MARK: - Engine Setup

    private func prepareEngineIfNeeded() throws {
        if audioEngine != nil,
           accentBuffer != nil,
           tickBuffer != nil,
           dialTickBuffer != nil {
            return
        }

        tearDownEngine()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let dialPlayer = AVAudioPlayerNode()
        engine.attach(player)
        engine.attach(dialPlayer)

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard let format else {
            throw MetronomeEngineError.invalidAudioFormat
        }

        accentBuffer = makeClickBuffer(
            format: format,
            frequency: MetronomeConfig.accentFrequency,
            amplitude: MetronomeConfig.accentAmplitude,
            duration: MetronomeConfig.clickDuration
        )
        tickBuffer = makeClickBuffer(
            format: format,
            frequency: MetronomeConfig.tickFrequency,
            amplitude: MetronomeConfig.tickAmplitude,
            duration: MetronomeConfig.clickDuration
        )
        dialTickBuffer = makeClickBuffer(
            format: format,
            frequency: MetronomeConfig.dialTickFrequency,
            amplitude: MetronomeConfig.dialTickAmplitude,
            duration: MetronomeConfig.dialTickDuration
        )

        guard accentBuffer != nil, tickBuffer != nil, dialTickBuffer != nil else {
            throw MetronomeEngineError.bufferCreationFailed
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.connect(dialPlayer, to: engine.mainMixerNode, format: format)

        audioEngine = engine
        playerNode = player
        dialPlayerNode = dialPlayer
    }

    private func tearDownEngine() {
        playerNode?.stop()
        dialPlayerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        dialPlayerNode = nil
        accentBuffer = nil
        tickBuffer = nil
        dialTickBuffer = nil
    }

    private enum MetronomeEngineError: Error {
        case invalidAudioFormat
        case bufferCreationFailed
    }

    // MARK: - Scheduling

    private func resetSchedulingState() {
        beatCounter = 0
        nextBeatSampleTime = 0
        scheduledBeatCount = 0
        beatIndex = 0
        isAccentBeat = false
    }

    private func restartScheduling() {
        playerNode?.stop()
        resetSchedulingState()
        playerNode?.play()
        scheduleBeats(count: MetronomeConfig.beatsToScheduleAhead)
    }

    private func scheduleBeats(count: Int) {
        guard let playerNode else { return }

        if nextBeatSampleTime == 0 {
            nextBeatSampleTime = resolveAnchorSampleTime(for: playerNode)
        }

        for _ in 0..<count {
            scheduleNextBeat()
        }
    }

    private func resolveAnchorSampleTime(for playerNode: AVAudioPlayerNode) -> AVAudioFramePosition {
        let leadFrames = AVAudioFramePosition(MetronomeConfig.startLeadTime * sampleRate)

        if let lastRenderTime = playerNode.lastRenderTime,
           let anchorTime = playerNode.playerTime(forNodeTime: lastRenderTime) {
            return anchorTime.sampleTime + leadFrames
        }

        return leadFrames
    }

    private func scheduleNextBeat() {
        guard isRunning,
              let playerNode,
              let accentBuffer,
              let tickBuffer else { return }

        let beatInBar = beatCounter % timeSignature.beatsPerBar
        let isAccent = beatInBar == 0
        let buffer = isAccent ? accentBuffer : tickBuffer
        let scheduledBeat = beatCounter
        let scheduledAccent = isAccent
        let scheduledBeatInBar = beatInBar

        let beatTime = AVAudioTime(sampleTime: nextBeatSampleTime, atRate: sampleRate)
        let framesPerBeat = AVAudioFramePosition(MetronomeConfig.beatInterval(for: bpm) * sampleRate)
        nextBeatSampleTime += framesPerBeat
        beatCounter += 1
        scheduledBeatCount += 1

        playerNode.scheduleBuffer(buffer, at: beatTime, options: []) { [weak self] in
            Task { @MainActor in
                self?.handleBeatPlayed(
                    beatInBar: scheduledBeatInBar,
                    isAccent: scheduledAccent,
                    scheduledBeat: scheduledBeat
                )
            }
        }
    }

    private func handleBeatPlayed(beatInBar: Int, isAccent: Bool, scheduledBeat: Int) {
        guard isRunning else { return }

        beatIndex = beatInBar
        isAccentBeat = isAccent
        pulseToken = UUID()

        if isAccent {
            #if canImport(UIKit)
            hapticGenerator.impactOccurred(intensity: 0.9)
            #endif
        }

        scheduledBeatCount -= 1
        if scheduledBeatCount < MetronomeConfig.beatsToScheduleAhead {
            scheduleNextBeat()
        }
    }

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
}
