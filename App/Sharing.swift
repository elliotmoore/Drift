import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A Drift sound file: JSON, `.drift`. Declared in Info.plist (project.yml), so the
    /// share sheet names it properly and tapping one in Messages or Files opens Drift.
    static let driftSound = UTType(exportedAs: "org.drift.sound", conformingTo: .json)
}

/// What a .drift file holds: one or more saved sounds, with a format tag and version so
/// later Drifts can still read today's files.
struct SoundFile: Codable {
    var format = "drift.sounds"
    var version = 1
    var sounds: [Snapshot]

    /// Reads a .drift file, or a bare sound or list of sounds. Every sound is cleaned up
    /// (values clamped, unknown settings dropped) and given a fresh identity.
    static func read(_ data: Data) throws -> [Snapshot] {
        let decoder = JSONDecoder()
        let raw: [Snapshot]
        if let file = try? decoder.decode(SoundFile.self, from: data) {
            raw = file.sounds
        } else if let list = try? decoder.decode([Snapshot].self, from: data) {
            raw = list
        } else {
            raw = [try decoder.decode(Snapshot.self, from: data)]
        }
        return raw.prefix(500).map { s in
            let name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let clean = { (t: String?) in t.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) } }
            return Snapshot(name: String((name.isEmpty ? "Imported" : name).prefix(80)),
                            date: Date(), state: s.state.sanitized(),
                            author: clean(s.author), license: clean(s.license), basedOn: clean(s.basedOn))
        }
    }
}

/// Something the share sheet can send: a .drift file named after the sound (or bank).
struct SoundShare: Transferable {
    let name: String
    let sounds: [Snapshot]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .driftSound) { share in
            let safe = share.name.components(separatedBy: CharacterSet(charactersIn: "/\\\\:?%*|\"<>"))
                .joined(separator: "-")
            let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appending(path: "\(safe.isEmpty ? "Drift" : safe).drift")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(SoundFile(sounds: Credit.stamp(share.sounds))).write(to: url)
            return SentTransferredFile(url)
        }
    }
}

extension Synth {
    /// Adds sounds from a file to Saved. Returns how many came in.
    @discardableResult
    func importSounds(from url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count < 20_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let sounds = try SoundFile.read(data)
        addToSaved(sounds)
        return sounds.count
    }
}

// MARK: - Credit

/// The licences a shared sound can carry.
enum License: String, CaseIterable, Identifiable {
    case ccBy = "CC BY 4.0"
    case cc0 = "CC0"
    var id: String { rawValue }
    var summary: String {
        switch self {
        case .ccBy: "Free to use, please credit"
        case .cc0: "Public domain, no credit needed"
        }
    }
    static func summary(_ raw: String?) -> String? { raw.flatMap { License(rawValue: $0)?.summary ?? $0 } }
}

/// Your name and licence for shared sounds. Kept on the device, not in sounds you keep.
enum Credit {
    static var name: String {
        get { UserDefaults.standard.string(forKey: "creditName") ?? "" }
        set { UserDefaults.standard.set(String(newValue.prefix(60)), forKey: "creditName") }
    }
    static var license: License {
        get { License(rawValue: UserDefaults.standard.string(forKey: "creditLicense") ?? "") ?? .ccBy }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "creditLicense") }
    }

    /// Sounds as they leave: yours get your name and licence; other people's keep theirs.
    static func stamp(_ sounds: [Snapshot]) -> [Snapshot] {
        let me = name.trimmingCharacters(in: .whitespaces)
        return sounds.map { s in
            guard s.author == nil, !me.isEmpty else { return s }
            var c = s
            c.author = me
            c.license = license.rawValue
            return c
        }
    }
}

extension Snapshot {
    /// "by Sam", if someone else made it.
    var creditLine: String? { author.map { "by \($0)" } }
    /// How to credit this sound in something made from it.
    var originLine: String { "‘\(name)’" + (author.map { " by \($0)" } ?? "") }
    /// Everything about where it came from, for the Library.
    var fullCredit: String? {
        let parts = [creditLine, License.summary(license), basedOn.map { "Based on \($0)" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
