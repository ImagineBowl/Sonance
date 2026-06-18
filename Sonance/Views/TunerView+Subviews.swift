//
//  TunerView+Subviews.swift
//  Sonance
//
//  Created by Ahsan Minhas on 02/06/2026.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Main Content

extension TunerView {
    var tunerContent: some View {
        GeometryReader { geometry in
            let gauge = TunerLayout.gaugeMetrics(
                containerWidth: geometry.size.width,
                containerHeight: geometry.size.height
            )

            VStack {
                Spacer()

                noteDisplayView
                    .padding(.top, TunerLayout.noteTopPadding)
                    .padding(.bottom, TunerLayout.noteBottomPadding)

                tunerGaugeView(gauge: gauge)

                centsDisplayView
                frequencyDisplayView

                instrumentModeView
                    .padding(.horizontal, TunerLayout.isPad ? 48 : 32)
                    .padding(.top, 8)

                inputSensitivityAndMicView
                    .padding(.horizontal, TunerLayout.isPad ? 48 : 32)
                    .padding(.top, 8)
                    .padding(.bottom, TunerLayout.isPad ? 32 : 20)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Permission

extension TunerView {
    var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.white.opacity(0.7))
                .accessibilityHidden(true)

            Text("Microphone Access Required")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            Text("Please enable microphone access in Settings to use the tuner.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Open Settings", action: openAppSettings)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.gray.opacity(0.8))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(Capsule())
                .accessibilityHint("Opens Settings so you can enable microphone access")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Note & Readouts

extension TunerView {
    var noteDisplayView: some View {
        VStack(spacing: 4) {
            ZStack {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(detectedNote.note)
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                    Text("\(detectedNote.octave)")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.white)
                .opacity(detectedNote.isDetected ? 1 : 0)

                Text("♪")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .opacity(detectedNote.isDetected ? 0 : 1)
            }

            VStack(spacing: 4) {
                ZStack {
                    Text("In Tune!")
                        .opacity(detectedNote.isDetected && presentation.phase == .inTune ? 1 : 0)
                    Text("Sharp")
                        .opacity(detectedNote.isDetected && presentation.phase != .inTune && detectedNote.offset > 0 ? 1 : 0)
                    Text("Flat")
                        .opacity(detectedNote.isDetected && presentation.phase != .inTune && detectedNote.offset <= 0 ? 1 : 0)
                    Text("Listening...")
                        .opacity(!detectedNote.isDetected && audioAnalyzer.isRunning ? 1 : 0)
                    Text("Tap to Start")
                        .opacity(!detectedNote.isDetected && !audioAnalyzer.isRunning ? 1 : 0)
                }
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(detectedNote.isDetected ? Color.white.opacity(0.9) : Color.white.opacity(0.6))
                .accessibilityLabel(
                    detectedNote.isDetected
                        ? tuningStatus
                        : (audioAnalyzer.isRunning ? "Listening" : "Tap to Start")
                )

                Label("Note locked", systemImage: "lock.fill")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .opacity(audioAnalyzer.isNoteLocked ? 1 : 0)
                    .accessibilityHidden(!audioAnalyzer.isNoteLocked)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(noteAccessibilityLabel)
    }

    var centsDisplayView: some View {
        Group {
            if detectedNote.isDetected {
                HStack(spacing: 4) {
                    Text(detectedNote.offset >= 0 ? "+" : "")
                    Text("\(detectedNote.offset, specifier: "%.1f")")
                    Text("cents")
                        .opacity(0.8)
                }
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
            } else {
                Text("-- cents")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }

    var frequencyDisplayView: some View {
        Group {
            if detectedNote.isDetected {
                Text("\(detectedNote.frequency, specifier: "%.1f") Hz")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.7))
            } else {
                Text("-- Hz")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Gauge

extension TunerView {
    func tunerGaugeView(gauge: TunerLayout.GaugeMetrics) -> some View {
        ZStack {
            ArcShape(angle: 180)
                .stroke(Color.white.opacity(0.2), lineWidth: 12)
                .frame(width: gauge.width, height: gauge.height)

            ForEach(-5...5, id: \.self) { index in
                gaugeTickView(index: index, radius: gauge.radius)
            }

            Rectangle()
                .fill(Color.white)
                .frame(width: 4, height: 25)
                .offset(y: -gauge.radius)

            gaugeNeedleView(gaugeWidth: gauge.width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tuning gauge")
        .accessibilityValue(gaugeAccessibilityValue)
    }

    private func gaugeTickView(index: Int, radius: CGFloat) -> some View {
        let angle = Double(index) * 180.0 / 10.0
        let isMajorTick = index % 5 == 0

        return Rectangle()
            .fill(Color.white.opacity(isMajorTick ? 1.0 : 0.6))
            .frame(width: isMajorTick ? 3.0 : 2.0, height: isMajorTick ? 20.0 : 10.0)
            .offset(y: -radius)
            .rotationEffect(.degrees(angle), anchor: .center)
    }

    private func gaugeNeedleView(gaugeWidth: CGFloat) -> some View {
        Group {
            if detectedNote.isDetected {
                let clampedOffset = max(
                    -TunerConfig.maxCentsOffset,
                    min(TunerConfig.maxCentsOffset, detectedNote.offset)
                )
                let needleAngle = clampedOffset * 180.0 / (TunerConfig.maxCentsOffset * 2)
                let needleHeight = gaugeWidth * 0.4
                let needleOffset = gaugeWidth * 0.2

                NeedleShapeWithRoundedBase()
                    .fill(Color.white)
                    .frame(width: 16, height: needleHeight)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .offset(y: -needleOffset)
                    .rotationEffect(.degrees(needleAngle))
                    .animation(
                        audioAnalyzer.instrumentMode == .bass
                            ? .spring(response: 0.55, dampingFraction: 0.86)
                            : .spring(response: 0.4, dampingFraction: 0.7),
                        value: detectedNote.offset
                    )
            } else {
                NeedleShapeWithRoundedBase()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 16, height: gaugeWidth * 0.4)
                    .offset(y: -(gaugeWidth * 0.2))
            }
        }
    }
}

// MARK: - Controls

extension TunerView {
    var instrumentModeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Instrument", systemImage: "guitars")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))

            Picker("Instrument", selection: $audioAnalyzer.instrumentMode) {
                ForEach(InstrumentMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("instrumentModePicker")

            if audioAnalyzer.instrumentMode == .bass {
                Text("Extended low range for bass guitar. Pluck near the mic.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    var inputSensitivityAndMicView: some View {
        HStack(alignment: .center, spacing: 14) {
            inputSensitivityContent
                .frame(maxWidth: .infinity, alignment: .leading)

            micControlButton
        }
        .padding(14)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var inputSensitivityContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Input Sensitivity", systemImage: "waveform")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))

                Spacer()

                Text(audioAnalyzer.isSignalAboveThreshold ? "Signal detected" : "Below threshold")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(audioAnalyzer.isSignalAboveThreshold ? 0.95 : 0.55))
            }

            sensitivityMeterView
                .frame(height: 10)

            Slider(value: $audioAnalyzer.inputSensitivity, in: 0...1) {
                Text("Input Sensitivity")
            } minimumValueLabel: {
                Text("Less")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
            } maximumValueLabel: {
                Text("More")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .tint(Color.white)
            .accessibilityIdentifier("inputSensitivitySlider")
            .accessibilityValue("\(Int(audioAnalyzer.inputSensitivity * 100)) percent")
        }
    }

    private var sensitivityMeterView: some View {
        GeometryReader { geometry in
            let meterMax = TunerConfig.inputMeterMax(for: audioAnalyzer.inputThreshold)
            let levelWidth = geometry.size.width * CGFloat(min(audioAnalyzer.amplitude / meterMax, 1))
            let thresholdX = geometry.size.width * CGFloat(min(audioAnalyzer.inputThreshold / meterMax, 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))

                Capsule()
                    .fill(Color.white.opacity(audioAnalyzer.isSignalAboveThreshold ? 0.95 : 0.55))
                    .frame(width: max(levelWidth, audioAnalyzer.amplitude > 0 ? 4 : 0))
                    .animation(.easeOut(duration: 0.08), value: audioAnalyzer.amplitude)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 18)
                    .offset(x: max(thresholdX - 1, 0))
            }
        }
    }

    var micControlButton: some View {
        Button(action: toggleTuning) {
            VStack(spacing: 4) {
                Image(systemName: audioAnalyzer.isRunning ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                Text(audioAnalyzer.isRunning ? "Stop" : "Start")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(tuningColor)
            .frame(width: TunerLayout.micButtonSize, height: TunerLayout.micButtonSize)
            .background(Color.white)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        .accessibilityLabel(audioAnalyzer.isRunning ? "Stop tuning" : "Start tuning")
        .accessibilityIdentifier("tunerControlButton")
    }

    func toggleTuning() {
        if audioAnalyzer.isRunning {
            audioAnalyzer.stop()
        } else {
            audioAnalyzer.start()
        }
    }

    func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
        #endif
    }
}
