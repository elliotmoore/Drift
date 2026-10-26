import Foundation

/// Every control the engine exposes, with the range and default the UI uses.
/// `key` is the stable name stored in snapshots, so it must never change once shipped.
struct ParamSpec: Identifiable, Hashable {
    let id: drift_param
    var key: String
    let name: String
    let range: ClosedRange<Float>
    var defaultValue: Float
    var bipolar = false
    var integer = false
    /// How far full motion depth moves this parameter (in its own units).
    var motionSpan: Float? = nil
    /// The centre detent of a bipolar slider, if it is not the default value.
    var detent: Float? = nil
    /// Which voice (0-2) this copy belongs to. Voice 0 uses the plain key, so sounds saved
    /// before there were voices load unchanged; voices 2 and 3 add "@2" / "@3".
    var voice = 0

    /// True for the controls each voice has its own copy of (engine, sliders, Drone, Hold,
    /// Level, Triggers and the X/Y routes).
    var perVoice: Bool { drift_is_per_voice(id) != 0 }
    /// The key without its voice suffix, for help text and the pad's up/down target.
    var baseKey: String { voice == 0 ? key : String(key.split(separator: "@")[0]) }

    /// This control's copy for voice `v` (itself for voice 0 or a shared control).
    func forVoice(_ v: Int) -> ParamSpec {
        guard perVoice, v > 0 else { return self }
        var c = self
        c.key = "\(baseKey)@\(v + 1)"
        c.voice = v
        c.defaultValue = P.voiceDefault(self, voice: v)
        return c
    }

    static func == (a: ParamSpec, b: ParamSpec) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }

    var span: Float { range.upperBound - range.lowerBound }
    var center: Float { detent ?? defaultValue }
    var modSpan: Float { motionSpan ?? span * 0.5 }
    func clamp(_ v: Float) -> Float { min(max(v, range.lowerBound), range.upperBound) }
}

extension drift_param: @retroactive Hashable {}

enum P {
    // Voice
    static let engine     = ParamSpec(id: DP_ENGINE, key: "engine", name: "Engine", range: 0...23, defaultValue: 8, integer: true)
    static let note       = ParamSpec(id: DP_NOTE, key: "note", name: "Pitch", range: 24...96, defaultValue: 48, motionSpan: 12)
    static let harmonics  = ParamSpec(id: DP_HARMONICS, key: "harmonics", name: "Harmonics", range: 0...1, defaultValue: 0.5)
    static let timbre     = ParamSpec(id: DP_TIMBRE, key: "timbre", name: "Timbre", range: 0...1, defaultValue: 0.5)
    static let morph      = ParamSpec(id: DP_MORPH, key: "morph", name: "Morph", range: 0...1, defaultValue: 0.5)
    static let fmAmt      = ParamSpec(id: DP_FM_AMT, key: "fmAmt", name: "Env → Pitch", range: -1...1, defaultValue: 0, bipolar: true)
    static let timbreAmt  = ParamSpec(id: DP_TIMBRE_AMT, key: "timbreAmt", name: "Env → Timbre", range: -1...1, defaultValue: 0, bipolar: true)
    static let morphAmt   = ParamSpec(id: DP_MORPH_AMT, key: "morphAmt", name: "Env → Morph", range: -1...1, defaultValue: 0, bipolar: true)
    static let decay      = ParamSpec(id: DP_DECAY, key: "decay", name: "Decay", range: 0...1, defaultValue: 0.5)
    static let lpgColour  = ParamSpec(id: DP_LPG_COLOUR, key: "lpgColour", name: "Gate Colour", range: 0...1, defaultValue: 0.5)
    static let volume     = ParamSpec(id: DP_VOLUME, key: "volume", name: "Volume", range: 0...1, defaultValue: 0.8)
    static let output     = ParamSpec(id: DP_OUTPUT, key: "output", name: "Output", range: 0...3, defaultValue: 0, integer: true)
    static let drone      = ParamSpec(id: DP_DRONE, key: "drone", name: "Drone", range: 0...1, defaultValue: 0, integer: true)
    static let sustain    = ParamSpec(id: DP_SUSTAIN, key: "sustain", name: "Sustain", range: 0...1, defaultValue: 0, integer: true)

    // Sequencer: t
    static let run        = ParamSpec(id: DM_RUN, key: "run", name: "Run", range: 0...1, defaultValue: 0, integer: true)
    static let rate       = ParamSpec(id: DM_RATE, key: "rate", name: "Rate", range: -48...48, defaultValue: 0, bipolar: true, motionSpan: 12)
    static let tRange     = ParamSpec(id: DM_T_RANGE, key: "tRange", name: "Range", range: 0...2, defaultValue: 1, integer: true)
    static let tModel     = ParamSpec(id: DM_T_MODEL, key: "tModel", name: "Model", range: 0...5, defaultValue: 0, integer: true)
    static let tBias      = ParamSpec(id: DM_T_BIAS, key: "tBias", name: "Bias", range: 0...1, defaultValue: 0.5, bipolar: true)
    static let tJitter    = ParamSpec(id: DM_T_JITTER, key: "tJitter", name: "Jitter", range: 0...1, defaultValue: 0)
    static let tDejaVu    = ParamSpec(id: DM_T_DEJAVU, key: "tDejaVu", name: "Déjà Vu", range: 0...1, defaultValue: 0, bipolar: true, detent: 0.5)
    static let gateLen    = ParamSpec(id: DM_GATE_LEN, key: "gateLen", name: "Gate Length", range: 0...1, defaultValue: 0.5)
    static let gateRand   = ParamSpec(id: DM_GATE_RAND, key: "gateRand", name: "Gate Variation", range: 0...1, defaultValue: 0)
    static let length     = ParamSpec(id: DM_LENGTH, key: "length", name: "Loop Length", range: 1...16, defaultValue: 8, integer: true)

    // Sequencer: X and Y
    static let xSpread    = ParamSpec(id: DM_X_SPREAD, key: "xSpread", name: "Spread", range: 0...1, defaultValue: 0.5)
    static let xBias      = ParamSpec(id: DM_X_BIAS, key: "xBias", name: "Bias", range: 0...1, defaultValue: 0.5, bipolar: true)
    static let xSteps     = ParamSpec(id: DM_X_STEPS, key: "xSteps", name: "Steps", range: 0...1, defaultValue: 0.7, bipolar: true)
    static let xDejaVu    = ParamSpec(id: DM_X_DEJAVU, key: "xDejaVu", name: "Déjà Vu", range: 0...1, defaultValue: 0, bipolar: true, detent: 0.5)
    static let xDiversity = ParamSpec(id: DM_X_DIVERSITY, key: "xDiversity", name: "Diversity", range: 0...2, defaultValue: 0, integer: true)
    static let xRange     = ParamSpec(id: DM_X_RANGE, key: "xRange", name: "Range", range: 0...2, defaultValue: 0, integer: true)
    static let xScale     = ParamSpec(id: DM_X_SCALE, key: "xScale", name: "Scale", range: 0...6, defaultValue: 6, integer: true)
    static let ySpread    = ParamSpec(id: DM_Y_SPREAD, key: "ySpread", name: "Spread", range: 0...1, defaultValue: 0.5)
    static let yBias      = ParamSpec(id: DM_Y_BIAS, key: "yBias", name: "Bias", range: 0...1, defaultValue: 0.5, bipolar: true)
    static let ySteps     = ParamSpec(id: DM_Y_STEPS, key: "ySteps", name: "Steps", range: 0...1, defaultValue: 0, bipolar: true)
    static let yDivider   = ParamSpec(id: DM_Y_DIVIDER, key: "yDivider", name: "Divider", range: 0...11, defaultValue: 4, integer: true)

    // Routing
    static let drive      = ParamSpec(id: DR_DRIVE, key: "drive", name: "Plays the Voice", range: 0...1, defaultValue: 1, integer: true)
    static let trigSrc    = ParamSpec(id: DR_TRIG_SRC, key: "trigSrc", name: "Triggers", range: 0...4, defaultValue: 3, integer: true)
    static let x1Dest     = ParamSpec(id: DR_X1_DEST, key: "x1Dest", name: "X1", range: 0...6, defaultValue: 1, integer: true)
    static let x2Dest     = ParamSpec(id: DR_X2_DEST, key: "x2Dest", name: "X2", range: 0...6, defaultValue: 0, integer: true)
    static let x3Dest     = ParamSpec(id: DR_X3_DEST, key: "x3Dest", name: "X3", range: 0...6, defaultValue: 0, integer: true)
    static let yDest      = ParamSpec(id: DR_Y_DEST, key: "yDest", name: "Y", range: 0...6, defaultValue: 0, integer: true)
    static let x1Depth    = ParamSpec(id: DR_X1_DEPTH, key: "x1Depth", name: "X1 Depth", range: -1...1, defaultValue: 1, bipolar: true)
    static let x2Depth    = ParamSpec(id: DR_X2_DEPTH, key: "x2Depth", name: "X2 Depth", range: -1...1, defaultValue: 0.5, bipolar: true)
    static let x3Depth    = ParamSpec(id: DR_X3_DEPTH, key: "x3Depth", name: "X3 Depth", range: -1...1, defaultValue: 0.5, bipolar: true)
    static let xClock     = ParamSpec(id: DM_X_CLOCK, key: "xClock", name: "Clocked By", range: 0...3, defaultValue: 0, integer: true)
    static let voices     = ParamSpec(id: DV_VOICES, key: "voices", name: "Voices", range: 1...3, defaultValue: 1, integer: true)
    static let level      = ParamSpec(id: DP_LEVEL, key: "level", name: "Level", range: 0...1, defaultValue: 1)
    static let burstDiv   = ParamSpec(id: DB_BURST_DIV, key: "burstDiv", name: "Burst Speed", range: 0...5, defaultValue: 3, integer: true)
    static let yDepth     = ParamSpec(id: DR_Y_DEPTH, key: "yDepth", name: "Y Depth", range: -1...1, defaultValue: 0.5, bipolar: true)

    // Effects, on the whole mix. All start off, so older sounds load unchanged.
    static let phOn       = ParamSpec(id: FX_PH_ON, key: "phOn", name: "Phaser", range: 0...1, defaultValue: 0, integer: true)
    static let phRate     = ParamSpec(id: FX_PH_RATE, key: "phRate", name: "Rate", range: 0...1, defaultValue: 0.3)
    static let phDepth    = ParamSpec(id: FX_PH_DEPTH, key: "phDepth", name: "Depth", range: 0...1, defaultValue: 0.7)
    static let phFeedback = ParamSpec(id: FX_PH_FEEDBACK, key: "phFeedback", name: "Feedback", range: 0...1, defaultValue: 0.5)
    static let dlOn       = ParamSpec(id: FX_DL_ON, key: "dlOn", name: "Delay", range: 0...1, defaultValue: 0, integer: true)
    static let dlSync     = ParamSpec(id: FX_DL_SYNC, key: "dlSync", name: "Sync", range: 0...1, defaultValue: 1, integer: true)
    static let dlDiv      = ParamSpec(id: FX_DL_DIV, key: "dlDiv", name: "Time", range: 0...7, defaultValue: 3, integer: true)
    static let dlTime     = ParamSpec(id: FX_DL_TIME, key: "dlTime", name: "Time", range: 0...1, defaultValue: 0.45)
    static let dlFeedback = ParamSpec(id: FX_DL_FEEDBACK, key: "dlFeedback", name: "Feedback", range: 0...1, defaultValue: 0.4)
    static let dlTone     = ParamSpec(id: FX_DL_TONE, key: "dlTone", name: "Tone", range: 0...1, defaultValue: 0.6)
    static let dlMix      = ParamSpec(id: FX_DL_MIX, key: "dlMix", name: "Mix", range: 0...1, defaultValue: 0.35)
    static let dlPingPong = ParamSpec(id: FX_DL_PINGPONG, key: "dlPingPong", name: "Ping-Pong", range: 0...1, defaultValue: 1, integer: true)
    static let rvOn       = ParamSpec(id: FX_RV_ON, key: "rvOn", name: "Reverb", range: 0...1, defaultValue: 0, integer: true)
    static let rvMix      = ParamSpec(id: FX_RV_MIX, key: "rvMix", name: "Mix", range: 0...1, defaultValue: 0.35)
    static let rvSize     = ParamSpec(id: FX_RV_SIZE, key: "rvSize", name: "Size", range: 0...1, defaultValue: 0.5)
    static let rvBright   = ParamSpec(id: FX_RV_BRIGHT, key: "rvBright", name: "Brightness", range: 0...1, defaultValue: 0.6)
    static let rvFreeze   = ParamSpec(id: FX_RV_FREEZE, key: "rvFreeze", name: "Freeze", range: 0...1, defaultValue: 0, integer: true)
    static let brDiv      = ParamSpec(id: FX_BR_DIV, key: "brDiv", name: "Repeat Length", range: 0...5, defaultValue: 3, integer: true)

    private static let base: [ParamSpec] = [
        engine, note, harmonics, timbre, morph, fmAmt, timbreAmt, morphAmt, decay, lpgColour, volume,
        output, drone, sustain,
        run, rate, tRange, tModel, tBias, tJitter, tDejaVu, gateLen, gateRand, length,
        xSpread, xBias, xSteps, xDejaVu, xDiversity, xRange, xScale, ySpread, yBias, ySteps, yDivider,
        drive, trigSrc, x1Dest, x2Dest, x3Dest, yDest, x1Depth, x2Depth, x3Depth, yDepth, xClock, burstDiv,
        voices, level,
        phOn, phRate, phDepth, phFeedback,
        dlOn, dlSync, dlDiv, dlTime, dlFeedback, dlTone, dlMix, dlPingPong,
        rvOn, rvMix, rvSize, rvBright, rvFreeze, brDiv,
    ]

    /// Every control, with voices 2 and 3's copies of the per-voice ones.
    static let all: [ParamSpec] = base + base.filter(\.perVoice).flatMap { [$0.forVoice(1), $0.forVoice(2)] }

    /// Voices 2 and 3 start as a snare on t3 and a hi-hat on t2, not following the melody.
    static func voiceDefault(_ p: ParamSpec, voice v: Int) -> Float {
        switch p.key {
        case "engine": return v == 1 ? 22 : 23
        case "trigSrc": return v == 1 ? 2 : 1
        case "x1Dest": return 0
        default: return p.defaultValue
        }
    }

    static let byKey: [String: ParamSpec] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// Continuous parameters motion can drive, grouped for the target picker.
    static let motionTargets: [(String, [ParamSpec])] = [
        ("Plaits", [note, harmonics, timbre, morph, decay, lpgColour, fmAmt, timbreAmt, morphAmt, volume]),
        ("Clock", [rate, tBias, tJitter, tDejaVu, gateLen, gateRand]),
        ("Random X", [xSpread, xBias, xSteps, xDejaVu]),
        ("Random Y", [ySpread, yBias, ySteps]),
        ("Routing", [x1Depth, x2Depth, x3Depth, yDepth]),
        ("FX", [phRate, phDepth, phFeedback, dlTime, dlFeedback, dlTone, dlMix, rvMix, rvSize, rvBright]),
    ]

    /// The motion target groups, with a Plaits group per voice when there are three.
    static func motionTargetGroups(voices: Bool) -> [(String, [ParamSpec])] {
        guard voices else { return motionTargets }
        let plaits = motionTargets[0].1
        return [("Plaits · Voice 1", plaits)]
            + (1...2).map { v in ("Plaits · Voice \(v + 1)", plaits.map { $0.forVoice(v) }) }
            + motionTargets.dropFirst()
    }

    /// Voice parameters that Nudge and Shuffle may move.
    static let voiceMutable: [ParamSpec] = [harmonics, timbre, morph, fmAmt, timbreAmt, morphAmt, decay, lpgColour]
    static let randomMutable: [ParamSpec] = [tBias, tJitter, gateLen, gateRand, xSpread, xBias, xSteps, ySpread, yBias, ySteps]
}

// MARK: - Engines

struct EngineInfo: Identifiable {
    let id: Int          // Plaits engine index
    let name: String
    let symbol: String
    let summary: String
    let harmonics: String
    let timbre: String
    let morph: String
}

enum Engines {
    /// The engine chips, in this order: the FM engines (2-Op and the three 6-Op banks) sit together.
    static let all: [EngineInfo] = [
        .init(id: 8,  name: "Virtual Analog", symbol: "waveform", summary: "Two detuned analog-style oscillators", harmonics: "Detune", timbre: "Square shape", morph: "Saw shape"),
        .init(id: 9,  name: "Waveshaper", symbol: "waveform.path", summary: "Triangle through a shaper and folder", harmonics: "Shaper curve", timbre: "Fold", morph: "Asymmetry"),
        .init(id: 10, name: "2-Op FM", symbol: "point.3.connected.trianglepath.dotted", summary: "Two sine operators", harmonics: "Ratio", timbre: "Index", morph: "Feedback"),
        .init(id: 2,  name: "6-Op FM I", symbol: "dial.low", summary: "DX-style patches, bank 1", harmonics: "Patch", timbre: "Modulator level", morph: "Envelope stretch"),
        .init(id: 3,  name: "6-Op FM II", symbol: "dial.medium", summary: "DX-style patches, bank 2", harmonics: "Patch", timbre: "Modulator level", morph: "Envelope stretch"),
        .init(id: 4,  name: "6-Op FM III", symbol: "dial.high", summary: "DX-style patches, bank 3", harmonics: "Patch", timbre: "Modulator level", morph: "Envelope stretch"),
        .init(id: 11, name: "Grain Formant", symbol: "mouth", summary: "Formants from windowed sine grains", harmonics: "Formant ratio", timbre: "Formant", morph: "Width"),
        .init(id: 12, name: "Additive", symbol: "chart.bar", summary: "Harmonics shaped by spectral bumps", harmonics: "Bumps", timbre: "Prominent harmonic", morph: "Bump shape"),
        .init(id: 13, name: "Wavetable", symbol: "square.grid.3x3", summary: "Grids of single-cycle waves", harmonics: "Bank", timbre: "Row", morph: "Column"),
        .init(id: 14, name: "Chords", symbol: "pianokeys", summary: "Four-note chords, strings or wavetables", harmonics: "Chord type", timbre: "Voicing", morph: "Waveform"),
        .init(id: 15, name: "Speech", symbol: "waveform.and.mic", summary: "Formant, SAM and LPC speech", harmonics: "Method", timbre: "Speaker size", morph: "Phoneme"),
        .init(id: 16, name: "Swarm", symbol: "ant", summary: "Eight drifting saw grains", harmonics: "Pitch wander", timbre: "Density", morph: "Grain length"),
        .init(id: 17, name: "Filtered Noise", symbol: "wind", summary: "Clocked noise, resonant filter", harmonics: "Filter type", timbre: "Clock", morph: "Resonance"),
        .init(id: 18, name: "Particles", symbol: "drop", summary: "Impulses ringing through filters", harmonics: "Pitch randomness", timbre: "Density", morph: "Filter"),
        .init(id: 19, name: "String", symbol: "guitars", summary: "Plucked or bowed string model", harmonics: "Inharmonicity", timbre: "Brightness", morph: "Decay"),
        .init(id: 20, name: "Modal", symbol: "bell", summary: "Struck bells, bars and plates", harmonics: "Material", timbre: "Brightness", morph: "Decay"),
        .init(id: 21, name: "Kick", symbol: "circle.circle", summary: "Analog-style bass drum", harmonics: "Attack and drive", timbre: "Brightness", morph: "Decay"),
        .init(id: 22, name: "Snare", symbol: "circle.dotted", summary: "Analog-style snare", harmonics: "Tone or noise", timbre: "Tone", morph: "Decay"),
        .init(id: 23, name: "Hi-Hat", symbol: "sparkle", summary: "Metallic hat", harmonics: "Metal or noise", timbre: "Brightness", morph: "Decay"),
        .init(id: 0,  name: "Filtered Analog", symbol: "slider.horizontal.below.square.filled.and.square", summary: "Classic waveforms through a filter", harmonics: "Resonance", timbre: "Cutoff", morph: "Waveform"),
        .init(id: 1,  name: "Phase Distortion", symbol: "scribble.variable", summary: "Casio-style phase distortion", harmonics: "Ratio", timbre: "Amount", morph: "Asymmetry"),
        .init(id: 5,  name: "Wave Terrain", symbol: "mountain.2", summary: "A path across a 2D terrain", harmonics: "Terrain", timbre: "Path radius", morph: "Path offset"),
        .init(id: 6,  name: "String Machine", symbol: "music.note.list", summary: "Ensemble strings and organ", harmonics: "Chord", timbre: "Chorus and filter", morph: "Waveform"),
        .init(id: 7,  name: "Chiptune", symbol: "gamecontroller", summary: "Square waves and arpeggios", harmonics: "Chord", timbre: "Arpeggio", morph: "Pulse width"),
    ]

    static func info(_ index: Int) -> EngineInfo {
        all.first { $0.id == index } ?? all[0]
    }
}

enum Names {
    static let tModels = ["Coin Toss", "Clusters", "Drums", "Independent", "Divider", "Three States"]
    static let tRanges = ["¼×", "1×", "4×"]
    static let scales = ["Same as Pad", "Major", "Minor", "Pentatonic", "Pelog", "Bhairav", "Shri"]
    /// Chip order above -> engine scale index (6 = the pad's scale).
    static let scaleIndex = [6, 0, 1, 2, 3, 4, 5]
    static let xRanges = ["0–2 V", "0–5 V", "±5 V"]
    static let diversity = ["Identical", "Bump", "Tilt"]
    static let dividers = ["1/64", "1/48", "1/32", "1/24", "1/16", "1/12", "1/8", "1/6", "1/4", "1/3", "1/2", "1/1"]
    static let triggers = ["t1", "t2", "t3", "t1 + t3", "Off"]
    static let dests = ["Off", "Pitch", "Harmonics", "Timbre", "Morph", "Level", "Engine"]
    static let xClocks = ["Own t", "t1", "t2", "t3"]
    static let burstDivs = ["1/4", "1/8", "1/8T", "1/16", "1/16T", "1/32"]
    static let delayDivs = ["1/16", "1/8T", "1/8", "1/8.", "1/4", "1/4.", "1/2", "1 bar"]

    /// Déjà Vu, read the way the module's knob is: random, locked in the middle, jumbled.
    static func dejaVu(_ v: Float) -> String {
        if v < 0.01 { return "Random" }
        if abs(v - 0.5) < 0.005 { return "Locked" }
        if v > 0.99 { return "Jumbled" }
        return v < 0.5 ? "\(Int((v / 0.5 * 100).rounded()))% repeat" : "\(Int(((v - 0.5) / 0.5 * 100).rounded()))% jumble"
    }
    static let outputs = ["Main", "Aux", "Mix", "Split"]
    static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    static func note(_ semis: Float) -> String {
        let n = Int(semis.rounded())
        let cents = Int(((semis - Float(n)) * 100).rounded())
        let base = "\(noteNames[((n % 12) + 12) % 12])\(n / 12 - 1)"
        return cents == 0 ? base : base + String(format: " %+d¢", cents)
    }
}
