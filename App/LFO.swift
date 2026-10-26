import Foundation
import QuartzCore

/// Two LFOs that work like the gyro: motion sources you can give to any slider.
/// Not Mutable Instruments code -- a simple, gentle LFO -- but it can follow Marbles' beat.
enum LFOShape: String, CaseIterable, Codable, Identifiable {
    case sine, triangle, rampUp, rampDown, square, smoothRandom, stepRandom

    var id: String { rawValue }
    var name: String {
        switch self {
        case .sine: "Sine"
        case .triangle: "Triangle"
        case .rampUp: "Ramp Up"
        case .rampDown: "Ramp Down"
        case .square: "Square"
        case .smoothRandom: "Smooth Random"
        case .stepRandom: "Step Random"
        }
    }
}

/// What's saved with a sound.
struct LFOSettings: Codable, Hashable {
    var shape: LFOShape = .sine
    /// Cycles per second when free-running, 0.02 (one every 50 s) to 8.
    var rate: Float = 0.25
    /// Follow Marbles' beat instead of `rate` (free-running while Marbles is stopped).
    var sync = false
    /// Index into `LFOSettings.divisions`.
    var division = 2

    /// Beats per cycle when synced: 4 bars, 2 bars, 1 bar, 2 beats, 1 beat, half a beat.
    static let divisions: [(name: String, beats: Double)] = [
        ("4 bars", 16), ("2 bars", 8), ("1 bar", 4), ("2 beats", 2), ("1 beat", 1), ("½ beat", 0.5),
    ]

    func sanitized() -> LFOSettings {
        var s = self
        s.rate = rate.isFinite ? min(max(rate, 0.02), 8) : 0.25
        s.division = min(max(division, 0), Self.divisions.count - 1)
        return s
    }
}

/// The running LFOs: phases and the random values, ticked 60 times a second.
final class LFOBank {
    private(set) var values: [Float] = [0, 0]
    private var phase: [Double] = [0, 0]
    private var randFrom: [Float] = [0, 0]
    private var randTo: [Float] = [Float.random(in: -1...1), Float.random(in: -1...1)]
    private var last = CACurrentMediaTime()

    /// Advance both LFOs. While Marbles plays, synced ones read its beat position.
    func tick(_ settings: [LFOSettings], beatPosition: Double?, bpm: Float) {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 0.1)
        last = now
        for k in 0..<min(2, settings.count) {
            let s = settings[k]
            let old = phase[k]
            if s.sync, let beats = beatPosition {
                let cycle = LFOSettings.divisions[s.division].beats
                phase[k] = (beats / cycle).truncatingRemainder(dividingBy: 1)
            } else if s.sync {
                // Marbles stopped: keep moving at the synced rate for its tempo.
                let cycle = LFOSettings.divisions[s.division].beats
                phase[k] = (phase[k] + dt * Double(bpm) / 60 / cycle).truncatingRemainder(dividingBy: 1)
            } else {
                phase[k] = (phase[k] + dt * Double(s.rate)).truncatingRemainder(dividingBy: 1)
            }
            if phase[k] < old {                      // a new cycle: the next random value
                randFrom[k] = randTo[k]
                randTo[k] = Float.random(in: -1...1)
            }
            values[k] = shape(s.shape, Float(phase[k]), k)
        }
    }

    private func shape(_ s: LFOShape, _ p: Float, _ k: Int) -> Float {
        switch s {
        case .sine: return sinf(2 * .pi * p)
        case .triangle: return p < 0.5 ? 4 * p - 1 : 3 - 4 * p
        case .rampUp: return 2 * p - 1
        case .rampDown: return 1 - 2 * p
        case .square: return p < 0.5 ? 1 : -1
        case .stepRandom: return randTo[k]
        case .smoothRandom:
            let t = (1 - cosf(.pi * p)) / 2              // eased, so it glides
            return randFrom[k] + (randTo[k] - randFrom[k]) * t
        }
    }
}
