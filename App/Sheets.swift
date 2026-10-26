import SwiftUI
import UniformTypeIdentifiers

// MARK: - Toolbar shared by both screens

extension View {
    func synthToolbar(mutable: [ParamSpec]) -> some View { modifier(SynthToolbar(mutable: mutable)) }
}

private struct SynthToolbar: ViewModifier {
    @Environment(Synth.self) private var synth
    let mutable: [ParamSpec]
    @State private var showMotion = false

    private var isVoice: Bool { mutable == P.voiceMutable }
    /// "Voice 2 · Snare", "Virtual Analog" or "Marbles".
    private var target: String {
        guard isVoice else { return "Marbles" }
        return synth.voicesOn ? "Voice \(synth.activeVoice + 1) · \(synth.engine.name)" : synth.engine.name
    }
    @State private var showLibrary = false
    @State private var showGuide = false
    @State private var saved = 0
    @State private var resets = 0
    @State private var kept = 0
    @State private var toast = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Menu {
                        // Says what the wand changes: the voice on show, or Marbles. The three
                        // sit side by side, so the menu fits on screen even with large text.
                        Section(target) {
                            ControlGroup {
                                Button("Nudge", systemImage: "wand.and.sparkles") {
                                    synth.labelNextChange("Nudge")
                                    synth.nudge(mutable.map(synth.sv))
                                }
                                Button("Shuffle", systemImage: "shuffle") {
                                    synth.labelNextChange("Shuffle")
                                    synth.shuffle(mutable.map(synth.sv))
                                }
                                Button("Surprise", systemImage: "sparkles") {
                                    synth.labelNextChange("Surprise Me")
                                    synth.shuffle(mutable.map(synth.sv))
                                    if isVoice {
                                        synth.set(synth.sv(P.engine), Engines.all.randomElement()!.id)
                                    } else {
                                        synth.set(P.tModel, Int.random(in: 0...5))
                                        // Keep Same as Pad if it is on: a random scale would clash with the pad.
                                        if synth.int(P.xScale) != 6 { synth.set(P.xScale, Int.random(in: 0...5)) }
                                    }
                                }
                            } label: {
                                Text(target)
                            }
                            .controlGroupStyle(.menu)
                        }
                        // These change everything: every voice, Marbles and the routing.
                        Section {
                            Button("Something Nice", systemImage: "leaf") {
                                synth.labelNextChange("Something Nice")
                                synth.somethingNice()
                            }
                            Button("Keep This Sound", systemImage: "pin") {
                                synth.keepThisSound()
                                kept += 1
                            }
                            Button("Reset to Default", systemImage: "arrow.counterclockwise", role: .destructive) {
                                synth.resetToDefault()
                                resets += 1
                            }
                        }
                    } label: {
                        Label("Mutate", systemImage: "wand.and.sparkles")
                    }
                    Button("Guide", systemImage: "questionmark.circle") { showGuide = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Tap opens the sheet; long-press switches motion on or off.
                    Menu {
                        Toggle("Motion On", systemImage: "gyroscope", isOn: Bindable(synth).motionEnabled)
                    } label: {
                        Label("Motion", systemImage: "gyroscope")
                            .opacity(synth.motionEnabled ? 1 : 0.35)
                    } primaryAction: {
                        showMotion = true
                    }
                    // Tap opens the Library; long-press for Undo and Redo.
                    Menu {
                        Button("Redo", systemImage: "arrow.uturn.forward") { synth.redo() }
                            .disabled(!synth.canRedo)
                        Button("Undo", systemImage: "arrow.uturn.backward") { synth.undo() }
                            .disabled(!synth.canUndo)
                    } label: {
                        Label("Library", systemImage: "square.stack")
                    } primaryAction: {
                        showLibrary = true
                    }
                    Button("Save", systemImage: "bookmark") {
                        synth.saveSnapshot()
                        saved += 1
                        withAnimation(.snappy) { toast = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            withAnimation(.snappy) { toast = false }
                        }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .sensoryFeedback(.impact(weight: .heavy), trigger: resets)
            .sensoryFeedback(.success, trigger: kept)
            .overlay(alignment: .top) {
                if toast {
                    Label("Saved", systemImage: "bookmark.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect()
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 4)
                }
            }
            .sheet(isPresented: $showMotion) {
                MotionView()
                    .presentationDetents(synth.motion.available ? [.medium, .large] : [.large])
                    .interactiveDismissDisabled(!synth.motion.available)
            }
            .sheet(isPresented: $showGuide) {
                GuideView()
            }
            .sheet(isPresented: $showLibrary) {
                LibraryView().presentationDetents([.medium, .large])
            }
    }
}

// MARK: - Motion

struct MotionView: View {
    @Environment(Synth.self) private var synth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var motion = synth.motion
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Bindable(synth).motionEnabled) {
                        Label("Motion", systemImage: "gyroscope")
                    }
                } footer: {
                    Text(synth.motionEnabled
                         ? "Turn off to return every motion assignment to zero. Your assignments are kept."
                         : "Motion is off. Every slider plays exactly where you set it.")
                }
                if synth.motionEnabled {
                Section {
                    ForEach(synth.motionSlots) { slot in
                        SlotRow(slot: slot)
                    }
                    .onDelete { synth.motionSlots.remove(atOffsets: $0) }
                    Menu {
                        ForEach(MotionSource.allCases) { src in
                            Button(src.name, systemImage: src.symbol) {
                                // Starts on the voice you're looking at; change the target below.
                                synth.motionSlots.append(MotionSlot(source: src, targetKey: synth.sv(P.timbre).key))
                            }
                        }
                    } label: {
                        Label("Add Assignment", systemImage: "plus")
                    }
                    if !synth.motionSlots.isEmpty {
                        Button(role: .destructive) { synth.motionSlots.removeAll() } label: {
                            Label { Text("Remove All") } icon: { Image(systemName: "trash").foregroundStyle(.red) }
                        }
                    }
                } header: {
                    Text("Assignments")
                }
                if !synth.motion.available {
                    Section {
                        VirtualMotionPad()
                    } header: {
                        Text("Stand-in")
                    } footer: {
                        Text("No motion sensors here, so drag the pad to stand in for tilting the phone.")
                    }
                }
                Section {
                    ForEach(MotionSource.allCases) { src in
                        HStack {
                            Label(src.name, systemImage: src.symbol)
                            Spacer()
                            SourceMeter(value: synth.sourceValue(src), bipolar: src.bipolar)
                                .frame(width: 110, height: 8)
                        }
                    }
                } header: {
                    Text("Live")
                }

                Section {
                    Button("Set Level Here", systemImage: "scope") { synth.motion.recenter() }
                    Toggle(isOn: $motion.frozen) { Label("Freeze", systemImage: "pause.circle") }
                    VStack(alignment: .leading) {
                        Text("Full tilt at \(Int(synth.motion.tiltRange))°")
                        Slider(value: $motion.tiltRange, in: 15...80, step: 5)
                    }
                } footer: {
                    Text("Freeze holds the current motion values so you can put the phone down.")
                }

                ForEach(0..<2, id: \.self) { k in
                    LFOSection(index: k)
                }
                }
            }
            .navigationTitle("Motion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

private struct SlotRow: View {
    @Environment(Synth.self) private var synth
    let slot: MotionSlot

    private var binding: Binding<MotionSlot> {
        Binding(
            get: { synth.motionSlots.first { $0.id == slot.id } ?? slot },
            set: { new in
                if let i = synth.motionSlots.firstIndex(where: { $0.id == slot.id }) { synth.motionSlots[i] = new }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Source", selection: binding.source) {
                    ForEach(MotionSource.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("Target", selection: binding.targetKey) {
                    ForEach(P.motionTargetGroups(voices: synth.voicesOn), id: \.0) { group in
                        Section(group.0) {
                            // With three voices, say which one: "Timbre" alone could be any of them.
                            ForEach(group.1) { p in
                                Text(synth.voicesOn && p.perVoice ? "\(p.name) · Voice \(p.voice + 1)" : p.name).tag(p.key)
                            }
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            HStack {
                Text("Depth").foregroundStyle(.secondary)
                Slider(value: binding.depth, in: -1...1)
                Text(String(format: "%+.0f", binding.wrappedValue.depth * 100))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

private struct SourceMeter: View {
    let value: Float
    let bipolar: Bool
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let v = CGFloat(min(max(value, -1), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                Capsule()
                    .fill(Color.orange)
                    .frame(width: max(bipolar ? abs(v) * w / 2 : max(v, 0) * w, 3))
                    .offset(x: bipolar ? (v < 0 ? w / 2 + v * w / 2 : w / 2) : 0)
            }
        }
    }
}

/// The Simulator's stand-in for tilting: drag inside the square, twist below.
private struct VirtualMotionPad: View {
    @Environment(Synth.self) private var synth
    var body: some View {
        @Bindable var motion = synth.motion
        VStack(spacing: 12) {
            GeometryReader { g in
                let s = g.size
                let t = synth.motion.virtualTilt
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.fill.tertiary)
                    Path { p in
                        p.move(to: CGPoint(x: s.width / 2, y: 0)); p.addLine(to: CGPoint(x: s.width / 2, y: s.height))
                        p.move(to: CGPoint(x: 0, y: s.height / 2)); p.addLine(to: CGPoint(x: s.width, y: s.height / 2))
                    }
                    .stroke(.secondary.opacity(0.3))
                    Circle().fill(Color.orange).frame(width: 26, height: 26)
                        .position(x: (t.x + 1) / 2 * s.width, y: (t.y + 1) / 2 * s.height)
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                    synth.motion.virtualTilt = CGPoint(x: min(max(d.location.x / s.width * 2 - 1, -1), 1),
                                                       y: min(max(d.location.y / s.height * 2 - 1, -1), 1))
                })
            }
            .frame(height: 180)
            HStack {
                Text("Twist")
                Slider(value: $motion.virtualTwist, in: -1...1)
                Button("Shake") { synth.motion.virtualShakeBurst() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Library

struct LibraryView: View {
    @Environment(Synth.self) private var synth
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Snapshot?
    @State private var newName = ""
    @State private var confirmClear = false
    @State private var importing = false
    @State private var askName = false
    @AppStorage("creditName") private var creditName = ""
    @AppStorage("creditLicense") private var creditLicense = License.ccBy.rawValue
    @State private var playing: UUID?        // the entry you last tapped
    @State private var promoted = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Save Current Sound", systemImage: "bookmark") { synth.saveSnapshot() }
                    Button("Import Sounds…", systemImage: "square.and.arrow.down") { importing = true }
                    HStack {
                        // Coloured by hand: in a list row the system draws a disabled one black.
                        Button("Undo", systemImage: "arrow.uturn.backward") { synth.undo() }
                            .disabled(!synth.canUndo)
                            .foregroundStyle(synth.canUndo ? Color.accentColor : Color.secondary)
                        Spacer()
                        Button("Redo", systemImage: "arrow.uturn.forward") { synth.redo() }
                            .disabled(!synth.canRedo)
                            .foregroundStyle(synth.canRedo ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .sensoryFeedback(.selection, trigger: synth.historyCursor)
                }
                Section {
                    if synth.snapshots.isEmpty {
                        Text("Tap the bookmark whenever something sounds good.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(synth.snapshots) { s in
                        let share = SoundShare(name: s.name, sounds: [s])
                        row(s, subtitle: s.date.formatted(date: .abbreviated, time: .shortened))
                            .contextMenu {
                                if let credit = s.fullCredit { Section(credit) {} }
                                shareButton(share, title: s.name)
                                Button("Rename", systemImage: "pencil") { newName = s.name; renaming = s }
                                Button("Delete", systemImage: "trash", role: .destructive) { synth.delete(s) }
                            }
                            .swipeActions(edge: .leading) {
                                shareButton(share, title: s.name)
                                    .tint(.accentColor)
                            }
                    }
                    .onDelete { idx in idx.map { synth.snapshots[$0] }.forEach(synth.delete) }
                } header: {
                    HStack {
                        Text("Saved")
                        Spacer()
                        if !synth.snapshots.isEmpty {
                            shareButton(SoundShare(name: "Drift Sounds", sounds: synth.snapshots),
                                        title: "\(synth.snapshots.count) Drift sounds", label: "Share All")
                                .font(.footnote)
                                .textCase(nil)
                        }
                    }
                }
                Section {
                    ForEach(synth.history) { s in
                        row(s, subtitle: s.date.formatted(.relative(presentation: .named)))
                            .swipeActions(edge: .leading) {
                                Button("Save", systemImage: "bookmark") { synth.promote(s); promoted += 1 }
                                    .tint(.accentColor)
                            }
                            .contextMenu {
                                Button("Save to Saved Sounds", systemImage: "bookmark") { synth.promote(s); promoted += 1 }
                            }
                    }
                    .onDelete { synth.deleteHistory(at: $0) }
                } header: {
                    Text("Recent Changes")
                } footer: {
                    Text("Drift keeps your last 100 changes, so a sound you forgot to save can still be found. Swipe right to save one, left to delete it.")
                }
                if !synth.history.isEmpty {
                    Section {
                        Button(role: .destructive) { confirmClear = true } label: {
                            Label { Text("Clear Recent Changes") } icon: { Image(systemName: "trash").foregroundStyle(.red) }
                        }
                        .confirmationDialog("Clear all \(synth.history.count) recent changes?",
                                            isPresented: $confirmClear, titleVisibility: .visible) {
                            Button("Clear Recent Changes", role: .destructive) { synth.clearHistory() }
                        } message: {
                            Text("Your saved sounds are kept. Undo can't go back past this point.")
                        }
                    } footer: {
                        Text("Only clears Recent Changes. Saved sounds are not affected.")
                    }
                }
                Section {
                    TextField("Your name", text: $creditName)
                        .textContentType(.name)
                        .submitLabel(.done)
                    Picker("Licence", selection: $creditLicense) {
                        ForEach(License.allCases) { Text($0.summary).tag($0.rawValue) }
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Your name and licence go on sounds you share. Sounds made from someone else's keep their credit too.")
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .onAppear { synth.checkpoint() }
            .alert("Name to credit on shared sounds?", isPresented: $askName) {
                TextField("Your name", text: $creditName)
                Button("Save") {}
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Shared sounds say who made them and that they're \(License(rawValue: creditLicense)?.summary.lowercased() ?? "free to use"). You can change this under Sharing.")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.driftSound, .json],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { urls.forEach(synth.importFile) }
            }
            .sensoryFeedback(.success, trigger: promoted)
            .sensoryFeedback(.selection, trigger: playing)
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { if let r = renaming { synth.rename(r, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// Share, once you've given a name to credit; until then it asks for one first.
    @ViewBuilder private func shareButton(_ share: SoundShare, title: String, label: String = "Share") -> some View {
        if creditName.trimmingCharacters(in: .whitespaces).isEmpty {
            Button(label, systemImage: "square.and.arrow.up") { askName = true }
        } else {
            ShareLink(item: share, preview: SharePreview(title)) {
                Label(label, systemImage: "square.and.arrow.up")
            }
        }
    }

    private func row(_ s: Snapshot, subtitle: String) -> some View {
        // Tapping plays it and leaves the Library open, so you can audition one after another.
        Button {
            synth.audition(s)
            playing = s.id
        } label: {
            HStack {
                Image(systemName: Engines.info(Int(s.state.values[P.engine.key] ?? 8)).symbol)
                    .frame(width: 28)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    // Concrete colours: in a list button, .primary and .secondary take the tint.
                    Text(s.name).foregroundStyle(Color.primary)
                    let by = s.author.flatMap { $0 == creditName ? nil : "by \($0) · " } ?? ""
                    Text("\(by)\(s.engineName) · \(subtitle)").font(.caption).foregroundStyle(Color.secondary)
                }
                Spacer()
                if playing == s.id {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Playing")
                }
            }
        }
    }
}

/// One LFO's settings: shape, and either a free rate or a division of Marbles' beat.
private struct LFOSection: View {
    @Environment(Synth.self) private var synth
    let index: Int

    private var binding: Binding<LFOSettings> {
        Binding(get: { synth.lfoSettings[index] },
                set: { var all = synth.lfoSettings; all[index] = $0; synth.lfoSettings = all })
    }

    var body: some View {
        let s = binding.wrappedValue
        Section {
            Picker("Shape", selection: binding.shape) {
                ForEach(LFOShape.allCases) { Text($0.name).tag($0) }
            }
            Toggle("Follow Marbles' Beat", isOn: binding.sync)
            if s.sync {
                Picker("Every", selection: binding.division) {
                    ForEach(LFOSettings.divisions.indices, id: \.self) { Text(LFOSettings.divisions[$0].name).tag($0) }
                }
            } else {
                VStack(alignment: .leading) {
                    Text(Self.rateText(s.rate)).monospacedDigit()
                    // Logarithmic: equal travel for each doubling of speed.
                    Slider(value: Binding(get: { log2(Double(s.rate)) },
                                          set: { binding.wrappedValue.rate = Float(exp2($0)) }),
                           in: log2(0.02)...log2(8))
                }
            }
        } header: {
            Text("LFO \(index + 1)")
        }
    }

    static func rateText(_ hz: Float) -> String {
        hz >= 1 ? String(format: "%.1f per second", hz) : String(format: "Once every %.1f s", 1 / hz)
    }
}
