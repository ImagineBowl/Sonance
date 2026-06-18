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
    private var accentBuffer: AVAudioPCMBuffer?
    private var tickBuffer: AVAudioPCMBuffer?
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
            audioEngine.prepare()
            try audioEngine.start()
            playerNode.play()

            scheduleBeats(count: MetronomeConfig.beatsToScheduleAhead)
            isRunning = true
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
        bpm = min(bpm + amount, MetronomeConfig.maxBPM)
    }

    func decrementBPM(by amount: Double = MetronomeConfig.bpmStep) {
        bpm = max(bpm - amount, MetronomeConfig.minBPM)
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
        bpm = min(max(tappedBPM, MetronomeConfig.minBPM), MetronomeConfig.maxBPM)
    }

    // MARK: - Engine Setup

    private func prepareEngineIfNeeded() throws {
        if audioEngine != nil, accentBuffer != nil, tickBuffer != nil {
            return
        }

        tearDownEngine()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard let format else {
            throw MetronomeEngineError.invalidAudioFormat
        }

        accentBuffer = makeClickBuffer(
            format: format,
            frequency: MetronomeConfig.accentFrequency,
            amplitude: MetronomeConfig.accentAmplitude
        )
        tickBuffer = makeClickBuffer(
            format: format,
            frequency: MetronomeConfig.tickFrequency,
            amplitude: MetronomeConfig.tickAmplitude
        )

        guard accentBuffer != nil, tickBuffer != nil else {
            throw MetronomeEngineError.bufferCreationFailed
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)

        audioEngine = engine
        playerNode = player
    }

    private func tearDownEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        accentBuffer = nil
        tickBuffer = nil
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
            guard let anchorTime = playerNode.playerTime(forNodeTime: playerNode.lastRenderTime ?? AVAudioTime(sampleTime: 0, atRate: sampleRate)) else {
                return
            }
            let leadFrames = AVAudioFramePosition(MetronomeConfig.startLeadTime * sampleRate)
            nextBeatSampleTime = anchorTime.sampleTime + leadFrames
        }

        for _ in 0..<count {
            scheduleNextBeat()
        }
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
        amplitude: Float
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(MetronomeConfig.clickDuration * sampleRate)
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
