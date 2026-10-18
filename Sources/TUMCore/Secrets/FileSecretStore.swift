import Foundation

/// File-backed secret store for non-Keychain platforms (future Windows) or CI.
/// Path defaults to the config directory; file mode should stay user-private.
public struct FileSecretStore: SecretStore {
    private let fileURL: URL

    public init(directory: URL = ConfigStore.configDirectory) {
        self.fileURL = directory.appendingPathComponent("secrets.json")
    }

    public func get(account: String) throws -> String? {
        try load()[account]
    }

    public func set(_ value: String, account: String) throws {
        var map = try load()
        map[account] = value
        try save(map)
    }

    public func delete(account: String) throws {
        var map = try load()
        map.removeValue(forKey: account)
        try save(map)
    }

    private func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func save(_ map: [String: String]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(map)
        try data.write(to: fileURL, options: .atomic)
        #if os(macOS) || os(Linux)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        #endif
    }
}
