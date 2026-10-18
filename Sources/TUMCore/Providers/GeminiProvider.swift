import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Gemini usage from Google directly: API key health + Cloud Monitoring request counts
/// against Service Usage daily quotas for the GCP project configured in Settings.
public struct GeminiProvider: UsageProvider {
    public let id: ProviderID = .gemini
    private let config: GeminiConfig
    private let secrets: any SecretStore
    private let http: HTTPClient

    public init(
        config: GeminiConfig,
        secrets: any SecretStore,
        http: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.secrets = secrets
        self.http = http
    }

    public func fetch() async -> ProviderSnapshot {
        do {
            if let cached = Self.loadCache(maxAge: TimeInterval(max(config.cacheTTLSeconds, 60))) {
                return cached
            }

            let apiKey = try GeminiAuth.resolveAPIKey(config: config, secrets: secrets)
            let model = try await verifyKey(apiKey: apiKey)

            let project = config.gcpProject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !project.isEmpty else {
                throw ProviderError.notConfigured("Gemini gcpProject is empty.")
            }

            let token = try GeminiAuth.resolveGCloudAccessToken(config: config)
            let limits = try await fetchDailyLimits(project: project, token: token)
            let usage = try await fetchTodayUsage(project: project, token: token)

            let snap = Self.snapshot(
                model: model,
                project: project,
                limits: limits,
                usage: usage
            )
            Self.saveCache(snap)
            return snap
        } catch let error as ProviderError {
            let state: ProviderLiveState = {
                switch error {
                case .missingCredentials: return .needsAuth
                default: return .offline
                }
            }()
            return .unavailable(
                .gemini,
                state: state,
                message: error.localizedDescription,
                planLabel: "Google AI"
            )
        } catch {
            return .unavailable(
                .gemini,
                state: .offline,
                message: error.localizedDescription,
                planLabel: "Google AI"
            )
        }
    }

    // MARK: - API key probe

    private func verifyKey(apiKey: String) async throws -> String {
        let modelURL = GeminiAuth.modelsBase.appendingPathComponent(config.probeModel)
        var components = URLComponents(url: modelURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw ProviderError.invalidResponse }

        let (data, response) = try await http.getJSON(url: url)
        guard (200..<300).contains(response.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            if response.statusCode == 401 || response.statusCode == 403 {
                throw ProviderError.missingCredentials("GOOGLE_API_KEY rejected by Gemini API.")
            }
            throw ProviderError.http(response.statusCode, text)
        }
        return config.probeModel
    }

    // MARK: - Service Usage (limits)

    private struct DailyLimits: Sendable {
        var embedRPD: Double?
        var embedTier: String?
        var generateRPD: Double?
        var generateTier: String?
    }

    private func fetchDailyLimits(project: String, token: String) async throws -> DailyLimits {
        var components = URLComponents(
            string: "https://serviceusage.googleapis.com/v1beta1/projects/\(project)/services/generativelanguage.googleapis.com/consumerQuotaMetrics"
        )!
        components.queryItems = [URLQueryItem(name: "pageSize", value: "200")]
        guard let url = components.url else { throw ProviderError.invalidResponse }

        let (data, response) = try await http.getJSON(
            url: url,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
            ]
        )
        guard (200..<300).contains(response.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            if response.statusCode == 401 || response.statusCode == 403 {
                throw ProviderError.missingCredentials(
                    "gcloud token rejected for Service Usage. Run `gcloud auth login`."
                )
            }
            throw ProviderError.http(response.statusCode, text)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metrics = root["metrics"] as? [[String: Any]]
        else {
            throw ProviderError.decoding("Service Usage metrics")
        }

        let embed = Self.pickDailyLimit(
            from: metrics,
            metricSuffixes: [
                "embed_content_paid_tier_3_requests",
                "embed_content_paid_tier_2_requests",
                "embed_content_paid_tier_requests",
                "embed_content_free_tier_requests",
            ]
        )
        let generate = Self.pickDailyLimit(
            from: metrics,
            metricSuffixes: [
                "generate_content_paid_tier_3_requests",
                "generate_content_paid_tier_2_requests",
                "generate_content_paid_tier_requests",
                "generate_content_free_tier_requests",
            ]
        )

        return DailyLimits(
            embedRPD: embed?.limit,
            embedTier: embed?.tier,
            generateRPD: generate?.limit,
            generateTier: generate?.tier
        )
    }

    private static func pickDailyLimit(
        from metrics: [[String: Any]],
        metricSuffixes: [String]
    ) -> (tier: String, limit: Double)? {
        for suffix in metricSuffixes {
            guard let metric = metrics.first(where: {
                (($0["metric"] as? String) ?? "").hasSuffix(suffix)
                    || (($0["metric"] as? String) ?? "").contains("/\(suffix)")
            }) else { continue }

            let limits = (metric["consumerQuotaLimits"] as? [[String: Any]]) ?? []
            for limit in limits {
                let unit = (limit["unit"] as? String) ?? ""
                // Prefer project/model daily buckets (not per-user).
                guard unit.contains("1/d/") , !unit.contains("{user}") else { continue }
                let buckets = (limit["quotaBuckets"] as? [[String: Any]]) ?? []
                guard let raw = buckets.first?["effectiveLimit"] else { continue }
                let value: Double? = {
                    switch raw {
                    case let s as String: return Double(s)
                    case let i as Int: return Double(i)
                    case let d as Double: return d
                    default: return nil
                    }
                }()
                guard let value, value > 0 else { continue }
                let tier: String = {
                    if suffix.contains("paid_tier_3") { return "Tier 3" }
                    if suffix.contains("paid_tier_2") { return "Tier 2" }
                    if suffix.contains("paid_tier") { return "Tier 1" }
                    return "Free"
                }()
                return (tier, value)
            }
        }
        return nil
    }

    // MARK: - Cloud Monitoring (usage)

    private struct TodayUsage: Sendable {
        var embeds: Double
        var generates: Double
    }

    private func fetchTodayUsage(project: String, token: String) async throws -> TodayUsage {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")
            ?? TimeZone(secondsFromGMT: 0)
            ?? .current
        let start = cal.startOfDay(for: Date())
        let end = Date()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startStr = formatter.string(from: start)
        let endStr = formatter.string(from: end)

        let filter =
            "metric.type=\"serviceruntime.googleapis.com/api/request_count\" AND resource.labels.service=\"generativelanguage.googleapis.com\""

        var embeds = 0.0
        var generates = 0.0
        var pageToken: String?

        repeat {
            var components = URLComponents(
                string: "https://monitoring.googleapis.com/v3/projects/\(project)/timeSeries"
            )!
            var items: [URLQueryItem] = [
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "interval.startTime", value: startStr),
                URLQueryItem(name: "interval.endTime", value: endStr),
                URLQueryItem(name: "pageSize", value: "200"),
            ]
            if let pageToken {
                items.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = items
            guard let url = components.url else { throw ProviderError.invalidResponse }

            let (data, response) = try await http.getJSON(
                url: url,
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Accept": "application/json",
                ]
            )
            guard (200..<300).contains(response.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                if response.statusCode == 401 || response.statusCode == 403 {
                    throw ProviderError.missingCredentials(
                        "gcloud token rejected for Monitoring. Run `gcloud auth login`."
                    )
                }
                throw ProviderError.http(response.statusCode, text)
            }

            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProviderError.decoding("Monitoring timeSeries")
            }

            for series in (root["timeSeries"] as? [[String: Any]]) ?? [] {
                let metricLabels = (series["metric"] as? [String: Any])?["labels"] as? [String: Any]
                let method = (metricLabels?["method"] as? String) ?? ""
                let points = (series["points"] as? [[String: Any]]) ?? []
                let sum = points.reduce(0.0) { partial, point in
                    partial + Self.metricValue(point["value"])
                }
                if method.localizedCaseInsensitiveContains("EmbedContent")
                    || method.localizedCaseInsensitiveContains("BatchEmbedContents") {
                    embeds += sum
                } else if method.localizedCaseInsensitiveContains("GenerateContent") {
                    generates += sum
                }
            }

            pageToken = root["nextPageToken"] as? String
        } while pageToken != nil

        return TodayUsage(embeds: embeds, generates: generates)
    }

    private static func metricValue(_ value: Any?) -> Double {
        guard let dict = value as? [String: Any] else { return 0 }
        if let s = dict["int64Value"] as? String, let v = Double(s) { return v }
        if let i = dict["int64Value"] as? Int { return Double(i) }
        if let d = dict["doubleValue"] as? Double { return d }
        if let s = dict["doubleValue"] as? String, let v = Double(s) { return v }
        return 0
    }

    // MARK: - Snapshot

    private static func snapshot(
        model: String,
        project: String,
        limits: DailyLimits,
        usage: TodayUsage
    ) -> ProviderSnapshot {
        var meters: [UsageMeter] = []

        if let limit = limits.embedRPD, limit > 0 {
            let used = min(usage.embeds, limit)
            let remaining = max(0, limit - used) / limit
            meters.append(
                UsageMeter(
                    id: "embed-rpd",
                    title: "Embeds / day",
                    remainingFraction: remaining,
                    resetDescription: TUMFormatting.resetLabel(
                        from: TUMFormatting.nextPacificMidnight()
                    ),
                    footnote: "\(formatCount(usage.embeds)) / \(formatCount(limit))"
                        + (limits.embedTier.map { " · \($0)" } ?? "")
                )
            )
        }

        if let limit = limits.generateRPD, limit > 0 {
            let used = min(usage.generates, limit)
            let remaining = max(0, limit - used) / limit
            meters.append(
                UsageMeter(
                    id: "gen-rpd",
                    title: "Generate / day",
                    remainingFraction: remaining,
                    resetDescription: TUMFormatting.resetLabel(
                        from: TUMFormatting.nextPacificMidnight()
                    ),
                    footnote: "\(formatCount(usage.generates)) / \(formatCount(limit))"
                        + (limits.generateTier.map { " · \($0)" } ?? "")
                )
            )
        }

        if meters.isEmpty {
            meters.append(
                UsageMeter(
                    id: "key",
                    title: "API key",
                    remainingFraction: 1,
                    resetDescription: "Key OK · \(project)",
                    footnote: "No daily quota limits returned"
                )
            )
        }

        return ProviderSnapshot(
            id: .gemini,
            planLabel: model,
            state: .live,
            meters: Array(meters.prefix(2)),
            detailSummary: "Google · \(project)",
            shareOnlyDetails: project.isEmpty ? [] : ["gcp:\(project)"]
        )
    }

    private static func formatCount(_ value: Double) -> String {
        let n = Int(value.rounded())
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Cache

    private static var cacheURL: URL {
        ConfigStore.configDirectory
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("gemini-google.json")
    }

    private struct CacheEnvelope: Codable {
        var fetchedAt: Date
        var planLabel: String
        var detailSummary: String
        var meters: [CachedMeter]
    }

    private struct CachedMeter: Codable {
        var id: String
        var title: String
        var remainingFraction: Double
        var resetDescription: String?
        var footnote: String?
    }

    private static func loadCache(maxAge: TimeInterval) -> ProviderSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL),
              let env = try? JSONDecoder().decode(CacheEnvelope.self, from: data),
              Date().timeIntervalSince(env.fetchedAt) <= maxAge
        else { return nil }
        return ProviderSnapshot(
            id: .gemini,
            planLabel: env.planLabel,
            state: .live,
            meters: env.meters.map {
                UsageMeter(
                    id: $0.id,
                    title: $0.title,
                    remainingFraction: $0.remainingFraction,
                    resetDescription: $0.resetDescription,
                    footnote: $0.footnote
                )
            },
            detailSummary: env.detailSummary,
            fetchedAt: env.fetchedAt
        )
    }

    private static func saveCache(_ snap: ProviderSnapshot) {
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let env = CacheEnvelope(
            fetchedAt: snap.fetchedAt,
            planLabel: snap.planLabel,
            detailSummary: snap.detailSummary,
            meters: snap.meters.map {
                CachedMeter(
                    id: $0.id,
                    title: $0.title,
                    remainingFraction: $0.remainingFraction,
                    resetDescription: $0.resetDescription,
                    footnote: $0.footnote
                )
            }
        )
        if let data = try? JSONEncoder().encode(env) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
