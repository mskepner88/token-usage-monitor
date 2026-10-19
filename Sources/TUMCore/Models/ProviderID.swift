import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case grok
    case claude
    case codex
    case ollama
    case gemini
    case cerebras
    case bedrock
    case vercelGateway
    case cursor
    case localModels

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .grok: "Grok"
        case .claude: "Claude"
        case .codex: "GPT"
        case .ollama: "Ollama"
        case .gemini: "Gemini"
        case .cerebras: "Cerebras"
        case .bedrock: "Bedrock"
        case .vercelGateway: "AI Gateway"
        case .cursor: "Cursor"
        case .localModels: "Machines"
        }
    }

    public var accentHex: String {
        switch self {
        case .grok: "#C4C9D4"
        case .claude: "#D97757"
        case .codex: "#4C8DFF"
        case .ollama: "#A78BFA"
        case .gemini: "#8AB4F8"
        case .cerebras: "#F97316"
        case .bedrock: "#FF9900"
        case .vercelGateway: "#0070F3"
        case .cursor: "#1EC8A5"
        case .localModels: "#34D399"
        }
    }

    public var dashboardURL: URL? {
        switch self {
        case .grok: URL(string: "https://grok.com/?_s=usage")
        case .claude: URL(string: "https://claude.ai/settings/usage")
        case .codex: URL(string: "https://chatgpt.com/codex")
        case .ollama: URL(string: "https://ollama.com/settings")
        case .gemini: URL(string: "https://aistudio.google.com/usage")
        case .cerebras: URL(string: "https://cloud.cerebras.ai")
        case .bedrock: URL(string: "https://console.aws.amazon.com/cost-management/home#/cost-explorer")
        case .vercelGateway: URL(string: "https://vercel.com/docs/ai-gateway")
        case .cursor: URL(string: "https://www.cursor.com/dashboard")
        case .localModels: nil
        }
    }

    public static var defaultOrder: [ProviderID] {
        [.cursor, .grok, .claude, .codex, .ollama, .localModels, .gemini, .cerebras, .vercelGateway, .bedrock]
    }
}
