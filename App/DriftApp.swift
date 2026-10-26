import SwiftUI

@main
struct DriftApp: App {
    @State private var synth = Synth()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab { VoiceView() } label: { Label("Plaits", image: "PlaitsLogo", fallback: "waveform") }
                Tab { RandomView() } label: { Label("Marbles", image: "MarblesLogo", fallback: "circle.grid.3x3") }
                Tab("FX", systemImage: "fx") { FXView() }
                Tab("Scope", systemImage: "waveform.path.ecg") { ScopeView() }
            }
            .environment(synth)
            .onAppear { synth.start() }
            // A .drift file opened from Messages, Files or AirDrop.
            .onOpenURL { synth.importFile($0) }
            .alert(synth.importMessage ?? "", isPresented: Binding(
                get: { synth.importMessage != nil }, set: { if !$0 { synth.importMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .onChange(of: phase) { _, p in
                if p == .active { synth.start() } else { synth.persist(); synth.releaseAll() }
            }
        }
    }
}

extension Label where Title == Text, Icon == Image {
    /// Uses your private artwork (Local/Assets.xcassets) when it's in the build, otherwise
    /// an SF Symbol -- so the public repo builds without Mutable Instruments' logos.
    init(_ title: String, image name: String, fallback symbol: String) {
        if UIImage(named: name) != nil {
            self.init(title, image: name)
        } else {
            self.init(title, systemImage: symbol)
        }
    }
}
