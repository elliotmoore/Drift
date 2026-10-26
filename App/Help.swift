import SwiftUI

/// Plain-language explanations, shown when a slider is long-pressed and behind the ⓘ
/// buttons on the Marbles page.
enum Help {
    static func text(for p: ParamSpec, engine: EngineInfo) -> String? {
        switch p.baseKey {
        case P.note.key: return "The base pitch. The pad sets it when you play, and Marbles' melody is added on top of it."
        case P.harmonics.key: return "On \(engine.name): \(engine.harmonics.lowercased()). Each engine uses Harmonics, Timbre and Morph differently, so the same position sounds different on another engine."
        case P.timbre.key: return "On \(engine.name): \(engine.timbre.lowercased()). Usually the brightness or character of the sound."
        case P.morph.key: return "On \(engine.name): \(engine.morph.lowercased()). Usually the shape or texture of the sound."
        case P.decay.key: return "How long each struck note rings. Short for plucks and hits, long for bells and pads. With Hold, how long a note takes to fade after you let go."
        case P.lpgColour.key: return "Low: notes close like a filter, getting darker as they fade, the classic Buchla-style pluck. High: they just get quieter."
        case P.fmAmt.key: return "How much each strike bends the pitch. Positive drops from above, like a laser or tom; negative swoops up. Middle is off."
        case P.timbreAmt.key: return "How much each strike moves Timbre. The note starts brighter (positive) or darker (negative) and settles back. Middle is off."
        case P.morphAmt.key: return "How much each strike moves Morph, the same way as Env → Timbre. Middle is off."
        case P.level.key: return "This voice's level in the mix of the three voices. Volume, which sets the overall level, returns when you go back to one voice."
        case P.volume.key: return "Output level. Up to about 80 the sound is clean; above that a limiter rounds off the loudest peaks, so you get louder without harsh clipping."
        case P.rate.key: return "The speed of Marbles' clock. ¼× and 4× beside it change the range."
        case P.tBias.key: return "In Coin Toss: which of t1 or t3 wins more often. In other models it shapes density or pattern. Middle is even."
        case P.tJitter.key: return "Makes the timing loose. At 0 the beats are on a perfect grid; higher drifts them like a human or a broken clock."
        case P.tDejaVu.key: return "Memory for the rhythm, as on Marbles. Left: always new. Towards the middle it repeats more, and at the middle it locks into a loop of Loop Length steps. Right of the middle it stays in the loop but jumps around it; fully right plays the loop in random order. The lock button jumps straight to Locked; double-tap the slider, or press New Loop, for a new loop."
        case P.length.key: return "How many steps the Déjà Vu loop has, for both rhythm and melody. Marbles' own knob offers 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14 and 16."
        case P.gateLen.key: return "How long each gate stays open. With Hold on (Plaits page), this is how long each Marbles note lasts."
        case P.gateRand.key: return "Randomises each gate's length around Gate Length."
        case P.xSpread.key: return "How far the melody jumps. Fully left: one constant voltage. Middle: a bell curve around the centre. Two-thirds: every value equally likely. Fully right: only the lowest and highest, so the X outputs act like random gates."
        case P.xBias.key: return "Leans the melody low or high in its range. Middle is centred."
        case P.xSteps.key: return "Middle: classic stepped random. Left: smoother, then gliding lines, then smooth curves. Right: snapped to the scale, then the scale is stripped back note by note until only the root is left."
        case P.xDejaVu.key: return "Memory for the melody, like Déjà Vu on the Clock tab: left is always new, the middle locks the notes into a loop, right jumbles the loop's order. The lock button jumps straight to Locked; double-tap the slider for a new loop."
        case P.ySpread.key, P.yBias.key: return "Y is a slow random voltage, ticking at a division of the clock. Send it somewhere in Routing."
        case P.ySteps.key: return "Left: Y glides smoothly. Right: it jumps in steps."
        case P.yDivider.key: return "How often Y changes, as a fraction of X2's clock. 1/16 by default, as on the module."
        case P.phRate.key: return "How fast the phaser sweeps, from one slow pass every half-minute to a fast warble."
        case P.phDepth.key: return "How far the sweep travels. Low is a subtle shimmer; high swoops from low to high."
        case P.phFeedback.key: return "Feeds the phaser back into itself: the notches get sharper and the sound more resonant and metallic."
        case P.dlTime.key: return "Time between echoes, from a 20 ms slapback to 2 seconds. Moving it while echoes are sounding bends their pitch, like tape."
        case P.dlFeedback.key: return "How much of each echo comes back again: low for one or two repeats, high for long trails. Near the top it keeps going almost for ever."
        case P.dlTone.key: return "The colour of the echoes. Dark makes each repeat duller, like an old tape delay; bright keeps them clear."
        case P.dlMix.key: return "How loud the echoes are against the dry sound."
        case P.rvMix.key: return "How much of the sound goes through the reverb. All the way right is only the reverb."
        case P.rvSize.key: return "How long the reverb lasts, from a small room to a long hall, over the same range as on Rings."
        case P.rvBright.key: return "How bright the reverb is. Low is dark and soft, high is airy."
        case P.x1Depth.key, P.x2Depth.key, P.x3Depth.key, P.yDepth.key:
            return "How strongly this output moves its destination. Negative turns it upside down."
        default: return nil
        }
    }

    static let liveView = """
    t1, t2, t3 are Marbles' three rhythm outputs, the same as the hardware's gate jacks. t2 is the steady clock; t1 and t3 are the random ones (in Coin Toss each beat goes to one or the other).

    X1, X2, X3 are its three random melody voltages, and Y is a slower fourth one. The lines on the right trace X1 (blue), X2 (pink), X3 (green) and Y (purple) over the last two seconds. X lines use the X range's scale and Y its own ±5 V; each meter uses the same scale as its line. Outputs not routed anywhere are drawn faint. Underneath, the first row says which rhythm plays each voice (t3 → Snare) and the second where each voltage goes (X1 → Pitch).

    The Loop number names the current set of random values: it changes when you press New Loop, and comes back with a saved sound. Catch loops the last few beats exactly as they were played, Y included.
    """

    static let scope = """
    Wave: the sound itself, held steady on the note so you can see its shape change as you move the sliders.

    Spectrum: the sound split into frequencies, low on the left, high on the right. Peaks are harmonics; Harmonics and Timbre move them around.

    Out × Aux: Plaits' two outputs plotted against each other. A line means they move together; loops and clouds show how different Aux is.

    Touch the display to play a note. Wave and Spectrum show what you hear (the Output setting on the pad).
    """

    static let phaser = "A phaser sweeps notches up and down through the sound, for that swirling, jet-plane movement. It works on everything, Marbles and pad alike.\n\nRate, Depth and Feedback can be given to motion or an LFO like any slider."
    static let delay = "Echoes. Follow Marbles' Beat keeps them in time with Marbles' tempo (Rate on the Clock tab), even while Marbles is stopped: 1/8. is a dotted eighth, 1/8T an eighth-note triplet. Free sets the time yourself.\n\nPing-Pong bounces the echoes between left and right; use headphones to hear it."
    static let reverb = "The reverb from Mutable Instruments' Rings (and Elements), from Émilie Gillet's code, set up as on the module.\n\nFreeze, from Elements, holds whatever the reverb is ringing and stops taking in new sound, so you can play over a frozen cloud. Switch it off to let the tail fade."
    static let beatRepeat = "Hold to repeat the current slice of the beat, effects and all, like a DJ stutter. Where your finger is sets the slice: 1× repeats a whole beat, 8× a 32nd. Slide while holding to change it.\n\nWith Marbles playing, slices start on the beat, so repeats stay in time. Let go and the music carries on."
    static let clock = "Clock shapes when things happen: the speed, which of t1 and t3 fire, how loose the timing is, and whether the rhythm repeats."
    static let x = "X makes three random voltages, X1, X2 and X3, that change on the beat. Send them somewhere in Routing to hear them: X1 to Pitch is the classic random melody.\n\nThe sliders shape them: how far they jump, whether they glide or snap to a scale, and whether they repeat. Same as Pad keeps Marbles in the pad's key.\n\nClocked By: Own t means X1 changes on t1, X2 on t2 and X3 on t3. Pick one t to make all three change together, like patching it into the module's X clock input."
    static let y = "Y is a slow random voltage of its own, good for gradually moving a parameter. Send it somewhere in Routing to hear it.\n\nDivider sets how often it changes, as a fraction of the clock. Déjà Vu never repeats Y; use Catch to keep a moment of it."
    static let routing = "Routing decides what Marbles does to Plaits.\n\nTriggers: which rhythm strikes Plaits. All three t lights keep flashing whatever you choose; only the chosen ones play notes. Off, or Drone on the Plaits page, lets Marbles move the sound without striking it.\n\nVoltages: where X1–X3 and Y go, and how strongly (Depth). X1 to Pitch is the classic random melody. Engine works like Plaits' Model input: the engine changes on each strike."
}

/// A small ⓘ that shows a short explanation in a popover.
struct InfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Help")
        .popover(isPresented: $shown) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(idealWidth: 320)
                .presentationCompactAdaptation(.popover)
        }
    }
}
