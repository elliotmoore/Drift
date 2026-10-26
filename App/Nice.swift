import Foundation

/// "Something Nice": random, but only inside ranges that sound pleasant. Each engine has
/// a sweet spot for Harmonics, Timbre and Morph, worked out from what those controls do
/// on the module (see the Plaits manual and Guide.swift); noisy, spoken and percussive
/// engines are left out.
enum Nice {
    struct Spot {
        let engine: Int
        let harmonics: ClosedRange<Float>
        let timbre: ClosedRange<Float>
        let morph: ClosedRange<Float>
        /// Exact Harmonics values to choose from instead of a range (chords, ratios).
        var harmonicsChoices: [Float]? = nil
    }

    /// Chords' Harmonics picks one of 11 chord types; these are m7, m9, 6/9, maj9, maj7.
    private static let warmChords: [Float] = [4, 5, 7, 8, 9].map { (Float($0) + 0.5) / 11 }

    static let spots: [Spot] = [
        // Virtual Analog: a little detune, square not too thin, saw-ish
        Spot(engine: 8, harmonics: 0.42...0.58, timbre: 0.25...0.5, morph: 0.35...0.7),
        // Waveshaper: gentle folding, near-symmetrical
        Spot(engine: 9, harmonics: 0.3...0.6, timbre: 0.05...0.35, morph: 0.4...0.6),
        // 2-op FM: low index (no clang), gentle feedback
        Spot(engine: 10, harmonics: 0.25...0.55, timbre: 0.1...0.35, morph: 0.45...0.58),
        // Grain formant: vowel-like, not squeaky
        Spot(engine: 11, harmonics: 0.4...0.6, timbre: 0.3...0.6, morph: 0.2...0.5),
        // Additive: a few soft bumps around the lower harmonics
        Spot(engine: 12, harmonics: 0.1...0.4, timbre: 0.2...0.5, morph: 0.3...0.7),
        // Wavetable: the smooth, interpolated banks
        Spot(engine: 13, harmonics: 0.0...0.45, timbre: 0.2...0.6, morph: 0.2...0.8),
        // Chords: warm chord types, string-machine half of Morph
        Spot(engine: 14, harmonics: 0...1, timbre: 0.3...0.6, morph: 0.1...0.45, harmonicsChoices: warmChords),
        // Swarm: supersaw -- moderate wander and density, full overlap
        Spot(engine: 16, harmonics: 0.1...0.3, timbre: 0.3...0.6, morph: 0.75...0.95),
        // String: the harmonic zone of Harmonics, medium brightness, long decay
        Spot(engine: 19, harmonics: 0.22...0.3, timbre: 0.3...0.6, morph: 0.5...0.85),
        // Modal: bell-ish materials, long decay
        Spot(engine: 20, harmonics: 0.2...0.5, timbre: 0.3...0.6, morph: 0.5...0.85),
        // Filtered analog: low resonance, mid cutoff
        Spot(engine: 0, harmonics: 0.1...0.4, timbre: 0.3...0.6, morph: 0.2...0.6),
        // String machine: warm chords and chorus
        Spot(engine: 6, harmonics: 0...1, timbre: 0.3...0.6, morph: 0.2...0.6, harmonicsChoices: warmChords),
    ]

    static let scales: [PadScale] = [.pentatonic, .minorPentatonic, .major, .dorian]

    /// The drums' sweet spots, for voices 2 and 3 when they're a kit: round kick, crisp
    /// snare, a soft closed hat.
    static let drumSpots: [Spot] = [
        Spot(engine: 21, harmonics: 0.3...0.5, timbre: 0.3...0.5, morph: 0.35...0.6),
        Spot(engine: 22, harmonics: 0.3...0.6, timbre: 0.4...0.6, morph: 0.3...0.5),
        Spot(engine: 23, harmonics: 0.3...0.6, timbre: 0.5...0.75, morph: 0.15...0.35),
    ]
}

extension Synth {
    /// Something Nice: a pleasant sound and sequence, all of it at once. Every voice that's
    /// on gets a sweet spot (a gentle engine, or a well-set drum if it's a drum voice),
    /// Marbles gets a calm in-key sequence, and the routing is set so Marbles plays them
    /// musically, with a touch of reverb (and sometimes delay). The transport, Drone and Hold
    /// stay as they are. Undo brings back what you had.
    func somethingNice() {
        niceMarbles()
        set(P.drive, 1)
        for v in 0..<(voicesOn ? 3 : 1) {
            let isDrum = (21...23).contains(int(P.engine.forVoice(v)))
            if v > 0 && isDrum { niceDrum(v) } else { niceVoice(v) }
        }
        niceFX()
    }

    /// A little space: always some reverb, sometimes a soft echo in time. No phaser, no
    /// freeze; the effects you'd reach for to make a sound feel finished.
    private func niceFX() {
        set(P.rvOn, 1)
        set(P.rvFreeze, 0)
        set(P.rvMix, Float.random(in: 0.2...0.38))
        set(P.rvSize, Float.random(in: 0.4...0.7))
        set(P.rvBright, Float.random(in: 0.45...0.7))
        set(P.phOn, 0)
        if Bool.random() {
            set(P.dlOn, 1)
            set(P.dlSync, 1)
            set(P.dlDiv, [2, 3, 4].randomElement()!)      // 1/8, dotted 1/8, 1/4
            set(P.dlFeedback, Float.random(in: 0.25...0.45))
            set(P.dlTone, Float.random(in: 0.35...0.6))
            set(P.dlMix, Float.random(in: 0.15...0.3))
            set(P.dlPingPong, 1)
        } else {
            set(P.dlOn, 0)
        }
    }

    /// A gentle engine at its sweet spot, a soft envelope. Voice 1 plays Marbles' X1 melody;
    /// voices 2 and 3, if they're tonal too, follow X2 and X3 (same scale, so they agree).
    private func niceVoice(_ v: Int) {
        let p = { (spec: ParamSpec) in spec.forVoice(v) }
        let spot = Nice.spots.randomElement()!
        set(p(P.engine), spot.engine)
        set(p(P.harmonics), spot.harmonicsChoices?.randomElement() ?? Float.random(in: spot.harmonics))
        set(p(P.timbre), Float.random(in: spot.timbre))
        set(p(P.morph), Float.random(in: spot.morph))
        set(p(P.decay), Float.random(in: 0.5...0.75))
        set(p(P.lpgColour), Float.random(in: 0.3...0.7))
        set(p(P.timbreAmt), Float.random(in: 0...0.3))
        set(p(P.morphAmt), Float.random(in: -0.15...0.15))
        set(p(P.fmAmt), 0)
        set(p(P.level), v == 0 ? 1 : 0.7)
        // Melody from X1 (X2, X3 for the other voices), a little slow movement from Y.
        let melody = [P.x1Dest, P.x2Dest, P.x3Dest]
        for (k, dest) in melody.enumerated() { set(p(dest), k == v ? 1 : 0) }
        set(p([P.x1Depth, P.x2Depth, P.x3Depth][v]), 1)
        if Bool.random() {
            set(p(P.yDest), 3)                                  // Timbre
            set(p(P.yDepth), Float.random(in: 0.15...0.3))
        } else {
            set(p(P.yDest), 0)
        }
        // Voice 1: every other beat (t1) or every beat (t1 + t3). The others keep their rhythm.
        if v == 0 { set(p(P.trigSrc), [0, 3].randomElement()!) }
        else if int(p(P.trigSrc)) == Names.triggers.count - 1 { set(p(P.trigSrc), v == 1 ? 2 : 1) }
    }

    /// A drum voice: same drum, set in its sweet spot, on its own rhythm, not following the melody.
    private func niceDrum(_ v: Int) {
        let p = { (spec: ParamSpec) in spec.forVoice(v) }
        let spot = Nice.drumSpots.first { $0.engine == int(p(P.engine)) } ?? Nice.drumSpots[1]
        set(p(P.harmonics), Float.random(in: spot.harmonics))
        set(p(P.timbre), Float.random(in: spot.timbre))
        set(p(P.morph), Float.random(in: spot.morph))
        set(p(P.decay), Float.random(in: 0.35...0.6))
        set(p(P.timbreAmt), 0)
        set(p(P.morphAmt), 0)
        set(p(P.fmAmt), 0)
        set(p(P.level), Float.random(in: 0.55...0.7))
        for dest in [P.x1Dest, P.x2Dest, P.x3Dest, P.yDest] { set(p(dest), 0) }
        if int(p(P.trigSrc)) == Names.triggers.count - 1 { set(p(P.trigSrc), v == 1 ? 2 : 1) }
    }

    /// A pleasant sequence: in key with the pad, on the scale, calm and a little repetitive.
    private func niceMarbles() {
        var p = pad
        p.scale = Nice.scales.randomElement()!
        pad = p
        set(P.xScale, 6)                                  // Same as Pad
        set(P.xSteps, Float.random(in: 0.62...0.8))        // on the scale, strong notes
        set(P.xSpread, Float.random(in: 0.3...0.5))        // modest jumps
        set(P.xBias, Float.random(in: 0.4...0.6))
        set(P.xRange, 0)                                  // two octaves
        set(P.tModel, [0, 3].randomElement()!)            // Coin Toss or Independent
        set(P.tBias, Float.random(in: 0.4...0.6))
        set(P.tJitter, Float.random(in: 0...0.1))
        set(P.rate, Float.random(in: -5...3))             // about 85-140 BPM at 1x
        set(P.gateLen, Float.random(in: 0.4...0.7))
        set(P.gateRand, Float.random(in: 0...0.2))
        set(P.tDejaVu, Float.random(in: 0.25...0.45))     // repeats, but still moves
        set(P.xDejaVu, Float.random(in: 0.25...0.45))
    }
}
