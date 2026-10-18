import Foundation

public enum CerebrasAuth {
    public static let secretsAccount = "cerebras-api-key"
    public static let chatURL = URL(string: "https://api.cerebras.ai/v1/chat/completions")!

    public static func resolveAPIKey(
        config: CerebrasConfig,
        secrets: any SecretStore
    ) throws -> String {
        if let raw = try secrets.get(account: secretsAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }

        if let env = ProcessInfo.processInfo.environment["CEREBRAS_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }

        for path in candidateEnvFiles(config: config) {
            let values = VercelGatewayAuth.parseDotEnv(
                (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            )
            if let key = values["CEREBRAS_API_KEY"], !key.isEmpty {
                return key
            }
        }

        throw ProviderError.missingCredentials(
            "CEREBRAS_API_KEY not found. Set it in a project's `.env` or paste it in Settings."
        )
    }

    public static func resolveChatModel(config: CerebrasConfig) -> String {
        if let env = ProcessInfo.processInfo.environment["CEREBRAS_CHAT_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        for path in candidateEnvFiles(config: config) {
            let values = VercelGatewayAuth.parseDotEnv(
                (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            )
            if let model = values["CEREBRAS_CHAT_MODEL"], !model.isEmpty {
                return model
            }
        }
        return config.probeModel
    }

    public static func saveAPIKey(_ value: String, secrets: any SecretStore) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secrets.delete(account: secretsAccount)
        } else {
            try secrets.set(trimmed, account: secretsAccount)
        }
    }

    private static func candidateEnvFiles(config: CerebrasConfig) -> [String] {
        var paths: [String] = []
        if let override = config.envFilePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            paths.append(TUMFormatting.expandHome(override))
        }
        let root = TUMFormatting.expandHome(config.projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return paths }
        paths.append((root as NSString).appendingPathComponent(".env"))
        paths.append((root as NSString).appendingPathComponent(".env.local"))
        return paths
    }
}
