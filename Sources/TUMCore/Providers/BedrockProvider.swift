import Foundation

/// Month-to-date Amazon Bedrock (+ marketplace Bedrock Edition) spend via AWS Cost Explorer.
public struct BedrockProvider: UsageProvider {
    public let id: ProviderID = .bedrock
    private let config: BedrockConfig

    public init(config: BedrockConfig) {
        self.config = config
    }

    public func fetch() async -> ProviderSnapshot {
        let accounts = config.accounts.filter {
            !$0.profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !accounts.isEmpty else {
            return .unavailable(
                .bedrock,
                state: .needsAuth,
                message: "Add an AWS SSO profile in Settings to track Bedrock spend.",
                planLabel: "MTD",
                fullWidth: true
            )
        }

        do {
            if let cached = Self.loadCache(maxAge: TimeInterval(max(config.cacheTTLSeconds, 300))),
               let snap = try? Self.snapshot(from: cached, budget: config.monthlyBudgetUSD) {
                return snap
            }

            var rows: [BedrockAccountSpend] = []
            var errors: [String] = []
            for account in accounts {
                do {
                    let spend = try await Self.fetchAccountSpend(account: account)
                    rows.append(spend)
                } catch {
                    errors.append("\(account.label): \(error.localizedDescription)")
                }
            }

            guard !rows.isEmpty else {
                throw ProviderError.missingCredentials(
                    errors.first
                        ?? "AWS Cost Explorer failed. Run `aws sso login --profile <your-sso-profile>`."
                )
            }

            let payload = BedrockSpendPayload(accounts: rows, fetchedAt: .now)
            Self.saveCache(payload)
            var snap = try Self.snapshot(from: payload, budget: config.monthlyBudgetUSD)
            if !errors.isEmpty {
                snap.message = errors.joined(separator: " · ")
            }
            return snap
        } catch let error as ProviderError {
            let state: ProviderLiveState = {
                switch error {
                case .missingCredentials: return .needsAuth
                default: return .offline
                }
            }()
            return .unavailable(
                .bedrock,
                state: state,
                message: error.localizedDescription,
                planLabel: "MTD",
                fullWidth: true
            )
        } catch {
            return .unavailable(
                .bedrock,
                state: .offline,
                message: error.localizedDescription,
                planLabel: "MTD",
                fullWidth: true
            )
        }
    }

    // MARK: - Parse / UI

    private static func snapshot(
        from payload: BedrockSpendPayload,
        budget: Double
    ) throws -> ProviderSnapshot {
        let total = payload.accounts.reduce(0) { $0 + $1.usd }
        let budget = max(budget, 1)
        let monthEnd = Calendar.current.date(
            byAdding: DateComponents(month: 1, day: -1),
            to: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        )
        let reset = monthEnd.map { TUMFormatting.resetLabel(from: $0, includeTime: false) }

        var meters: [UsageMeter] = [
            UsageMeter(
                id: "total",
                title: "This month",
                remainingFraction: max(0, 1 - total / budget),
                resetDescription: reset,
                footnote: "\(money(total)) of \(money(budget)) budget"
            ),
        ]

        for account in payload.accounts.sorted(by: { $0.usd > $1.usd }) {
            meters.append(
                UsageMeter(
                    id: account.label.lowercased(),
                    title: account.label,
                    remainingFraction: max(0, 1 - account.usd / budget),
                    resetDescription: nil,
                    footnote: money(account.usd)
                )
            )
        }

        let labels = payload.accounts.map(\.label).filter { !$0.isEmpty }
        let summary = labels.isEmpty ? "Accounts" : labels.joined(separator: " + ")
        let accountNotes = payload.accounts.compactMap { account -> String? in
            let id = account.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            return "account:\(id)"
        }

        return ProviderSnapshot(
            id: .bedrock,
            planLabel: money(total) + " MTD",
            state: .live,
            meters: Array(meters.prefix(3)),
            detailSummary: summary,
            fetchedAt: payload.fetchedAt,
            fullWidth: true,
            shareOnlyDetails: accountNotes
        )
    }

    private static func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value >= 100 ? 0 : 2
        f.minimumFractionDigits = value >= 100 ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    // MARK: - AWS CE

    private static func fetchAccountSpend(account: BedrockAccountConfig) async throws -> BedrockAccountSpend {
        let aws = resolveAWSBinary()
        guard FileManager.default.isExecutableFile(atPath: aws) else {
            throw ProviderError.notConfigured("AWS CLI not found")
        }

        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let startComps = cal.dateComponents([.year, .month], from: now)
        guard let monthStart = cal.date(from: startComps) else {
            throw ProviderError.decoding("Bad calendar")
        }
        // CE End is exclusive; use tomorrow UTC date string.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        let start = df.string(from: monthStart)
        let end = df.string(from: cal.date(byAdding: .day, value: 1, to: now) ?? now)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: aws)
        process.arguments = [
            "ce", "get-cost-and-usage",
            "--profile", account.profile,
            "--time-period", "Start=\(start),End=\(end)",
            "--granularity", "MONTHLY",
            "--metrics", "UnblendedCost",
            "--group-by", "Type=DIMENSION,Key=SERVICE",
            "--region", "us-east-1",
            "--output", "json",
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            if errText.localizedCaseInsensitiveContains("sso")
                || errText.localizedCaseInsensitiveContains("expired")
                || errText.localizedCaseInsensitiveContains("Token has expired") {
                throw ProviderError.missingCredentials(
                    "SSO expired for \(account.profile). Run `aws sso login --profile \(account.profile)`."
                )
            }
            throw ProviderError.http(
                Int(process.terminationStatus),
                String(errText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decoding("CE root")
        }
        var total = 0.0
        for result in (json["ResultsByTime"] as? [[String: Any]]) ?? [] {
            for group in (result["Groups"] as? [[String: Any]]) ?? [] {
                let name = (group["Keys"] as? [String])?.first ?? ""
                guard isBedrockService(name) else { continue }
                if let amount = ((group["Metrics"] as? [String: Any])?["UnblendedCost"] as? [String: Any])?["Amount"] as? String,
                   let v = Double(amount) {
                    total += v
                }
            }
        }
        return BedrockAccountSpend(
            label: account.label,
            profile: account.profile,
            accountId: account.accountId,
            usd: total
        )
    }

    private static func isBedrockService(_ name: String) -> Bool {
        name == "Amazon Bedrock"
            || name.localizedCaseInsensitiveContains("Amazon Bedrock Edition")
            || name.localizedCaseInsensitiveContains("bedrock")
    }

    private static func resolveAWSBinary() -> String {
        for path in ["/usr/local/bin/aws", "/opt/homebrew/bin/aws", "/usr/bin/aws"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/usr/local/bin/aws"
    }

    // MARK: - Cache

    private struct BedrockAccountSpend: Codable, Sendable {
        var label: String
        var profile: String
        var accountId: String
        var usd: Double

        private enum CodingKeys: String, CodingKey {
            case label, profile, accountId, usd
        }

        init(label: String, profile: String, accountId: String, usd: Double) {
            self.label = label
            self.profile = profile
            self.accountId = accountId
            self.usd = usd
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try container.decode(String.self, forKey: .label)
            profile = try container.decode(String.self, forKey: .profile)
            accountId = try container.decodeIfPresent(String.self, forKey: .accountId) ?? ""
            usd = try container.decode(Double.self, forKey: .usd)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(label, forKey: .label)
            try container.encode(profile, forKey: .profile)
            try container.encode(accountId, forKey: .accountId)
            try container.encode(usd, forKey: .usd)
        }
    }

    private struct BedrockSpendPayload: Codable, Sendable {
        var accounts: [BedrockAccountSpend]
        var fetchedAt: Date
    }

    private static var cacheURL: URL {
        ConfigStore.configDirectory
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("bedrock-ce.json")
    }

    private static func loadCache(maxAge: TimeInterval) -> BedrockSpendPayload? {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(BedrockSpendPayload.self, from: data),
              Date().timeIntervalSince(payload.fetchedAt) <= maxAge
        else { return nil }
        return payload
    }

    private static func saveCache(_ payload: BedrockSpendPayload) {
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
