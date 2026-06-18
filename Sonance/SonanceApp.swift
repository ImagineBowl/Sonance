//
//  SonanceApp.swift
//  Sonance
//
//  Created by Ahsan Minhas on 27/03/2025.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct SonanceApp: App {
    @StateObject private var audioAnalyzer = AudioAnalyzer()
    @StateObject private var metronomeEngine = MetronomeEngine()

    init() {
        #if canImport(UIKit)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(audioAnalyzer: audioAnalyzer, metronomeEngine: metronomeEngine)
        }
    }
}
