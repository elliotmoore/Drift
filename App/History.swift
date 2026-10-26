import Foundation

/// Names for Recent Changes, worked out from what changed: "Timbre → 72",
/// "Voice 2 · Engine → Kick", "New Loop", "4 changes".
extension Synth {
    static func describeChange(from old: PatchState?, to new: PatchState) -> String {
        let voices = (new.values[P.voices.key] ?? 1) >= 3
        guard let old else { return Engines.info(Int(new.values[P.engine.key] ?? 8)).name }
        let changed = P.all.filter { p in
            p.key != P.run.key && (old.values[p.key] ?? p.defaultValue) != (new.values[p.key] ?? p.defaultValue)
        }
        // An engine change is the one you'd remember, whatever else moved with it.
        if let e = changed.first(where: { $0.baseKey == P.engine.key }) {
            return prefix(e, voices) + "Engine → " + Engines.info(Int((new.values[e.key] ?? 8).rounded())).name
        }
        switch changed.count {
        case 0:
            if old.seed != new.seed { return "New Loop" }
            if old.pad != new.pad { return "Pad" }
            if old.motion != new.motion { return "Motion" }
            if old.lfos != new.lfos { return "LFO" }
            return Engines.info(Int(new.values[P.engine.key] ?? 8)).name
        case 1:
            let p = changed[0]
            return prefix(p, voices) + "\(p.name) → \(display(p, new.values[p.key] ?? p.defaultValue))"
        default:
            return "\(changed.count) changes"
        }
    }

    private static func prefix(_ p: ParamSpec, _ voices: Bool) -> String {
        voices && p.perVoice ? "Voice \(p.voice + 1) · " : ""
    }

    /// A value the way its slider or chips show it.
    private static func display(_ p: ParamSpec, _ v: Float) -> String {
        let i = Int(v.rounded())
        let pick = { (names: [String]) in names.indices.contains(i) ? names[i] : "\(i)" }
        switch p.baseKey {
        case P.note.key: return Names.note(v)
        case P.tModel.key: return pick(Names.tModels)
        case P.tRange.key: return pick(Names.tRanges)
        case P.trigSrc.key: return pick(Names.triggers)
        case P.x1Dest.key, P.x2Dest.key, P.x3Dest.key, P.yDest.key: return pick(Names.dests)
        case P.xRange.key: return pick(Names.xRanges)
        case P.xDiversity.key: return pick(Names.diversity)
        case P.yDivider.key: return pick(Names.dividers)
        case P.xClock.key: return pick(Names.xClocks)
        case P.output.key: return pick(Names.outputs)
        case P.burstDiv.key: return pick(Names.burstDivs)
        case P.xScale.key: return Names.scaleIndex.firstIndex(of: i).map { Names.scales[$0] } ?? "\(i)"
        case P.tDejaVu.key, P.xDejaVu.key: return Names.dejaVu(v)
        case P.drone.key, P.sustain.key, P.drive.key, P.phOn.key, P.dlOn.key, P.rvOn.key,
             P.rvFreeze.key, P.dlPingPong.key: return v >= 0.5 ? "On" : "Off"
        case P.dlSync.key: return v >= 0.5 ? "Follow Beat" : "Free"
        case P.dlDiv.key: return pick(Names.delayDivs)
        case P.brDiv.key: return pick(Names.burstDivs)
        case P.voices.key: return i >= 3 ? "Three" : "One"
        default: break
        }
        if p.integer { return "\(i)" }
        if p.bipolar && p.range.lowerBound < 0 { return String(format: "%+.0f", v * 100) }
        return String(format: "%.0f", (v - p.range.lowerBound) / p.span * 100)
    }
}
