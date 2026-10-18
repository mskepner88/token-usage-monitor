import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct VercelGatewayProvider: UsageProvider {
    public let id: ProviderID = .vercelGateway
    private let config: VercelGatewayConfig
    private let secrets: any SecretStore
    private let http: HTTPClient

    public init(
        config: VercelGatewayConfig,
        secrets: any SecretStore,
        http: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.secrets = secrets
        self.http = http
    }

    public func fetch() async -> ProviderSnapshot {
        do {
            let cred = try await VercelGatewayAuth.resolve(config: config, secrets: secrets)
            let (data, response) = try await http.getJSON(
                url: VercelGatewayAuth.creditsURL,
                headers: [
                    "Authorization": "Bearer \(cred.token)",
                    "Accept": "application/json",
                ]
            )

            guard (200..<300).contains(response.statusCode) else {
                if response.statusCode == 401 || response.statusCode == 403 {
                    // Stale OIDC cache — force a fresh pull once.
                    try? FileManager.default.removeItem(at: VercelGatewayAuth.cacheEnvURL)
                    let retry = try await VercelGatewayAuth.resolve(config: config, secrets: secrets)
                    let (data2, response2) = try await http.getJSON(
                        url: VercelGatewayAuth.creditsURL,
                        headers: [
                            "Authorization": "Bearer \(retry.token)",
                            "Accept": "application/json",
                        ]
                    )
                    guard (200..<300).contains(response2.statusCode) else {
                        let text = String(data: data2, encoding: .utf8) ?? ""
                        throw ProviderError.http(response2.statusCode, text)
                    }
                    return try snapshot(from: data2, cred: retry)
                }
                let text = String(data: data, encoding: .utf8) ?? ""
                throw ProviderError.http(response.statusCode, text)
            }

            return try snapshot(from: data, cred: cred)
        } catch let error as ProviderError {
            let state: ProviderLiveState = {
                switch error {
                case .missingCredentials: return .needsAuth
                default: return .offline
                }
            }()
            return .unavailable(
                .vercelGateway,
                state: state,
                message: error.localizedDescription,
                planLabel: "Credits"
            )
        } catch {
            return .unavailable(
                .vercelGateway,
                state: .offline,
                message: error.localizedDescription,
                planLabel: "Credits"
            )
        }
    }

    private func snapshot(from data: Data, cred: VercelGatewayAuth.Credential) throws -> ProviderSnapshot {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let balance = Self.usd(obj["balance"])
        let totalUsed = Self.usd(obj["total_used"] ?? obj["totalUsed"])
        guard let balance else {
            throw ProviderError.decoding("Missing balance in /v1/credits")
        }

        let used = totalUsed ?? 0
        let pool = balance + used
        let remainingFraction = pool > 0 ? balance / pool : 1

        let balanceLabel = Self.money(balance)
        let usedLabel = Self.money(used)

        let meter = UsageMeter(
            id: "credits",
            title: "Credits",
            remainingFraction: remainingFraction,
            resetDescription: "\(balanceLabel) left",
            footnote: "\(usedLabel) used · via \(cred.source.rawValue)"
        )

        return ProviderSnapshot(
            id: .vercelGateway,
            planLabel: "Credits",
            state: .live,
            meters: [meter],
            detailSummary: "Vercel · \(cred.source.rawValue)"
        )
    }

    private static func usd(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String:
            return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    private static func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value < 10 ? 3 : 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}
