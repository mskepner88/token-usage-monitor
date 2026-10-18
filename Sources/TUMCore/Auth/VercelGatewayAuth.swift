import Foundation

/// Resolves Vercel AI Gateway credentials from Settings, the environment, a project `.env.local`,
/// or `VERCEL_OIDC_TOKEN` from `vercel env pull`.
public enum VercelGatewayAuth {
    public static let secretsAccount = "ai-gateway-api-key"
    public static let creditsURL = URL(string: "https://ai-gateway.vercel.sh/v1/credits")!

    public static var cacheEnvURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("TokenUsageMonitor", isDirectory: true)
            .appendingPathComponent("vercel-gateway.env")
    }

    public enum Source: String, Sendable {
        case secrets
        case processEnv
        case envFile
        case vercelPull
    }

    public struct Credential: Sendable {
        public var token: String
        public var source: Source
        public var kind: Kind

        public enum Kind: String, Sendable {
            case apiKey
            case oidc
        }
    }

    public static func resolve(
        config: VercelGatewayConfig,
        secrets: any SecretStore
    ) async throws -> Credential {
        if let raw = try secrets.get(account: secretsAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return Credential(token: raw, source: .secrets, kind: .apiKey)
        }

        if let env = ProcessInfo.processInfo.environment["AI_GATEWAY_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return Credential(token: env, source: .processEnv, kind: .apiKey)
        }

        for path in candidateEnvFiles(config: config) {
            if let cred = readCredential(from: path) {
                if cred.kind == .oidc, isJWTExpired(cred.token) {
                    continue
                }
                return Credential(token: cred.token, source: .envFile, kind: cred.kind)
            }
        }

        if let cached = readCredential(from: cacheEnvURL.path),
           !(cached.kind == .oidc && isJWTExpired(cached.token)) {
            return Credential(token: cached.token, source: .vercelPull, kind: cached.kind)
        }

        let pulled = try await pullViaVercelCLI(projectPath: config.projectPath)
        return Credential(token: pulled.token, source: .vercelPull, kind: pulled.kind)
    }

    /// Force `vercel env pull` against the linked project path (ignores a pasted key).
    public static func pullFresh(projectPath: String) async throws -> Credential {
        try? FileManager.default.removeItem(at: cacheEnvURL)
        let pulled = try await pullViaVercelCLI(projectPath: projectPath)
        return Credential(token: pulled.token, source: .vercelPull, kind: pulled.kind)
    }

    public static func saveAPIKey(_ value: String, secrets: any SecretStore) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secrets.delete(account: secretsAccount)
        } else {
            try secrets.set(trimmed, account: secretsAccount)
        }
    }

    // MARK: - Env files

    private static func candidateEnvFiles(config: VercelGatewayConfig) -> [String] {
        var paths: [String] = []
        if let override = config.envFilePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            paths.append(TUMFormatting.expandHome(override))
        }
        let project = TUMFormatting.expandHome(config.projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else { return paths }
        paths.append((project as NSString).appendingPathComponent(".env.local"))
        paths.append((project as NSString).appendingPathComponent(".env"))
        return paths
    }

    private struct ParsedToken {
        var token: String
        var kind: Credential.Kind
    }

    private static func readCredential(from path: String) -> ParsedToken? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let values = parseDotEnv(text)
        if let key = values["AI_GATEWAY_API_KEY"], !key.isEmpty {
            return ParsedToken(token: key, kind: .apiKey)
        }
        if let oidc = values["VERCEL_OIDC_TOKEN"], !oidc.isEmpty {
            return ParsedToken(token: oidc, kind: .oidc)
        }
        return nil
    }

    public static func parseDotEnv(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                out[key] = value
            }
        }
        return out
    }

    // MARK: - vercel env pull

    private static func pullViaVercelCLI(projectPath: String) async throws -> ParsedToken {
        let project = TUMFormatting.expandHome(projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else {
            throw ProviderError.missingCredentials(
                "Project path is empty. Set the path to a project with .env.local, or paste AI_GATEWAY_API_KEY."
            )
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project, isDirectory: &isDir), isDir.boolValue else {
            throw ProviderError.missingCredentials(
                "Project not found at \(project). Set the path in Settings or paste AI_GATEWAY_API_KEY."
            )
        }

        guard let vercel = resolveVercelBinary() else {
            throw ProviderError.missingCredentials(
                "Vercel CLI not found. Install it, run `vercel login`, link the project, or paste AI_GATEWAY_API_KEY."
            )
        }

        let cacheURL = cacheEnvURL
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: vercel)
        process.arguments = [
            "env", "pull", cacheURL.path,
            "--environment=production",
            "--yes",
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: project)
        let err = Pipe()
        process.standardOutput = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ProviderError.missingCredentials(
                "vercel env pull failed (\(process.terminationStatus)). \(msg.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }

        guard let parsed = readCredential(from: cacheURL.path) else {
            throw ProviderError.missingCredentials(
                "Pulled the project env but found no AI_GATEWAY_API_KEY or VERCEL_OIDC_TOKEN."
            )
        }
        return parsed
    }

    private static func resolveVercelBinary() -> String? {
        let candidates = [
            "/usr/local/bin/vercel",
            "/opt/homebrew/bin/vercel",
            "\(NSHomeDirectory())/.local/bin/vercel",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["vercel"]
        let out = Pipe()
        which.standardOutput = out
        which.standardError = Pipe()
        do {
            try which.run()
            which.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func isJWTExpired(_ token: String, skewSeconds: TimeInterval = 120) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return false }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - b64.count % 4) % 4
        if pad > 0 { b64 += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval ?? (json["exp"] as? Int).map(TimeInterval.init)
        else { return false }
        return Date().timeIntervalSince1970 >= (exp - skewSeconds)
    }
}
