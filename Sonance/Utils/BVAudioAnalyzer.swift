//
//  BVAudioAnalyzer.swift
//  Sonance
//
//  Created by Ahsan Minhas on 27/03/2025.
//

import AVFoundation
import Accelerate
import os

/// Detected note information including note name, octave, and cent offset
struct DetectedNote: Equatable {
    let note: String
    let octave: Int
    let offset: Double
    let frequency: Double
    
    static let empty = DetectedNote(note: "", octave: 0, offset: 0, frequency: 0)
    
    var displayName: String {
        note.isEmpty ? "" : "\(note)\(octave)"
    }
    
    var isDetected: Bool {
        !note.isEmpty && frequency > 0
    }
}

/// Audio analyzer that detects pitch from microphone input using FFT
class AudioAnalyzer: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sonance", category: "AudioAnalyzer")
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var fftSetup: FFTSetup?
    private var log2n: vDSP_Length = 0
    private var bufferSizePOT: Int = 0
    
    private var currentMinAmplitude: Float = TunerConfig.minAmplitude(for: TunerConfig.defaultInputSensitivity)
    private var currentInputGain: Float = TunerConfig.inputGain(for: TunerConfig.defaultInputSensitivity)
    private var currentPeakProminence: Float = TunerConfig.peakProminenceThreshold(for: TunerConfig.defaultInputSensitivity)
    private var aboveThresholdCount = 0
    private var lastUIUpdateTime: TimeInterval = 0
    private var pendingAmplitude: Float = 0
    private var pendingFrequency: Double = 0
    private var isTapInstalled = false
    
    @Published var frequency: Double = 0.0
    @Published var isRunning: Bool = false
    @Published var permissionGranted: Bool = false
    @Published var amplitude: Float = 0.0
    @Published var inputSensitivity: Double = TunerConfig.defaultInputSensitivity {
        didSet {
            let clamped = min(max(inputSensitivity, 0), 1)
            if clamped != inputSensitivity {
                inputSensitivity = clamped
                return
            }
            updateInputSettings(for: clamped)
            UserDefaults.standard.set(clamped, forKey: Self.inputSensitivityKey)
        }
    }
    
    var inputThreshold: Float {
        currentMinAmplitude
    }
    
    var isSignalAboveThreshold: Bool {
        amplitude >= currentMinAmplitude
    }
    
    private static let inputSensitivityKey = "inputSensitivityV2"
    
    var detectedNote: DetectedNote {
        return frequencyToNote(frequency: frequency)
    }
    
    init() {
        if UserDefaults.standard.object(forKey: Self.inputSensitivityKey) != nil {
            let saved = UserDefaults.standard.double(forKey: Self.inputSensitivityKey)
            inputSensitivity = min(max(saved, 0), 1)
        }
        updateInputSettings(for: inputSensitivity)
        checkMicrophonePermission()
    }
    
    private func updateInputSettings(for sensitivity: Double) {
        currentMinAmplitude = TunerConfig.minAmplitude(for: sensitivity)
        currentInputGain = TunerConfig.inputGain(for: sensitivity)
        currentPeakProminence = TunerConfig.peakProminenceThreshold(for: sensitivity)
        aboveThresholdCount = 0
    }
    
    // MARK: - Permission Handling
    
    /// Check and request microphone permission
    private func checkMicrophonePermission() {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async {
                self.permissionGranted = true
                self.start()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted {
                        self?.start()
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.permissionGranted = false
            }
        @unknown default:
            break
        }
        #else
        // iOS
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
                if granted {
                    self?.start()
                }
            }
        }
        #endif
    }
    
    // MARK: - Audio Engine Setup
    
    private func prepareAudioEngine() throws {
        if audioEngine == nil {
            audioEngine = AVAudioEngine()
        }
        
        guard let audioEngine else { return }
        
        inputNode = audioEngine.inputNode
        guard let inputNode else { return }
        
        log2n = vDSP_Length(round(log2(Double(TunerConfig.bufferSize))))
        bufferSizePOT = Int(pow(2, Double(log2n)))
        
        if fftSetup == nil {
            fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        }
        
        guard !isTapInstalled else { return }
        
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioEngineError.invalidInputFormat
        }
        
        inputNode.installTap(onBus: 0, bufferSize: TunerConfig.bufferSize, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer: buffer)
        }
        isTapInstalled = true
    }
    
    private func tearDownAudioEngine() {
        if isTapInstalled {
            inputNode?.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
    }
    
    private enum AudioEngineError: Error {
        case invalidInputFormat
    }
    
    // MARK: - Public Control Methods
    
    /// Start the audio analysis
    func start() {
        guard permissionGranted, !isRunning else { return }
        
        do {
            #if os(iOS)
            try configureAudioSession()
            #endif
            
            if audioEngine == nil || !isTapInstalled {
                tearDownAudioEngine()
                try prepareAudioEngine()
            }
            
            guard let audioEngine else { return }
            
            audioEngine.prepare()
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        } catch {
            Self.logger.error("Error starting audio engine: \(error.localizedDescription)")
            tearDownAudioEngine()
        }
    }
    
    #if os(iOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
    }
    #endif
    
    /// Stop the audio analysis
    func stop() {
        audioEngine?.stop()
        aboveThresholdCount = 0
        DispatchQueue.main.async {
            self.isRunning = false
            self.frequency = 0.0
            self.amplitude = 0.0
        }
    }
    
    deinit {
        stop()
        if isTapInstalled {
            inputNode?.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }
    
    // MARK: - Note Detection
    
    /// Convert frequency to musical note with octave and cent offset
    private func frequencyToNote(frequency: Double) -> DetectedNote {
        guard frequency > 0 else { return .empty }
        
        // Calculate MIDI note number from frequency
        // Formula: midiNote = 69 + 12 * log2(frequency / 440)
        let midiNote = Double(TunerConfig.referenceMidiNote) + 12.0 * log2(frequency / TunerConfig.referenceFrequency)
        let roundedNote = Int(round(midiNote))
        
        // Handle negative MIDI notes (very low frequencies)
        let noteIndex = ((roundedNote % 12) + 12) % 12
        let noteName = TunerConfig.noteNames[noteIndex]
        
        // Calculate octave (MIDI note 0 = C-1, so octave = note/12 - 1)
        let octave = (roundedNote / 12) - 1
        
        // Calculate offset in cents (100 cents = 1 semitone)
        let offset = (midiNote - Double(roundedNote)) * 100.0
        
        return DetectedNote(note: noteName, octave: octave, offset: offset, frequency: frequency)
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let floatChannelData = buffer.floatChannelData,
              let fftSetup = fftSetup else { return }
        
        let channelData = floatChannelData.pointee
        let bufferLength = Int(buffer.frameLength)
        
        var realParts = [Float](repeating: 0.0, count: bufferSizePOT)
        var imaginaryParts = [Float](repeating: 0.0, count: bufferSizePOT)
        
        let copyCount = min(bufferLength, bufferSizePOT)
        realParts.replaceSubrange(0..<copyCount, with: UnsafeBufferPointer(start: channelData, count: copyCount))
        
        if currentInputGain != 1 {
            var gain = currentInputGain
            vDSP_vsmul(realParts, 1, &gain, &realParts, 1, vDSP_Length(bufferSizePOT))
        }
        
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: bufferSizePOT, isHalfWindow: false)
        vDSP.multiply(window, realParts, result: &realParts)
        let windowedSamples = Array(realParts.prefix(copyCount))
        
        var signalLevel: Float = 0
        windowedSamples.withUnsafeBufferPointer { samples in
            vDSP_rmsqv(samples.baseAddress!, 1, &signalLevel, vDSP_Length(copyCount))
        }
        
        realParts.withUnsafeMutableBufferPointer { realBuffer in
            imaginaryParts.withUnsafeMutableBufferPointer { imagBuffer in
                var splitComplex = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                
                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                
                var magnitudes = [Float](repeating: 0.0, count: bufferSizePOT / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(bufferSizePOT / 2))
                
                let spectralSlice = Array(magnitudes[5...])
                let maxMagnitude = spectralSlice.max() ?? 0.0
                let medianMagnitude = sortedMedian(spectralSlice)
                let peakProminence = maxMagnitude / max(medianMagnitude, 1e-12)
                
                let passesLevel = signalLevel >= currentMinAmplitude
                let passesProminence = peakProminence >= currentPeakProminence
                
                if passesLevel && passesProminence {
                    aboveThresholdCount += 1
                } else {
                    aboveThresholdCount = 0
                }
                
                guard aboveThresholdCount >= TunerConfig.signalHoldBuffers else {
                    deliverResults(amplitude: signalLevel, frequency: 0)
                    return
                }
                
                guard let maxIndex = magnitudes[5...].firstIndex(of: maxMagnitude) else {
                    deliverResults(amplitude: signalLevel, frequency: 0)
                    return
                }
                
                let sampleRate = buffer.format.sampleRate
                let binWidth = sampleRate / Double(bufferSizePOT)
                let interpolatedIndex = logParabolicPeakInterpolation(magnitudes: magnitudes, maxIndex: maxIndex)
                let roughFrequency = Double(interpolatedIndex) * binWidth
                
                let refinedFrequency = refineFrequencyWithAutocorrelation(
                    samples: windowedSamples,
                    sampleRate: sampleRate,
                    roughFrequency: roughFrequency
                )
                
                if refinedFrequency >= TunerConfig.lowFrequencyCutoff &&
                   refinedFrequency <= TunerConfig.highFrequencyCutoff {
                    deliverResults(amplitude: signalLevel, frequency: refinedFrequency)
                } else {
                    deliverResults(amplitude: signalLevel, frequency: 0)
                }
            }
        }
    }
    
    private func deliverResults(amplitude: Float, frequency: Double) {
        pendingAmplitude = amplitude
        pendingFrequency = frequency
        
        let now = CACurrentMediaTime()
        guard now - lastUIUpdateTime >= TunerConfig.uiUpdateInterval else { return }
        
        lastUIUpdateTime = now
        let amplitudeToPublish = pendingAmplitude
        let frequencyToPublish = pendingFrequency
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.amplitude = amplitudeToPublish
            self.frequency = frequencyToPublish
        }
    }
    
    private func sortedMedian(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
    
    /// Log-magnitude parabolic interpolation for sharper FFT peak location
    private func logParabolicPeakInterpolation(magnitudes: [Float], maxIndex: Int) -> Float {
        guard maxIndex > 0, maxIndex < magnitudes.count - 1 else { return Float(maxIndex) }
        
        let alpha = Double(max(magnitudes[maxIndex - 1], 1e-12))
        let beta = Double(max(magnitudes[maxIndex], 1e-12))
        let gamma = Double(max(magnitudes[maxIndex + 1], 1e-12))
        
        let denominator = log(alpha) - 2 * log(beta) + log(gamma)
        guard abs(denominator) > 1e-12 else { return Float(maxIndex) }
        
        let offset = 0.5 * (log(alpha) - log(gamma)) / denominator
        return Float(maxIndex) + Float(offset)
    }
    
    /// Refine FFT estimate using normalized autocorrelation in the time domain
    private func refineFrequencyWithAutocorrelation(
        samples: [Float],
        sampleRate: Double,
        roughFrequency: Double
    ) -> Double {
        guard roughFrequency > 0, samples.count > 20 else { return roughFrequency }
        
        let roughPeriod = sampleRate / roughFrequency
        let centerLag = Int(round(roughPeriod))
        let searchRange = max(2, Int(round(roughPeriod * TunerConfig.autocorrelationSearchRatio)))
        
        let minLag = max(2, centerLag - searchRange)
        let maxLag = min(samples.count - 2, centerLag + searchRange)
        guard minLag < maxLag else { return roughFrequency }
        
        var correlations: [(lag: Int, value: Float)] = []
        correlations.reserveCapacity(maxLag - minLag + 1)
        
        for lag in minLag...maxLag {
            correlations.append((lag, normalizedAutocorrelation(samples: samples, lag: lag)))
        }
        
        guard let peakIndex = correlations.indices.max(by: { correlations[$0].value < correlations[$1].value }),
              peakIndex > 0,
              peakIndex < correlations.count - 1 else {
            return roughFrequency
        }
        
        let left = correlations[peakIndex - 1]
        let center = correlations[peakIndex]
        let right = correlations[peakIndex + 1]
        
        let refinedLag = parabolicPeakLag(
            leftLag: left.lag,
            centerLag: center.lag,
            rightLag: right.lag,
            leftValue: Double(left.value),
            centerValue: Double(center.value),
            rightValue: Double(right.value)
        )
        
        guard refinedLag > 0 else { return roughFrequency }
        return sampleRate / refinedLag
    }
    
    private func normalizedAutocorrelation(samples: [Float], lag: Int) -> Float {
        let count = samples.count - lag
        guard count > 0 else { return 0 }
        
        var sum: Float = 0
        var energyA: Float = 0
        var energyB: Float = 0
        
        for index in 0..<count {
            let a = samples[index]
            let b = samples[index + lag]
            sum += a * b
            energyA += a * a
            energyB += b * b
        }
        
        let normalization = sqrt(energyA * energyB)
        guard normalization > 0 else { return 0 }
        return sum / normalization
    }
    
    private func parabolicPeakLag(
        leftLag: Int,
        centerLag: Int,
        rightLag: Int,
        leftValue: Double,
        centerValue: Double,
        rightValue: Double
    ) -> Double {
        let denominator = leftValue - 2 * centerValue + rightValue
        guard abs(denominator) > 1e-12 else { return Double(centerLag) }
        
        let offset = 0.5 * (leftValue - rightValue) / denominator
        return Double(centerLag) + offset
    }
    
    /// Quadratic peak interpolation for more accurate frequency detection
    /// Uses parabolic interpolation around the peak bin
    private func quadraticPeakInterpolation(magnitudes: [Float], maxIndex: Int) -> Float {
        let left = maxIndex > 0 ? magnitudes[maxIndex - 1] : 0
        let center = magnitudes[maxIndex]
        let right = maxIndex < magnitudes.count - 1 ? magnitudes[maxIndex + 1] : 0
        
        let denominator = 2 * (2 * center - left - right)
        guard denominator != 0 else { return Float(maxIndex) }
        
        let correction = (right - left) / denominator
        return Float(maxIndex) + correction
    }
}
