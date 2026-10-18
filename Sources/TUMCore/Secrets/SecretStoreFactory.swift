import Foundation

public enum SecretBackend: String, Codable, Sendable, CaseIterable {
    /// Local JSON under Application Support / XDG config (best for development).
    case file
    /// macOS Keychain (more prompts; better if you share the machine).
    case keychain
}

public enum SecretStoreFactory {
    public static func make(backend: SecretBackend) -> any SecretStore {
        switch backend {
        case .file:
            return FileSecretStore()
        case .keychain:
            #if os(macOS)
            return KeychainSecretStore()
            #else
            return FileSecretStore()
            #endif
        }
    }

    public static var secretsFileURL: URL {
        ConfigStore.configDirectory.appendingPathComponent("secrets.json")
    }
}
