//
//  TunerView.swift
//  Sonance
//
//  Created by Ahsan Minhas on 27/03/2025.
//

import SwiftUI

struct TunerView: View {
    @ObservedObject var audioAnalyzer: AudioAnalyzer
    @Environment(\.openURL) var openURL

    var body: some View {
        ZStack {
            tuningColor
                .animation(.easeInOut(duration: 0.3), value: tuningColorBucket)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if !audioAnalyzer.permissionGranted {
                    permissionDeniedView
                } else {
                    tunerContent
                }
            }
        }
        .onAppear {
            audioAnalyzer.start()
        }
        .onChange(of: audioAnalyzer.permissionGranted) { _, granted in
            if granted {
                audioAnalyzer.start()
            }
        }
        .onDisappear {
            audioAnalyzer.stop()
        }
    }
}

#Preview {
    TunerView(audioAnalyzer: AudioAnalyzer())
}
