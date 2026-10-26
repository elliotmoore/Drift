import SwiftUI

/// The FX tab: Phaser, Delay and Reverb on the whole mix, and a Beat Repeat strip.
/// Each effect has a switch; its sliders stay usable while it's off, so you can set it
/// up before you bring it in.
struct FXView: View {
    @Environment(Synth.self) private var synth

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Side padding inside the scroll view, so nothing is clipped at its edges
                // and the delay times can scroll edge to edge.
                ScrollView {
                    VStack(spacing: 18) {
                        PhaserSection()
                        DelaySection()
                        ReverbSection()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                RepeatStrip()
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
            .navigationTitle("FX")
            .navigationBarTitleDisplayMode(.inline)
            .synthToolbar(mutable: P.voiceMutable)
        }
    }
}

/// An effect's heading: its name, ⓘ, and its on switch.
private struct EffectHeader: View {
    @Environment(Synth.self) private var synth
    let spec: ParamSpec
    let help: String

    var body: some View {
        HStack {
            Text(spec.name).font(.title3.weight(.semibold))
            InfoButton(text: help)
            Spacer()
            Toggle(spec.name, isOn: synth.boolBinding(spec))
                .labelsHidden()
        }
    }
}

private struct PhaserSection: View {
    @Environment(Synth.self) private var synth
    var body: some View {
        VStack(spacing: 8) {
            EffectHeader(spec: P.phOn, help: Help.phaser)
            VStack(spacing: 8) {
                ParamSlider(spec: P.phRate, detail: "Sweep speed", format: { v in
                    let hz = 0.03 * pow(200, v)
                    return hz >= 1 ? String(format: "%.1f Hz", hz) : String(format: "%.0f s", 1 / hz)
                })
                ParamSlider(spec: P.phDepth, detail: "How wide it sweeps")
                ParamSlider(spec: P.phFeedback, detail: "Sharper, more resonant")
            }
            .opacity(synth.bool(P.phOn) ? 1 : 0.5)
        }
    }
}

private struct DelaySection: View {
    @Environment(Synth.self) private var synth
    var body: some View {
        VStack(spacing: 8) {
            EffectHeader(spec: P.dlOn, help: Help.delay)
            VStack(spacing: 8) {
                Picker("Time", selection: synth.binding(P.dlSync)) {
                    Text("Follow Marbles' Beat").tag(1)
                    Text("Free").tag(0)
                }
                .pickerStyle(.segmented)
                if synth.bool(P.dlSync) {
                    ChipRow(items: Names.delayDivs.indices.map { ($0, Names.delayDivs[$0], nil) },
                            selected: synth.int(P.dlDiv)) { synth.set(P.dlDiv, $0) }
                        .padding(.horizontal, -16)
                } else {
                    ParamSlider(spec: P.dlTime, detail: "Time between echoes", format: { v in
                        let s = 0.02 * pow(100, v)
                        return s >= 1 ? String(format: "%.2f s", s) : String(format: "%.0f ms", s * 1000)
                    })
                }
                ParamSlider(spec: P.dlFeedback, detail: "How many echoes")
                Grid(horizontalSpacing: 8) {
                    GridRow {
                        ParamSlider(spec: P.dlTone, detail: "Dark ← → bright")
                        ParamSlider(spec: P.dlMix, detail: "Echo level")
                    }
                }
                Toggle(isOn: synth.boolBinding(P.dlPingPong)) {
                    Label("Ping-Pong", systemImage: "arrow.left.arrow.right")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .opacity(synth.bool(P.dlOn) ? 1 : 0.5)
        }
    }
}

private struct ReverbSection: View {
    @Environment(Synth.self) private var synth
    var body: some View {
        VStack(spacing: 8) {
            EffectHeader(spec: P.rvOn, help: Help.reverb)
            VStack(spacing: 8) {
                ParamSlider(spec: P.rvMix, detail: "Dry ← → wet")
                Grid(horizontalSpacing: 8) {
                    GridRow {
                        ParamSlider(spec: P.rvSize, detail: "Room ← → hall")
                        ParamSlider(spec: P.rvBright, detail: "Dark ← → airy")
                    }
                }
                Toggle(isOn: synth.boolBinding(P.rvFreeze)) {
                    Label("Freeze", systemImage: "snowflake")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .opacity(synth.bool(P.rvOn) ? 1 : 0.5)
        }
    }
}

/// Beat Repeat, played like the burst strip: hold to repeat; where your finger is sets the
/// slice, from a whole beat (left) to 1/32 (right). Slide while holding to change it.
struct RepeatStrip: View {
    @Environment(Synth.self) private var synth
    @State private var zone: Int?
    static let labels = ["1×", "2×", "3×", "4×", "6×", "8×"]
    private let dashesPerZone = 7

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                SectionLabel(text: "Beat Repeat")
                InfoButton(text: Help.beatRepeat)
            }
            GeometryReader { geo in
                let w = geo.size.width
                Canvas { ctx, size in
                    let zones = Self.labels.count
                    let zw = size.width / CGFloat(zones)
                    let gap: CGFloat = 10
                    let area = size.height - 20
                    for d in 0..<(zones * dashesPerZone) {
                        let z = d / dashesPerZone, k = d % dashesPerZone
                        let x = CGFloat(z) * zw + gap / 2 + (CGFloat(k) + 0.5) / CGFloat(dashesPerZone) * (zw - gap)
                        let current = zone == z
                        let h = area * (0.35 + 0.55 * CGFloat(z) / CGFloat(zones - 1))
                        let rect = CGRect(x: x - 1, y: 4 + (area - h) / 2, width: 2, height: h)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                                 with: .color(current ? Color.purple : Color.secondary.opacity(0.35)))
                    }
                }
                .overlay(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(Self.labels.indices, id: \.self) { z in
                            Text(Self.labels[z])
                                .font(.caption2.weight(zone == z ? .bold : .regular))
                                .foregroundStyle(zone == z ? Color.purple : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 3)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    if let z = zone {
                        Text("Repeating \(Names.burstDivs[z])")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    TouchSurface(began: { move(to: $0.x, width: w) },
                                 moved: { move(to: $0.x, width: w) },
                                 ended: { release() })
                }
            }
            .frame(height: 64)
        }
        .sensoryFeedback(.selection, trigger: zone)
        .onDisappear { release() }
        .accessibilityElement()
        .accessibilityLabel("Beat Repeat")
        .accessibilityHint("Hold to repeat the current slice of the beat. Further right repeats shorter slices.")
    }

    private func move(to x: CGFloat, width: CGFloat) {
        let z = min(max(Int(x / width * CGFloat(Self.labels.count)), 0), Self.labels.count - 1)
        guard z != zone else { return }
        zone = z
        synth.set(P.brDiv, z)
        synth.beatRepeat(true)
    }

    private func release() {
        guard zone != nil else { return }
        zone = nil
        synth.beatRepeat(false)
    }
}
