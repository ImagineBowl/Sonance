//
//  TunerView+Presentation.swift
//  Sonance
//
//  Created by Ahsan Minhas on 02/06/2026.
//

import SwiftUI

extension TunerView {
    var detectedNote: DetectedNote {
        audioAnalyzer.detectedNote
    }

    var presentation: TuningPresentation {
        TuningPresentation(note: detectedNote)
    }

    var tuningColor: Color {
        presentation.backgroundColor
    }

    var tuningStatus: String {
        presentation.statusText
    }

    var tuningColorBucket: Int {
        presentation.colorBucket
    }

    var noteAccessibilityLabel: String {
        presentation.noteAccessibilityLabel(isRunning: audioAnalyzer.isRunning)
    }

    var gaugeAccessibilityValue: String {
        presentation.gaugeAccessibilityValue(isRunning: audioAnalyzer.isRunning)
    }
}
