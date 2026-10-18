import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GrokProvider: UsageProvider {
    public let id: ProviderID = .grok
    private let config: GrokConfig
    private let secrets: any SecretStore
    private let http: HTTPClient

    public init(
        config: GrokConfig,
        secrets: any SecretStore,
        http: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.secrets = secrets
        self.http = http
    }

    public func fetch() async -> ProviderSnapshot {
        do {
            let entry = try await GrokAuth.refreshIfNeeded(path: config.authPath, http: http)
            let headers = [
                "Authorization": "Bearer \(entry.key)",
                "Accept": "application/json",
                "User-Agent": "TokenUsageMonitor/0.1",
                // Required for `?format=credits` weekly SuperGrok pool (same as grok CLI).
                "x-xai-token-auth": "xai-grok-cli",
            ]

            async let subsData = http.getJSON(url: GrokAuth.subscriptionsURL, headers: [
                "Authorization": "Bearer \(entry.key)",
                "Accept": "application/json",
                "User-Agent": "TokenUsageMonitor/0.1",
            ])
            async let creditsData = http.getJSON(url: GrokAuth.creditsBillingURL, headers: headers)

            let (subRaw, subResp) = try await subsData
            let (credRaw, credResp) = try await creditsData

            var plan = "Grok"
            if (200..<300).contains(subResp.statusCode),
               let json = try JSONSerialization.jsonObject(with: subRaw) as? [String: Any] {
                plan = Self.planLabel(from: json)
            }

            var meters: [UsageMeter] = []
            if (200..<300).contains(credResp.statusCode),
               let meter = try? Self.creditsMeter(from: credRaw) {
                meters.append(meter)
            }

            // Optional cookie path kept as a secondary weekly source if credits JSON fails.
            if meters.isEmpty,
               let cookie = try? secrets.get(account: config.cookieKeychainAccount),
               !cookie.isEmpty,
               let weekly = await fetchWeeklyViaCookie(cookie) {
                meters.append(weekly)
            }

            guard !meters.isEmpty else {
                return .unavailable(
                    .grok,
                    state: .needsAuth,
                    message: "Could not read SuperGrok weekly credits. Run `grok login`.",
                    planLabel: plan
                )
            }

            return ProviderSnapshot(
                id: .grok,
                planLabel: plan,
                state: .live,
                meters: Array(meters.prefix(2)),
                detailSummary: meters.count > 1 ? "All \(meters.count) limits" : "Weekly pool"
            )
        } catch let error as ProviderError {
            let state: ProviderLiveState =
                error.errorDescription?.localizedCaseInsensitiveContains("login") == true
                ? .needsAuth : .error
            return .unavailable(.grok, state: state, message: error.localizedDescription)
        } catch {
            return .unavailable(.grok, state: .error, message: error.localizedDescription)
        }
    }

    /// `GET …/v1/billing?format=credits` → weekly SuperGrok pool %.
    private static func creditsMeter(from data: Data) throws -> UsageMeter {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let configObj = json["config"] as? [String: Any]
        else {
            throw ProviderError.decoding("Grok credits billing root")
        }

        let usedPercent: Double = {
            if let d = configObj["creditUsagePercent"] as? Double { return d }
            if let i = configObj["creditUsagePercent"] as? Int { return Double(i) }
            return -1
        }()
        guard usedPercent >= 0 else {
            throw ProviderError.decoding("Grok creditUsagePercent missing")
        }

        let periodEnd = (configObj["billingPeriodEnd"] as? String)
            .flatMap(parseDate)
            ?? ((configObj["currentPeriod"] as? [String: Any])?["end"] as? String).flatMap(parseDate)

        let periodType = ((configObj["currentPeriod"] as? [String: Any])?["type"] as? String) ?? ""
        let title = periodType.contains("WEEKLY") ? "This week" : "Credits"

        var footnote: String?
        if let products = configObj["productUsage"] as? [[String: Any]] {
            let parts: [String] = products.compactMap { row in
                let name = (row["product"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let pct = (row["usagePercent"] as? Double)
                    ?? (row["usagePercent"] as? Int).map(Double.init)
                guard let pct else { return nil }
                if let name, !name.isEmpty {
                    return "\(name) \(Int(pct.rounded()))%"
                }
                return "Other \(Int(pct.rounded()))%"
            }
            if !parts.isEmpty {
                footnote = parts.prefix(3).joined(separator: " · ")
            }
        }

        return .fromUsedPercent(
            id: "week",
            title: title,
            usedPercent: usedPercent,
            resetDescription: periodEnd.map { TUMFormatting.resetLabel(from: $0, includeTime: false) },
            footnote: footnote
        )
    }

    private func fetchWeeklyViaCookie(_ cookie: String) async -> UsageMeter? {
        let url = URL(string: "https://grok.com/rest/subscriptions")!
        let headers = [
            "Cookie": cookie,
            "Accept": "application/json",
            "User-Agent": "TokenUsageMonitor/0.1",
        ]
        guard let (data, response) = try? await http.getJSON(url: url, headers: headers),
              (200..<300).contains(response.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let percent = json["usagePercent"] as? Double
            ?? (json["usagePercent"] as? Int).map(Double.init) {
            return .fromUsedPercent(
                id: "week",
                title: "This week",
                usedPercent: percent,
                resetDescription: Self.periodEnd(from: json).map { TUMFormatting.resetLabel(from: $0) }
            )
        }
        return nil
    }

    private static func planLabel(from json: [String: Any]) -> String {
        if let dominant = json["dominantPlan"] as? [String: Any] {
            if let names = dominant["surfaceNames"] as? [String: String],
               let display = names["SURFACE_DISPLAY"], !display.isEmpty {
                return display
            }
            if let plan = dominant["plan"] as? String {
                return friendlyPlan(plan)
            }
            if let tier = dominant["tier"] as? String {
                return friendlyPlan(tier)
            }
        }
        if let subs = json["subscriptions"] as? [[String: Any]],
           let tier = subs.first?["tier"] as? String {
            return friendlyPlan(tier)
        }
        return "Grok"
    }

    private static func friendlyPlan(_ raw: String) -> String {
        let s = raw
            .replacingOccurrences(of: "SUBSCRIPTION_TIER_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .lowercased()
        if s.contains("heavy") || s.contains("ultra") { return "SuperGrok Heavy" }
        if s.contains("super") && s.contains("pro") { return "SuperGrok Pro" }
        if s.contains("super") { return "SuperGrok" }
        if s.contains("pro") { return "Pro" }
        return s.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }

    private static func periodEnd(from json: [String: Any]) -> Date? {
        if let dominant = json["dominantPlan"] as? [String: Any],
           let end = dominant["billingPeriodEnd"] as? String {
            return parseDate(end)
        }
        if let subs = json["subscriptions"] as? [[String: Any]],
           let end = subs.first?["billingPeriodEnd"] as? String {
            return parseDate(end)
        }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }
}
