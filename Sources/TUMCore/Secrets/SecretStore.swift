import Foundation

public protocol SecretStore: Sendable {
    func get(account: String) throws -> String?
    func set(_ value: String, account: String) throws
    func delete(account: String) throws
}

public enum TUMSecrets {
    /// Namespace for secrets TUM stores itself (Cursor cookie, optional overrides).
    public static let service = SkeptacularBrand.bundleID
}
