//
//  MetronomeConfig.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import Foundation

struct TimeSignature: Equatable, Codable, Identifiable {
    var beats: Int
    var noteValue: Int

    var id: String { rawValue }
    var rawValue: String { "\(beats)/\(noteValue)" }
    var displayName: String { rawValue }
    var beatsPerBar: Int { beats }

    static let `default` = TimeSignature(beats: 4, noteValue: 4)
    static let minBeats = 1
    static let maxBeats = 12
    static let allowedNoteValues = [2, 4, 8, 16]

    static let presets: [TimeSignature] = [
        TimeSignature(beats: 2, noteValue: 4),
        TimeSignature(beats: 3, noteValue: 4),
        TimeSignature(beats: 4, noteValue: 4),
        TimeSignature(beats: 5, noteValue: 4),
        TimeSignature(beats: 6, noteValue: 8),
        TimeSignature(beats: 7, noteValue: 8),
        TimeSignature(beats: 9, noteValue: 8),
        TimeSignature(beats: 12, noteValue: 8)
    ]

    init(beats: Int, noteValue: Int) {
        self.beats = min(max(beats, Self.minBeats), Self.maxBeats)
        self.noteValue = Self.normalizedNoteValue(noteValue)
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "/")
        guard parts.count == 2,
              let beats = Int(parts[0]),
              let noteValue = Int(parts[1]) else {
            return nil
        }
        self.init(beats: beats, noteValue: noteValue)
    }

    mutating func incrementBeats() {
        beats = min(beats + 1, Self.maxBeats)
    }

    mutating func decrementBeats() {
        beats = max(beats - 1, Self.minBeats)
    }

    mutating func incrementNoteValue() {
        noteValue = Self.nextNoteValue(after: noteValue)
    }

    mutating func decrementNoteValue() {
        noteValue = Self.previousNoteValue(before: noteValue)
    }

    private static func normalizedNoteValue(_ value: Int) -> Int {
        allowedNoteValues.min(by: { abs($0 - value) < abs($1 - value) }) ?? 4
    }

    private static func nextNoteValue(after value: Int) -> Int {
        guard let index = allowedNoteValues.firstIndex(of: normalizedNoteValue(value)) else { return 4 }
        return allowedNoteValues[(index + 1) % allowedNoteValues.count]
    }

    private static func previousNoteValue(before value: Int) -> Int {
        guard let index = allowedNoteValues.firstIndex(of: normalizedNoteValue(value)) else { return 4 }
        return allowedNoteValues[(index - 1 + allowedNoteValues.count) % allowedNoteValues.count]
    }
}

enum MetronomeConfig {
    static let minBPM: Double = 10
    static let maxBPM: Double = 240
    static let defaultBPM: Double = 120
    static let defaultTimeSignature: TimeSignature = .default

    static let bpmStep: Double = 1
    static let knobDegreesPerBPM: Double = 4.5
    static let tapTempoWindow: TimeInterval = 2.0
    static let minTapCount = 2

    static let minimumScheduledBeats = 8
    static let initialScheduledBeats = 16
    static let maxRefillBatchSize = 128
    /// Extra beats queued when entering background so playback survives suspension.
    static let scheduledLeadTime: TimeInterval = 600

    static func initialBeatsToSchedule() -> Int {
        initialScheduledBeats
    }

    static func beatsToSchedule(for bpm: Double, timeSignature: TimeSignature) -> Int {
        let interval = beatInterval(for: bpm, timeSignature: timeSignature)
        guard interval > 0 else { return minimumScheduledBeats }
        return max(minimumScheduledBeats, Int(ceil(scheduledLeadTime / interval)))
    }

    static let startLeadTime: TimeInterval = 0.05

    static let accentFrequency: Double = 1_000
    static let tickFrequency: Double = 800
    static let clickDuration: TimeInterval = 0.04
    static let accentAmplitude: Float = 0.9
    static let tickAmplitude: Float = 0.55
    static let dialTickFrequency: Double = 1_450
    static let dialTickDuration: TimeInterval = 0.018
    static let dialTickAmplitude: Float = 0.42

    /// BPM is expressed as quarter-note tempo; the bottom number of the time signature scales click spacing.
    static let referenceBeatNoteValue = 4

    private static let bpmKey = "metronomeBPM"
    private static let timeSignatureKey = "metronomeTimeSignature"

    static func savedBPM() -> Double {
        guard UserDefaults.standard.object(forKey: bpmKey) != nil else {
            return defaultBPM
        }
        let saved = UserDefaults.standard.double(forKey: bpmKey)
        return min(max(saved, minBPM), maxBPM)
    }

    static func saveBPM(_ bpm: Double) {
        UserDefaults.standard.set(bpm, forKey: bpmKey)
    }

    static func savedTimeSignature() -> TimeSignature {
        guard let raw = UserDefaults.standard.string(forKey: timeSignatureKey),
              let signature = TimeSignature(rawValue: raw) else {
            return defaultTimeSignature
        }
        return signature
    }

    static func saveTimeSignature(_ signature: TimeSignature) {
        UserDefaults.standard.set(signature.rawValue, forKey: timeSignatureKey)
    }

    static func beatInterval(for bpm: Double, timeSignature: TimeSignature) -> TimeInterval {
        let beatUnitScale = Double(referenceBeatNoteValue) / Double(timeSignature.noteValue)
        return (60.0 / bpm) * beatUnitScale
    }

    static func bpm(fromBeatInterval interval: TimeInterval, timeSignature: TimeSignature) -> Double {
        guard interval > 0 else { return defaultBPM }
        let beatUnitScale = Double(referenceBeatNoteValue) / Double(timeSignature.noteValue)
        return (60.0 / interval) * beatUnitScale
    }
}
