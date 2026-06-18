//
//  MetronomeNowPlayingController.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

#if canImport(UIKit)
import MediaPlayer
#endif

@MainActor
final class MetronomeNowPlayingController {
    private weak var engine: MetronomeEngine?
    private var isConfigured = false

    func configure(with engine: MetronomeEngine) {
        self.engine = engine
        guard !isConfigured else { return }
        isConfigured = true
        configureRemoteCommands()
    }

    func update(bpm: Double, timeSignature: TimeSignature, isRunning: Bool) {
        #if canImport(UIKit)
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = "\(Int(bpm.rounded())) BPM"
        info[MPMediaItemPropertyArtist] = "\(timeSignature.displayName) Time Signature"
        info[MPMediaItemPropertyAlbumTitle] = "Sonance Metronome"
        info[MPNowPlayingInfoPropertyPlaybackRate] = isRunning ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    func clear() {
        #if canImport(UIKit)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }

    private func configureRemoteCommands() {
        #if canImport(UIKit)
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.handlePlayCommand()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handlePauseCommand()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleToggleCommand()
            return .success
        }

        [
            center.nextTrackCommand,
            center.previousTrackCommand,
            center.skipForwardCommand,
            center.skipBackwardCommand,
            center.seekForwardCommand,
            center.seekBackwardCommand,
            center.changePlaybackRateCommand,
            center.changeRepeatModeCommand,
            center.changeShuffleModeCommand
        ].forEach { $0.isEnabled = false }
        #endif
    }

    private func handlePlayCommand() {
        Task { @MainActor in
            guard let engine, !engine.isRunning else { return }
            engine.start()
        }
    }

    private func handlePauseCommand() {
        Task { @MainActor in
            guard let engine, engine.isRunning else { return }
            engine.stop()
        }
    }

    private func handleToggleCommand() {
        Task { @MainActor in
            engine?.toggle()
        }
    }
}
