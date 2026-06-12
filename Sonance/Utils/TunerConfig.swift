//
//  TunerConfig.swift
//  Sonance
//
//  Created by Ahsan Minhas on 11/12/2025.
//

import AVFoundation

/// Tuning profile for different instruments
enum InstrumentMode: String, CaseIterable, Identifiable, Codable {
    case standard
    case bass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .bass: return "Bass"
        }
    }
}

/// Configuration constants for the tuner
enum TunerConfig {
    // MARK: - Audio Processing

    /// Buffer size for standard tuning (power of 2 for FFT efficiency)
    static let bufferSize: AVAudioFrameCount = 8192

    /// Longer buffer for bass — better low-frequency resolution
    static let bassBufferSize: AVAudioFrameCount = 16384

    /// Default input sensitivity (0 = least sensitive, 1 = most sensitive)
    static let defaultInputSensitivity: Double = 0.84

    /// RMS signal floor at maximum sensitivity
    static let minAmplitudeFloor: Float = 0.00075

    /// RMS signal floor at minimum sensitivity
    static let minAmplitudeCeiling: Float = 0.0195

    /// Input gain at minimum sensitivity
    static let inputGainMin: Float = 1.36

    /// Input gain at maximum sensitivity
    static let inputGainMax: Float = 11.2

    /// Consecutive buffers above threshold before pitch detection activates
    static let signalHoldBuffers: Int = 2

    /// Minimum interval between UI updates from the audio thread
    static let uiUpdateInterval: TimeInterval = 1.0 / 30.0

    /// Maps sensitivity to the RMS level required for detection
    static func minAmplitude(for sensitivity: Double) -> Float {
        let clamped = Float(min(max(sensitivity, 0), 1))
        let strictness = pow(1 - clamped, 0.5)
        return minAmplitudeFloor + strictness * (minAmplitudeCeiling - minAmplitudeFloor)
    }

    /// Maps sensitivity to pre-FFT input gain
    static func inputGain(for sensitivity: Double) -> Float {
        let clamped = Float(min(max(sensitivity, 0), 1))
        return inputGainMin + clamped * (inputGainMax - inputGainMin)
    }

    /// Peak must stand this many times above the spectral median
    static func peakProminenceThreshold(for sensitivity: Double) -> Float {
        let clamped = Float(min(max(sensitivity, 0), 1))
        let strictness = pow(1 - clamped, 0.32)
        return 0.375 + strictness * 1.65
    }

    /// Fixed meter headroom above the threshold marker
    static func inputMeterMax(for threshold: Float) -> Float {
        max(threshold + 0.06, 0.1)
    }

    static func bufferSize(for mode: InstrumentMode) -> AVAudioFrameCount {
        mode == .bass ? bassBufferSize : bufferSize
    }

    /// Low frequency cutoff in Hz for standard mode
    static let lowFrequencyCutoffStandard: Double = 50.0

    /// Low frequency cutoff in Hz for bass mode (supports B0 ~31 Hz)
    static let lowFrequencyCutoffBass: Double = 28.0

    static func lowFrequencyCutoff(for mode: InstrumentMode) -> Double {
        mode == .bass ? lowFrequencyCutoffBass : lowFrequencyCutoffStandard
    }

    /// High frequency cutoff in Hz (~C8, highest practical note)
    static let highFrequencyCutoff: Double = 4200.0

    /// Search window for autocorrelation refinement (±% of estimated period)
    static let autocorrelationSearchRatio: Double = 0.05

    /// Wider autocorrelation search for bass fundamentals
    static let bassAutocorrelationSearchRatio: Double = 0.08

    static func autocorrelationSearchRatio(for mode: InstrumentMode) -> Double {
        mode == .bass ? bassAutocorrelationSearchRatio : autocorrelationSearchRatio
    }

    /// Reference frequency for A4 in Hz (standard tuning)
    static let referenceFrequency: Double = 440.0

    /// Reference MIDI note number for A4
    static let referenceMidiNote: Int = 69

    // MARK: - Note Lock

    /// Search band around locked target (± cents)
    static let noteLockWindowCents: Double = 55.0

    /// Buffers with stable note before locking
    static let noteLockStableBuffers: Int = 2

    /// Buffers outside lock window before unlocking
    static let noteLockUnlockBuffers: Int = 3

    /// Max deviation from target to count toward lock acquisition
    static let noteLockAcquireCents: Double = 40.0

    /// EMA weight for new samples while locked (0–1)
    static let frequencySmoothingFactor: Double = 0.35

    // MARK: - Harmonic Correction

    /// Apply subharmonic correction above this frequency
    static let harmonicCorrectionMinFrequency: Double = 55.0

    /// Apply subharmonic correction below this frequency
    static let harmonicCorrectionMaxFrequency: Double = 220.0

    /// Subharmonic magnitude must reach this fraction of the peak to prefer fundamental
    static let harmonicEnergyRatioThreshold: Float = 0.22

    // MARK: - Tuning Thresholds (in cents)

    /// Threshold for "in tune" (within this many cents)
    static let inTuneThreshold: Double = 5.0

    /// Threshold for "close" (within this many cents)
    static let closeThreshold: Double = 15.0

    /// Maximum cents offset (for gauge scaling)
    static let maxCentsOffset: Double = 50.0

    // MARK: - Note Names

    /// Standard Western chromatic scale note names
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // MARK: - Frequency Helpers

    static func midiNote(for frequency: Double) -> Double {
        Double(referenceMidiNote) + 12.0 * log2(frequency / referenceFrequency)
    }

    static func frequency(forMidiNote midiNote: Double) -> Double {
        referenceFrequency * pow(2.0, (midiNote - Double(referenceMidiNote)) / 12.0)
    }

    static func centsBetween(_ frequencyA: Double, and frequencyB: Double) -> Double {
        1200.0 * log2(frequencyA / frequencyB)
    }
}
