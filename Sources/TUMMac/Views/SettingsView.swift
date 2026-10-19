import SwiftUI
import TUMCore

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section("Order") {
                ForEach(Array(store.config.providerOrder.enumerated()), id: \.element) { index, id in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        Text(id.displayName)
                        Spacer()
                        Button {
                            store.moveProvider(from: index, direction: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)

                        Button {
                            store.moveProvider(from: index, direction: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index >= store.config.providerOrder.count - 1)
                    }
                }
                Text("Default: Grok → Claude → GPT → Ollama → Gemini → AI Gateway")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Providers") {
                Toggle("Grok", isOn: $store.config.providers.grok.enabled)
                Toggle("Claude", isOn: $store.config.providers.claude.enabled)
                Toggle("GPT (Codex)", isOn: $store.config.providers.codex.enabled)
                Toggle("Ollama Cloud", isOn: $store.config.providers.ollama.enabled)
                Toggle("Gemini", isOn: $store.config.providers.gemini.enabled)
                Toggle("Cerebras", isOn: $store.config.providers.cerebras.enabled)
                Toggle("Bedrock (AWS spend)", isOn: $store.config.providers.bedrock.enabled)
                Toggle("Vercel AI Gateway", isOn: $store.config.providers.vercelGateway.enabled)
                Toggle("Cursor Ultra", isOn: $store.config.providers.cursor.enabled)
            }

            Section("Refresh") {
                Stepper(
                    value: $store.config.refreshIntervalSeconds,
                    in: 30...3600,
                    step: 30
                ) {
                    Text("Every \(store.config.refreshIntervalSeconds)s")
                }
            }

            Section("Secrets storage") {
                Picker("Backend", selection: $store.config.secretBackend) {
                    Text("Local file (dev-friendly)").tag(SecretBackend.file)
                    Text("Keychain").tag(SecretBackend.keychain)
                }
                Text(SecretStoreFactory.secretsFileURL.path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Text("File mode writes cookies to secrets.json (mode 600, outside git). Switch to Keychain later if you want.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ollama Cloud") {
                TextField("Local daemon URL", text: $store.config.providers.ollama.baseURL)
                Text("Uses `POST /api/me` + `GET /api/balance` on your local Ollama after `ollama signin`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Bedrock (Cost Explorer)") {
                Text(
                    "Month-to-date Bedrock spend for each AWS account you add. Off until an SSO profile is set. The soft budget only drives the bar %."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Text("Monthly budget")
                    Spacer()
                    TextField(
                        "2000",
                        value: $store.config.providers.bedrock.monthlyBudgetUSD,
                        format: .number
                    )
                    .frame(width: 80)
                    Text("USD")
                        .foregroundStyle(.secondary)
                }
                ForEach($store.config.providers.bedrock.accounts) { $account in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Label", text: $account.label)
                        TextField("<your-sso-profile>", text: $account.profile)
                        TextField("<your-aws-account-id>", text: $account.accountId)
                        Button("Remove account") {
                            store.config.providers.bedrock.accounts.removeAll { $0.id == account.id }
                        }
                    }
                }
                Button("Add AWS account") {
                    store.config.providers.bedrock.accounts.append(
                        BedrockAccountConfig(label: "", profile: "", accountId: "")
                    )
                }
                Text(bedrockLoginHint)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("Cerebras") {
                Text(
                    "Rate-limit headroom from `x-ratelimit-*` headers on a 1-token probe. Uses `CEREBRAS_API_KEY` from a project `.env` or Settings. Off until you set a path."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                TextField("path to a project with .env.local", text: $store.config.providers.cerebras.projectPath)
                TextEditor(text: $store.cerebrasKeyDraft)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 44)
                Button("Save Cerebras API key") {
                    store.saveCerebrasKey()
                }
            }

            Section("Gemini (Google AI)") {
                TextField("path to a project with .env.local", text: $store.config.providers.gemini.projectPath)
                TextField("<your-gcp-project-id>", text: $store.config.providers.gemini.gcpProject)
                Text(
                    "Uses `GOOGLE_API_KEY` from that project's `.env.local` (or Settings) plus gcloud auth for Cloud Monitoring / Service Usage daily embed and generate quotas. Off until you set a path or project id."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                TextEditor(text: $store.geminiKeyDraft)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 44)
                Button("Save Google API key") {
                    store.saveGeminiKey()
                }
            }

            Section("Vercel AI Gateway") {
                TextField(
                    "path to a project with .env.local",
                    text: $store.config.providers.vercelGateway.projectPath
                )
                Text(
                    "Uses `AI_GATEWAY_API_KEY` from the environment or that project's `.env.local`, or runs `vercel env pull` for `VERCEL_OIDC_TOKEN`, then `GET https://ai-gateway.vercel.sh/v1/credits`. Off until you set a path."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                TextEditor(text: $store.vercelGatewayKeyDraft)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 50)
                HStack {
                    Button("Save API key") {
                        store.saveVercelGatewayKey()
                    }
                    Button("Pull via vercel CLI") {
                        store.pullVercelGatewayEnv()
                    }
                }
            }

            Section("Claude credentials (file only)") {
                Text(
                    "TUM never opens the Keychain for Claude. Paste the JSON from Claude Code credentials (or run the export command in Terminal once), then Save."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("security find-generic-password -s \"Claude Code-credentials\" -a \"$USER\" -w > \"$HOME/Library/Application Support/TokenUsageMonitor/claude-credentials.json\"")
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                Text("Important: include -a \"$USER\" — an old root entry can otherwise be exported.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextEditor(text: $store.claudeCredentialsDraft)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 70)
                Button("Save Claude credentials") {
                    store.saveClaudeCredentials()
                }
            }

            Section("Grok weekly cookie (optional)") {
                Text(
                    "Uses `grok login` OAuth + CLI billing `?format=credits` for the weekly SuperGrok pool. Optional grok.com Cookie is only a fallback."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                TextEditor(text: $store.grokCookieDraft)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 60)
                Button("Save Grok cookie") {
                    store.saveGrokCookie()
                }
            }

            Section("Cursor Ultra") {
                Text(
                    "Reads your signed-in Cursor app token from `state.vscdb` and calls GetCurrentPeriodUsage (same ~4% weekly limit as the dashboard). Cookie paste is only a fallback."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                TextEditor(text: $store.cursorCookieDraft)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 44)
                Button("Save Cursor cookie (optional)") {
                    store.saveCursorCookie()
                }
            }

            Section("Share snapshot") {
                Text(
                    "The shared PNG shows provider names and percentages. Tokens, cookies, emails, account IDs, and dollar budgets stay off the card unless you turn them on."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Toggle("Include account IDs", isOn: $store.config.share.includeAccountIDs)
                Toggle("Include dollar budgets", isOn: $store.config.share.includeDollarBudgets)
                Toggle("Include email addresses", isOn: $store.config.share.includeEmails)
                Toggle("Include tokens and cookies", isOn: $store.config.share.includeTokensAndCookies)
            }

            Section("iPhone widget") {
                Toggle("Write a snapshot for the iPhone widget", isOn: $store.config.phoneWidgetSnapshot)
                Text(
                    "After each refresh, saves tum-snapshot.json to iCloud Drive for the free Scriptable widget. It holds service names, plans, percentages, and reset times only."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(store.phoneWidgetPath ?? PhoneWidgetSnapshotWriter.destination().path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            Section("Paths") {
                LabeledContent("Config") {
                    Text(ConfigStore.configURL.path)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            Section("About") {
                Text("TUM by \(SkeptacularBrand.displayName)")
                    .font(.headline)
                Text(SkeptacularBrand.pitch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Leave a tip", destination: SkeptacularBrand.tipURL)
                Link("Also from Skeptacular Apps", destination: SkeptacularBrand.activeClipboardURL)
                Text(
                    "Usage endpoints for Codex / Claude / Cursor are unofficial and may change. This project is not affiliated with OpenAI, Anthropic, Cursor, or Ollama."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = store.lastError {
                Section("Status") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 720)
        .onDisappear {
            store.saveConfig()
        }
        .onChange(of: store.config.share) { _, _ in
            store.saveConfig()
        }
        .onChange(of: store.config.phoneWidgetSnapshot) { _, _ in
            store.saveConfig()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.saveConfig()
                    store.saveClaudeCredentials()
                    store.saveGrokCookie()
                    store.saveCursorCookie()
                    store.saveVercelGatewayKey()
                    store.saveGeminiKey()
                    store.saveCerebrasKey()
                }
            }
        }
    }

    private var bedrockLoginHint: String {
        let profiles = store.config.providers.bedrock.accounts
            .map { $0.profile.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if profiles.isEmpty {
            return "aws sso login --profile <your-sso-profile>"
        }
        return profiles.map { "aws sso login --profile \($0)" }.joined(separator: "; ")
    }
}
