//
//  MetronomeBeatIndicator.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import SwiftUI

struct MetronomeBeatIndicator: View {
    let beatIndex: Int
    let beatsPerBar: Int
    let isAccentBeat: Bool
    let isRunning: Bool
    let pulseToken: UUID

    @State private var pulseScale: CGFloat = 1.0

    private var indicatorSize: CGFloat {
        TunerLayout.isPad ? 200 : 160
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: indicatorSize, height: indicatorSize)

            Circle()
                .fill(isAccentBeat ? Color.accentColor : Color.white.opacity(0.85))
                .frame(width: indicatorSize * 0.55, height: indicatorSize * 0.55)
                .scaleEffect(pulseScale)
                .shadow(color: .black.opacity(0.25), radius: isAccentBeat ? 12 : 6)

            Text("\(beatIndex + 1)")
                .font(.system(size: TunerLayout.isPad ? 52 : 44, weight: .bold, design: .rounded))
                .foregroundStyle(isAccentBeat ? Color.white : Color.black.opacity(0.75))
                .accessibilityHidden(true)
        }
        .opacity(isRunning ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onChange(of: pulseToken) { _, _ in
            triggerPulse()
        }
    }

    private var accessibilityLabel: String {
        guard isRunning else { return "Metronome stopped" }
        let beatLabel = isAccentBeat ? "Accent beat \(beatIndex + 1)" : "Beat \(beatIndex + 1)"
        return "\(beatLabel) of \(beatsPerBar)"
    }

    private func triggerPulse() {
        let peakScale: CGFloat = isAccentBeat ? 1.18 : 1.08
        withAnimation(.spring(response: 0.12, dampingFraction: 0.55)) {
            pulseScale = peakScale
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.72).delay(0.08)) {
            pulseScale = 1.0
        }
    }
}

#Preview {
    MetronomeBeatIndicator(
        beatIndex: 0,
        beatsPerBar: 4,
        isAccentBeat: true,
        isRunning: true,
        pulseToken: UUID()
    )
    .padding()
    .background(Color.gray)
}
