import MediaPlayer

/// AirPods, headphone remotes, the lock screen and Control Center: play/pause there
/// starts Marbles or stops everything. iOS only sends these to the app that is "now
/// playing", which is why the audio session doesn't mix with other apps (AudioEngine).
extension Synth {
    /// Marbles playing, or any voice droning: something you'd want a pause button to stop.
    var sounding: Bool {
        running || (0..<(voicesOn ? 3 : 1)).contains { bool(P.drone.forVoice($0)) }
    }

    /// Silence: Marbles stops, every drone goes off, every held note is let go.
    func stopEverything() {
        set(P.run, 0)
        for v in 0..<3 { set(P.drone.forVoice(v), 0) }
        releaseAll()
    }

    func setUpRemoteControl() {
        let center = MPRemoteCommandCenter.shared()
        // Called on the main thread.
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.set(P.run, 1) }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.stopEverything() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.stopEverything() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.sounding { self.stopEverything() } else { self.set(P.run, 1) }
            }
            return .success
        }
        updateNowPlaying()
    }

    /// What the lock screen and Control Center show, and whether they offer play or pause.
    func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Drift",
            MPMediaItemPropertyArtist: running ? "Marbles playing \(engine.name)" : engine.name,
            MPNowPlayingInfoPropertyPlaybackRate: sounding ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
    }
}
