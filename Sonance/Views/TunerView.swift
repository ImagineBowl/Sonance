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
    }
}

#Preview {
    TunerView(audioAnalyzer: AudioAnalyzer())
}
