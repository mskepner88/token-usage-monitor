import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CodexProvider: UsageProvider {
    public let id: ProviderID = .codex
    private let config: CodexConfig
    private let http: HTTPClient

    public init(config: CodexConfig, http: HTTPClient = HTTPClient()) {
        self.config = config
        self.http = http
    }

    public func fetch() async -> ProviderSnapshot {
        do {
            var auth = try CodexAuth.load(from: config.authPath)
            var (data, response) = try await requestUsage(auth: auth)

            if response.statusCode == 401 {
                auth = try await CodexAuth.refresh(auth, http: http)
                try CodexAuth.save(auth, to: config.authPath)
                (data, response) = try await requestUsage(auth: auth)
            }

            guard (200..<300).contains(response.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw ProviderError.http(response.statusCode, text)
            }
            return try Self.parse(data: data)
        } catch let error as ProviderError {
            let state: ProviderLiveState =
                (error.errorDescription?.localizedCaseInsensitiveContains("login") == true
                    || error.errorDescription?.localizedCaseInsensitiveContains("credentials") == true)
                ? .needsAuth : .error
            return .unavailable(.codex, state: state, message: error.localizedDescription)
        } catch {
            return .unavailable(.codex, state: .error, message: error.localizedDescription)
        }
    }

    private func requestUsage(auth: CodexAuthFile) async throws -> (Data, HTTPURLResponse) {
        var headers: [String: String] = [
            "Authorization": "Bearer \(auth.tokens.accessToken)",
            "Accept": "application/json",
            "User-Agent": "TokenUsageMonitor/0.1",
            "Origin": "https://chatgpt.com",
            "Referer": "https://chatgpt.com/"
        ]
        if let account = auth.tokens.accountID {
            headers["ChatGPT-Account-ID"] = account
        }
        return try await http.getJSON(url: CodexAuth.usageURL, headers: headers)
    }

    static func parse(data: Data) throws -> ProviderSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decoding("Codex usage root")
        }
        let plan = (json["plan_type"] as? String)?.capitalized ?? "Codex"
        let rate = json["rate_limit"] as? [String: Any]
        let primary = rate?["primary_window"] as? [String: Any]
        let secondary = rate?["secondary_window"] as? [String: Any]

        var meters: [UsageMeter] = []
        if let primary {
            meters.append(meter(from: primary, id: "week", title: "This week", preferWeeklyLabel: true))
        }
        if let secondary, meters.isEmpty || meters.count < 2 {
            // Prefer showing weekly as primary when primary is the 5h window.
            let primarySeconds = (primary?["limit_window_seconds"] as? Int) ?? 0
            if let primary, primarySeconds > 0 && primarySeconds < 86_400 {
                // Rebuild: 5h + week
                meters = [
                    meter(from: primary, id: "session", title: "5-hour window", preferWeeklyLabel: false),
                    meter(from: secondary, id: "week", title: "This week", preferWeeklyLabel: true)
                ]
            } else {
                meters.append(meter(from: secondary, id: "secondary", title: "Secondary", preferWeeklyLabel: false))
            }
        }

        // Match screenshot style: single weekly bar when 5h is unused / identical.
        if meters.count == 2,
           let p = primary,
           let used = p["used_percent"] as? Double,
           used == 0,
           let sec = secondary {
            meters = [meter(from: sec, id: "week", title: "This week", preferWeeklyLabel: true)]
        }

        var footnote: String?
        if let resets = json["rate_limit_reset_credits"] as? [String: Any],
           let count = resets["available_count"] as? Int {
            footnote = "\(count) quota resets available."
        }

        if var first = meters.first, footnote != nil {
            first.footnote = footnote
            meters[0] = first
        }

        let detail = meters.count > 1 ? "All \(meters.count) limits" : "Details"
        return ProviderSnapshot(
            id: .codex,
            planLabel: planLabel(plan),
            state: .live,
            meters: meters,
            detailSummary: detail
        )
    }

    private static func planLabel(_ plan: String) -> String {
        switch plan.lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        default: return plan
        }
    }

    private static func meter(
        from window: [String: Any],
        id: String,
        title: String,
        preferWeeklyLabel: Bool
    ) -> UsageMeter {
        let used = (window["used_percent"] as? Double)
            ?? (window["used_percent"] as? Int).map(Double.init)
            ?? 0
        let resetAt = window["reset_at"] as? Int
        let seconds = window["limit_window_seconds"] as? Int
        var label = title
        if preferWeeklyLabel, let seconds, seconds >= 600_000 {
            label = "This week"
        } else if let seconds, seconds <= 20_000 {
            label = "5-hour window"
        }
        return .fromUsedPercent(
            id: id,
            title: label,
            usedPercent: used,
            resetDescription: TUMFormatting.resetLabel(unixSeconds: resetAt),
            resetsAt: resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}
