//
//  SonanceApp.swift
//  Sonance
//
//  Created by Ahsan Minhas on 27/03/2025.
//

import SwiftUI

@main
struct SonanceApp: App {
    @StateObject private var audioAnalyzer = AudioAnalyzer()
    @StateObject private var metronomeEngine = MetronomeEngine()

    var body: some Scene {
        WindowGroup {
            RootView(audioAnalyzer: audioAnalyzer, metronomeEngine: metronomeEngine)
        }
    }
}
