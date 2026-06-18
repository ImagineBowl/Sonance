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

    // Note lock state
    private var lockedMidiNote: Int?
    private var lockedTargetFrequency: Double?
    private var stableNoteCount = 0
    private var lastCandidateMidiNote: Int?
    private var unlockCount = 0
    private var smoothedFrequency: Double = 0

    @Published var frequency: Double = 0.0
    @Published var isRunning: Bool = false
    @Published var permissionGranted: Bool = false
    @Published var amplitude: Float = 0.0
    @Published private(set) var isNoteLocked: Bool = false
    @Published var instrumentMode: InstrumentMode = .standard {
        didSet {
            guard instrumentMode != oldValue else { return }
            UserDefaults.standard.set(instrumentMode.rawValue, forKey: Self.instrumentModeKey)
            resetNoteLock()
            reconfigureAudioEngineIfNeeded()
        }
    }
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
    private static let instrumentModeKey = "instrumentMode"

    var detectedNote: DetectedNote {
        if let lockedMidiNote, let lockedTargetFrequency {
            return noteFromLockedTarget(
                frequency: frequency,
                lockedMidiNote: lockedMidiNote,
                lockedTargetFrequency: lockedTargetFrequency
            )
        }
        return frequencyToNote(frequency: frequency)
    }

    init() {
        if UserDefaults.standard.object(forKey: Self.inputSensitivityKey) != nil {
            let saved = UserDefaults.standard.double(forKey: Self.inputSensitivityKey)
            inputSensitivity = min(max(saved, 0), 1)
        }
        if let savedMode = UserDefaults.standard.string(forKey: Self.instrumentModeKey),
           let mode = InstrumentMode(rawValue: savedMode) {
            instrumentMode = mode
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

    func unlockNote() {
        resetNoteLock()
        DispatchQueue.main.async {
            self.frequency = 0
        }
    }

    private func resetNoteLock() {
        lockedMidiNote = nil
        lockedTargetFrequency = nil
        stableNoteCount = 0
        lastCandidateMidiNote = nil
        unlockCount = 0
        smoothedFrequency = 0
        DispatchQueue.main.async {
            self.isNoteLocked = false
        }
    }

    // MARK: - Permission Handling

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

    private var activeBufferSize: AVAudioFrameCount {
        TunerConfig.bufferSize(for: instrumentMode)
    }

    private func configureFFT() {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
            self.fftSetup = nil
        }

        log2n = vDSP_Length(round(log2(Double(activeBufferSize))))
        bufferSizePOT = Int(pow(2, Double(log2n)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    private func prepareAudioEngine() throws {
        if audioEngine == nil {
            audioEngine = AVAudioEngine()
        }

        guard let audioEngine else { return }

        inputNode = audioEngine.inputNode
        guard let inputNode else { return }

        configureFFT()

        guard !isTapInstalled else { return }

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioEngineError.invalidInputFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: activeBufferSize, format: format) { [weak self] buffer, _ in
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

    private func reconfigureAudioEngineIfNeeded() {
        guard permissionGranted else { return }
        let wasRunning = isRunning

        tearDownAudioEngine()
        aboveThresholdCount = 0
        pendingFrequency = 0
        pendingAmplitude = 0

        DispatchQueue.main.async {
            self.isRunning = false
            self.frequency = 0
            self.amplitude = 0
            if wasRunning {
                self.start()
            }
        }
    }

    private enum AudioEngineError: Error {
        case invalidInputFormat
    }

    // MARK: - Public Control Methods

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
        try AudioSessionCoordinator.activate(.tuner)
    }
    #endif

    func stop() {
        audioEngine?.stop()
        aboveThresholdCount = 0
        resetNoteLock()
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

    private func frequencyToNote(frequency: Double) -> DetectedNote {
        guard frequency > 0 else { return .empty }

        let midiNote = TunerConfig.midiNote(for: frequency)
        let roundedNote = Int(round(midiNote))
        let noteIndex = ((roundedNote % 12) + 12) % 12
        let noteName = TunerConfig.noteNames[noteIndex]
        let octave = (roundedNote / 12) - 1
        let offset = (midiNote - Double(roundedNote)) * 100.0

        return DetectedNote(note: noteName, octave: octave, offset: offset, frequency: frequency)
    }

    private func noteFromLockedTarget(
        frequency: Double,
        lockedMidiNote: Int,
        lockedTargetFrequency: Double
    ) -> DetectedNote {
        guard frequency > 0 else { return .empty }

        let noteIndex = ((lockedMidiNote % 12) + 12) % 12
        let noteName = TunerConfig.noteNames[noteIndex]
        let octave = (lockedMidiNote / 12) - 1
        let offset = TunerConfig.centsBetween(frequency, and: lockedTargetFrequency)

        return DetectedNote(note: noteName, octave: octave, offset: offset, frequency: frequency)
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let floatChannelData = buffer.floatChannelData,
              let fftSetup = fftSetup else { return }

        let channelData = floatChannelData.pointee
        let bufferLength = Int(buffer.frameLength)
        let lowCutoff = TunerConfig.lowFrequencyCutoff(for: instrumentMode)

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
                    resetNoteLock()
                    deliverResults(amplitude: signalLevel, frequency: 0)
                    return
                }

                guard aboveThresholdCount >= TunerConfig.signalHoldBuffers else {
                    deliverResults(amplitude: signalLevel, frequency: 0)
                    return
                }

                let sampleRate = buffer.format.sampleRate
                let binWidth = sampleRate / Double(bufferSizePOT)

                let searchRange = lockSearchRangeHz()
                guard let peak = findStrongestPeak(
                    magnitudes: magnitudes,
                    binWidth: binWidth,
                    minHz: searchRange?.min,
                    maxHz: searchRange?.max,
                    lowCutoff: lowCutoff
                ) else {
                    if lockedTargetFrequency != nil, smoothedFrequency > 0 {
                        deliverResults(amplitude: signalLevel, frequency: smoothedFrequency)
                    } else {
                        deliverResults(amplitude: signalLevel, frequency: 0)
                    }
                    return
                }

                let interpolatedIndex = logParabolicPeakInterpolation(magnitudes: magnitudes, maxIndex: peak.index)
                var roughFrequency = Double(interpolatedIndex) * binWidth

                roughFrequency = correctHarmonicToFundamental(
                    frequency: roughFrequency,
                    magnitudes: magnitudes,
                    binWidth: binWidth,
                    lowCutoff: lowCutoff
                )

                let refinedFrequency = refineFrequencyWithAutocorrelation(
                    samples: windowedSamples,
                    sampleRate: sampleRate,
                    roughFrequency: roughFrequency
                )

                guard refinedFrequency >= lowCutoff,
                      refinedFrequency <= TunerConfig.highFrequencyCutoff else {
                    deliverResults(amplitude: signalLevel, frequency: 0)
                    return
                }

                let outputFrequency = applyNoteLock(to: refinedFrequency)
                deliverResults(amplitude: signalLevel, frequency: outputFrequency)
            }
        }
    }

    private func lockSearchRangeHz() -> (min: Double, max: Double)? {
        guard let lockedTargetFrequency else { return nil }
        let ratio = TunerConfig.noteLockWindowCents / 1200.0
        return (
            min: lockedTargetFrequency * pow(2.0, -ratio),
            max: lockedTargetFrequency * pow(2.0, ratio)
        )
    }

    private func findStrongestPeak(
        magnitudes: [Float],
        binWidth: Double,
        minHz: Double?,
        maxHz: Double?,
        lowCutoff: Double
    ) -> (index: Int, magnitude: Float)? {
        let startBin = minHz.map { max(5, Int(floor($0 / binWidth))) } ?? 5
        let endBin = minHz != nil
            ? min(magnitudes.count - 2, Int(ceil((maxHz ?? TunerConfig.highFrequencyCutoff) / binWidth)))
            : magnitudes.count - 2

        guard startBin <= endBin else { return nil }

        var bestIndex = -1
        var bestMagnitude: Float = 0

        for index in startBin...endBin {
            let frequency = Double(index) * binWidth
            guard frequency >= lowCutoff else { continue }

            let magnitude = magnitudes[index]
            if magnitude > bestMagnitude {
                bestMagnitude = magnitude
                bestIndex = index
            }
        }

        guard bestIndex >= 0 else { return nil }
        return (bestIndex, bestMagnitude)
    }

    private func correctHarmonicToFundamental(
        frequency: Double,
        magnitudes: [Float],
        binWidth: Double,
        lowCutoff: Double
    ) -> Double {
        guard frequency >= TunerConfig.harmonicCorrectionMinFrequency,
              frequency <= TunerConfig.harmonicCorrectionMaxFrequency else {
            return frequency
        }

        let peakMagnitude = magnitude(atFrequency: frequency, magnitudes: magnitudes, binWidth: binWidth)
        var bestFrequency = frequency
        var bestScore = peakMagnitude

        for divisor in [2.0, 3.0] {
            let candidate = frequency / divisor
            guard candidate >= lowCutoff else { continue }

            let fundamentalMagnitude = magnitude(atFrequency: candidate, magnitudes: magnitudes, binWidth: binWidth)
            let harmonicBoost = magnitude(atFrequency: candidate * 2, magnitudes: magnitudes, binWidth: binWidth) * 0.5
            let score = fundamentalMagnitude + harmonicBoost

            if fundamentalMagnitude >= peakMagnitude * TunerConfig.harmonicEnergyRatioThreshold,
               score >= bestScore {
                bestScore = score
                bestFrequency = candidate
            }
        }

        return bestFrequency
    }

    private func magnitude(atFrequency frequency: Double, magnitudes: [Float], binWidth: Double) -> Float {
        let index = Int(round(frequency / binWidth))
        guard index > 0, index < magnitudes.count - 1 else { return 0 }
        return magnitudes[index]
    }

    private func applyNoteLock(to rawFrequency: Double) -> Double {
        let roundedMidi = Int(round(TunerConfig.midiNote(for: rawFrequency)))

        if let lockedMidiNote, let lockedTargetFrequency {
            let deviation = abs(TunerConfig.centsBetween(rawFrequency, and: lockedTargetFrequency))

            if deviation > TunerConfig.noteLockWindowCents {
                unlockCount += 1
                if unlockCount >= TunerConfig.noteLockUnlockBuffers {
                    resetNoteLock()
                    return rawFrequency
                }
            } else {
                unlockCount = 0
            }

            let alpha = TunerConfig.frequencySmoothingFactor
            smoothedFrequency = smoothedFrequency > 0
                ? alpha * rawFrequency + (1 - alpha) * smoothedFrequency
                : rawFrequency

            return smoothedFrequency
        }

        let candidateNote = noteFromMidi(roundedMidi)
        let offset = abs(TunerConfig.centsBetween(rawFrequency, and: candidateNote.frequency))

        if roundedMidi == lastCandidateMidiNote, offset <= TunerConfig.noteLockAcquireCents {
            stableNoteCount += 1
        } else {
            lastCandidateMidiNote = roundedMidi
            stableNoteCount = 1
        }

        if stableNoteCount >= TunerConfig.noteLockStableBuffers {
            lockedMidiNote = roundedMidi
            lockedTargetFrequency = candidateNote.frequency
            smoothedFrequency = rawFrequency
            unlockCount = 0
            DispatchQueue.main.async {
                self.isNoteLocked = true
            }
        }

        return rawFrequency
    }

    private func noteFromMidi(_ midiNote: Int) -> DetectedNote {
        let frequency = TunerConfig.frequency(forMidiNote: Double(midiNote))
        return frequencyToNote(frequency: frequency)
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

    private func refineFrequencyWithAutocorrelation(
        samples: [Float],
        sampleRate: Double,
        roughFrequency: Double
    ) -> Double {
        guard roughFrequency > 0, samples.count > 20 else { return roughFrequency }

        let searchRatio = TunerConfig.autocorrelationSearchRatio(for: instrumentMode)
        let roughPeriod = sampleRate / roughFrequency
        let centerLag = Int(round(roughPeriod))
        let searchRange = max(2, Int(round(roughPeriod * searchRatio)))

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
}
