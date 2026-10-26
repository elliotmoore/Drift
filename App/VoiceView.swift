import SwiftUI

struct VoiceView: View {
    @Environment(Synth.self) private var synth

    var body: some View {
        let e = synth.engine
        let v = { (p: ParamSpec) in synth.sv(p) }
        // A little shorter with the voice switcher showing, so the pad keeps its room.
        let main: CGFloat = synth.voicesOn ? 48 : 56
        NavigationStack {
            VStack(spacing: 10) {
                if synth.voicesOn { VoiceSwitcher() }

                ChipRow(items: Engines.all.map { ($0.id, $0.name, $0.symbol) },
                        selected: e.id) { synth.set(v(P.engine), $0) }
                    .padding(.horizontal, -16)
                    .id(synth.activeVoice)        // re-centre on the new voice's engine

                VStack(spacing: 8) {
                    ParamSlider(spec: v(P.note), detail: nil, height: main, format: Names.note)
                    ParamSlider(spec: v(P.harmonics), detail: e.harmonics, height: main)
                    ParamSlider(spec: v(P.timbre), detail: e.timbre, height: main)
                    ParamSlider(spec: v(P.morph), detail: e.morph, height: main)
                }

                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        ParamSlider(spec: v(P.decay), height: 46)
                        ParamSlider(spec: v(P.lpgColour), title: "Colour", height: 46)
                    }
                    GridRow {
                        ParamSlider(spec: v(P.timbreAmt), height: 46)
                        ParamSlider(spec: v(P.morphAmt), height: 46)
                    }
                    GridRow {
                        ParamSlider(spec: v(P.fmAmt), height: 46)
                        // With voices, this voice's level in the mix; otherwise the volume.
                        if synth.voicesOn {
                            ParamSlider(spec: v(P.level), height: 46)
                        } else {
                            ParamSlider(spec: P.volume, height: 46)
                        }
                    }
                }

                PlayBar()
                PlayPad()
                    .frame(minHeight: 160)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .navigationTitle("Plaits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                Picker("Voices", selection: Binding(get: { synth.voicesOn }, set: { synth.setVoices($0) })) {
                    Label("One Voice", systemImage: "circle").tag(false)
                    Label("Three Voices", systemImage: "circle.grid.3x3.circle").tag(true)
                }
            }
            .synthToolbar(mutable: P.voiceMutable)
        }
    }
}

/// Mode, sequencer transport and pad settings, just above the pad.
struct PlayBar: View {
    @Environment(Synth.self) private var synth

    var body: some View {
        // Full labels when they fit; on a narrow phone or with large text, Drone and Hold
        // drop to icons so nothing wraps.
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
    }

    private func bar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: synth.boolBinding(synth.sv(P.drone))) {
                Label("Drone", systemImage: "infinity")
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .accessibilityHint("Keeps the sound going with nobody playing it")

            Toggle(isOn: synth.boolBinding(synth.sv(P.sustain))) {
                Label("Hold", systemImage: "hand.point.up")
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .disabled(synth.bool(synth.sv(P.drone)))
            .accessibilityHint("Your finger holds the note instead of plucking it")

            Spacer(minLength: 8)

            Button {
                synth.toggle(P.run)
            } label: {
                Label("Marbles", systemImage: synth.running ? "stop.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderedProminent)
            .tint(synth.running ? .orange : .accentColor)
            .accessibilityLabel(synth.running ? "Stop Marbles" : "Start Marbles")
            .sensoryFeedback(.impact, trigger: synth.running)
        }
    }
}

/// Lets a label style be chosen at run time.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Scale-locked play surface. Left to right is pitch, snapped to the pad's scale;
/// up and down moves one parameter. Sliding to a new note restrikes it.
struct PlayPad: View {
    @Environment(Synth.self) private var synth
    @State private var touch: CGPoint?
    @State private var noteIndex: Int?

    /// Finger up, or the touch was cancelled: let go once.
    private func release() {
        guard touch != nil else { return }
        touch = nil
        noteIndex = nil
        synth.gate(false)
    }

    var body: some View {
        let notes = synth.pad.notes
        let yTarget = P.byKey[synth.pad.yTargetKey].map { synth.sv($0) }
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, size in
                let w = size.width / CGFloat(notes.count)
                for (i, n) in notes.enumerated() {
                    let x = CGFloat(i) * w
                    let isRoot = (n - synth.pad.root) % 12 == 0
                    let lit = noteIndex == i
                    let rect = CGRect(x: x + 1, y: 0, width: w - 2, height: size.height)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 6),
                             with: .color(lit ? Color.accentColor.opacity(0.55)
                                          : Color.primary.opacity(isRoot ? 0.10 : 0.05)))
                    if isRoot && w > 14 {
                        ctx.draw(Text(Names.note(Float(n))).font(.caption2).foregroundStyle(.secondary),
                                 at: CGPoint(x: x + w / 2, y: size.height - 12))
                    }
                }
                if let t = touch {
                    ctx.fill(Path(ellipseIn: CGRect(x: t.x - 22, y: t.y - 22, width: 44, height: 44)),
                             with: .color(Color.accentColor.opacity(0.35)))
                }
            }
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                TouchSurface(began: { play(at: $0, size: size, notes: notes, yTarget: yTarget) },
                             moved: { play(at: $0, size: size, notes: notes, yTarget: yTarget) },
                             ended: { release() })
            }
            .sensoryFeedback(.selection, trigger: noteIndex)
            .accessibilityLabel("Play surface")
            .overlay(alignment: .top) {
                // Above the play surface, so tapping these never plays a note.
                HStack {
                    UpDownMenu(target: yTarget)
                    Spacer()
                    ScaleMenu()
                }
                .padding(8)
            }
        }
    }

    /// A finger down or moving on the pad: pick the note under it, set up/down, and strike
    /// when the note changes (or glide, while holding).
    private func play(at loc: CGPoint, size: CGSize, notes: [Int], yTarget: ParamSpec?) {
        let p = CGPoint(x: min(max(loc.x, 0), size.width), y: min(max(loc.y, 0), size.height))
        let i = min(Int(p.x / size.width * CGFloat(notes.count)), notes.count - 1)
        let first = touch == nil
        touch = p
        if let yTarget {
            synth.set(yTarget, yTarget.range.lowerBound + Float(1 - p.y / size.height) * yTarget.span)
        }
        if i != noteIndex {
            noteIndex = i
            synth.set(synth.sv(P.note), Float(notes[i]))
            if first { synth.gate(true) }
            else if !synth.bool(synth.sv(P.sustain)) { synth.strike() }
        }
    }
}

/// The pad's "↕ Timbre" label: tap to choose what up and down controls.
private struct UpDownMenu: View {
    @Environment(Synth.self) private var synth
    let target: ParamSpec?

    var body: some View {
        Menu {
            Picker("Up and Down Controls", selection: Binding(
                get: { synth.pad.yFollow ? "follow" : synth.pad.yTargetKey },
                set: { v in
                    if v == "follow" {
                        synth.pad.yFollow = true
                        if synth.pad.yTargetKey.isEmpty { synth.pad.yTargetKey = P.timbre.key }
                    } else {
                        synth.pad.yFollow = false
                        synth.pad.yTargetKey = v
                    }
                })) {
                Label("Follow Last Touched", systemImage: "hand.point.up.left").tag("follow")
                Divider()
                ForEach(PadSettings.yTargets) { Text($0.name).tag($0.key) }
                Text("Nothing").tag("")
            }
        } label: {
            Label(target?.name ?? "Nothing", systemImage: "arrow.up.and.down")
                .contentTransition(.interpolate)
                .animation(.snappy, value: target?.key)
                .padCapsule()
        }
        .accessibilityLabel("Up and down controls \(target?.name ?? "nothing")")
    }
}

/// The pad's key and scale label: tap for scale, key, range and output.
private struct ScaleMenu: View {
    @Environment(Synth.self) private var synth

    var body: some View {
        @Bindable var s = synth
        Menu {
            Picker("Scale", selection: $s.pad.scale) {
                ForEach(PadScale.allCases) { Text($0.name).tag($0) }
            }
            Picker("Key", selection: $s.pad.root) {
                ForEach(0..<12, id: \.self) { Text(Names.noteNames[$0]).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Lowest Octave", selection: $s.pad.lowOctave) {
                ForEach(0..<6, id: \.self) { Text("C\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Octaves", selection: $s.pad.octaves) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            Section("Sound") {
                Picker("Output", selection: synth.binding(P.output)) {
                    ForEach(Names.outputs.indices, id: \.self) { Text(Names.outputs[$0]).tag($0) }
                }
                .pickerStyle(.menu)
            }
        } label: {
            Label("\(Names.noteNames[synth.pad.root]) \(synth.pad.scale.shortName)", systemImage: "music.note")
                .padCapsule()
        }
        .accessibilityLabel("Pad scale, \(Names.noteNames[synth.pad.root]) \(synth.pad.scale.name)")
    }
}

private extension View {
    func padCapsule() -> some View {
        self.font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

/// Which voice the page is showing and playing: Voice 1 · 2 · 3, each with its engine.
/// A dot flashes when that voice is struck, so you can see the kit playing.
struct VoiceSwitcher: View {
    @Environment(Synth.self) private var synth
    @State private var flash = VoiceFlash()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let lit = flash.update(at: timeline.date)
            // One track with a raised selection, like a segmented control, so it reads as
            // "which voice" and not as another row of engine chips. Every label is the same
            // size: the row gives up equal widths, then the numbers, before it shortens a name.
            ViewThatFits(in: .horizontal) {
                track(lit, style: .full, equal: true)
                track(lit, style: .full, equal: false)    // each as wide as its label
                track(lit, style: .nameOnly, equal: false)
                track(lit, style: .truncated, equal: true)
            }
            .animation(.snappy(duration: 0.2), value: synth.activeVoice)
        }
        .sensoryFeedback(.selection, trigger: synth.activeVoice)
    }
}

private enum VoiceLabelStyle { case full, nameOnly, truncated }

extension VoiceSwitcher {
    fileprivate func track(_ lit: [Bool], style: VoiceLabelStyle, equal: Bool) -> some View {
        let layout = equal ? AnyLayout(EqualWidthHStack(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            ForEach(0..<3, id: \.self) { v in
                let on = synth.activeVoice == v
                let name = Engines.info(synth.int(P.engine.forVoice(v))).name
                Button {
                    synth.selectedVoice = v
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(lit[v] ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                        Text(style == .nameOnly ? name : "\(v + 1) · \(name)")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    // One weight for all three, so selecting one doesn't change its width.
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: style != .truncated, vertical: false)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background {
                        if on {
                            Capsule()
                                // White in light mode, a lighter grey in dark, as a segmented control does.
                                .fill(Color(UIColor { $0.userInterfaceStyle == .dark ? .systemGray3 : .systemBackground }))
                                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        }
                    }
                    .foregroundStyle(Color.primary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voice \(v + 1), \(name)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.fill.tertiary, in: Capsule())
    }
}

/// Lays its children out side by side at equal widths. Its ideal width is the widest
/// child's times the count, so ViewThatFits can tell whether every label fits whole.
private struct EqualWidthHStack: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? (ideal.map(\.width).max()! * CGFloat(subviews.count) + gaps)
        let each = (width - gaps) / CGFloat(subviews.count)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: each, height: proposal.height)).height }.max()!
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let each = (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        for (i, sv) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(i) * (each + spacing)
            sv.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                     proposal: ProposedViewSize(width: each, height: bounds.height))
        }
    }
}

/// Tracks each voice's strike count and lights its dot for a moment after a strike.
final class VoiceFlash {
    private var seen = [UInt32](repeating: 0, count: 3)
    private var until = [Date](repeating: .distantPast, count: 3)

    func update(at now: Date) -> [Bool] {
        var m = drift_meters()
        drift_meters_read(&m)
        let strikes = [m.voice_strikes.0, m.voice_strikes.1, m.voice_strikes.2]
        for v in 0..<3 where strikes[v] != seen[v] {
            seen[v] = strikes[v]
            until[v] = now.addingTimeInterval(0.12)
        }
        return until.map { $0 > now }
    }
}
