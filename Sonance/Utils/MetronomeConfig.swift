//
//  MetronomeConfig.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import Foundation

enum TimeSignature: String, CaseIterable, Identifiable, Codable {
    case fourFour = "4/4"
    case threeFour = "3/4"
    case sixEight = "6/8"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var beatsPerBar: Int {
        switch self {
        case .fourFour: return 4
        case .threeFour: return 3
        case .sixEight: return 6
        }
    }
}

enum MetronomeConfig {
    static let minBPM: Double = 40
    static let maxBPM: Double = 240
    static let defaultBPM: Double = 120
    static let defaultTimeSignature: TimeSignature = .fourFour

    static let bpmStep: Double = 1
    static let tapTempoWindow: TimeInterval = 2.0
    static let minTapCount = 2

    static let beatsToScheduleAhead = 8
    static let startLeadTime: TimeInterval = 0.05

    static let accentFrequency: Double = 1_000
    static let tickFrequency: Double = 800
    static let clickDuration: TimeInterval = 0.04
    static let accentAmplitude: Float = 0.9
    static let tickAmplitude: Float = 0.55

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

    static func beatInterval(for bpm: Double) -> TimeInterval {
        60.0 / bpm
    }
}
