import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct GrokAuthEntry: Codable, Sendable {
    var key: String
    var refreshToken: String?
    var expiresAt: String?
    var email: String?
    var oidcClientID: String?
    var oidcIssuer: String?

    enum CodingKeys: String, CodingKey {
        case key
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case email
        case oidcClientID = "oidc_client_id"
        case oidcIssuer = "oidc_issuer"
    }
}

enum GrokAuth {
    static let tokenURL = URL(string: "https://auth.x.ai/oauth2/token")!
    /// Default CLI billing (monthlyLimit/used) — often zeros for SuperGrok.
    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing")!
    /// Weekly SuperGrok pool (`creditUsagePercent`) — requires `x-xai-token-auth: xai-grok-cli`.
    static let creditsBillingURL = URL(
        string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
    )!
    static let subscriptionsURL = URL(string: "https://grok.com/rest/subscriptions")!

    static func load(from path: String) throws -> (key: String, entry: GrokAuthEntry, file: [String: GrokAuthEntry]) {
        let expanded = TUMFormatting.expandHome(path)
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProviderError.missingCredentials(
                "Grok auth not found at \(path). Run `grok login` first."
            )
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode([String: GrokAuthEntry].self, from: data)
        guard let (key, entry) = file.first else {
            throw ProviderError.missingCredentials("Grok auth file is empty. Run `grok login`.")
        }
        return (key, entry, file)
    }

    static func save(file: [String: GrokAuthEntry], to path: String) throws {
        let expanded = TUMFormatting.expandHome(path)
        let url = URL(fileURLWithPath: expanded)
        let backup = url.deletingPathExtension().appendingPathExtension("json.tum-backup")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    static func refreshIfNeeded(
        path: String,
        http _: HTTPClient
    ) async throws -> GrokAuthEntry {
        var (mapKey, entry, file) = try load(from: path)
        if let expiresAt = entry.expiresAt,
           let expiry = ISO8601DateFormatter().date(from: expiresAt)
            ?? ISO8601DateFormatter().date(from: expiresAt.replacingOccurrences(of: "Z", with: "+00:00")),
           expiry.timeIntervalSinceNow > 120 {
            return entry
        }
        guard let refresh = entry.refreshToken, !refresh.isEmpty else {
            throw ProviderError.missingCredentials("Grok token expired. Run `grok login`.")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refresh),
            URLQueryItem(name: "client_id", value: entry.oidcClientID ?? "")
        ]
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.missingCredentials(
                "Grok session expired. Run `grok login`. (\(httpResponse.statusCode))"
            )
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = json["access_token"] as? String
        else {
            throw ProviderError.decoding("Grok refresh response")
        }
        entry.key = access
        if let newRefresh = json["refresh_token"] as? String {
            entry.refreshToken = newRefresh
        }
        if let expiresIn = json["expires_in"] as? Double {
            let date = Date().addingTimeInterval(expiresIn)
            entry.expiresAt = ISO8601DateFormatter().string(from: date)
        }
        file[mapKey] = entry
        try save(file: file, to: path)
        return entry
    }
}
