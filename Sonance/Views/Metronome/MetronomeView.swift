//
//  MetronomeView.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import SwiftUI

struct MetronomeView: View {
    @ObservedObject var engine: MetronomeEngine
    @State private var isTimeSignatureSheetPresented = false

    var body: some View {
        ZStack {
            backgroundColor
                .animation(.easeInOut(duration: 0.25), value: engine.isRunning)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                MetronomeTempoKnob(engine: engine)
                    .padding(.bottom, TunerLayout.isPad ? 28 : 20)

                MetronomeBeatIndicator(
                    beatIndex: engine.beatIndex,
                    beatsPerBar: engine.timeSignature.beatsPerBar,
                    isAccentBeat: engine.isAccentBeat,
                    isRunning: engine.isRunning,
                    pulseToken: engine.pulseToken
                )
                .padding(.vertical, TunerLayout.isPad ? 24 : 16)

                beatDotsView
                    .padding(.bottom, TunerLayout.isPad ? 24 : 16)

                controlsCard

                Spacer()

                controlButtonView
                    .padding(.bottom, TunerLayout.isPad ? 56 : 40)
            }
            .padding(.horizontal, TunerLayout.isPad ? 48 : 24)
        }
        .onDisappear {
            engine.endSession()
        }
        .sheet(isPresented: $isTimeSignatureSheetPresented) {
            MetronomeTimeSignatureSheet(timeSignature: $engine.timeSignature)
        }
    }

    private var backgroundColor: Color {
        engine.isRunning ? Color.accentColor.opacity(0.85) : Color(red: 0.12, green: 0.14, blue: 0.18)
    }

    private var beatDotsView: some View {
        HStack(spacing: 10) {
            ForEach(0..<engine.timeSignature.beatsPerBar, id: \.self) { index in
                Circle()
                    .fill(index == engine.beatIndex && engine.isRunning ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == 0 ? 12 : 9, height: index == 0 ? 12 : 9)
                    .scaleEffect(index == engine.beatIndex && engine.isRunning ? 1.2 : 1.0)
                    .animation(.easeOut(duration: 0.1), value: engine.beatIndex)
            }
        }
        .accessibilityHidden(true)
    }

    private var controlsCard: some View {
        HStack(spacing: 12) {
            Button {
                isTimeSignatureSheetPresented = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Time Signature", systemImage: "music.note")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))

                    Text(engine.timeSignature.displayName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .accessibilityLabel("Time signature \(engine.timeSignature.displayName)")
            .accessibilityHint("Opens time signature settings")
            .accessibilityIdentifier("metronomeTimeSignatureButton")

            Button(action: engine.tapTempo) {
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Tap")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.white)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel("Tap tempo")
            .accessibilityHint("Tap repeatedly to set the beats per minute")
            .accessibilityIdentifier("metronomeTapTempoButton")
        }
        .padding(14)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var controlButtonView: some View {
        Button(action: engine.toggle) {
            HStack(spacing: 8) {
                Image(systemName: engine.isRunning ? "stop.fill" : "play.fill")
                Text(engine.isRunning ? "Stop" : "Start")
            }
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(backgroundColor)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .accessibilityLabel(engine.isRunning ? "Stop metronome" : "Start metronome")
        .accessibilityIdentifier("metronomeControlButton")
    }
}

#Preview {
    MetronomeView(engine: MetronomeEngine())
}
