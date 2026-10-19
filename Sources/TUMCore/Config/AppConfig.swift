import Foundation

public struct AppConfig: Codable, Sendable, Equatable {
    public var refreshIntervalSeconds: Int
    public var providerOrder: [ProviderID]
    /// Where TUM stores cookies / pasted secrets. Default `file` avoids Keychain prompts while developing.
    public var secretBackend: SecretBackend
    public var providers: ProviderConfigs
    /// Privacy flags for the shareable usage card. All off by default.
    public var share: UsageShareOptions
    /// Write `tum-snapshot.json` to iCloud Drive after each refresh for the iPhone widget. Off by default.
    public var phoneWidgetSnapshot: Bool

    public init(
        refreshIntervalSeconds: Int = 120,
        providerOrder: [ProviderID] = ProviderID.defaultOrder,
        secretBackend: SecretBackend = .file,
        providers: ProviderConfigs = .init(),
        share: UsageShareOptions = .default,
        phoneWidgetSnapshot: Bool = false
    ) {
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.providerOrder = providerOrder
        self.secretBackend = secretBackend
        self.providers = providers
        self.share = share
        self.phoneWidgetSnapshot = phoneWidgetSnapshot
    }

    public static let `default` = AppConfig()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? 120
        providerOrder = try container.decodeIfPresent([ProviderID].self, forKey: .providerOrder)
            ?? ProviderID.defaultOrder
        secretBackend = try container.decodeIfPresent(SecretBackend.self, forKey: .secretBackend) ?? .file
        providers = try container.decodeIfPresent(ProviderConfigs.self, forKey: .providers) ?? .init()
        share = try container.decodeIfPresent(UsageShareOptions.self, forKey: .share) ?? .default
        phoneWidgetSnapshot = try container.decodeIfPresent(Bool.self, forKey: .phoneWidgetSnapshot) ?? false
    }
}

public struct ProviderConfigs: Codable, Sendable, Equatable {
    public var grok: GrokConfig
    public var claude: ClaudeConfig
    public var codex: CodexConfig
    public var ollama: OllamaConfig
    public var gemini: GeminiConfig
    public var cerebras: CerebrasConfig
    public var bedrock: BedrockConfig
    public var vercelGateway: VercelGatewayConfig
    public var cursor: CursorConfig

    public init(
        grok: GrokConfig = .init(),
        claude: ClaudeConfig = .init(),
        codex: CodexConfig = .init(),
        ollama: OllamaConfig = .init(),
        gemini: GeminiConfig = .init(),
        cerebras: CerebrasConfig = .init(),
        bedrock: BedrockConfig = .init(),
        vercelGateway: VercelGatewayConfig = .init(),
        cursor: CursorConfig = .init()
    ) {
        self.grok = grok
        self.claude = claude
        self.codex = codex
        self.ollama = ollama
        self.gemini = gemini
        self.cerebras = cerebras
        self.bedrock = bedrock
        self.vercelGateway = vercelGateway
        self.cursor = cursor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grok = try container.decodeIfPresent(GrokConfig.self, forKey: .grok) ?? .init()
        claude = try container.decodeIfPresent(ClaudeConfig.self, forKey: .claude) ?? .init()
        codex = try container.decodeIfPresent(CodexConfig.self, forKey: .codex) ?? .init()
        ollama = try container.decodeIfPresent(OllamaConfig.self, forKey: .ollama) ?? .init()
        gemini = try container.decodeIfPresent(GeminiConfig.self, forKey: .gemini) ?? .init()
        cerebras = try container.decodeIfPresent(CerebrasConfig.self, forKey: .cerebras) ?? .init()
        bedrock = try container.decodeIfPresent(BedrockConfig.self, forKey: .bedrock) ?? .init()
        vercelGateway = try container.decodeIfPresent(VercelGatewayConfig.self, forKey: .vercelGateway) ?? .init()
        cursor = try container.decodeIfPresent(CursorConfig.self, forKey: .cursor) ?? .init()
    }
}

public struct GrokConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var authPath: String
    /// Optional grok.com cookie for weekly SuperGrok pool (CLI OAuth can't read it).
    public var cookieKeychainAccount: String

    public init(
        enabled: Bool = true,
        authPath: String = "~/.grok/auth.json",
        cookieKeychainAccount: String = "grok-session"
    ) {
        self.enabled = enabled
        self.authPath = authPath
        self.cookieKeychainAccount = cookieKeychainAccount
    }
}

public struct CodexConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var authPath: String

    public init(enabled: Bool = true, authPath: String = "~/.codex/auth.json") {
        self.enabled = enabled
        self.authPath = authPath
    }
}

public struct ClaudeConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var keychainService: String
    /// Anthropic's OAuth usage endpoint rate-limits aggressively; reuse cache within this window.
    public var minFetchIntervalSeconds: Int

    public init(
        enabled: Bool = true,
        keychainService: String = "Claude Code-credentials",
        minFetchIntervalSeconds: Int = 300
    ) {
        self.enabled = enabled
        self.keychainService = keychainService
        self.minFetchIntervalSeconds = minFetchIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        keychainService = try container.decodeIfPresent(String.self, forKey: .keychainService)
            ?? "Claude Code-credentials"
        minFetchIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .minFetchIntervalSeconds)
            ?? 300
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, keychainService, minFetchIntervalSeconds
    }
}

public struct CursorConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var cookieKeychainAccount: String
    /// Optional override for Cursor `state.vscdb` (defaults to Application Support path).
    public var stateDBPath: String?

    public init(
        enabled: Bool = true,
        cookieKeychainAccount: String = "cursor-session",
        stateDBPath: String? = nil
    ) {
        self.enabled = enabled
        self.cookieKeychainAccount = cookieKeychainAccount
        self.stateDBPath = stateDBPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        cookieKeychainAccount = try container.decodeIfPresent(String.self, forKey: .cookieKeychainAccount)
            ?? "cursor-session"
        stateDBPath = try container.decodeIfPresent(String.self, forKey: .stateDBPath)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, cookieKeychainAccount, stateDBPath
    }
}

public struct OllamaConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Local daemon that proxies Ollama Cloud auth after `ollama signin`.
    public var baseURL: String

    public init(
        enabled: Bool = true,
        baseURL: String = "http://127.0.0.1:11434"
    ) {
        self.enabled = enabled
        self.baseURL = baseURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "http://127.0.0.1:11434"
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, baseURL
    }
}

public struct BedrockAccountConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var label: String
    public var profile: String
    public var accountId: String

    public init(id: UUID = UUID(), label: String, profile: String, accountId: String) {
        self.id = id
        self.label = label
        self.profile = profile
        self.accountId = accountId
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, profile, accountId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decode(String.self, forKey: .label)
        profile = try container.decode(String.self, forKey: .profile)
        accountId = try container.decode(String.self, forKey: .accountId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(profile, forKey: .profile)
        try container.encode(accountId, forKey: .accountId)
    }
}

/// Amazon Bedrock month-to-date spend (Cost Explorer) for the AWS accounts you list.
/// Off until at least one account is configured.
public struct BedrockConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Soft monthly budget used only for the remaining-% bar.
    public var monthlyBudgetUSD: Double
    public var cacheTTLSeconds: Int
    public var accounts: [BedrockAccountConfig]

    public init(
        enabled: Bool = false,
        monthlyBudgetUSD: Double = 2000,
        cacheTTLSeconds: Int = 21_600,
        accounts: [BedrockAccountConfig] = []
    ) {
        self.enabled = enabled
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.cacheTTLSeconds = cacheTTLSeconds
        self.accounts = accounts
    }

    public var isConfigured: Bool {
        accounts.contains { account in
            !account.profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !account.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlyBudgetUSD = try container.decodeIfPresent(Double.self, forKey: .monthlyBudgetUSD) ?? 2000
        cacheTTLSeconds = try container.decodeIfPresent(Int.self, forKey: .cacheTTLSeconds) ?? 21_600
        accounts = try container.decodeIfPresent([BedrockAccountConfig].self, forKey: .accounts) ?? []
        let configured = accounts.contains { account in
            !account.profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !account.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? configured
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, monthlyBudgetUSD, cacheTTLSeconds, accounts
    }
}

/// Cerebras Inference. `CEREBRAS_API_KEY` comes from Settings or a project `.env` you point at.
/// Off until a project path or env file is set.
public struct CerebrasConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var projectPath: String
    public var envFilePath: String?
    public var probeModel: String
    /// Avoid spamming the probe chat; limits replenish continuously.
    public var cacheTTLSeconds: Int

    public init(
        enabled: Bool = false,
        projectPath: String = "",
        envFilePath: String? = nil,
        probeModel: String = "gpt-oss-120b",
        cacheTTLSeconds: Int = 60
    ) {
        self.enabled = enabled
        self.projectPath = projectPath
        self.envFilePath = envFilePath
        self.probeModel = probeModel
        self.cacheTTLSeconds = cacheTTLSeconds
    }

    public var isConfigured: Bool {
        !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(envFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        envFilePath = try container.decodeIfPresent(String.self, forKey: .envFilePath)
        probeModel = try container.decodeIfPresent(String.self, forKey: .probeModel)
            ?? "gpt-oss-120b"
        cacheTTLSeconds = try container.decodeIfPresent(Int.self, forKey: .cacheTTLSeconds) ?? 60
        let configured = !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(envFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? configured
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, projectPath, envFilePath, probeModel, cacheTTLSeconds
    }
}

/// Gemini / Google AI. `GOOGLE_API_KEY` comes from Settings or a project `.env.local` you point at,
/// plus GCP quotas via `gcloud` for the project id you set.
/// Off until a path or GCP project is configured.
public struct GeminiConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var projectPath: String
    public var envFilePath: String?
    /// Model used for a cheap connectivity probe (`models.get`).
    public var probeModel: String
    /// GCP project that owns the API key (Service Usage + Monitoring).
    public var gcpProject: String
    /// Optional path to `gcloud` (defaults to common install locations).
    public var gcloudPath: String?
    public var cacheTTLSeconds: Int

    public init(
        enabled: Bool = false,
        projectPath: String = "",
        envFilePath: String? = nil,
        probeModel: String = "gemini-3.6-flash",
        gcpProject: String = "",
        gcloudPath: String? = nil,
        cacheTTLSeconds: Int = 120
    ) {
        self.enabled = enabled
        self.projectPath = projectPath
        self.envFilePath = envFilePath
        self.probeModel = probeModel
        self.gcpProject = gcpProject
        self.gcloudPath = gcloudPath
        self.cacheTTLSeconds = cacheTTLSeconds
    }

    public var isConfigured: Bool {
        !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !gcpProject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(envFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        envFilePath = try container.decodeIfPresent(String.self, forKey: .envFilePath)
        probeModel = try container.decodeIfPresent(String.self, forKey: .probeModel)
            ?? "gemini-3.6-flash"
        gcpProject = try container.decodeIfPresent(String.self, forKey: .gcpProject) ?? ""
        gcloudPath = try container.decodeIfPresent(String.self, forKey: .gcloudPath)
        cacheTTLSeconds = try container.decodeIfPresent(Int.self, forKey: .cacheTTLSeconds) ?? 120
        let configured = !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !gcpProject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(envFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? configured
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, projectPath, envFilePath, probeModel, gcpProject, gcloudPath, cacheTTLSeconds
    }
}

/// Vercel AI Gateway credits (`AI_GATEWAY_API_KEY` or `vercel env pull` OIDC).
/// Off until you set a linked project path.
public struct VercelGatewayConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Linked Vercel project that already uses AI Gateway (a directory with `.vercel/project.json`).
    public var projectPath: String
    /// Optional explicit dotenv path (defaults to `<projectPath>/.env.local`).
    public var envFilePath: String?

    public init(
        enabled: Bool = false,
        projectPath: String = "",
        envFilePath: String? = nil
    ) {
        self.enabled = enabled
        self.projectPath = projectPath
        self.envFilePath = envFilePath
    }

    public var isConfigured: Bool {
        !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(envFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        envFilePath = try container.decodeIfPresent(String.self, forKey: .envFilePath)
        let configured = !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(envFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? configured
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, projectPath, envFilePath
    }
}
