//
//  AudioSessionCoordinator.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import AVFoundation

enum AudioSessionMode {
    case tuner
    case metronome
}

enum AudioSessionCoordinator {
    static func activate(_ mode: AudioSessionMode) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        switch mode {
        case .tuner:
            try session.setCategory(.record, mode: .measurement, options: [])
        case .metronome:
            if session.category == .record || session.category == .playAndRecord {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try session.setActive(true)
        #endif
    }

    static func deactivate() throws {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        #endif
    }
}
