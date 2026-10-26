import SwiftUI

/// A full-width fill slider in the style of Control Center. Dragging is relative (the
/// value never jumps to the finger); move your finger up or down away from the slider
/// while dragging for fine control. Double-tap resets; long-press assigns motion.
struct ParamSlider: View {
    @Environment(Synth.self) private var synth
    let spec: ParamSpec
    var title: String? = nil
    var detail: String? = nil
    var height: CGFloat = 56
    private var h: CGFloat { height }
    var format: ((Float) -> String)? = nil
    /// Replaces double-tap-to-reset, e.g. Déjà Vu's double-tap for a new loop.
    var doubleTap: (() -> Void)? = nil

    @State private var lastX: CGFloat?
    @State private var dragValue: Float?
    @State private var tick = 0
    @State private var fine = false

    private var value: Float { synth.value(spec) }
    private var effective: Float { synth.effective(spec) }
    private var slots: [MotionSlot] { synth.slots(for: spec) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.fill.tertiary)
                fill(width: w)
                if !slots.isEmpty { ghost(width: w) }
                labels
                    .padding(.horizontal, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(drag(width: w))
            .onTapGesture(count: 2) {
                if let doubleTap { doubleTap() } else { synth.reset(spec) }
                tick += 1
            }
            .contextMenu { menu }
        }
        .frame(height: h)
        .sensoryFeedback(.selection, trigger: tick)
        .accessibilityElement()
        .accessibilityLabel(title ?? spec.name)
        .accessibilityValue(formatted(value))
        .accessibilityAdjustableAction { dir in
            let step = spec.integer ? 1 : spec.span / 50
            synth.set(spec, value + (dir == .increment ? step : -step))
        }
    }

    private func fraction(_ v: Float) -> CGFloat {
        CGFloat((v - spec.range.lowerBound) / spec.span)
    }

    @ViewBuilder private func fill(width w: CGFloat) -> some View {
        let f = fraction(value)
        if spec.bipolar {
            let c = fraction(spec.center)
            Rectangle()
                .fill(Color.accentColor.opacity(fine ? 0.6 : 0.42))
                .frame(width: max(abs(f - c) * w, 2))
                .offset(x: min(f, c) * w)
        } else {
            Rectangle()
                .fill(Color.accentColor.opacity(fine ? 0.6 : 0.42))
                .frame(width: f * w)
        }
    }

    private func ghost(width w: CGFloat) -> some View {
        Capsule()
            .fill(Color.orange)
            .frame(width: 3, height: h * 0.6)
            .offset(x: min(max(fraction(effective) * w - 1.5, 2), w - 5))
            .shadow(color: .orange.opacity(0.6), radius: 4)
    }

    private var labels: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title ?? spec.name)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            ForEach(slots) { s in
                Image(systemName: s.source.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
            Text(formatted(value))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private func formatted(_ v: Float) -> String {
        if let format { return format(v) }
        if spec.integer { return "\(Int(v.rounded()))" }
        if spec.bipolar && spec.range.lowerBound < 0 { return String(format: "%+.0f", v * 100) }
        return String(format: "%.0f", (v - spec.range.lowerBound) / spec.span * 100)
    }

    private func drag(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                // Incremental, so the value never jumps to the finger and switching
                // between normal and fine speed is seamless.
                let last = lastX ?? g.startLocation.x
                lastX = g.location.x
                if dragValue == nil { dragValue = value; synth.focus(spec) }
                // Finger more than 50 pt above or below the slider: one fifth speed.
                fine = abs(g.location.y - h / 2) - h / 2 > 50
                let speed: Float = fine ? 0.2 : 1
                var v = spec.clamp(dragValue! + Float((g.location.x - last) / w) * spec.span * speed)
                dragValue = v
                // A named centre (Locked) gets a wider click zone than a plain centre.
                let zone: Float = spec.detent != nil ? 0.04 : 0.015
                if spec.bipolar && !spec.integer && abs(v - spec.center) < spec.span * zone {
                    v = spec.center   // a soft detent at the centre
                }
                let before = value
                synth.set(spec, v)
                let after = synth.value(spec)
                if spec.integer ? (after != before)
                    : (after == spec.center && before != spec.center && spec.bipolar) {
                    tick += 1
                }
            }
            .onEnded { _ in
                lastX = nil
                dragValue = nil
                fine = false
            }
    }

    @ViewBuilder private var menu: some View {
        if let help = Help.text(for: spec, engine: synth.engine) {
            Section(help) {}
        }
        Button("Reset", systemImage: "arrow.uturn.backward") { synth.reset(spec) }
        Menu("Motion", systemImage: "gyroscope") {
            ForEach(MotionSource.allCases) { src in
                Toggle(isOn: Binding(
                    get: { slots.contains { $0.source == src } },
                    set: { _ in synth.assign(src, to: spec) })) {
                    Label(src.name, systemImage: src.symbol)
                }
            }
            if !slots.isEmpty {
                Divider()
                Button("Remove Motion", systemImage: "xmark", role: .destructive) { synth.clearMotion(for: spec) }
            }
        }
    }
}

extension Synth {
    func binding(_ p: ParamSpec) -> Binding<Int> {
        Binding(get: { self.int(p) }, set: { self.set(p, $0) })
    }
    func boolBinding(_ p: ParamSpec) -> Binding<Bool> {
        Binding(get: { self.bool(p) }, set: { self.set(p, $0 ? 1 : 0) })
    }
}

/// A native segmented picker over an integer parameter.
struct Segments: View {
    @Environment(Synth.self) private var synth
    let spec: ParamSpec
    let labels: [String]

    var body: some View {
        Picker(spec.name, selection: synth.binding(spec)) {
            ForEach(labels.indices, id: \.self) { Text(labels[$0]).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// A row of selectable capsules for choices with too many options to segment.
struct ChipRow<ID: Hashable>: View {
    let items: [(id: ID, title: String, symbol: String?)]
    let selected: ID
    let select: (ID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.id) { item in
                        let on = item.id == selected
                        Button { select(item.id) } label: {
                            HStack(spacing: 6) {
                                if let s = item.symbol { Image(systemName: s) }
                                Text(item.title)
                            }
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary),
                                        in: Capsule())
                            .foregroundStyle(on ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, s in withAnimation { proxy.scrollTo(s, anchor: .center) } }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Small section heading used inside the screens.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// A play surface that reads touches straight from UIKit: began, moved, and ended or
/// cancelled, each exactly once. SwiftUI's gestures can reset mid-tap or never report a
/// cancelled touch, which an instrument can't afford (lost taps, stuck notes).
/// Follows one finger; locations are in the surface's own coordinates.
struct TouchSurface: UIViewRepresentable {
    var began: (CGPoint) -> Void
    var moved: (CGPoint) -> Void
    var ended: () -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = false
        return v
    }

    func updateUIView(_ v: TouchView, context: Context) {
        v.began = began
        v.moved = moved
        v.ended = ended
    }

    final class TouchView: UIView {
        var began: (CGPoint) -> Void = { _ in }
        var moved: (CGPoint) -> Void = { _ in }
        var ended: () -> Void = {}
        private var finger: UITouch?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard finger == nil, let t = touches.first else { return }
            finger = t
            began(t.location(in: self))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let f = finger, touches.contains(f) else { return }
            moved(f.location(in: self))
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
        private func finish(_ touches: Set<UITouch>) {
            guard let f = finger, touches.contains(f) else { return }
            finger = nil
            ended()
        }
        /// Leaving the screen mid-touch (tab switch, sheet) counts as letting go.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil, finger != nil { finger = nil; ended() }
        }
    }
}

/// Catch: loop what Marbles just played. Orange while a loop is caught; tap to let go.
struct CatchButton: View {
    @Environment(Synth.self) private var synth
    var compact = false

    var body: some View {
        let caught = synth.caughtBeats > 0
        Button {
            synth.toggleCatch()
        } label: {
            Label(caught ? "Caught \(synth.caughtBeats)" : "Catch",
                  systemImage: caught ? "lasso.badge.sparkles" : "lasso")
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 34)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.bordered)
        .tint(caught ? .orange : .accentColor)
        .opacity(synth.running || caught ? 1 : 0.45)
        .sensoryFeedback(.impact(weight: .medium), trigger: synth.caughtBeats)
        .sensoryFeedback(.error, trigger: synth.catchMissed)
        .accessibilityLabel(caught ? "Release caught loop" : "Catch")
        .accessibilityHint("Loops the last few beats Marbles played, exactly, Y included")
    }
}
