//
//  TunerView.swift
//  Sonance
//
//  Created by Ahsan Minhas on 27/03/2025.
//

import SwiftUI

struct TunerView: View {
    @ObservedObject var audioAnalyzer: AudioAnalyzer
    
    private var detectedNote: DetectedNote {
        audioAnalyzer.detectedNote
    }
    
    private var tuningColor: Color {
        guard detectedNote.isDetected else {
            return Color.gray.opacity(0.8)
        }
        
        let absOffset = abs(detectedNote.offset)
        if absOffset > TunerConfig.closeThreshold {
            return .snRED
        } else if absOffset > TunerConfig.inTuneThreshold {
            return .snOrange
        } else {
            return Color.accentColor
        }
    }
    
    private var tuningStatus: String {
        guard detectedNote.isDetected else { return "" }
        
        let absOffset = abs(detectedNote.offset)
        if absOffset <= TunerConfig.inTuneThreshold {
            return "In Tune!"
        } else if detectedNote.offset > 0 {
            return "Sharp"
        } else {
            return "Flat"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Permission denied state
            if !audioAnalyzer.permissionGranted {
                permissionDeniedView
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 16) {
                        Spacer()
                        
                        // Note display
                        noteDisplayView
                        .padding(.bottom, 50)
                        
                        // Tuner gauge
                        tunerGaugeView(geometry: geometry)
                        
                        // Cents offset
                        centsDisplayView
                        
                        // Frequency display
                        frequencyDisplayView

                        instrumentModeView
                            .padding(.horizontal, 32)
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        // Control button
                        controlButtonView
                            .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(tuningColor.animation(.easeInOut(duration: 0.3)))
        .onAppear {
            audioAnalyzer.start()
        }
        .onDisappear {
            audioAnalyzer.stop()
        }
        .ignoresSafeArea()

    }
    
    // MARK: - Subviews
    
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.white.opacity(0.7))
            
            Text("Microphone Access Required")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
            
            Text("Please enable microphone access in Settings to use the tuner.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noteDisplayView: some View {
        VStack(spacing: 4) {
            if detectedNote.isDetected {
                // Note with octave
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(detectedNote.note)
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                    Text("\(detectedNote.octave)")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.white)
                
                // Tuning status
                VStack(spacing: 4) {
                    Text(tuningStatus)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))

                    if audioAnalyzer.isNoteLocked {
                        Label("Note locked", systemImage: "lock.fill")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
            } else {
                // Empty state
                Text("♪")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                
                Text(audioAnalyzer.isRunning ? "Listening..." : "Tap to Start")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }
    
    private func tunerGaugeView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background arc
            ArcShape(angle: 180)
                .stroke(Color.white.opacity(0.2), lineWidth: 12)
                .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.3)
            
            // Tick marks
            ForEach(-5...5, id: \.self) { i in
                let angle = Double(i) * 180.0 / 10.0
                let isMajorTick = i % 5 == 0
                let tickHeight: CGFloat = isMajorTick ? 20.0 : 10.0
                let tickWidth: CGFloat = isMajorTick ? 3.0 : 2.0
                let radius = geometry.size.width * 0.35
                
                Rectangle()
                    .fill(Color.white.opacity(isMajorTick ? 1.0 : 0.6))
                    .frame(width: tickWidth, height: tickHeight)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(angle), anchor: .center)
            }
            
            // Center indicator (in-tune zone)
            Rectangle()
                .fill(Color.white)
                .frame(width: 4, height: 25)
                .offset(y: -geometry.size.width * 0.35)
            
            // Needle
            if detectedNote.isDetected {
                let clampedOffset = max(-TunerConfig.maxCentsOffset, min(TunerConfig.maxCentsOffset, detectedNote.offset))
                let needleAngle = clampedOffset * 180.0 / (TunerConfig.maxCentsOffset * 2)
                
                NeedleShapeWithRoundedBase()
                    .fill(Color.white)
                    .frame(width: 16, height: geometry.size.width * 0.32)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .offset(y: -geometry.size.width * 0.16)
                    .rotationEffect(.degrees(needleAngle))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: detectedNote.offset)
            } else {
                // Inactive needle
                NeedleShapeWithRoundedBase()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 16, height: geometry.size.width * 0.32)
                    .offset(y: -geometry.size.width * 0.16)
            }
        }
    }
    
    private var centsDisplayView: some View {
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
    
    private var frequencyDisplayView: some View {
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
    
    private var instrumentModeView: some View {
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

    private var controlButtonView: some View {
        Button(action: {
            if audioAnalyzer.isRunning {
                audioAnalyzer.stop()
            } else {
                audioAnalyzer.start()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: audioAnalyzer.isRunning ? "stop.fill" : "mic.fill")
                Text(audioAnalyzer.isRunning ? "Stop" : "Start")
            }
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(tuningColor)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
    }
}

#Preview {
    TunerView(audioAnalyzer: AudioAnalyzer())
}
