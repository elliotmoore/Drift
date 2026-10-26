import Accelerate
import SwiftUI

/// The third tab: what Plaits is actually producing, with the controls that shape it.
struct ScopeView: View {
    @Environment(Synth.self) private var synth
    @State private var mode = Mode.wave
    @State private var visible = false
    @State private var scope = ScopeData()
    @State private var touching = false

    enum Mode: String, CaseIterable, Identifiable {
        case wave = "Wave", spectrum = "Spectrum", xy = "Out × Aux"
        var id: String { rawValue }
    }

    var body: some View {
        let e = synth.engine
        NavigationStack {
            VStack(spacing: 10) {
                HStack {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    CatchButton(compact: true)
                    InfoButton(text: Help.scope)
                }

                TimelineView(.animation(paused: !visible)) { timeline in
                    Canvas { ctx, size in
                        // Using the frame's time is what makes SwiftUI redraw every frame;
                        // without it the canvas looks unchanged and is skipped.
                        _ = timeline.date
                        scope.read(at: timeline.date)
                        switch mode {
                        case .wave: drawWave(ctx, size)
                        case .spectrum: drawSpectrum(ctx, size)
                        case .xy: drawXY(ctx, size)
                        }
                        // Silent for a moment: say how to get something to look at.
                        if scope.silent {
                            ctx.draw(Text(synth.running ? "Marbles is playing, but no voice is sounding"
                                                        : "Touch here to play a note,\nor press Play on Marbles")
                                        .font(.callout)
                                        .foregroundStyle(.secondary),
                                     at: CGPoint(x: size.width / 2, y: size.height * 0.36))
                        }
                    }
                }
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("\(e.name) · \(Names.note(synth.effective(synth.sv(P.note))))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                // Touch the scope to play a note, as on the pad.
                .overlay {
                    TouchSurface(began: { _ in if !touching { touching = true; synth.gate(true) } },
                                 moved: { _ in },
                                 ended: { releaseTouch() })
                }
                .accessibilityLabel("Scope. Touch to play a note.")
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .navigationTitle("Scope")
            .navigationBarTitleDisplayMode(.inline)
            .synthToolbar(mutable: P.voiceMutable)
            .onAppear { visible = true }
            .onDisappear { visible = false }
        }
    }

    private func releaseTouch() {
        guard touching else { return }
        touching = false
        synth.gate(false)
    }

    // MARK: Drawing

    /// The signal you are hearing: Out, Aux or their mix, as the Output setting says.
    private func heard(_ i: Int) -> Float {
        switch synth.int(P.output) {
        case 1: scope.aux[i]
        case 2: (scope.out[i] + scope.aux[i]) * 0.71
        default: scope.out[i]
        }
    }

    private func drawWave(_ ctx: GraphicsContext, _ size: CGSize) {
        let n = ScopeData.count
        // About two and a half cycles of the current note, so the shape is readable.
        let hz = 440 * pow(2, (Double(synth.effective(synth.sv(P.note))) - 69) / 12)
        let window = min(max(Int(2.5 * 48_000 / hz), 128), n / 2)

        // Centred on its own average (an oscilloscope's AC coupling), so a constant
        // offset -- e.g. a filter shut right down -- doesn't push the wave off-centre.
        var mean: Float = 0
        for i in (n - window * 2)..<n { mean += heard(i) }
        mean /= Float(window * 2)
        let sample = { (i: Int) in heard(i) - mean }

        // Start on the latest rising zero crossing that still leaves a full window, so
        // the wave stands still instead of scrolling.
        var peak: Float = 0
        for i in (n - window * 2)..<n { peak = max(peak, abs(sample(i))) }
        let th = peak * 0.02
        var start = n - window
        var i = n - window - 1
        while i > n - window * 2 {
            if sample(i - 1) < -th && sample(i) >= 0 { start = i; break }
            i -= 1
        }

        scope.gain = max(peak, scope.gain * 0.97, 0.02)   // auto-gain, slow to fall
        let mid = size.height / 2
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: mid)); axis.addLine(to: CGPoint(x: size.width, y: mid))
        ctx.stroke(axis, with: .color(.secondary.opacity(0.25)), lineWidth: 1)

        var path = Path()
        for k in 0..<window {
            let x = size.width * CGFloat(k) / CGFloat(window - 1)
            let y = mid - CGFloat(sample(start + k) / scope.gain) * mid * 0.85
            k == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        ctx.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
    }

    private func drawSpectrum(_ ctx: GraphicsContext, _ size: CGSize) {
        let db = scope.spectrum { heard($0) }
        // Log frequency, 30 Hz to 16 kHz; -84 dB to 0 dB.
        let lo = log2(30.0), hi = log2(16_000.0)
        let binHz = 48_000.0 / Double(ScopeData.fftSize)

        var grid = Path()
        for f in [100.0, 1_000.0, 10_000.0] {
            let x = size.width * CGFloat((log2(f) - lo) / (hi - lo))
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            ctx.draw(Text(f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))").font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: x + 12, y: size.height - 10))
        }
        ctx.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 1)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for b in 1..<db.count {
            let f = Double(b) * binHz
            guard f >= 30, f <= 16_000 else { continue }
            let x = size.width * CGFloat((log2(f) - lo) / (hi - lo))
            let y = size.height * CGFloat(1 - (max(db[b], -84) + 84) / 84)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        ctx.fill(path, with: .linearGradient(Gradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.15)]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    private func drawXY(_ ctx: GraphicsContext, _ size: CGSize) {
        let n = ScopeData.count, m = 1536
        var mo: Float = 0, ma: Float = 0
        for i in (n - m)..<n { mo += scope.out[i]; ma += scope.aux[i] }
        mo /= Float(m); ma /= Float(m)
        var peak: Float = 0.02
        for i in (n - m)..<n { peak = max(peak, abs(scope.out[i] - mo), abs(scope.aux[i] - ma)) }
        scope.gain = max(peak, scope.gain * 0.97)
        let r = min(size.width, size.height) / 2 * 0.85
        let c = CGPoint(x: size.width / 2, y: size.height / 2)

        var cross = Path()
        cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
        cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
        ctx.stroke(cross, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
        ctx.draw(Text("Out →").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: c.x + r - 18, y: c.y + 10))
        ctx.draw(Text("Aux ↑").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: c.x + 22, y: c.y - r + 8))

        var path = Path()
        for k in 0..<m {
            let i = n - m + k
            let p = CGPoint(x: c.x + CGFloat((scope.out[i] - mo) / scope.gain) * r,
                            y: c.y - CGFloat((scope.aux[i] - ma) / scope.gain) * r)
            k == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        ctx.stroke(path, with: .color(.accentColor.opacity(0.8)), lineWidth: 1.2)
    }
}

/// Recent audio from the engine, and the FFT that turns it into a spectrum.
/// Not observed: the TimelineView redraws it every frame.
final class ScopeData {
    static let count = 4096
    static let fftSize = 4096
    var out = [Float](repeating: 0, count: count)
    var aux = [Float](repeating: 0, count: count)
    var gain: Float = 0.1

    private let log2n = vDSP_Length(12)
    private var setup: FFTSetup?            // made on first use of Spectrum
    private lazy var window: [Float] = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                                    count: Self.fftSize, isHalfWindow: false)
    private var smoothed = [Float](repeating: -120, count: fftSize / 2)

    deinit { if let setup { vDSP_destroy_fftsetup(setup) } }

    /// True after a second and a half of near silence (so not between drum hits).
    private(set) var silent = false
    private var lastSound = Date.distantPast

    func read(at now: Date) {
        out.withUnsafeMutableBufferPointer { o in
            aux.withUnsafeMutableBufferPointer { a in
                drift_scope_read(o.baseAddress!, a.baseAddress!, Int32(Self.count))
            }
        }
        var peak: Float = 0
        for i in (Self.count - 1024)..<Self.count { peak = max(peak, abs(out[i]), abs(aux[i])) }
        if peak > 0.001 { lastSound = now }
        silent = now.timeIntervalSince(lastSound) > 1.5
    }

    /// dB per FFT bin of `signal`, falling back slowly so it reads steadily.
    func spectrum(_ signal: (Int) -> Float) -> [Float] {
        if setup == nil { setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) }
        guard let setup else { return smoothed }
        let n = Self.fftSize, half = n / 2
        var x = (0..<n).map { signal(Self.count - n + $0) * window[$0] }
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                x.withUnsafeMutableBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }
        // Power to dB, relative to a full-scale sine through the Hann window.
        let ref = Float(n * n) / 4
        for b in 0..<half {
            let db = 10 * log10(max(mags[b] / ref, 1e-12))
            smoothed[b] = max(db, smoothed[b] - 1.5)
        }
        return smoothed
    }
}

/// Trig and Burst on one strip, after the SP-1 rocker in Wakes. Not on any page at the
/// moment (taken off Scope in 0.9.1, when Beat Repeat arrived on the FX tab); kept so it
/// can come back. Touch to strike; where your
/// finger is sets the repeat: far left strikes once, further right repeats faster (1/4 to
/// 1/32 of a beat, locked to Marbles' clock when it plays). Slide while holding to change it.
struct BurstSlider: View {
    @Environment(Synth.self) private var synth
    @State private var zone: Int?                 // nil = not touching; 0 = single strike

    /// Zone 0 is a single strike; zones 1...6 are Burst Speed 0...5, labelled as repeats
    /// per beat so the numbers rise as it gets faster. The note value shows while held.
    static let labels = ["Trig", "1×", "2×", "3×", "4×", "6×", "8×"]
    private let dashesPerZone = 7

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Canvas { ctx, size in
                let zones = Self.labels.count
                let zw = size.width / CGFloat(zones)
                let gap: CGFloat = 10                       // between zones, so each reads as a block
                for d in 0..<(zones * dashesPerZone) {
                    let z = d / dashesPerZone, k = d % dashesPerZone
                    let x = CGFloat(z) * zw + gap / 2 + (CGFloat(k) + 0.5) / CGFloat(dashesPerZone) * (zw - gap)
                    let lit = zone.map { z <= $0 } ?? false
                    let current = zone == z
                    // Dashes grow taller to the right: faster repeats.
                    // Above the labels, never behind them.
                    let area = size.height - 20
                    let h = area * (0.35 + 0.55 * CGFloat(z) / CGFloat(zones - 1))
                    let rect = CGRect(x: x - 1, y: 4 + (area - h) / 2, width: 2, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .color(current ? Color.accentColor
                                          : lit ? Color.accentColor.opacity(0.45)
                                          : Color.secondary.opacity(0.35)))
                }
            }
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Self.labels.indices, id: \.self) { z in
                        Text(Self.labels[z])
                            .font(.caption2.weight(zone == z ? .bold : .regular))
                            .foregroundStyle(zone == z ? Color.accentColor : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 3)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if let z = zone, z > 0 {
                    Text("\(Names.burstDivs[z - 1]) notes")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .padding(6)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                TouchSurface(began: { move(to: $0.x, width: w) },
                             moved: { move(to: $0.x, width: w) },
                             ended: { release() })
            }
        }
        .frame(height: 64)
        .sensoryFeedback(.selection, trigger: zone)
        .onDisappear { release() }
        .accessibilityElement()
        .accessibilityLabel("Trig and Burst")
        .accessibilityHint("Touch to strike. Further right repeats faster while held. Over a drone, it chops the sound.")
    }

    private func move(to x: CGFloat, width: CGFloat) {
        let z = min(max(Int(x / width * CGFloat(Self.labels.count)), 0), Self.labels.count - 1)
        if zone == nil { synth.strip(true); synth.gate(true) }   // the first touch strikes
        guard z != zone else { return }
        zone = z
        if z > 0 { synth.set(P.burstDiv, z - 1) }
        synth.burst(z > 0)
    }

    private func release() {
        guard zone != nil else { return }
        zone = nil
        synth.burst(false)
        synth.gate(false)
        synth.strip(false)
    }
}
