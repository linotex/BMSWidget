import Foundation

/// Hands the latest snapshot and the UI language from the app to the widget through files in the real
/// ~/Library/Application Support/BMSWidget. Both targets are sandboxed and reach it through a
/// home-relative-path temporary exception, so no App Group (and no Team ID) is needed.
enum SnapshotStore {
    private static func url(_ name: String) -> URL? {
        // NSHomeDirectory() points into the sandbox container; the shared files live in the real home.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home))
            .appendingPathComponent("Library/Application Support/BMSWidget/\(name)")
    }

    private static func write(_ data: Data, to name: String) {
        guard let url = url(name) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func save(_ snapshot: BMSSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        write(data, to: "snapshot.json")
    }

    static func load() -> BMSSnapshot? {
        guard let url = url("snapshot.json"), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BMSSnapshot.self, from: data)
    }

    static func save(_ language: Language) {
        write(Data(language.rawValue.utf8), to: "language")
    }

    static func loadLanguage() -> Language {
        guard let url = url("language"), let data = try? Data(contentsOf: url) else { return .en }
        return Language(rawValue: String(decoding: data, as: UTF8.self)) ?? .en
    }
}
