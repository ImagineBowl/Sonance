//
//  TuningPresentation.swift
//  Sonance
//
//  Created by Ahsan Minhas on 02/06/2026.
//

import SwiftUI

struct TuningPresentation {
    enum Phase: Int {
        case idle = 0
        case inTune = 1
        case close = 2
        case outOfTune = 3
    }

    let note: DetectedNote
    let phase: Phase

    init(note: DetectedNote) {
        self.note = note

        guard note.isDetected else {
            phase = .idle
            return
        }

        let absOffset = abs(note.offset)
        if absOffset > TunerConfig.closeThreshold {
            phase = .outOfTune
        } else if absOffset > TunerConfig.inTuneThreshold {
            phase = .close
        } else {
            phase = .inTune
        }
    }

    var backgroundColor: Color {
        switch phase {
        case .idle:
            return Color.gray.opacity(0.8)
        case .inTune:
            return Color.accentColor
        case .close:
            return .snOrange
        case .outOfTune:
            return .snRED
        }
    }

    var statusText: String {
        guard note.isDetected else { return "" }

        switch phase {
        case .inTune:
            return "In Tune!"
        case .close, .outOfTune:
            return note.offset > 0 ? "Sharp" : "Flat"
        case .idle:
            return ""
        }
    }

    var colorBucket: Int { phase.rawValue }

    func noteAccessibilityLabel(isRunning: Bool) -> String {
        guard note.isDetected else {
            return isRunning ? "Listening for pitch" : "Tap start to begin tuning"
        }

        return "\(note.displayName), \(statusText), \(String(format: "%.1f", abs(note.offset))) cents"
    }

    func gaugeAccessibilityValue(isRunning: Bool) -> String {
        guard note.isDetected else {
            return isRunning ? "Listening" : "No pitch detected"
        }

        if phase == .inTune {
            return "In tune"
        }

        let direction = note.offset > 0 ? "sharp" : "flat"
        return "\(direction) by \(String(format: "%.1f", abs(note.offset))) cents"
    }
}
