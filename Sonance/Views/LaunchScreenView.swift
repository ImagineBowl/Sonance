//
//  LaunchScreenView.swift
//  Sonance
//
//  Created by Ahsan Minhas on 02/06/2026.
//

import SwiftUI

struct LaunchScreenView: View {
    let onComplete: () -> Void

    @State private var logoScale: CGFloat = 0.35
    @State private var logoOpacity: Double = 0
    @State private var backgroundOpacity: Double = 1

    private let logoSize: CGFloat = 180
    private var logoCornerRadius: CGFloat { logoSize * 0.2237 }

    private let introAnimation = Animation.spring(response: 0.75, dampingFraction: 0.72)
    private let exitAnimation = Animation.easeIn(duration: 0.55)

    private let introHoldDuration: TimeInterval = 0.4
    private let introDuration: TimeInterval = 0.75
    private let exitDuration: TimeInterval = 0.55

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: logoCornerRadius, style: .continuous))
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .accessibilityLabel("Sonance")
        }
        .task {
            await runLaunchAnimation()
        }
    }

    @MainActor
    private func runLaunchAnimation() async {
        withAnimation(introAnimation) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        try? await Task.sleep(for: .seconds(introDuration + introHoldDuration))

        withAnimation(exitAnimation) {
            logoScale = 1.55
            logoOpacity = 0
            backgroundOpacity = 0
        }

        try? await Task.sleep(for: .seconds(exitDuration))
        onComplete()
    }
}

#Preview {
    LaunchScreenView(onComplete: {})
}
