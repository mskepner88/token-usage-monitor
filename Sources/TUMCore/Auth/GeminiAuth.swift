import Foundation

/// Resolves `GOOGLE_API_KEY` from Settings, the environment, or a project `.env.local` you configure,
/// plus a gcloud access token for Service Usage / Cloud Monitoring quotas.
public enum GeminiAuth {
    public static let secretsAccount = "google-api-key"
    public static let modelsBase = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!

    public static func resolveAPIKey(
        config: GeminiConfig,
        secrets: any SecretStore
    ) throws -> String {
        if let raw = try secrets.get(account: secretsAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }

        if let env = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }

        for path in candidateEnvFiles(config: config) {
            let values = VercelGatewayAuth.parseDotEnv(
                (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            )
            if let key = values["GOOGLE_API_KEY"], !key.isEmpty {
                return key
            }
        }

        throw ProviderError.missingCredentials(
            "GOOGLE_API_KEY not found. Set it in a project's `.env.local` or paste it in Settings."
        )
    }

    public static func saveAPIKey(_ value: String, secrets: any SecretStore) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secrets.delete(account: secretsAccount)
        } else {
            try secrets.set(trimmed, account: secretsAccount)
        }
    }

    /// `gcloud auth print-access-token` for the signed-in user / ADC.
    public static func resolveGCloudAccessToken(config: GeminiConfig) throws -> String {
        let gcloud = resolveGCloudBinary(config: config)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gcloud)
        process.arguments = ["auth", "print-access-token"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            throw ProviderError.missingCredentials(
                "gcloud not runnable at \(gcloud). Install Google Cloud SDK."
            )
        }
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0, !token.isEmpty else {
            throw ProviderError.missingCredentials(
                "gcloud auth failed. Run `gcloud auth login`. \(errText.prefix(120))"
            )
        }
        return token
    }

    public static func resolveGCloudBinary(config: GeminiConfig) -> String {
        if let override = config.gcloudPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return TUMFormatting.expandHome(override)
        }
        let candidates = [
            NSString(string: "~/google-cloud-sdk/bin/gcloud").expandingTildeInPath,
            "/opt/homebrew/bin/gcloud",
            "/usr/local/bin/gcloud",
            "/usr/bin/gcloud",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return NSString(string: "~/google-cloud-sdk/bin/gcloud").expandingTildeInPath
    }

    private static func candidateEnvFiles(config: GeminiConfig) -> [String] {
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
}
