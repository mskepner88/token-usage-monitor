import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cerebras Inference rate-limit headroom from `x-ratelimit-*` headers on a tiny probe chat.
public struct CerebrasProvider: UsageProvider {
    public let id: ProviderID = .cerebras
    private let config: CerebrasConfig
    private let secrets: any SecretStore

    public init(config: CerebrasConfig, secrets: any SecretStore) {
        self.config = config
        self.secrets = secrets
    }

    public func fetch() async -> ProviderSnapshot {
        do {
            if let cached = Self.loadCache(maxAge: TimeInterval(max(config.cacheTTLSeconds, 30))) {
                return cached
            }

            let key = try CerebrasAuth.resolveAPIKey(config: config, secrets: secrets)
            let model = CerebrasAuth.resolveChatModel(config: config)

            var request = URLRequest(url: CerebrasAuth.chatURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "messages": [["role": "user", "content": "."]],
                "max_tokens": 1,
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw ProviderError.missingCredentials(
                        "Cerebras API key rejected. Update the project `.env` or Settings."
                    )
                }
                if http.statusCode == 429 {
                    throw ProviderError.http(429, "Rate limited — wait a moment and refresh.")
                }
                throw ProviderError.http(http.statusCode, text)
            }

            let snap = try Self.snapshot(from: http, model: model)
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
                .cerebras,
                state: state,
                message: error.localizedDescription,
                planLabel: "Cerebras"
            )
        } catch {
            return .unavailable(
                .cerebras,
                state: .offline,
                message: error.localizedDescription,
                planLabel: "Cerebras"
            )
        }
    }

    private static func snapshot(from http: HTTPURLResponse, model: String) throws -> ProviderSnapshot {
        func header(_ name: String) -> Double? {
            // URLResponse is case-insensitive for header lookups.
            if let raw = http.value(forHTTPHeaderField: name) {
                return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }

        let tokRemainMin = header("x-ratelimit-remaining-tokens-minute")
        let tokLimitMin = header("x-ratelimit-limit-tokens-minute")
        let tokRemainDay = header("x-ratelimit-remaining-tokens-day")
        let tokLimitDay = header("x-ratelimit-limit-tokens-day")
        let reqRemainMin = header("x-ratelimit-remaining-requests-minute")
        let reqLimitMin = header("x-ratelimit-limit-requests-minute")

        var meters: [UsageMeter] = []

        if let remain = tokRemainMin, let limit = tokLimitMin, limit > 0 {
            meters.append(
                UsageMeter(
                    id: "tpm",
                    title: "Tokens / min",
                    remainingFraction: remain / limit,
                    resetDescription: "Replenishes continuously",
                    footnote: "\(Self.formatCount(remain)) / \(Self.formatCount(limit))"
                )
            )
        }

        if let remain = tokRemainDay, let limit = tokLimitDay, limit > 0 {
            meters.append(
                UsageMeter(
                    id: "tpd",
                    title: "Tokens / day",
                    remainingFraction: remain / limit,
                    resetDescription: nil,
                    footnote: "\(Self.formatCount(remain)) / \(Self.formatCount(limit))"
                )
            )
        }

        if meters.isEmpty,
           let remain = reqRemainMin, let limit = reqLimitMin, limit > 0 {
            meters.append(
                UsageMeter(
                    id: "rpm",
                    title: "Requests / min",
                    remainingFraction: remain / limit,
                    footnote: "\(Self.formatCount(remain)) / \(Self.formatCount(limit))"
                )
            )
        }

        guard !meters.isEmpty else {
            throw ProviderError.decoding("No x-ratelimit headers on Cerebras response")
        }

        return ProviderSnapshot(
            id: .cerebras,
            planLabel: model,
            state: .live,
            meters: Array(meters.prefix(2)),
            detailSummary: "Rate limits"
        )
    }

    private static func formatCount(_ value: Double) -> String {
        let n = Int(value.rounded())
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Short cache (limits replenish continuously; avoid probe spam)

    private static var cacheURL: URL {
        ConfigStore.configDirectory
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("cerebras-limits.json")
    }

    private struct CacheEnvelope: Codable {
        var fetchedAt: Date
        var planLabel: String
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
        let meters = env.meters.map {
            UsageMeter(
                id: $0.id,
                title: $0.title,
                remainingFraction: $0.remainingFraction,
                resetDescription: $0.resetDescription,
                footnote: $0.footnote
            )
        }
        return ProviderSnapshot(
            id: .cerebras,
            planLabel: env.planLabel,
            state: .live,
            meters: meters,
            detailSummary: "Rate limits",
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
