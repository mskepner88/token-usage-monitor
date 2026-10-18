import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OllamaProvider: UsageProvider {
    public let id: ProviderID = .ollama
    private let config: OllamaConfig
    private let http: HTTPClient

    public init(config: OllamaConfig, http: HTTPClient = HTTPClient()) {
        self.config = config
        self.http = http
    }

    public func fetch() async -> ProviderSnapshot {
        guard let base = URL(string: config.baseURL) else {
            return .unavailable(.ollama, state: .error, message: "Invalid Ollama base URL")
        }

        do {
            // Cloud identity + included session/weekly remaining % (proxied by local daemon after sign-in).
            let meURL = base.appendingPathComponent("api/me")
            var meRequest = URLRequest(url: meURL)
            meRequest.httpMethod = "POST"
            meRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

            async let meTask = URLSession.shared.data(for: meRequest)
            async let balanceTask = http.getJSON(url: base.appendingPathComponent("api/balance"))

            let (meData, meResponse) = try await meTask
            let (balanceData, balanceResponse) = try await balanceTask

            guard let meHTTP = meResponse as? HTTPURLResponse else {
                throw ProviderError.invalidResponse
            }
            guard (200..<300).contains(meHTTP.statusCode) else {
                throw ProviderError.missingCredentials(
                    "Not signed in to Ollama Cloud. Run `ollama signin`."
                )
            }
            guard (200..<300).contains(balanceResponse.statusCode) else {
                let text = String(data: balanceData, encoding: .utf8) ?? ""
                throw ProviderError.http(balanceResponse.statusCode, text)
            }

            let me = try JSONSerialization.jsonObject(with: meData) as? [String: Any] ?? [:]
            let balance = try JSONSerialization.jsonObject(with: balanceData) as? [String: Any] ?? [:]
            let plan = (me["plan"] as? String)?.capitalized ?? "Cloud"

            let included = balance["included"] as? [String: Any] ?? [:]
            var meters: [UsageMeter] = []

            if let session = included["session"] as? [String: Any] {
                meters.append(meter(from: session, id: "session", title: "5-hour window"))
            }
            if let weekly = included["weekly"] as? [String: Any] {
                meters.append(meter(from: weekly, id: "week", title: "This week"))
            }

            if let purchased = balance["purchased"] as? [String: Any],
               let usd = purchased["balance_usd"] as? Double ?? (purchased["balance_usd"] as? Int).map(Double.init),
               usd > 0,
               var first = meters.first {
                first.footnote = String(format: "$%.2f purchased balance", usd)
                meters[0] = first
            }

            if meters.isEmpty {
                throw ProviderError.decoding("No Ollama Cloud balance windows")
            }

            return ProviderSnapshot(
                id: .ollama,
                planLabel: plan,
                state: .live,
                meters: Array(meters.prefix(2)),
                detailSummary: "All \(meters.count) limits"
            )
        } catch let error as ProviderError {
            let state: ProviderLiveState = {
                switch error {
                case .missingCredentials: return .needsAuth
                default: return .offline
                }
            }()
            return .unavailable(
                .ollama,
                state: state,
                message: error.localizedDescription,
                planLabel: "Cloud"
            )
        } catch {
            return .unavailable(
                .ollama,
                state: .offline,
                message: "Ollama daemon not reachable at \(config.baseURL). Open the Ollama app and run `ollama signin`.",
                planLabel: "Cloud"
            )
        }
    }

    private func meter(from dict: [String: Any], id: String, title: String) -> UsageMeter {
        let remaining = (dict["remaining_percent"] as? Double)
            ?? (dict["remaining_percent"] as? Int).map(Double.init)
            ?? 100
        let reset: String? = {
            guard let raw = dict["resets_at"] as? String else { return nil }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
                return TUMFormatting.resetLabel(from: date)
            }
            return "Resets \(raw)"
        }()
        return UsageMeter(
            id: id,
            title: title,
            remainingFraction: remaining / 100,
            resetDescription: reset
        )
    }
}
