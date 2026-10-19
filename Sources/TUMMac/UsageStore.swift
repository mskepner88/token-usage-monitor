import AppKit
import Foundation
import SwiftUI
import TUMCore

@MainActor
final class UsageStore: ObservableObject {
    @Published var dashboard: UsageDashboard = UsageDashboard(providers: [])
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var config: AppConfig
    @Published var cursorCookieDraft: String = ""
    @Published var grokCookieDraft: String = ""
    @Published var claudeCredentialsDraft: String = ""
    @Published var vercelGatewayKeyDraft: String = ""
    @Published var geminiKeyDraft: String = ""
    @Published var cerebrasKeyDraft: String = ""
    @Published var showTipNudge = false
    @Published var shareNotice: String?
    @Published var phoneWidgetPath: String?

    var onDashboardChange: ((UsageDashboard) -> Void)?

    private let tipJar = TipJar(fileURL: TipJar.defaultFileURL)

    private var refreshTask: Task<Void, Never>?
    private var secrets: any SecretStore
    private var lastRefreshAt: Date?
    /// Skip overlapping refreshes from launch + popover open + timer.
    private let minRefreshGapSeconds: TimeInterval = 20

    init() {
        var loaded = ConfigStore.load()
        if loaded.providerOrder.isEmpty {
            loaded.providerOrder = ProviderID.defaultOrder
        }
        // Drop removed providers from saved order (e.g. elevenLabs → cerebras).
        loaded.providerOrder.removeAll { id in
            !ProviderID.allCases.contains(id)
        }
        // Ensure newly added providers appear in the order list (Cursor first).
        for id in ProviderID.defaultOrder where !loaded.providerOrder.contains(id) {
            if id == .cursor {
                loaded.providerOrder.insert(id, at: 0)
            } else {
                loaded.providerOrder.append(id)
            }
        }
        // Cursor was off by default earlier; Ultra weekly limit needs it on.
        if !loaded.providers.cursor.enabled {
            loaded.providers.cursor.enabled = true
        }
        // Development-friendly default: file-backed secrets (no Keychain prompts).
        if loaded.secretBackend != .file && loaded.secretBackend != .keychain {
            loaded.secretBackend = .file
        }
        self.config = loaded
        self.secrets = SecretStoreFactory.make(backend: loaded.secretBackend)
        self.cursorCookieDraft = (try? secrets.get(account: config.providers.cursor.cookieKeychainAccount)) ?? ""
        self.grokCookieDraft = (try? secrets.get(account: config.providers.grok.cookieKeychainAccount)) ?? ""
        self.vercelGatewayKeyDraft =
            (try? secrets.get(account: VercelGatewayAuth.secretsAccount)) ?? ""
        self.geminiKeyDraft =
            (try? secrets.get(account: GeminiAuth.secretsAccount)) ?? ""
        self.cerebrasKeyDraft =
            (try? secrets.get(account: CerebrasAuth.secretsAccount)) ?? ""
        if let saved = try? secrets.get(account: ClaudeAuth.secretsAccount), !saved.isEmpty {
            self.claudeCredentialsDraft = saved
        } else if FileManager.default.fileExists(atPath: ClaudeAuth.credentialsFileURL.path),
                  let raw = try? String(contentsOf: ClaudeAuth.credentialsFileURL, encoding: .utf8) {
            self.claudeCredentialsDraft = raw
        }
        if let record = try? tipJar.loadOrStart() {
            showTipNudge = TipJar.shouldShowNudge(record: record, now: .now)
        }
        startTimer()
    }

    func dismissTipNudge(_ choice: TipJarChoice) {
        try? tipJar.resolve(choice)
        showTipNudge = false
    }

    func shareSnapshot() {
        let card = UsageShareCard.make(dashboard: dashboard, options: config.share)
        guard let png = ShareCardRenderer.pngData(for: card) else {
            shareNotice = "Couldn't render the snapshot."
            return
        }
        ShareCardRenderer.copyToPasteboard(png)
        shareNotice = "Snapshot copied. Save it if you want a file."
        ShareCardRenderer.promptSave(png)
    }

    func refresh(force: Bool = false) async {
        if !force,
           let last = lastRefreshAt,
           Date().timeIntervalSince(last) < minRefreshGapSeconds {
            return
        }
        if force {
            ProviderResponseCache.clear(provider: .claude)
            try? FileManager.default.removeItem(
                at: ConfigStore.configDirectory
                    .appendingPathComponent("cache/bedrock-ce.json")
            )
            try? FileManager.default.removeItem(
                at: ConfigStore.configDirectory
                    .appendingPathComponent("cache/cerebras-limits.json")
            )
            try? FileManager.default.removeItem(
                at: ConfigStore.configDirectory
                    .appendingPathComponent("cache/gemini-google.json")
            )
        }
        isRefreshing = true
        defer { isRefreshing = false }
        lastRefreshAt = .now
        let service = UsageService(config: config, secrets: secrets)
        dashboard = await service.refresh()
        onDashboardChange?(dashboard)
        if config.phoneWidgetSnapshot {
            writePhoneWidgetSnapshot()
        }
    }

    private func writePhoneWidgetSnapshot() {
        do {
            let url = try PhoneWidgetSnapshotWriter.write(.make(dashboard: dashboard))
            phoneWidgetPath = url.path
        } catch {
            lastError = "iPhone widget file: \(error.localizedDescription)"
        }
    }

    func saveConfig() {
        do {
            try ConfigStore.save(config)
            secrets = SecretStoreFactory.make(backend: config.secretBackend)
            startTimer()
            Task { await refresh() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveCursorCookie() {
        saveSecret(cursorCookieDraft, account: config.providers.cursor.cookieKeychainAccount)
    }

    func saveGrokCookie() {
        saveSecret(grokCookieDraft, account: config.providers.grok.cookieKeychainAccount)
    }

    func saveClaudeCredentials() {
        do {
            let trimmed = claudeCredentialsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try secrets.delete(account: ClaudeAuth.secretsAccount)
                try? FileManager.default.removeItem(at: ClaudeAuth.credentialsFileURL)
            } else {
                try ClaudeAuth.saveRaw(trimmed, secrets: secrets)
            }
            Task { await refresh() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveVercelGatewayKey() {
        do {
            try VercelGatewayAuth.saveAPIKey(vercelGatewayKeyDraft, secrets: secrets)
            Task { await refresh() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveGeminiKey() {
        do {
            try GeminiAuth.saveAPIKey(geminiKeyDraft, secrets: secrets)
            Task { await refresh() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveCerebrasKey() {
        do {
            try CerebrasAuth.saveAPIKey(cerebrasKeyDraft, secrets: secrets)
            try? FileManager.default.removeItem(
                at: ConfigStore.configDirectory
                    .appendingPathComponent("cache/cerebras-limits.json")
            )
            Task { await refresh() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pullVercelGatewayEnv() {
        Task {
            do {
                _ = try await VercelGatewayAuth.pullFresh(
                    projectPath: config.providers.vercelGateway.projectPath
                )
                await refresh()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func moveProvider(from index: Int, direction: Int) {
        let target = index + direction
        guard config.providerOrder.indices.contains(index),
              config.providerOrder.indices.contains(target)
        else { return }
        config.providerOrder.swapAt(index, target)
        saveConfig()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func saveSecret(_ value: String, account: String) {
        do {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try secrets.delete(account: account)
            } else {
                try secrets.set(trimmed, account: account)
            }
            Task { await refresh() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startTimer() {
        refreshTask?.cancel()
        let seconds = max(config.refreshIntervalSeconds, 30)
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }
}
