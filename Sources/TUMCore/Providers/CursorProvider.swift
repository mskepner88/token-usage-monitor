import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CursorProvider: UsageProvider {
    public let id: ProviderID = .cursor
    private let config: CursorConfig
    private let secrets: any SecretStore
    private let http: HTTPClient

    public init(
        config: CursorConfig,
        secrets: any SecretStore,
        http: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.secrets = secrets
        self.http = http
    }

    public func fetch() async -> ProviderSnapshot {
        do {
            let token = try CursorAuth.resolveAccessToken(config: config, secrets: secrets)

            // Prefer Connect RPC (Bearer) — same payload as the Ultra dashboard "Weekly usage limit".
            if let snap = await fetchPeriodUsage(bearer: token) {
                return snap
            }

            // Fallback: dashboard cookie + usage-summary (older shape).
            return try await fetchUsageSummary(token: token)
        } catch let error as ProviderError {
            let state: ProviderLiveState = {
                switch error {
                case .notConfigured, .missingCredentials: return .needsAuth
                default: return .error
                }
            }()
            return .unavailable(.cursor, state: state, message: error.localizedDescription)
        } catch {
            return .unavailable(.cursor, state: .error, message: error.localizedDescription)
        }
    }

    private func fetchPeriodUsage(bearer: String) async -> ProviderSnapshot? {
        let url = URL(
            string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
        )!
        guard let (data, response) = try? await http.postJSON(
            url: url,
            body: [:],
            headers: [
                "Authorization": "Bearer \(bearer)",
                "Accept": "application/json",
                "Connect-Protocol-Version": "1",
                "User-Agent": "TokenUsageMonitor/0.1",
            ]
        ), (200..<300).contains(response.statusCode) else {
            return nil
        }
        return try? Self.parsePeriodUsage(data: data)
    }

    private func fetchUsageSummary(token: String) async throws -> ProviderSnapshot {
        let url = URL(string: "https://cursor.com/api/usage-summary")!
        let headers = [
            "Cookie": CursorAuth.workosCookie(from: token),
            "Accept": "application/json",
            "User-Agent": "TokenUsageMonitor/0.1",
            "Referer": "https://cursor.com/dashboard",
            "Origin": "https://cursor.com",
        ]
        let (data, response) = try await http.getJSON(url: url, headers: headers)
        guard (200..<300).contains(response.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            if response.statusCode == 401 || response.statusCode == 403 {
                throw ProviderError.missingCredentials(
                    "Cursor session expired. Sign in again in the Cursor app."
                )
            }
            throw ProviderError.http(response.statusCode, text)
        }
        return try Self.parseUsageSummary(data: data)
    }

    /// Ultra dashboard "Weekly usage limit" lives here as `planUsage.autoPercentUsed`.
    static func parsePeriodUsage(data: Data) throws -> ProviderSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decoding("Cursor period usage root")
        }

        let planUsage = json["planUsage"] as? [String: Any] ?? [:]
        let auto = double(planUsage["autoPercentUsed"])
            ?? percentFromMessage(json["autoModelSelectedDisplayMessage"] as? String)
            ?? 0
        let api = double(planUsage["apiPercentUsed"])
            ?? percentFromMessage(json["namedModelSelectedDisplayMessage"] as? String)
            ?? 0

        let resetAt = dateFromEpochMs(json["billingCycleEnd"])
            ?? resetDate(from: json)
        let reset = resetLabel(resetAt)

        var meters: [UsageMeter] = [
            .fromUsedPercent(
                id: "weekly",
                title: "Weekly limit",
                usedPercent: auto,
                resetDescription: reset,
                resetsAt: resetAt,
                footnote: "Included in Ultra · Cursor Models"
            ),
        ]
        if api > 0.05 {
            meters.append(
                .fromUsedPercent(
                    id: "other",
                    title: "Other models",
                    usedPercent: api,
                    resetDescription: reset,
                    resetsAt: resetAt
                )
            )
        }

        let plan = membershipLabel(
            (json["membershipType"] as? String)
                ?? "ultra"
        )

        return ProviderSnapshot(
            id: .cursor,
            planLabel: plan,
            state: .live,
            meters: Array(meters.prefix(2)),
            detailSummary: "Ultra pools"
        )
    }

    static func parseUsageSummary(data: Data) throws -> ProviderSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decoding("Cursor usage root")
        }

        let membership = (json["membershipType"] as? String) ?? "Cursor"
        let plan = membershipLabel(membership)
        let individual = json["individualUsage"] as? [String: Any] ?? [:]
        let planUsage = individual["plan"] as? [String: Any] ?? [:]

        let auto = double(planUsage["autoPercentUsed"])
            ?? percentFromMessage(json["autoModelSelectedDisplayMessage"] as? String)
        let api = double(planUsage["apiPercentUsed"])
            ?? percentFromMessage(json["namedModelSelectedDisplayMessage"] as? String)
        let total = double(planUsage["totalPercentUsed"])
            ?? percentUsed(in: planUsage)

        let resetAt = resetDate(from: json)
        let reset = resetLabel(resetAt)
        var meters: [UsageMeter] = []

        if let auto {
            meters.append(
                .fromUsedPercent(
                    id: "weekly",
                    title: "Weekly limit",
                    usedPercent: auto,
                    resetDescription: reset,
                    resetsAt: resetAt,
                    footnote: "Cursor Models pool"
                )
            )
        }
        if let api, api > 0.05 {
            meters.append(
                .fromUsedPercent(
                    id: "other",
                    title: "Other models",
                    usedPercent: api,
                    resetDescription: reset,
                    resetsAt: resetAt
                )
            )
        }
        if meters.isEmpty, let total {
            meters.append(
                .fromUsedPercent(
                    id: "included",
                    title: "Included",
                    usedPercent: total,
                    resetDescription: reset,
                    resetsAt: resetAt
                )
            )
        }
        if meters.isEmpty {
            meters = legacyMeters(from: json)
        }
        if meters.isEmpty {
            throw ProviderError.decoding("Unrecognized Cursor usage payload")
        }

        return ProviderSnapshot(
            id: .cursor,
            planLabel: plan,
            state: .live,
            meters: Array(meters.prefix(2)),
            detailSummary: "All \(max(meters.count, 1)) limits"
        )
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func percentFromMessage(_ message: String?) -> Double? {
        guard let message else { return nil }
        // "You've used 4% of your included total usage"
        guard let r = message.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression)
        else { return nil }
        let num = message[r].replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(num)
    }

    private static func percentUsed(in dict: [String: Any]) -> Double? {
        if let v = dict["totalPercentUsed"] as? Double { return v }
        if let v = dict["totalPercentUsed"] as? Int { return Double(v) }
        if let v = dict["percentUsed"] as? Double { return v }
        if let used = dict["used"] as? Double, let limit = dict["limit"] as? Double, limit > 0 {
            return (used / limit) * 100
        }
        return nil
    }

    private static func dateFromEpochMs(_ value: Any?) -> Date? {
        let ms: Double? = {
            switch value {
            case let s as String: return Double(s)
            case let d as Double: return d
            case let i as Int: return Double(i)
            default: return nil
            }
        }()
        guard let ms, ms > 1_000_000_000_000 else {
            // maybe already seconds
            if let ms, ms > 1_000_000_000 {
                return Date(timeIntervalSince1970: ms)
            }
            return nil
        }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    private static func resetLabel(_ date: Date?) -> String? {
        date.map { TUMFormatting.resetLabel(from: $0, includeTime: false) }
    }

    private static func resetDate(from dict: [String: Any]) -> Date? {
        if let end = dict["billingCycleEnd"] as? String {
            if let ms = Double(end), ms > 1_000_000_000_000 {
                return dateFromEpochMs(ms)
            }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: end) ?? ISO8601DateFormatter().date(from: end) {
                return date
            }
        }
        return dateFromEpochMs(dict["billingCycleEnd"])
    }

    private static func membershipLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "pro": return "Pro"
        case "pro_plus", "proplus", "pro+": return "Pro+"
        case "ultra", "unified_ultra": return "Ultra"
        case "business": return "Business"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        case "hobby", "free": return "Hobby"
        default:
            if raw.lowercased().contains("ultra") { return "Ultra" }
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func legacyMeters(from json: [String: Any]) -> [UsageMeter] {
        var meters: [UsageMeter] = []
        for (key, value) in json {
            guard let dict = value as? [String: Any],
                  let used = dict["numRequests"] as? Double
                    ?? (dict["numRequests"] as? Int).map(Double.init),
                  let limit = dict["maxRequestUsage"] as? Double
                    ?? (dict["maxRequestUsage"] as? Int).map(Double.init),
                  limit > 0
            else { continue }
            meters.append(
                .fromUsedPercent(
                    id: key,
                    title: key == "gpt-4" ? "Included" : key,
                    usedPercent: (used / limit) * 100,
                    resetDescription: resetLabel(resetDate(from: json)),
                    resetsAt: resetDate(from: json)
                )
            )
        }
        return Array(meters.prefix(2))
    }
}
