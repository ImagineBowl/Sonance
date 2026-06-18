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
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLaunchComplete = false
    @State private var selectedTab: AppTab = .tuner
    @State private var availableUpdate: AppStoreUpdateInfo?
    @State private var showUpdateAlert = false

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
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .inactive, .background:
                    metronomeEngine.prepareForBackground()
                case .active:
                    metronomeEngine.recoverPlaybackIfNeeded()
                @unknown default:
                    break
                }
            }

            if !isLaunchComplete {
                LaunchScreenView {
                    isLaunchComplete = true
                    presentUpdateAlertIfNeeded()
                }
            }
        }
        .alert("Update Available", isPresented: $showUpdateAlert) {
            Button("Update") {
                if let availableUpdate {
                    AppStoreUpdateChecker.openAppStore(for: availableUpdate)
                }
            }
            Button("Not Now", role: .cancel) {
                if let availableUpdate {
                    AppStoreUpdateChecker.dismiss(availableUpdate)
                }
            }
        } message: {
            if let availableUpdate {
                Text("Version \(availableUpdate.storeVersion) is available on the App Store.")
            }
        }
        .task {
            await checkForAppStoreUpdate()
        }
    }

    private func checkForAppStoreUpdate() async {
        guard let update = await AppStoreUpdateChecker.fetchUpdateInfo(),
              !AppStoreUpdateChecker.isDismissed(update) else {
            return
        }

        availableUpdate = update
        presentUpdateAlertIfNeeded()
    }

    private func presentUpdateAlertIfNeeded() {
        guard isLaunchComplete, availableUpdate != nil else { return }
        showUpdateAlert = true
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
            metronomeEngine.warmUp()
        }
    }
}

#Preview {
    RootView(audioAnalyzer: AudioAnalyzer(), metronomeEngine: MetronomeEngine())
}
