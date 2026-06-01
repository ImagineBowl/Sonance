//
//  RootView.swift
//  Sonance
//
//  Created by Ahsan Minhas on 02/06/2026.
//

import SwiftUI

struct RootView: View {
    @ObservedObject var audioAnalyzer: AudioAnalyzer
    @State private var isLaunchComplete = false

    var body: some View {
        ZStack {
            TunerView(audioAnalyzer: audioAnalyzer)

            if !isLaunchComplete {
                LaunchScreenView {
                    isLaunchComplete = true
                }
            }
        }
    }
}

#Preview {
    RootView(audioAnalyzer: AudioAnalyzer())
}
