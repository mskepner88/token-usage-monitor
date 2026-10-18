import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ClaudeOAuth: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Double?
    var subscriptionType: String?
    var rateLimitTier: String?
    var scopes: [String]?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresAt
        case subscriptionType
        case rateLimitTier
        case scopes
    }
}

struct ClaudeCredentialsBlob: Codable, Sendable {
    var claudeAiOauth: ClaudeOAuth?
}

public enum ClaudeAuth {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let secretsAccount = "claude-oauth"

    /// Local file — never Keychain (avoids macOS permission dialogs).
    public static var credentialsFileURL: URL {
        ConfigStore.configDirectory.appendingPathComponent("claude-credentials.json")
    }

    public static func load(secrets: (any SecretStore)? = nil) throws -> ClaudeOAuth {
        // 1) TUM secrets.json
        if let secrets,
           let raw = try secrets.get(account: secretsAccount),
           !raw.isEmpty {
            return try decode(raw)
        }

        // 2) TUM Application Support file
        if FileManager.default.fileExists(atPath: credentialsFileURL.path) {
            let raw = try String(contentsOf: credentialsFileURL, encoding: .utf8)
            return try decode(raw)
        }

        // 3) Claude Code credentials file (if the CLI wrote one)
        let claudeFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if FileManager.default.fileExists(atPath: claudeFile.path) {
            let raw = try String(contentsOf: claudeFile, encoding: .utf8)
            return try decode(raw)
        }

        throw ProviderError.missingCredentials(
            "Claude credentials not found. Paste them in Settings (or save to \(credentialsFileURL.path)). TUM never reads the Keychain."
        )
    }

    public static func save(_ oauth: ClaudeOAuth, secrets: (any SecretStore)? = nil) throws {
        let blob = ClaudeCredentialsBlob(claudeAiOauth: oauth)
        let data = try JSONEncoder().encode(blob)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw ProviderError.decoding("Claude credentials encode")
        }

        try FileManager.default.createDirectory(
            at: credentialsFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: credentialsFileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialsFileURL.path
        )

        try secrets?.set(raw, account: secretsAccount)
    }

    public static func saveRaw(_ raw: String, secrets: (any SecretStore)? = nil) throws {
        let oauth = try decode(raw)
        try save(oauth, secrets: secrets)
    }

    static func refreshIfNeeded(
        _ oauth: ClaudeOAuth,
        secrets: (any SecretStore)?,
        http: HTTPClient
    ) async throws -> ClaudeOAuth {
        if let expiresAt = oauth.expiresAt {
            let expiry = Date(timeIntervalSince1970: expiresAt / 1000)
            if expiry.timeIntervalSinceNow > 120 {
                return oauth
            }
        }
        guard let refresh = oauth.refreshToken, !refresh.isEmpty else {
            throw ProviderError.missingCredentials(
                "Claude token expired. Run `claude login`, then paste credentials in TUM Settings."
            )
        }
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID
        ]
        let (data, response) = try await http.postJSON(url: tokenURL, body: body)
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError.missingCredentials(
                "Claude session expired. Run `claude login`, then paste credentials in TUM Settings. (\(response.statusCode))"
            )
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = json["access_token"] as? String
        else {
            throw ProviderError.decoding("Claude refresh response")
        }
        var updated = oauth
        updated.accessToken = access
        if let refreshToken = json["refresh_token"] as? String {
            updated.refreshToken = refreshToken
        }
        if let expiresIn = json["expires_in"] as? Double {
            updated.expiresAt = (Date().timeIntervalSince1970 + expiresIn) * 1000
        }
        try? save(updated, secrets: secrets)
        return updated
    }

    static func decode(_ raw: String) throws -> ClaudeOAuth {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmed.utf8)
        if let blob = try? JSONDecoder().decode(ClaudeCredentialsBlob.self, from: data),
           let oauth = blob.claudeAiOauth {
            return oauth
        }
        if let oauth = try? JSONDecoder().decode(ClaudeOAuth.self, from: data) {
            return oauth
        }
        // Bare access token paste
        if trimmed.count > 20, !trimmed.contains("{") {
            return ClaudeOAuth(accessToken: trimmed)
        }
        throw ProviderError.decoding("Claude credentials JSON")
    }
}
