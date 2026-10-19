import Foundation

public struct UsageService: Sendable {
    private let config: AppConfig
    private let secrets: any SecretStore
    private let http: HTTPClient

    public init(
        config: AppConfig = ConfigStore.load(),
        secrets: (any SecretStore)? = nil,
        http: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.secrets = secrets ?? SecretStoreFactory.make(backend: config.secretBackend)
        self.http = http
    }

    public func refresh() async -> UsageDashboard {
        var providers: [any UsageProvider] = []
        if config.providers.grok.enabled {
            providers.append(
                GrokProvider(config: config.providers.grok, secrets: secrets, http: http)
            )
        }
        if config.providers.claude.enabled {
            providers.append(
                ClaudeProvider(config: config.providers.claude, secrets: secrets, http: http)
            )
        }
        if config.providers.codex.enabled {
            providers.append(CodexProvider(config: config.providers.codex, http: http))
        }
        if config.providers.ollama.enabled {
            providers.append(OllamaProvider(config: config.providers.ollama, http: http))
        }
        if config.providers.gemini.enabled {
            providers.append(
                GeminiProvider(
                    config: config.providers.gemini,
                    secrets: secrets,
                    http: http
                )
            )
        }
        if config.providers.cerebras.enabled {
            providers.append(
                CerebrasProvider(
                    config: config.providers.cerebras,
                    secrets: secrets
                )
            )
        }
        if config.providers.bedrock.enabled {
            providers.append(BedrockProvider(config: config.providers.bedrock))
        }
        if config.providers.vercelGateway.enabled {
            providers.append(
                VercelGatewayProvider(
                    config: config.providers.vercelGateway,
                    secrets: secrets,
                    http: http
                )
            )
        }
        if config.providers.cursor.enabled {
            providers.append(
                CursorProvider(config: config.providers.cursor, secrets: secrets, http: http)
            )
        }
        if config.providers.localModels.enabled {
            providers.append(LocalModelsProvider(config: config.providers.localModels))
        }

        let snapshots = await withTaskGroup(of: ProviderSnapshot.self, returning: [ProviderSnapshot].self) { group in
            for provider in providers {
                group.addTask { await provider.fetch() }
            }
            var results: [ProviderSnapshot] = []
            for await snapshot in group {
                results.append(snapshot)
            }
            return results
        }

        let order = config.providerOrder.isEmpty ? ProviderID.defaultOrder : config.providerOrder
        let sorted = snapshots.sorted {
            let lhs = order.firstIndex(of: $0.id) ?? (100 + ($0.id.rawValue.hashValue & 0xff))
            let rhs = order.firstIndex(of: $1.id) ?? (100 + ($1.id.rawValue.hashValue & 0xff))
            return lhs < rhs
        }
        return UsageDashboard(providers: sorted)
    }
}
