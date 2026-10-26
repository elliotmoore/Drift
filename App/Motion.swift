import CoreMotion
import Foundation
import Observation

/// The ways the phone's movement can be read, each normalised to -1...1 (or 0...1).
enum MotionSource: String, CaseIterable, Codable, Identifiable {
    case tiltSide, tiltForward, twist, tiltAmount, shake, lfo1, lfo2

    var id: String { rawValue }
    var name: String {
        switch self {
        case .tiltSide: "Tilt Sideways"
        case .tiltForward: "Tilt Forward"
        case .twist: "Twist"
        case .tiltAmount: "All Tilt"
        case .shake: "Shake"
        case .lfo1: "LFO 1"
        case .lfo2: "LFO 2"
        }
    }
    var symbol: String {
        switch self {
        case .tiltSide: "arrow.left.and.right"
        case .tiltForward: "arrow.up.and.down"
        case .twist: "arrow.triangle.2.circlepath"
        case .tiltAmount: "move.3d"
        case .shake: "iphone.radiowaves.left.and.right"
        case .lfo1: "waveform.path"
        case .lfo2: "waveform.path.badge.plus"
        }
    }
    var bipolar: Bool { self != .tiltAmount && self != .shake }
    /// 0 or 1 for the LFOs, nil for the phone's movement.
    var lfoIndex: Int? { self == .lfo1 ? 0 : self == .lfo2 ? 1 : nil }
    /// The phone's own movement (what the sensors read).
    static let movement: [MotionSource] = [.tiltSide, .tiltForward, .twist, .tiltAmount, .shake]
}

/// One assignment: a motion source moving a parameter by `depth` of its motion span.
struct MotionSlot: Identifiable, Codable, Hashable {
    var id = UUID()
    var source: MotionSource
    var targetKey: String
    var depth: Float = 0.6
}

/// Reads device motion at 60 Hz. Tilt is measured relative to a reference attitude
/// captured by `recenter()`, so "level" is however you were holding the phone.
@MainActor
@Observable
final class MotionInput {
    private(set) var values: [MotionSource: Float] = [:]
    private(set) var available: Bool
    var frozen = false
    /// Degrees of tilt that reach full scale. Smaller = more sensitive.
    var tiltRange: Double = 40

    /// Stands in for the sensors where there are none (the Simulator).
    var virtualTilt: CGPoint = .zero { didSet { if !available { updateVirtual() } } }
    var virtualTwist: Double = 0 { didSet { if !available { updateVirtual() } } }

    var onUpdate: (() -> Void)?

    private let manager = CMMotionManager()
    private var reference: CMAttitude?
    private var shakeLevel: Float = 0
    private var virtualShake: Float = 0
    private var shakeTimer: Timer?

    init() {
        available = manager.isDeviceMotionAvailable
        for s in MotionSource.allCases { values[s] = 0 }
    }

    func start() {
        guard available, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            MainActor.assumeIsolated { self.consume(motion) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func recenter() {
        reference = nil
        if !available {
            virtualTilt = .zero
            virtualTwist = 0
        }
    }

    /// The Simulator's stand-in for a shake: a burst that decays.
    func virtualShakeBurst() {
        virtualShake = 1
        shakeTimer?.invalidate()
        shakeTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                self.virtualShake *= 0.94
                if self.virtualShake < 0.01 { self.virtualShake = 0; t.invalidate() }
                self.updateVirtual()
            }
        }
    }

    private func consume(_ motion: CMDeviceMotion) {
        if reference == nil { reference = motion.attitude.copy() as? CMAttitude }
        guard !frozen else { return }
        let a = motion.attitude.copy() as! CMAttitude
        if let reference { a.multiply(byInverseOf: reference) }

        let full = tiltRange * .pi / 180
        let side = Float(clamp(a.roll / full))
        let forward = Float(clamp(-a.pitch / full))
        let twist = Float(clamp(-a.yaw / (full * 2)))

        let acc = motion.userAcceleration
        let g = Float(sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z))
        // Fast attack, slow release, so a flick reads as a swell rather than a click.
        let target = min(max((g - 0.15) / 1.5, 0), 1)
        shakeLevel = target > shakeLevel ? shakeLevel + (target - shakeLevel) * 0.6 : shakeLevel * 0.96

        publish(side: side, forward: forward, twist: twist, shake: shakeLevel)
    }

    private func updateVirtual() {
        guard !frozen else { return }
        publish(side: Float(virtualTilt.x), forward: Float(-virtualTilt.y),
                twist: Float(virtualTwist), shake: virtualShake)
    }

    private func publish(side: Float, forward: Float, twist: Float, shake: Float) {
        values[.tiltSide] = side
        values[.tiltForward] = forward
        values[.twist] = twist
        values[.tiltAmount] = min(sqrt(side * side + forward * forward), 1)
        values[.shake] = shake
        onUpdate?()
    }

    private func clamp(_ x: Double) -> Double { min(max(x, -1), 1) }
}
