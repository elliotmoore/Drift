import Foundation
import Observation
import UIKit

// MARK: - State that can be saved

enum PadScale: String, CaseIterable, Codable, Identifiable {
    case chromatic, major, minor, pentatonic, minorPentatonic, dorian, phrygian, lydian, mixolydian, blues, wholeTone
    var id: String { rawValue }
    var name: String {
        switch self {
        case .chromatic: "Chromatic"
        case .major: "Major"
        case .minor: "Minor"
        case .pentatonic: "Pentatonic"
        case .minorPentatonic: "Minor Pentatonic"
        case .dorian: "Dorian"
        case .phrygian: "Phrygian"
        case .lydian: "Lydian"
        case .mixolydian: "Mixolydian"
        case .blues: "Blues"
        case .wholeTone: "Whole Tone"
        }
    }
    var shortName: String {
        switch self {
        case .minorPentatonic: "Minor Pent."
        case .pentatonic: "Pentatonic"
        case .wholeTone: "Whole Tone"
        default: name
        }
    }
    var degrees: [Int] {
        switch self {
        case .chromatic: Array(0..<12)
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .minor: [0, 2, 3, 5, 7, 8, 10]
        case .pentatonic: [0, 2, 4, 7, 9]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        case .dorian: [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: [0, 1, 3, 5, 7, 8, 10]
        case .lydian: [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: [0, 2, 4, 5, 7, 9, 10]
        case .blues: [0, 3, 5, 6, 7, 10]
        case .wholeTone: [0, 2, 4, 6, 8, 10]
        }
    }
}

struct PadSettings: Codable, Hashable {
    var scale: PadScale = .minorPentatonic
    var root = 0                 // 0 = C
    var lowOctave = 2            // C2 = MIDI 36
    var octaves = 3
    var yTargetKey = P.timbre.key
    /// Up and down follows whichever pad-friendly slider was touched last.
    var yFollow = true

    /// The sliders up and down may move.
    static let yTargets = [P.harmonics, P.timbre, P.morph, P.decay, P.lpgColour, P.timbreAmt, P.morphAmt, P.fmAmt]

    init() {}

    // Written by hand so settings saved before a field existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PadSettings()
        scale = try c.decodeIfPresent(PadScale.self, forKey: .scale) ?? d.scale
        root = try c.decodeIfPresent(Int.self, forKey: .root) ?? d.root
        lowOctave = try c.decodeIfPresent(Int.self, forKey: .lowOctave) ?? d.lowOctave
        octaves = try c.decodeIfPresent(Int.self, forKey: .octaves) ?? d.octaves
        yTargetKey = try c.decodeIfPresent(String.self, forKey: .yTargetKey) ?? d.yTargetKey
        yFollow = try c.decodeIfPresent(Bool.self, forKey: .yFollow) ?? d.yFollow
    }

    /// The notes of the pad, low to high, in MIDI semitones.
    var notes: [Int] {
        let base = (lowOctave + 1) * 12 + root
        var out: [Int] = []
        for o in 0..<octaves { for d in scale.degrees { out.append(base + o * 12 + d) } }
        out.append(base + octaves * 12)
        return out
    }
}

struct PatchState: Codable, Hashable {
    var values: [String: Float]
    var motion: [MotionSlot]
    var pad: PadSettings
    var seed: UInt32
    var lfos: [LFOSettings] = PatchState.defaultLFOs

    static let defaultLFOs = [LFOSettings(), LFOSettings(shape: .smoothRandom, rate: 0.1)]

    static var initial: PatchState {
        PatchState(values: Dictionary(uniqueKeysWithValues: P.all.map { ($0.key, $0.defaultValue) }),
                   motion: [MotionSlot(source: .tiltSide, targetKey: P.timbre.key, depth: 0.6),
                            MotionSlot(source: .tiltForward, targetKey: P.morph.key, depth: 0.6)],
                   pad: PadSettings(), seed: 1)
    }

    enum CodingKeys: String, CodingKey { case values, motion, pad, seed, lfos }

    init(values: [String: Float], motion: [MotionSlot], pad: PadSettings, seed: UInt32,
         lfos: [LFOSettings] = PatchState.defaultLFOs) {
        self.values = values; self.motion = motion; self.pad = pad; self.seed = seed; self.lfos = lfos
    }

    // Written by hand so sounds saved before the LFOs existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        values = try c.decode([String: Float].self, forKey: .values)
        motion = try c.decode([MotionSlot].self, forKey: .motion)
        pad = try c.decode(PadSettings.self, forKey: .pad)
        seed = try c.decode(UInt32.self, forKey: .seed)
        lfos = try c.decodeIfPresent([LFOSettings].self, forKey: .lfos) ?? PatchState.defaultLFOs
    }
}

extension PatchState {
    /// Every value pulled back inside its range, unknown keys dropped and missing ones
    /// filled in, so nothing read from disk can index past the end of a list.
    func sanitized() -> PatchState {
        var s = self
        var v: [String: Float] = [:]
        for p in P.all {
            let raw = values[p.key] ?? p.defaultValue
            let x = raw.isFinite ? raw : p.defaultValue
            v[p.key] = p.clamp(p.integer ? x.rounded() : x)
        }
        s.values = v
        s.motion = motion.compactMap { slot in
            guard P.byKey[slot.targetKey] != nil else { return nil }
            var m = slot
            m.depth = slot.depth.isFinite ? min(max(slot.depth, -1), 1) : 0.6
            return m
        }
        s.pad.root = min(max(pad.root, 0), 11)
        s.pad.lowOctave = min(max(pad.lowOctave, 0), 5)
        s.pad.octaves = min(max(pad.octaves, 1), 5)
        if !pad.yTargetKey.isEmpty && P.byKey[pad.yTargetKey] == nil { s.pad.yTargetKey = P.timbre.key }
        if seed == 0 { s.seed = 1 }
        s.lfos = (lfos + PatchState.defaultLFOs).prefix(2).map { $0.sanitized() }
        return s
    }
}

struct Snapshot: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var date = Date()
    var state: PatchState
    /// Who made it, if it came from someone (nil = yours, not shared yet).
    var author: String? = nil
    /// The licence it was shared under: see `License`.
    var license: String? = nil
    /// The sound it was made from, e.g. "'Friend's Bell' by Elliot Moore".
    var basedOn: String? = nil

    var engineName: String { Engines.info(Int(state.values[P.engine.key] ?? 8)).name }
}

// MARK: - The model

/// Owns every value the UI shows, applies motion on top, and keeps the engine in sync.
@MainActor
@Observable
final class Synth {
    private(set) var state: PatchState
    /// What motion is adding to each parameter right now (for the slider ghosts).
    private(set) var motionOffsets: [String: Float] = [:]
    var snapshots: [Snapshot] = []
    /// The last few minutes of changes, newest first, so a lost sound can be found again.
    private(set) var history: [Snapshot] = []

    let motion = MotionInput()
    let audio = AudioEngine()

    private var pushed: [String: Float] = [:]
    private var syncedPadBase = Int.min
    private var syncedPad: PadSettings?
    private var historyTimer: Timer?
    private let store = Store()

    init() {
        drift_init()
        state = store.loadCurrent() ?? .initial
        snapshots = store.loadSnapshots()
        history = store.loadHistory()
        motion.onUpdate = { [weak self] in self?.applyMotion() }
        pushAll()
        syncPadScale()
        drift_reseed(state.seed)
    }

    func start() {
        audio.start()                  // retries if the first start failed
        if motionEnabled { motion.start() }
        startLFOs()
        if !remoteReady { remoteReady = true; setUpRemoteControl() }
    }

    /// AirPods and lock-screen controls are set up once (RemoteControl.swift).
    private var remoteReady = false

    // MARK: LFOs

    let lfo = LFOBank()
    private var lfoTimer: Timer?

    var lfoSettings: [LFOSettings] {
        get { state.lfos }
        set { state.lfos = newValue.map { $0.sanitized() }; scheduleHistory() }
    }

    /// The LFOs tick 60 times a second, but only do work when one is assigned.
    private func startLFOs() {
        guard lfoTimer == nil else { return }
        lfoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickLFOs() }
        }
    }

    private func tickLFOs() {
        guard motionEnabled else { return }
        var m = drift_meters()
        drift_meters_read(&m)
        let beats: Double? = running ? Double(m.beats) + Double(m.ramp) : nil
        lfo.tick(state.lfos, beatPosition: beats, bpm: m.bpm)
        lfoValues = lfo.values                       // also drives the Motion sheet's meters
        if state.motion.contains(where: { $0.source.lfoIndex != nil }) { applyMotion() }
    }

    /// The LFOs' current values, for the Motion sheet's meters.
    private(set) var lfoValues: [Float] = [0, 0]

    /// A motion source's current value: the phone's movement or an LFO.
    func sourceValue(_ s: MotionSource) -> Float {
        if let k = s.lfoIndex { return lfoValues[k] }
        return motion.values[s] ?? 0
    }

    /// The master switch for the gyro. Off returns every motion offset to zero and stops
    /// the sensors; assignments are kept for when it comes back on. An app setting, not
    /// part of a saved sound.
    var motionEnabled: Bool = UserDefaults.standard.object(forKey: "motionEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(motionEnabled, forKey: "motionEnabled")
            motionEnabled ? motion.start() : motion.stop()
            applyMotion()
        }
    }

    // MARK: Values

    func value(_ p: ParamSpec) -> Float { state.values[p.key] ?? p.defaultValue }
    func int(_ p: ParamSpec) -> Int { Int(value(p).rounded()) }
    func bool(_ p: ParamSpec) -> Bool { value(p) >= 0.5 }

    /// The value the engine is actually hearing, motion included.
    func effective(_ p: ParamSpec) -> Float { p.clamp(value(p) + (motionOffsets[p.key] ?? 0)) }

    func set(_ p: ParamSpec, _ v: Float) {
        let v = p.clamp(p.integer ? v.rounded() : v)
        guard state.values[p.key] != v else { return }
        state.values[p.key] = v
        push(p)
        if p == P.note { syncPadScale() }
        if p == P.run || p.baseKey == P.drone.key || p.baseKey == P.engine.key { updateNowPlaying() }
        scheduleHistory()
    }

    func set(_ p: ParamSpec, _ v: Int) { set(p, Float(v)) }
    func toggle(_ p: ParamSpec) { set(p, bool(p) ? 0 : 1) }
    func reset(_ p: ParamSpec) { set(p, p.defaultValue) }

    var running: Bool { bool(P.run) }

    // MARK: Voices

    /// Three voices sounding, or just one (the app as it was).
    var voicesOn: Bool { int(P.voices) >= 3 }

    /// The voice the Plaits page, Routing, the pad and the strip are working on. Not saved
    /// with sounds: it's where you are, not part of the sound.
    var selectedVoice: Int = UserDefaults.standard.integer(forKey: "selectedVoice") {
        didSet { UserDefaults.standard.set(selectedVoice, forKey: "selectedVoice") }
    }
    /// The voice actually being played and edited: always voice 1 with one voice.
    var activeVoice: Int { voicesOn ? min(max(selectedVoice, 0), 2) : 0 }

    /// A per-voice control's copy for the active voice; shared controls come back as is.
    func sv(_ p: ParamSpec) -> ParamSpec { p.forVoice(activeVoice) }

    func setVoices(_ on: Bool) {
        releaseAll()
        set(P.voices, on ? 3 : 1)
        if !on { selectedVoice = 0 }
    }

    /// The engine the active voice is set to.
    var engine: EngineInfo { Engines.info(int(sv(P.engine))) }

    var pad: PadSettings {
        get { state.pad }
        set { state.pad = newValue; syncPadScale(); scheduleHistory() }
    }

    /// Hands the pad's key and scale to Marbles, for its "Same as Pad" scale. Marbles'
    /// notes are added to the voice's current note, so the scale is written relative to
    /// it: wherever the pitch sits, Marbles lands on notes of the pad's key.
    func syncPadScale() {
        // The pitch Plaits is actually on, motion included, so a gyro bend of whole
        // semitones keeps Marbles in the pad's key.
        let base = Int(effective(P.note).rounded())
        guard base != syncedPadBase || state.pad != syncedPad else { return }
        syncedPadBase = base
        syncedPad = state.pad
        let pad = state.pad
        var degrees: [(Float, UInt8)] = []
        for d in pad.scale.degrees {
            let rel = ((pad.root + d - base) % 12 + 12) % 12
            let weight: UInt8 = d == 0 ? 255 : d == 7 ? 192 : (d == 3 || d == 4) ? 160 : 128
            degrees.append((Float(rel), weight))
        }
        degrees.sort { $0.0 < $1.0 }
        let semis = degrees.map(\.0), weights = degrees.map(\.1)
        drift_set_pad_scale(semis, weights, Int32(semis.count))
    }

    // MARK: Playing

    /// One surface's finger down or up. Counted in the engine, so the pad, the Scope and the
    /// burst strip can overlap without cutting each other's notes.
    func gate(_ on: Bool) { drift_gate_v(Int32(activeVoice), on ? 1 : 0) }
    /// A new note under the same finger.
    func strike() { drift_strike_v(Int32(activeVoice)) }
    /// Let go of everything -- the app is leaving the screen.
    func releaseAll() { drift_gate_reset(); burst(false); strip(false); beatRepeat(false) }

    /// A finger is on the burst strip. Over a drone, that chops it (see DriftEngine).
    func strip(_ on: Bool) {
        if on { drift_set(DB_VOICE, Float(activeVoice)) }   // the strip plays the active voice
        drift_set(DB_STRIP, on ? 1 : 0)
    }

    /// Wakes' burst: re-strike at Burst Speed while held. A performance gesture, not saved.
    func burst(_ on: Bool) { drift_set(DB_BURST, on ? 1 : 0) }

    /// Beat Repeat held (FX tab). Momentary, so not part of the sound.
    func beatRepeat(_ on: Bool) { drift_set(FX_BR_HOLD, on ? 1 : 0) }

    /// A slider was touched. If the pad follows focus and this is something up and down
    /// can move, it becomes the pad's up and down.
    func focus(_ p: ParamSpec) {
        guard state.pad.yFollow, state.pad.yTargetKey != p.baseKey,
              PadSettings.yTargets.contains(where: { $0.key == p.baseKey }) else { return }
        state.pad.yTargetKey = p.baseKey
    }

    /// New Loop only makes an audible difference once Marbles is repeating itself.
    var dejaVuActive: Bool { value(P.tDejaVu) >= 0.02 || value(P.xDejaVu) >= 0.02 }

    // MARK: Catch and Keep

    /// How many beats the caught loop is; 0 = nothing caught. Not saved.
    private(set) var caughtBeats = 0
    /// Bumped when a Catch fails (not enough played yet), for a haptic.
    private(set) var catchMissed = 0

    /// Loop what Marbles just played (the last Loop Length beats, Y included), or let go.
    func toggleCatch() {
        if caughtBeats > 0 { releaseCatch(); return }
        guard running else { catchMissed += 1; return }
        drift_catch(1)
        // The audio thread catches between blocks; read back how much it got.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard let self else { return }
            var m = drift_meters()
            drift_meters_read(&m)
            self.caughtBeats = Int(m.caught_beats)
            if m.caught_beats == 0 { drift_catch(0); self.catchMissed += 1 }
        }
    }

    func releaseCatch() {
        guard caughtBeats > 0 else { return }
        drift_catch(0)
        caughtBeats = 0
    }

    /// Makes the sound you're hearing right now the starting point: whatever Marbles' X/Y
    /// (Harmonics, Timbre, Morph, Engine) and the gyro are adding goes into the sliders,
    /// and those Marbles routes are switched off. Pitch routes stay, so the melody goes on.
    func keepThisSound() {
        recordHistory()
        changeLabel = "Keep This Sound"
        var m = drift_meters()
        drift_meters_read(&m)
        if running {
            let volts = [m.volts.0, m.volts.1, m.volts.2, m.volts.3]
            let engines = [m.engines.0, m.engines.1, m.engines.2]
            // Every sounding voice: each has its own routes.
            for voice in 0..<(voicesOn ? 3 : 1) {
                let dests = [P.x1Dest, P.x2Dest, P.x3Dest, P.yDest].map { $0.forVoice(voice) }
                let depths = [P.x1Depth, P.x2Depth, P.x3Depth, P.yDepth].map { $0.forVoice(voice) }
                // Same scaling as the engine: +-5 V at full depth moves a parameter +-1.
                for k in 0..<4 {
                    let v = volts[k] * value(depths[k]) * 0.2
                    let target: ParamSpec
                    switch UInt32(int(dests[k])) {
                    case DD_HARMONICS.rawValue: target = P.harmonics.forVoice(voice)
                    case DD_TIMBRE.rawValue: target = P.timbre.forVoice(voice)
                    case DD_MORPH.rawValue: target = P.morph.forVoice(voice)
                    case DD_ENGINE.rawValue:
                        set(P.engine.forVoice(voice), Int(engines[voice])); set(dests[k], 0); continue
                    default: continue
                    }
                    set(target, value(target) + v)
                    set(dests[k], 0)
                }
            }
        }
        // The gyro: what it adds becomes the slider value, and "level" is reset to here so
        // it doesn't add it again.
        for (key, _) in motionOffsets {
            if let p = P.byKey[key] { set(p, effective(p)) }
        }
        motion.recenter()
        scheduleHistory()
    }

    func reseed() {
        releaseCatch()   // you asked for something new
        labelNextChange("New Loop")
        state.seed = UInt32.random(in: 1...UInt32.max)
        drift_reseed(state.seed)
        scheduleHistory()
    }

    /// Small random moves around where you are now.
    func nudge(_ params: [ParamSpec], amount: Float = 0.08) {
        for p in params {
            set(p, value(p) + Float.random(in: -amount...amount) * p.span)
        }
    }

    /// Anywhere at all, within the parameters given.
    func shuffle(_ params: [ParamSpec]) {
        for p in params {
            if p.bipolar && p.range.lowerBound < 0 {
                // Envelope amounts: mostly gentle, sometimes wild.
                set(p, Float.random(in: -1...1) * Float.random(in: 0...1))
            } else {
                set(p, Float.random(in: p.range))
            }
        }
    }

    // MARK: Motion

    var motionSlots: [MotionSlot] {
        get { state.motion }
        set { state.motion = newValue; applyMotion(); scheduleHistory() }
    }

    func slots(for p: ParamSpec) -> [MotionSlot] { state.motion.filter { $0.targetKey == p.key } }

    func assign(_ source: MotionSource, to p: ParamSpec) {
        if let i = state.motion.firstIndex(where: { $0.source == source && $0.targetKey == p.key }) {
            state.motion.remove(at: i)
        } else {
            state.motion.append(MotionSlot(source: source, targetKey: p.key, depth: 0.6))
        }
        applyMotion()
        scheduleHistory()
    }

    func clearMotion(for p: ParamSpec) {
        state.motion.removeAll { $0.targetKey == p.key }
        applyMotion()
        scheduleHistory()
    }

    private func applyMotion() {
        var offsets: [String: Float] = [:]
        for slot in state.motion where motionEnabled {
            guard let p = P.byKey[slot.targetKey] else { continue }
            offsets[p.key, default: 0] += slot.depth * sourceValue(slot.source) * p.modSpan
        }
        guard offsets != motionOffsets else { return }   // nothing moved: no redraws
        let touched = Set(offsets.keys).union(motionOffsets.keys)
        motionOffsets = offsets
        for key in touched { if let p = P.byKey[key] { push(p) } }
        if touched.contains(P.note.key) { syncPadScale() }
    }

    // MARK: Engine sync

    private func push(_ p: ParamSpec) {
        let v = effective(p)
        guard pushed[p.key] != v else { return }
        pushed[p.key] = v
        drift_set_v(Int32(p.voice), p.id, v)
        if p == P.run { UIApplication.shared.isIdleTimerDisabled = v >= 0.5 }
    }

    private func pushAll() {
        pushed.removeAll()
        for p in P.all { push(p) }
    }

    // MARK: Snapshots and history

    /// Puts sounds at the top of Saved (imports).
    func addToSaved(_ sounds: [Snapshot]) {
        snapshots.insert(contentsOf: sounds, at: 0)
        store.saveSnapshots(snapshots)
    }

    /// The credit of the sound you loaded, if it came from someone else, for what you save.
    var origin: String?

    /// What to tell you after an import (shown as an alert), or nil.
    var importMessage: String?

    /// Imports a file sent to Drift (Messages, Files, AirDrop) and says how it went.
    func importFile(_ url: URL) {
        do {
            let n = try importSounds(from: url)
            importMessage = n == 1 ? "1 sound added to Saved." : "\(n) sounds added to Saved."
        } catch {
            importMessage = "That file couldn't be read as Drift sounds."
        }
    }

    func saveSnapshot(name: String? = nil) {
        let n = name ?? "\(engine.name) · \(Date().formatted(date: .omitted, time: .shortened))"
        // Made from someone else's sound? Say so, so the credit travels with it.
        snapshots.insert(Snapshot(name: n, state: captureState(), basedOn: origin), at: 0)
        store.saveSnapshots(snapshots)
    }


    /// Back to the sound and sequence the app starts with, like pulling every cable.
    /// Keeps motion assignments, pad settings and the transport; what you had goes into
    /// the history first, so it can be found again.
    func resetToDefault() {
        recordHistory()
        changeLabel = "Reset to Default"
        releaseCatch()
        origin = nil
        let run = state.values[P.run.key] ?? 0
        state.values = PatchState.initial.values
        state.values[P.run.key] = run
        state.seed = PatchState.initial.seed
        pushAll()
        syncPadScale()
        applyMotion()
        drift_reseed(state.seed)
        persist()
    }

    // MARK: Browsing the Library

    /// Records where you are, once, when the Library opens -- so browsing can't lose it.
    func checkpoint() { recordHistory() }

    /// Plays a sound from the Library without recording anything, so browsing through
    /// Recent Changes doesn't reshuffle them. The transport stays as it is.
    func audition(_ s: Snapshot) {
        apply(s.state)
        origin = s.author != nil ? s.originLine : s.basedOn
        // Make it heard: if nothing is playing (no Drone, Marbles stopped), play a note.
        guard !running && !bool(sv(P.drone)) else { return }
        gate(true)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.gate(false)
        }
    }

    /// Copies a Recent Changes entry into Saved.
    func promote(_ s: Snapshot) {
        let name = "\(s.engineName) · \(s.date.formatted(date: .omitted, time: .shortened))"
        snapshots.insert(Snapshot(name: name, state: s.state), at: 0)
        store.saveSnapshots(snapshots)
    }

    func rename(_ s: Snapshot, to name: String) {
        guard let i = snapshots.firstIndex(of: s) else { return }
        snapshots[i].name = name
        store.saveSnapshots(snapshots)
    }

    func delete(_ s: Snapshot) {
        snapshots.removeAll { $0.id == s.id }
        store.saveSnapshots(snapshots)
    }

    func persist() {
        store.saveCurrent(captureState())
        store.saveHistory(history)
    }

    private func captureState() -> PatchState {
        var s = state
        s.seed = state.seed
        return s
    }

    /// What the next Recent Changes entry is called, when a wand item or button made it.
    private var changeLabel: String?

    /// Names the change about to happen ("Shuffle"). Anything still waiting to be
    /// recorded is recorded first, so it doesn't get the name too.
    func labelNextChange(_ label: String) {
        if historyTimer?.isValid == true { recordHistory() }
        changeLabel = label
    }

    private func scheduleHistory() {
        historyTimer?.invalidate()
        historyTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordHistory() }
        }
    }

    // MARK: Undo and redo

    /// Where in `history` the current sound is: 0 = the newest. Undo walks it backwards.
    private(set) var historyCursor = 0
    var canUndo: Bool { historyCursor + 1 < history.count || (historyCursor == 0 && history.first?.state != captureState() && !history.isEmpty) }
    var canRedo: Bool { historyCursor > 0 }

    func undo() {
        // A change still inside the 1.5 s window is recorded first, so it can be redone.
        if historyCursor == 0 { recordHistory() }
        guard historyCursor + 1 < history.count else { return }
        historyCursor += 1
        apply(history[historyCursor].state)
    }

    func redo() {
        guard historyCursor > 0 else { return }
        historyCursor -= 1
        apply(history[historyCursor].state)
    }

    /// Removes entries from Recent Changes. Saved sounds are never touched.
    func deleteHistory(at offsets: IndexSet) {
        let before = offsets.filter { $0 < historyCursor }.count
        if offsets.contains(historyCursor) {
            historyCursor = 0          // the current sound's entry went; undo restarts from the top
        } else {
            historyCursor -= before
        }
        history.remove(atOffsets: offsets)
        historyCursor = min(historyCursor, max(history.count - 1, 0))
        store.saveHistory(history)
    }

    /// Empties Recent Changes. Saved sounds are never touched.
    func clearHistory() {
        history.removeAll()
        historyCursor = 0
        store.saveHistory(history)
    }

    /// Puts a recorded sound back without recording it again.
    private func apply(_ s: PatchState) {
        historyTimer?.invalidate()
        origin = nil
        releaseCatch()
        let wasRunning = running
        state = s
        state.values[P.run.key] = wasRunning ? 1 : 0
        pushAll()
        syncPadScale()
        applyMotion()
        drift_reseed(state.seed)
        updateNowPlaying()
        store.saveCurrent(state)
    }

    private func recordHistory() {
        historyTimer?.invalidate()
        let s = captureState()
        if historyCursor < history.count, history[historyCursor].state == s { return }
        // A new change after undoing starts a new branch from here.
        if historyCursor > 0 { history.removeFirst(min(historyCursor, history.count)); historyCursor = 0 }
        if history.first?.state == s { return }
        let name = changeLabel ?? Self.describeChange(from: history.first?.state, to: s)
        changeLabel = nil
        history.insert(Snapshot(name: name, state: s), at: 0)
        if history.count > 100 { history.removeLast(history.count - 100) }
        // Written as you go (about 100 KB at most), so a force-quit loses nothing.
        store.saveCurrent(s)
        store.saveHistory(history)
    }
}

// MARK: - Files

/// JSON files in Application Support. Small, readable and easy to back up.
private struct Store {
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func read<T: Decodable>(_ name: String) -> T? {
        let url = dir.appending(path: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let value = try? JSONDecoder().decode(T.self, from: data) { return value }
        setAside(url)
        return nil
    }

    /// A list where one bad entry costs only that entry, not the whole file.
    private func readList(_ name: String) -> [Snapshot] {
        let url = dir.appending(path: name)
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let items = try? JSONDecoder().decode([Lossy<Snapshot>].self, from: data) else {
            setAside(url)
            return []
        }
        let good = items.compactMap(\.value)
        if good.count < items.count { try? data.write(to: dir.appending(path: name + ".unreadable"), options: .atomic) }
        return good.map { var s = $0; s.state = s.state.sanitized(); return s }
    }

    /// A file that can't be read is kept (one copy, replaced each time) instead of being
    /// overwritten by the next save, so nothing is lost and nothing piles up.
    private func setAside(_ url: URL) {
        let spare = url.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: spare)
        try? FileManager.default.moveItem(at: url, to: spare)
    }

    /// Encodes and writes off the main thread, in order, so saving never stalls the UI.
    private static let queue = DispatchQueue(label: "drift.store", qos: .utility)
    private func write<T: Encodable & Sendable>(_ value: T, _ name: String) {
        let url = dir.appending(path: name)
        Self.queue.async {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadCurrent() -> PatchState? {
        guard var s: PatchState = read("current.json") else { return nil }
        s = s.sanitized()   // fills in anything added since, and clamps everything
        // Always start silent: Marbles stopped and Drone off, whatever was going when the
        // app was closed. (Saved sounds keep their Drone setting; this is only the launch.)
        s.values[P.run.key] = 0
        for v in 0..<3 { s.values[P.drone.forVoice(v).key] = 0 }
        return s
    }
    func saveCurrent(_ s: PatchState) { write(s, "current.json") }
    func loadSnapshots() -> [Snapshot] { readList("snapshots.json") }
    func saveSnapshots(_ s: [Snapshot]) { write(s, "snapshots.json") }
    func loadHistory() -> [Snapshot] { readList("history.json") }
    func saveHistory(_ s: [Snapshot]) { write(s, "history.json") }
}

/// Decodes an element if it can, or nil instead of failing the whole list.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
