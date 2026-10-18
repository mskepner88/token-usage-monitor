import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ClaudeProvider: UsageProvider {
    public let id: ProviderID = .claude
    private let config: ClaudeConfig
    private let secrets: any SecretStore
    private let http: HTTPClient

    public init(
        config: ClaudeConfig,
        secrets: any SecretStore,
        http: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.secrets = secrets
        self.http = http
    }

    public func fetch() async -> ProviderSnapshot {
        let minAge = TimeInterval(max(config.minFetchIntervalSeconds, 60))

        // Prefer a fresh-enough cache — this endpoint 429s if polled like a dashboard.
        if let cached = ProviderResponseCache.load(provider: .claude, maxAge: minAge) {
            do {
                var snap = try Self.parse(data: cached.data, subscription: cached.subscription)
                snap.fetchedAt = cached.fetchedAt
                return snap
            } catch {
                // Fall through to network.
            }
        }

        do {
            var oauth = try ClaudeAuth.load(secrets: secrets)
            oauth = try await ClaudeAuth.refreshIfNeeded(
                oauth,
                secrets: secrets,
                http: http
            )

            let headers = [
                "Authorization": "Bearer \(oauth.accessToken)",
                "anthropic-beta": "oauth-2025-04-20",
                "Content-Type": "application/json",
                "User-Agent": "TokenUsageMonitor/0.1"
            ]
            let (data, response) = try await http.getJSON(url: ClaudeAuth.usageURL, headers: headers)
            guard (200..<300).contains(response.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                if response.statusCode == 401 || response.statusCode == 403 {
                    throw ProviderError.missingCredentials(
                        "Claude session expired. Run `claude login`."
                    )
                }
                if response.statusCode == 429 {
                    return rateLimitedSnapshot()
                }
                throw ProviderError.http(response.statusCode, text)
            }

            ProviderResponseCache.save(
                provider: .claude,
                payload: data,
                subscription: oauth.subscriptionType
            )
            return try Self.parse(data: data, subscription: oauth.subscriptionType)
        } catch let error as ProviderError {
            if case .http(429, _) = error {
                return rateLimitedSnapshot()
            }
            let state: ProviderLiveState =
                error.errorDescription?.localizedCaseInsensitiveContains("login") == true
                ? .needsAuth : .error
            return .unavailable(.claude, state: state, message: friendlyMessage(error.localizedDescription))
        } catch {
            return .unavailable(
                .claude,
                state: .error,
                message: friendlyMessage(error.localizedDescription)
            )
        }
    }

    private func rateLimitedSnapshot() -> ProviderSnapshot {
        if let cached = ProviderResponseCache.loadStale(provider: .claude),
           let snap = try? Self.parse(data: cached.data, subscription: cached.subscription) {
            var out = snap
            out.state = .stale
            out.fetchedAt = cached.fetchedAt
            out.message = "Rate limited — showing last good read."
            return out
        }
        return .unavailable(
            .claude,
            state: .stale,
            message: "Rate limited by Anthropic. TUM caches Claude for 5 minutes; try again shortly.",
            planLabel: "Claude"
        )
    }

    private func friendlyMessage(_ message: String) -> String {
        if message.contains("rate_limit_error") || message.contains("HTTP 429") {
            return "Rate limited by Anthropic. Try again in a few minutes."
        }
        return message
    }

    static func parse(data: Data, subscription: String?) throws -> ProviderSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decoding("Claude usage root")
        }

        var meters: [UsageMeter] = []

        if let five = window(json, keys: ["five_hour", "fiveHour", "session"]) {
            meters.append(
                meter(
                    from: five,
                    id: "session",
                    title: "5-hour window"
                )
            )
        }
        if let week = window(json, keys: ["seven_day", "sevenDay", "week", "weekly"]) {
            meters.append(
                meter(
                    from: week,
                    id: "week",
                    title: "This week"
                )
            )
        }

        // Nested utilization style used by some Anthropic responses.
        if meters.isEmpty, let util = json["utilization"] as? [String: Any] {
            if let five = util["five_hour"] as? [String: Any] {
                meters.append(meter(from: five, id: "session", title: "5-hour window"))
            }
            if let week = util["seven_day"] as? [String: Any] {
                meters.append(meter(from: week, id: "week", title: "This week"))
            }
        }

        if meters.isEmpty {
            throw ProviderError.decoding("No Claude usage windows found")
        }

        let plan = (subscription ?? (json["subscription_type"] as? String) ?? "Claude")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        return ProviderSnapshot(
            id: .claude,
            planLabel: plan,
            state: .live,
            meters: meters,
            detailSummary: "All \(meters.count) limits"
        )
    }

    private static func window(_ json: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = json[key] as? [String: Any] { return value }
        }
        return nil
    }

    private static func meter(from dict: [String: Any], id: String, title: String) -> UsageMeter {
        let used: Double = {
            if let u = dict["utilization"] as? Double { return u }
            if let u = dict["utilization"] as? Int { return Double(u) }
            if let u = dict["used_percent"] as? Double { return u }
            if let u = dict["percent_used"] as? Double { return u }
            return 0
        }()

        let reset: String? = {
            if let s = dict["resets_at"] as? String {
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let basic = ISO8601DateFormatter()
                basic.formatOptions = [.withInternetDateTime]
                if let date = fractional.date(from: s) ?? basic.date(from: s) {
                    return TUMFormatting.resetLabel(from: date)
                }
                return nil
            }
            if let unix = dict["resets_at"] as? Int {
                return TUMFormatting.resetLabel(unixSeconds: unix)
            }
            return nil
        }()

        return .fromUsedPercent(
            id: id,
            title: title,
            usedPercent: used,
            resetDescription: reset
        )
    }
}
