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

    var body: some Scene {
        WindowGroup {
            RootView(audioAnalyzer: audioAnalyzer)
        }
    }
}
// MARK: TESTING CICD
// MARK: TESTING CICD
