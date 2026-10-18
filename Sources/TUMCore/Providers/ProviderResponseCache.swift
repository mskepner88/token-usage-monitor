import Foundation

/// Disk cache for raw provider API payloads so we can avoid hammering rate-limited endpoints.
public enum ProviderResponseCache {
    private static var directory: URL {
        ConfigStore.configDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    private struct Envelope: Codable {
        var fetchedAt: Date
        var subscription: String?
        var payload: Data
    }

    public static func load(provider: ProviderID, maxAge: TimeInterval) -> (data: Data, subscription: String?, fetchedAt: Date)? {
        let url = fileURL(for: provider)
        guard let data = try? Data(contentsOf: url),
              let env = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }
        guard Date().timeIntervalSince(env.fetchedAt) <= maxAge else { return nil }
        return (env.payload, env.subscription, env.fetchedAt)
    }

    /// Returns any cached payload regardless of age (for 429 fallback).
    public static func loadStale(provider: ProviderID) -> (data: Data, subscription: String?, fetchedAt: Date)? {
        let url = fileURL(for: provider)
        guard let data = try? Data(contentsOf: url),
              let env = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }
        return (env.payload, env.subscription, env.fetchedAt)
    }

    public static func save(provider: ProviderID, payload: Data, subscription: String?) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let env = Envelope(fetchedAt: .now, subscription: subscription, payload: payload)
        guard let data = try? JSONEncoder().encode(env) else { return }
        try? data.write(to: fileURL(for: provider), options: .atomic)
    }

    public static func clear(provider: ProviderID) {
        try? FileManager.default.removeItem(at: fileURL(for: provider))
    }

    private static func fileURL(for provider: ProviderID) -> URL {
        directory.appendingPathComponent("\(provider.rawValue)-usage.json")
    }
}
