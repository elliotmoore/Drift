import AVFoundation

/// Pulls audio from the C engine through an AVAudioSourceNode at 48 kHz, Plaits' native
/// rate. The session asks for a 5 ms buffer, so a touch is heard almost at once.
///
/// All setup runs on its own queue: talking to the system audio service can block (for
/// seconds, in the Simulator), and that must never hold up the screen.
final class AudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var configured = false
    private let queue = DispatchQueue(label: "drift.audio", qos: .userInteractive)

    /// Safe to call again (e.g. on returning to the app): a failed start is retried.
    func start() {
        queue.async {
            if self.configured { self.startEngine() } else { self.setUp() }
        }
    }

    private func setUp() {
        configured = true
        let session = AVAudioSession.sharedInstance()
        do {
            // Not mixed with other apps: iOS only sends AirPods and lock-screen play/pause to
            // an app that isn't mixing. Starting Drift pauses other apps' music.
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Audio session: \(error)")
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let node = Self.makeSourceNode(format: format)
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        startEngine()

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            if type == .ended { self?.restart() }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.restart()
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            self?.restart()
        }
    }

    private func restart() {
        queue.async { self.startEngine() }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            print("Audio engine: \(error)")
        }
    }

    /// Built outside any actor: the render block runs on the real-time audio thread.
    private nonisolated static func makeSourceNode(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            drift_render(l, r, frameCount)
            return noErr
        }
    }
}
