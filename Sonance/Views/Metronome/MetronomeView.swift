//
//  MetronomeView.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import SwiftUI

struct MetronomeView: View {
    @ObservedObject var engine: MetronomeEngine

    var body: some View {
        ZStack {
            backgroundColor
                .animation(.easeInOut(duration: 0.25), value: engine.isRunning)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                bpmDisplayView
                    .padding(.bottom, TunerLayout.isPad ? 32 : 24)

                MetronomeBeatIndicator(
                    beatIndex: engine.beatIndex,
                    beatsPerBar: engine.timeSignature.beatsPerBar,
                    isAccentBeat: engine.isAccentBeat,
                    isRunning: engine.isRunning,
                    pulseToken: engine.pulseToken
                )
                .padding(.vertical, TunerLayout.isPad ? 40 : 28)

                beatDotsView
                    .padding(.bottom, TunerLayout.isPad ? 36 : 24)

                controlsCard

                Spacer()

                controlButtonView
                    .padding(.bottom, TunerLayout.isPad ? 56 : 40)
            }
            .padding(.horizontal, TunerLayout.isPad ? 48 : 24)
        }
        .onDisappear {
            engine.stop()
        }
    }

    private var backgroundColor: Color {
        engine.isRunning ? Color.accentColor.opacity(0.85) : Color(red: 0.12, green: 0.14, blue: 0.18)
    }

    private var bpmDisplayView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Image(systemName: "metronome")
                    .font(.system(size: TunerLayout.isPad ? 28 : 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .accessibilityHidden(true)

                Text("\(Int(engine.bpm.rounded()))")
                    .font(.system(size: TunerLayout.isPad ? 88 : 72, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: engine.bpm)

                Text("BPM")
                    .font(.system(size: TunerLayout.isPad ? 28 : 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Int(engine.bpm.rounded())) beats per minute")

            HStack(spacing: 20) {
                bpmAdjustButton(label: "Decrease BPM", systemImage: "minus") {
                    engine.decrementBPM()
                }

                bpmAdjustButton(label: "Increase BPM", systemImage: "plus") {
                    engine.incrementBPM()
                }
            }
        }
    }

    private func bpmAdjustButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.18))
                .clipShape(Circle())
        }
        .accessibilityLabel(label)
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
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Tempo", systemImage: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))

                Slider(
                    value: $engine.bpm,
                    in: MetronomeConfig.minBPM...MetronomeConfig.maxBPM,
                    step: MetronomeConfig.bpmStep
                ) {
                    Text("BPM")
                } minimumValueLabel: {
                    Text("\(Int(MetronomeConfig.minBPM))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                } maximumValueLabel: {
                    Text("\(Int(MetronomeConfig.maxBPM))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                .tint(Color.white)
                .accessibilityIdentifier("metronomeBPMSlider")
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Time", systemImage: "music.note")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))

                    Picker("Time Signature", selection: $engine.timeSignature) {
                        ForEach(TimeSignature.allCases) { signature in
                            Text(signature.displayName).tag(signature)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("metronomeTimeSignaturePicker")
                }

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
