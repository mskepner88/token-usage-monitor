import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CodexTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountID = "account_id"
    }
}

struct CodexAuthFile: Codable, Sendable {
    var tokens: CodexTokens
    var lastRefresh: String?
    var authMode: String?
    var openAIAPIKey: String?

    enum CodingKeys: String, CodingKey {
        case tokens
        case lastRefresh = "last_refresh"
        case authMode = "auth_mode"
        case openAIAPIKey = "OPENAI_API_KEY"
    }
}

enum CodexAuth {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static func load(from path: String) throws -> CodexAuthFile {
        let expanded = TUMFormatting.expandHome(path)
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProviderError.missingCredentials(
                "Codex auth not found at \(path). Run `codex login` first."
            )
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CodexAuthFile.self, from: data)
    }

    static func save(_ auth: CodexAuthFile, to path: String) throws {
        let expanded = TUMFormatting.expandHome(path)
        let url = URL(fileURLWithPath: expanded)
        // Keep a local backup before rotating refresh tokens.
        let backup = url.deletingPathExtension().appendingPathExtension("json.tum-backup")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var mutable = auth
        mutable.lastRefresh = ISO8601DateFormatter().string(from: Date())
        let data = try encoder.encode(mutable)
        try data.write(to: url, options: .atomic)
    }

    static func refresh(
        _ auth: CodexAuthFile,
        http: HTTPClient
    ) async throws -> CodexAuthFile {
        let body: [String: Any] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": auth.tokens.refreshToken,
            "scope": "openid profile email offline_access"
        ]
        let (data, response) = try await http.postJSON(url: tokenURL, body: body)
        guard (200..<300).contains(response.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.http(response.statusCode, text)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = json["access_token"] as? String,
            let refresh = json["refresh_token"] as? String
        else {
            throw ProviderError.decoding("Codex refresh response")
        }
        var updated = auth
        updated.tokens.accessToken = access
        updated.tokens.refreshToken = refresh
        if let id = json["id_token"] as? String {
            updated.tokens.idToken = id
        }
        return updated
    }
}
