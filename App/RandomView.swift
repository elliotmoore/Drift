import SwiftUI

struct RandomView: View {
    @Environment(Synth.self) private var synth
    @State private var section = Section.clock

    enum Section: String, CaseIterable, Identifiable {
        case clock = "Clock", notes = "X", y = "Y", routing = "Routing"
        var id: String { rawValue }
        var help: String {
            switch self {
            case .clock: Help.clock
            case .notes: Help.x
            case .y: Help.y
            case .routing: Help.routing
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Transport()
                HStack {
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    InfoButton(text: section.help)
                }

                Group {
                    switch section {
                    case .clock: ClockSection()
                    case .notes: XSection()
                    case .y: YSection()
                    case .routing: RoutingSection()
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .navigationTitle("Marbles")
            .navigationBarTitleDisplayMode(.inline)
            .synthToolbar(mutable: P.randomMutable)
            .animation(.snappy, value: section)
        }
    }
}

// MARK: - Transport and live view

private struct Transport: View {
    @Environment(Synth.self) private var synth

    var body: some View {
        VStack(spacing: 12) {
            // The whole row picks a layout together: full labels when Play, Catch and New Loop
            // all fit on one line, otherwise Catch and New Loop shrink to icons. Play never wraps.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { playButton; CatchButton(); newLoop(compact: false) }
                HStack(spacing: 12) { playButton; CatchButton(compact: true); newLoop(compact: true) }
            }

            LiveView()
                .frame(height: 138)
                // A fixed-height display: past this size its text would spill out of the box.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }

    private var playButton: some View {
        Button {
            synth.toggle(P.run)
        } label: {
            Label(synth.running ? "Stop" : "Play", systemImage: synth.running ? "stop.fill" : "play.fill")
                .font(.headline)
                .lineLimit(1)
                .fixedSize()                      // its full width counts when the row is measured
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(synth.running ? .orange : .accentColor)
        .sensoryFeedback(.impact(weight: .medium), trigger: synth.running)
    }

    private func newLoop(compact: Bool) -> some View {
        Button {
            synth.reseed()
        } label: {
            Label("New Loop", systemImage: "dice")
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 34)
                .symbolEffect(.bounce.up.byLayer, value: synth.state.seed)
        }
        .buttonStyle(.bordered)
        .opacity(synth.dejaVuActive ? 1 : 0.45)
        .sensoryFeedback(.impact(weight: .medium), trigger: synth.state.seed)
        .accessibilityHint("Marbles' reseed: a new set of random values for the Déjà Vu loop")
    }
}

/// Gates t1 t2 t3, the four voltages, and a trail of X1. Reads the engine every frame.
private struct LiveView: View {
    @Environment(Synth.self) private var synth
    @State private var trail = Trail()
    @State private var flash = false

    var body: some View {
        TimelineView(.animation(paused: !synth.running)) { timeline in
            let m = Self.read()
            let _ = trail.push([m.volts.0, m.volts.1, m.volts.2, m.volts.3], at: timeline.date)
            VStack(spacing: 8) {
            HStack(spacing: 14) {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        let on = (m.gates >> UInt8(i)) & 1 == 1
                        HStack(spacing: 6) {
                            Circle()
                                .fill(on ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 14, height: 14)
                                .shadow(color: on ? .accentColor : .clear, radius: 6)
                            Text("t\(i + 1)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<4, id: \.self) { k in
                        let s = scale(k)
                        Meter(volts: k == 0 ? m.volts.0 : k == 1 ? m.volts.1 : k == 2 ? m.volts.2 : m.volts.3,
                              lo: s.lo, hi: s.hi,
                              label: k == 3 ? "Y" : "X\(k + 1)",
                              color: Self.colors[k])
                    }
                }
                VStack(alignment: .trailing, spacing: 4) {
                    // Tempo and dice code above the traces, so lines never cross the text.
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Text(String(format: "%.0f BPM", m.bpm))
                            InfoButton(text: Help.liveView)
                        }
                        // A short name for the current roll of the dice, so a new one is visible.
                        // Which loop this is: changes with New Loop, so a new one is visible.
                        Label("Loop \(Self.diceName(synth.state.seed))", systemImage: "dice")
                            .contentTransition(.numericText())
                            .foregroundStyle(flash ? Color.accentColor : .secondary)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Canvas { ctx, size in
                    _ = timeline.date   // redraw every frame, not only when something else changes
                    // X1-X3 on the X range's scale, Y on its own +-5 V -- the same scales as
                    // the meters, so a line's right-hand end sits at its meter's height.
                    // Unrouted lines first and faint, routed ones on top.
                    let order = (0..<4).sorted { routed($0) == routed($1) ? $0 > $1 : !routed($0) }
                    for k in order {
                        let (lo, hi) = scale(k)
                        var path = Path()
                        for (i, v) in trail.values[k].enumerated() {
                            let x = size.width * CGFloat(i) / CGFloat(Trail.count - 1)
                            let f = CGFloat((min(max(v, lo), hi) - lo) / (hi - lo))
                            let y = size.height * (0.92 - 0.84 * f)
                            i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                        }
                        ctx.stroke(path, with: .color(Self.colors[k].opacity(routed(k) ? 1 : 0.3)),
                                   lineWidth: routed(k) ? 2 : 1)
                    }
                }
                }
            }
            legend
            }
            .padding(12)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(flash ? 0.18 : 0))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: synth.state.seed) {
            trail.reset()
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.12)) { flash = false }
        }
    }

    /// X1, X2, X3, Y -- the same colours on the meters, the lines and the legend.
    static let colors: [Color] = [.blue, .pink, .green, .purple]
    private static let dests = [P.x1Dest, P.x2Dest, P.x3Dest, P.yDest]

    /// The voltage range each output is drawn on: X1-X3 follow X's Range; Y is always +-5 V.
    private func scale(_ k: Int) -> (lo: Float, hi: Float) {
        if k == 3 { return (-5, 5) }
        switch synth.int(P.xRange) {
        case 0: return (0, 2)
        case 1: return (0, 5)
        default: return (-5, 5)
        }
    }

    private func routed(_ k: Int) -> Bool { synth.int(synth.sv(Self.dests[k])) != Int(DD_NONE.rawValue) }

    /// What plays what: the rhythms on top ("t3 → Snare"), where each voltage goes below.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            triggers
            routes
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    /// Which t plays each voice, so a sequence with every X route Off still reads as connected.
    private var triggers: some View {
        HStack(spacing: 10) {
            if !synth.bool(P.drive) {
                Label("Not playing the voices", systemImage: "bolt.slash")
            } else {
                ForEach(0..<(synth.voicesOn ? 3 : 1), id: \.self) { v in
                    let src = synth.int(P.trigSrc.forVoice(v))
                    let off = src >= Names.triggers.count - 1
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").foregroundStyle(off ? Color.secondary : Color.accentColor)
                        Text("\(off ? "Off" : Names.triggers[max(src, 0)]) → \(Engines.info(synth.int(P.engine.forVoice(v))).name)")
                    }
                    .opacity(off ? 0.6 : 1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    /// Where each output goes, e.g. "X1 → Pitch".
    private var routes: some View {
        HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { k in
                let name = k == 3 ? "Y" : "X\(k + 1)"
                let dest = Names.dests[min(max(synth.int(synth.sv(Self.dests[k])), 0), Names.dests.count - 1)]
                HStack(spacing: 4) {
                    Circle().fill(Self.colors[k]).frame(width: 7, height: 7)
                    Text("\(name) → \(dest)")
                }
                .foregroundStyle(routed(k) ? .primary : .secondary)
                .opacity(routed(k) ? 1 : 0.6)
            }
            Spacer(minLength: 0)
        }
    }

    static func diceName(_ seed: UInt32) -> String {
        String(format: "%04X", (seed ^ (seed >> 16)) & 0xFFFF)
    }

    static func read() -> drift_meters {
        var m = drift_meters()
        drift_meters_read(&m)
        return m
    }
}

private final class Trail {
    static let count = 120                       // about 2 seconds at 60 frames a second
    var values = [[Float]](repeating: [Float](repeating: 0, count: count), count: 4)
    func reset() {
        values = values.map { [Float](repeating: $0.last ?? 0, count: Self.count) }
    }
    private var last: Date?
    /// One sample per frame, however often the view happens to be re-evaluated.
    func push(_ v: [Float], at date: Date) {
        guard date != last else { return }
        last = date
        for k in 0..<4 {
            values[k].removeFirst()
            values[k].append(v[k])
        }
    }
}

/// One output's level, on the same scale as its trace line: filled from 0 V, which is the
/// bottom for 0-2 V and 0-5 V ranges and the middle for +-5 V.
private struct Meter: View {
    let volts: Float
    let lo: Float
    let hi: Float
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let h = g.size.height
                let frac = { (v: Float) in CGFloat(min(max((v - lo) / (hi - lo), 0), 1)) }
                let fv = frac(volts), fz = frac(0)
                ZStack {
                    Capsule().fill(.fill.tertiary)
                    Rectangle()
                        .fill(color)
                        .frame(height: max(abs(fv - fz) * h, 1))
                        .position(x: g.size.width / 2, y: h * (1 - (fv + fz) / 2))
                }
                .clipShape(Capsule())
            }
            .frame(width: 12)
            Text(label).font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sections

private struct ClockSection: View {
    @Environment(Synth.self) private var synth
    var body: some View {
        VStack(spacing: 8) {
            ChipRow(items: Names.tModels.indices.map { ($0, Names.tModels[$0], nil) },
                    selected: synth.int(P.tModel)) { synth.set(P.tModel, $0) }
                .padding(.horizontal, -16)
            HStack {
                ParamSlider(spec: P.rate, format: { _ in String(format: "%.0f BPM", Self.bpm(synth)) })
                Segments(spec: P.tRange, labels: Names.tRanges)
                    .frame(width: 130)
            }
            ParamSlider(spec: P.tBias, detail: "Which output wins the toss")
            ParamSlider(spec: P.tJitter, detail: "Timing wobble")
            DejaVuRow(spec: P.tDejaVu)
            ParamSlider(spec: P.length, detail: "Steps before the loop repeats")
            Grid(horizontalSpacing: 8) {
                GridRow {
                    ParamSlider(spec: P.gateLen, detail: "Note length")
                    ParamSlider(spec: P.gateRand, detail: "Random lengths")
                }
            }
        }
    }

    static func bpm(_ s: Synth) -> Float {
        let k: Float = [0.25, 1, 4][min(max(s.int(P.tRange), 0), 2)]
        return 120 * k * exp2(s.value(P.rate) / 12)
    }
}

private struct XSection: View {
    @Environment(Synth.self) private var synth
    var body: some View {
        VStack(spacing: 8) {
            ChipRow(items: Names.scales.indices.map { (Names.scaleIndex[$0], Names.scales[$0], $0 == 0 ? "pianokeys" : nil) },
                    selected: synth.int(P.xScale)) { synth.set(P.xScale, $0) }
                .padding(.horizontal, -16)
            ParamSlider(spec: P.xSpread, detail: "How far notes jump")
            ParamSlider(spec: P.xBias, detail: "Leaning low or high")
            ParamSlider(spec: P.xSteps, detail: "Smooth ← → scale steps")
            DejaVuRow(spec: P.xDejaVu)
            SectionLabel(text: "Diversity")
            Segments(spec: P.xDiversity, labels: Names.diversity)
            SectionLabel(text: "Range")
            Segments(spec: P.xRange, labels: Names.xRanges)
            SectionLabel(text: "Clocked By")
            Segments(spec: P.xClock, labels: Names.xClocks)
        }
    }
}

private struct YSection: View {
    @Environment(Synth.self) private var synth
    var body: some View {
        VStack(spacing: 8) {
            ParamSlider(spec: P.ySpread)
            ParamSlider(spec: P.yBias)
            ParamSlider(spec: P.ySteps, detail: "Smooth ← → stepped")
            ParamSlider(spec: P.yDivider, detail: "Slower than the clock",
                        format: { Names.dividers[min(max(Int($0.rounded()), 0), 11)] })
        }
    }
}

private struct RoutingSection: View {
    @Environment(Synth.self) private var synth
    var body: some View {
        VStack(spacing: 10) {
            // With three voices, each has its own Triggers and routes.
            if synth.voicesOn { VoiceSwitcher() }
            SectionLabel(text: "Triggers")
            Segments(spec: synth.sv(P.trigSrc), labels: Names.triggers)

            SectionLabel(text: "Voltages")
            route(synth.sv(P.x1Dest), synth.sv(P.x1Depth))
            route(synth.sv(P.x2Dest), synth.sv(P.x2Depth))
            route(synth.sv(P.x3Dest), synth.sv(P.x3Depth))
            route(synth.sv(P.yDest), synth.sv(P.yDepth))
        }
    }

    private func route(_ dest: ParamSpec, _ depth: ParamSpec) -> some View {
        HStack(spacing: 8) {
            Menu {
                Picker(dest.name, selection: synth.binding(dest)) {
                    ForEach(Names.dests.indices, id: \.self) { Text(Names.dests[$0]).tag($0) }
                }
            } label: {
                HStack {
                    Text(dest.name).font(.subheadline.monospaced().weight(.semibold))
                    Image(systemName: "arrow.right")
                    Text(Names.dests[synth.int(dest)])
                }
                .font(.subheadline)
                .frame(width: 150, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            ParamSlider(spec: depth, title: "Depth", height: 46)
        }
    }
}

/// A Déjà Vu slider with a lock button: one tap jumps to Locked, another goes back.
/// Double-tapping the slider plays a new loop, like double-pressing Marbles' Déjà Vu buttons.
private struct DejaVuRow: View {
    @Environment(Synth.self) private var synth
    let spec: ParamSpec
    @State private var before: Float?

    private var locked: Bool { abs(synth.value(spec) - 0.5) < 0.005 }

    var body: some View {
        HStack(spacing: 8) {
            ParamSlider(spec: spec, detail: "Random ← Locked → Jumbled", format: Names.dejaVu,
                        doubleTap: { synth.reseed() })
            Button {
                if locked {
                    synth.set(spec, before ?? 0)
                    before = nil
                } else {
                    before = synth.value(spec)
                    synth.set(spec, 0.5)
                }
            } label: {
                Image(systemName: locked ? "lock.fill" : "lock.open")
                    .font(.title3)
                    .frame(width: 52, height: 56)
                    .background(locked ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.fill.tertiary),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(locked ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: locked)
            .accessibilityLabel(locked ? "Unlock Déjà Vu" : "Lock Déjà Vu")
        }
    }
}
