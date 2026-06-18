//
//  MetronomeTempoKnob.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import SwiftUI

struct MetronomeTempoKnob: View {
    @ObservedObject var engine: MetronomeEngine

    @State private var visualRotation: Double = 0
    @State private var gestureStartRotation: Double = 0
    @State private var gestureStartBPM: Double = 0
    @State private var lastDragAngle: Double?
    @State private var lastIntegerBPM: Int = 0

    private var knobSize: CGFloat {
        TunerLayout.isPad ? 280 : 220
    }

    var body: some View {
        ZStack {
            knobRing

            knobTicks

            knobIndicator
                .rotationEffect(.degrees(visualRotation))

            knobCenterLabel
        }
        .frame(width: knobSize, height: knobSize)
        .contentShape(Circle())
        .gesture(rotationGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tempo knob")
        .accessibilityValue("\(Int(engine.bpm.rounded())) beats per minute")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                engine.incrementBPM()
            case .decrement:
                engine.decrementBPM()
            @unknown default:
                break
            }
        }
        .onAppear {
            lastIntegerBPM = Int(engine.bpm.rounded())
        }
        .onChange(of: engine.bpm) { _, newValue in
            lastIntegerBPM = Int(newValue.rounded())
        }
    }

    private var knobRing: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.2)
                        ],
                        center: .center,
                        startRadius: knobSize * 0.2,
                        endRadius: knobSize * 0.52
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 3)
                .padding(6)

            Circle()
                .stroke(Color.black.opacity(0.25), lineWidth: 8)
                .blur(radius: 4)
                .padding(2)
                .mask(Circle().padding(2))
        }
    }

    private var knobTicks: some View {
        ZStack {
            ForEach(0..<40, id: \.self) { index in
                let isMajor = index % 5 == 0
                Rectangle()
                    .fill(Color.white.opacity(isMajor ? 0.75 : 0.35))
                    .frame(width: isMajor ? 2.5 : 1.5, height: isMajor ? 14 : 8)
                    .offset(y: -(knobSize * 0.42))
                    .rotationEffect(.degrees(Double(index) * 9))
            }
        }
    }

    private var knobIndicator: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 6, height: knobSize * 0.16)
            .offset(y: -(knobSize * 0.3))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }

    private var knobCenterLabel: some View {
        VStack(spacing: 2) {
            Text("\(Int(engine.bpm.rounded()))")
                .font(.system(size: TunerLayout.isPad ? 64 : 52, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.12), value: engine.bpm)

            Text("BPM")
                .font(.system(size: TunerLayout.isPad ? 18 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .allowsHitTesting(false)
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let angle = Self.angle(for: value.location, knobSize: knobSize)

                guard let previousAngle = lastDragAngle else {
                    gestureStartRotation = visualRotation
                    gestureStartBPM = engine.bpm
                    lastDragAngle = angle
                    return
                }

                let delta = Self.normalizedAngleDelta(from: previousAngle, to: angle)
                visualRotation += delta
                lastDragAngle = angle

                let rotationOffset = visualRotation - gestureStartRotation
                let proposedBPM = gestureStartBPM + rotationOffset / MetronomeConfig.knobDegreesPerBPM

                if proposedBPM > MetronomeConfig.maxBPM,
                   lastIntegerBPM >= Int(MetronomeConfig.maxBPM) {
                    syncGestureAnchor(bpm: MetronomeConfig.maxBPM)
                    return
                }

                if proposedBPM < MetronomeConfig.minBPM,
                   lastIntegerBPM <= Int(MetronomeConfig.minBPM) {
                    syncGestureAnchor(bpm: MetronomeConfig.minBPM)
                    return
                }

                let roundedBPM = Int(
                    min(
                        max(proposedBPM.rounded(), MetronomeConfig.minBPM),
                        MetronomeConfig.maxBPM
                    )
                )

                guard roundedBPM != lastIntegerBPM else { return }

                lastIntegerBPM = roundedBPM
                engine.bpm = Double(roundedBPM)
                engine.playDialTick()
            }
            .onEnded { _ in
                lastDragAngle = nil
            }
    }

    private func syncGestureAnchor(bpm: Double) {
        gestureStartRotation = visualRotation
        gestureStartBPM = bpm
    }

    private static func angle(for location: CGPoint, knobSize: CGFloat) -> Double {
        let center = knobSize / 2
        let deltaX = location.x - center
        let deltaY = location.y - center
        return atan2(deltaY, deltaX) * 180 / .pi
    }

    private static func normalizedAngleDelta(from previous: Double, to current: Double) -> Double {
        var delta = current - previous
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

#Preview {
    MetronomeTempoKnob(engine: MetronomeEngine())
        .padding()
        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
}
