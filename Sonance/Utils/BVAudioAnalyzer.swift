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
final class AudioAnalyzer: ObservableObject {
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

    private var realParts: [Float] = []
    private var imaginaryParts: [Float] = []
    private var magnitudes: [Float] = []
    private var hanningWindow: [Float] = []
    private var windowedSamples: [Float] = []
    private var spectralScratch: [Float] = []

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
    @Published private(set) var detectedNote: DetectedNote = .empty
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
            self.detectedNote = .empty
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
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
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
        ensureProcessingBuffers()
    }

    private func ensureProcessingBuffers() {
        guard realParts.count != bufferSizePOT else { return }

        realParts = [Float](repeating: 0, count: bufferSizePOT)
        imaginaryParts = [Float](repeating: 0, count: bufferSizePOT)
        magnitudes = [Float](repeating: 0, count: bufferSizePOT / 2)
        windowedSamples = [Float](repeating: 0, count: bufferSizePOT)
        spectralScratch = [Float](repeating: 0, count: max(1, bufferSizePOT / 2 - 5))
        hanningWindow = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: bufferSizePOT,
            isHalfWindow: false
        )
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
            self.detectedNote = .empty
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
            self.detectedNote = .empty
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
              let fftSetup = fftSetup,
              !hanningWindow.isEmpty else { return }

        let channelData = floatChannelData.pointee
        let bufferLength = Int(buffer.frameLength)
        let lowCutoff = TunerConfig.lowFrequencyCutoff(for: instrumentMode)

        let copyCount = min(bufferLength, bufferSizePOT)
        realParts.withUnsafeMutableBufferPointer { realBuffer in
            guard let realBase = realBuffer.baseAddress else { return }
            vDSP_vclr(realBase, 1, vDSP_Length(bufferSizePOT))
            realBase.update(from: channelData, count: copyCount)
        }

        if currentInputGain != 1 {
            var gain = currentInputGain
            vDSP_vsmul(realParts, 1, &gain, &realParts, 1, vDSP_Length(bufferSizePOT))
        }

        vDSP.multiply(hanningWindow, realParts, result: &realParts)

        windowedSamples.withUnsafeMutableBufferPointer { windowBuffer in
            realParts.withUnsafeBufferPointer { realBuffer in
                guard let windowBase = windowBuffer.baseAddress,
                      let realBase = realBuffer.baseAddress else { return }
                windowBase.update(from: realBase, count: copyCount)
            }
        }

        var signalLevel: Float = 0
        windowedSamples.withUnsafeBufferPointer { samples in
            vDSP_rmsqv(samples.baseAddress!, 1, &signalLevel, vDSP_Length(copyCount))
        }

        realParts.withUnsafeMutableBufferPointer { realBuffer in
            imaginaryParts.withUnsafeMutableBufferPointer { imagBuffer in
                guard let realBase = realBuffer.baseAddress,
                      let imagBase = imagBuffer.baseAddress else { return }

                vDSP_vclr(imagBase, 1, vDSP_Length(bufferSizePOT))
                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)

                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(bufferSizePOT / 2))

                let spectralStart = 5
                let spectralCount = magnitudes.count - spectralStart
                guard spectralCount > 0 else {
                    deliverResults(amplitude: signalLevel, frequency: 0)
                    return
                }

                var maxMagnitude: Float = 0
                magnitudes.withUnsafeBufferPointer { buffer in
                    let slice = UnsafeBufferPointer(rebasing: buffer[spectralStart...])
                    vDSP_maxv(slice.baseAddress!, 1, &maxMagnitude, vDSP_Length(spectralCount))
                }
                let medianMagnitude = spectralMedian(from: magnitudes, start: spectralStart, count: spectralCount)
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

                guard let peak = selectAnalysisPeak(
                    magnitudes: magnitudes,
                    binWidth: binWidth,
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

                let refinedFrequency = windowedSamples.withUnsafeBufferPointer { samples in
                    refineFrequencyWithAutocorrelation(
                        samples: samples,
                        sampleCount: copyCount,
                        sampleRate: sampleRate,
                        roughFrequency: roughFrequency
                    )
                }

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

    /// Picks the FFT peak to analyze. While locked, prefers the in-window peak for stability,
    /// but falls back to the global peak when the signal clearly moved (e.g. octave jump).
    private func selectAnalysisPeak(
        magnitudes: [Float],
        binWidth: Double,
        lowCutoff: Double
    ) -> (index: Int, magnitude: Float)? {
        guard let globalPeak = findStrongestPeak(
            magnitudes: magnitudes,
            binWidth: binWidth,
            minHz: nil,
            maxHz: nil,
            lowCutoff: lowCutoff
        ) else { return nil }

        guard let lockedTargetFrequency,
              let searchRange = lockSearchRangeHz() else {
            return globalPeak
        }

        let globalFrequency = Double(globalPeak.index) * binWidth
        let globalDeviation = abs(TunerConfig.centsBetween(globalFrequency, and: lockedTargetFrequency))

        if globalDeviation <= TunerConfig.noteLockWindowCents {
            return findStrongestPeak(
                magnitudes: magnitudes,
                binWidth: binWidth,
                minHz: searchRange.min,
                maxHz: searchRange.max,
                lowCutoff: lowCutoff
            ) ?? globalPeak
        }

        if let localPeak = findStrongestPeak(
            magnitudes: magnitudes,
            binWidth: binWidth,
            minHz: searchRange.min,
            maxHz: searchRange.max,
            lowCutoff: lowCutoff
        ) {
            let localFrequency = Double(localPeak.index) * binWidth
            let localDeviation = abs(TunerConfig.centsBetween(localFrequency, and: lockedTargetFrequency))
            let keepsLock = localDeviation <= TunerConfig.noteLockWindowCents
                && localPeak.magnitude >= globalPeak.magnitude * TunerConfig.harmonicEnergyRatioThreshold

            if keepsLock {
                return localPeak
            }
        }

        resetNoteLock()
        return globalPeak
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

    private func resolvedDetectedNote(for frequency: Double) -> DetectedNote {
        if let lockedMidiNote, let lockedTargetFrequency {
            return noteFromLockedTarget(
                frequency: frequency,
                lockedMidiNote: lockedMidiNote,
                lockedTargetFrequency: lockedTargetFrequency
            )
        }
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
        let noteToPublish = resolvedDetectedNote(for: frequencyToPublish)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.amplitude = amplitudeToPublish
            self.frequency = frequencyToPublish
            self.detectedNote = noteToPublish
        }
    }

    private func spectralMedian(from magnitudes: [Float], start: Int, count: Int) -> Float {
        guard count > 0, spectralScratch.count >= count else { return 0 }

        magnitudes.withUnsafeBufferPointer { buffer in
            spectralScratch.withUnsafeMutableBufferPointer { scratch in
                guard let source = buffer.baseAddress?.advanced(by: start),
                      let destination = scratch.baseAddress else { return }
                destination.update(from: source, count: count)
            }
        }

        spectralScratch.withUnsafeMutableBufferPointer { scratch in
            guard let base = scratch.baseAddress else { return }
            var slice = UnsafeMutableBufferPointer(start: base, count: count)
            slice.sort(by: <)
        }
        return spectralScratch[count / 2]
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
        samples: UnsafeBufferPointer<Float>,
        sampleCount: Int,
        sampleRate: Double,
        roughFrequency: Double
    ) -> Double {
        guard roughFrequency > 0, sampleCount > 20 else { return roughFrequency }

        let searchRatio = TunerConfig.autocorrelationSearchRatio(for: instrumentMode)
        let roughPeriod = sampleRate / roughFrequency
        let centerLag = Int(round(roughPeriod))
        let searchRange = max(2, Int(round(roughPeriod * searchRatio)))

        let minLag = max(2, centerLag - searchRange)
        let maxLag = min(sampleCount - 2, centerLag + searchRange)
        guard minLag < maxLag else { return roughFrequency }

        var correlations: [(lag: Int, value: Float)] = []
        correlations.reserveCapacity(maxLag - minLag + 1)

        for lag in minLag...maxLag {
            correlations.append((lag, normalizedAutocorrelation(samples: samples, sampleCount: sampleCount, lag: lag)))
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

    private func normalizedAutocorrelation(samples: UnsafeBufferPointer<Float>, sampleCount: Int, lag: Int) -> Float {
        let count = sampleCount - lag
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
