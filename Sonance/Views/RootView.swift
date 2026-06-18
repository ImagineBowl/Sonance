//
//  RootView.swift
//  Sonance
//
//  Created by Ahsan Minhas on 02/06/2026.
//

import SwiftUI

enum AppTab: Hashable {
    case tuner
    case metronome
}

struct RootView: View {
    @ObservedObject var audioAnalyzer: AudioAnalyzer
    @ObservedObject var metronomeEngine: MetronomeEngine
    @State private var isLaunchComplete = false
    @State private var selectedTab: AppTab = .tuner

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                TunerView(audioAnalyzer: audioAnalyzer)
                    .tabItem {
                        Label("Tuner", systemImage: "tuningfork")
                    }
                    .tag(AppTab.tuner)

                MetronomeView(engine: metronomeEngine)
                    .tabItem {
                        Label("Metronome", systemImage: "metronome")
                    }
                    .tag(AppTab.metronome)
            }
            .onChange(of: selectedTab) { _, tab in
                handleTabChange(to: tab)
            }

            if !isLaunchComplete {
                LaunchScreenView {
                    isLaunchComplete = true
                }
            }
        }
    }

    private func handleTabChange(to tab: AppTab) {
        switch tab {
        case .tuner:
            metronomeEngine.endSession()
            if audioAnalyzer.permissionGranted {
                audioAnalyzer.start()
            }
        case .metronome:
            audioAnalyzer.stop()
        }
    }
}

#Preview {
    RootView(audioAnalyzer: AudioAnalyzer(), metronomeEngine: MetronomeEngine())
}
