import XCTest
@testable import TUMCore

final class PublicConfigTests: XCTestCase {
    func testFreshConfigLeavesWorkProvidersOff() {
        let config = AppConfig()
        XCTAssertFalse(config.providers.gemini.enabled)
        XCTAssertFalse(config.providers.gemini.isConfigured)
        XCTAssertEqual(config.providers.gemini.projectPath, "")
        XCTAssertEqual(config.providers.gemini.gcpProject, "")
        XCTAssertFalse(config.providers.cerebras.enabled)
        XCTAssertEqual(config.providers.cerebras.projectPath, "")
        XCTAssertFalse(config.providers.vercelGateway.enabled)
        XCTAssertEqual(config.providers.vercelGateway.projectPath, "")
        XCTAssertFalse(config.providers.bedrock.enabled)
        XCTAssertTrue(config.providers.bedrock.accounts.isEmpty)
        XCTAssertFalse(config.providers.localModels.enabled)
        XCTAssertTrue(config.providers.localModels.hosts.isEmpty)
        XCTAssertFalse(config.share.includeAccountIDs)
        XCTAssertFalse(config.share.includeDollarBudgets)
        XCTAssertFalse(config.share.includeEmails)
        XCTAssertFalse(config.share.includeTokensAndCookies)
    }

    func testMissingEnabledStaysOffUntilConfigured() throws {
        let bare = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertFalse(bare.providers.bedrock.enabled)
        XCTAssertTrue(bare.providers.bedrock.accounts.isEmpty)
        XCTAssertFalse(bare.providers.gemini.enabled)
        XCTAssertFalse(bare.providers.cerebras.enabled)
        XCTAssertFalse(bare.providers.vercelGateway.enabled)
        XCTAssertFalse(bare.providers.localModels.enabled)
        XCTAssertTrue(bare.providers.localModels.hosts.isEmpty)

        let configured = """
        {"providers":{"bedrock":{"accounts":[{"label":"Primary","profile":"dev","accountId":"<your-aws-account-id>"}]},"gemini":{"projectPath":"path to a project with .env.local"}}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: configured)
        XCTAssertTrue(decoded.providers.bedrock.enabled)
        XCTAssertEqual(decoded.providers.bedrock.accounts.first?.accountId, "<your-aws-account-id>")
        XCTAssertTrue(decoded.providers.gemini.enabled)
        XCTAssertFalse(decoded.providers.cerebras.enabled)
    }

    func testExampleConfigUsesPlaceholders() throws {
        let url = repoRoot().appendingPathComponent("config.example.json")
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertFalse(config.providers.gemini.enabled)
        XCTAssertEqual(config.providers.gemini.projectPath, "path to a project with .env.local")
        XCTAssertEqual(config.providers.gemini.gcpProject, "<your-gcp-project-id>")
        XCTAssertFalse(config.providers.cerebras.enabled)
        XCTAssertEqual(config.providers.cerebras.projectPath, "path to a project with .env.local")
        XCTAssertFalse(config.providers.vercelGateway.enabled)
        XCTAssertEqual(config.providers.vercelGateway.projectPath, "path to a project with .env.local")
        XCTAssertFalse(config.providers.bedrock.enabled)
        XCTAssertEqual(config.providers.bedrock.accounts.first?.profile, "<your-sso-profile>")
        XCTAssertEqual(config.providers.bedrock.accounts.first?.accountId, "<your-aws-account-id>")
        XCTAssertFalse(config.providers.localModels.enabled)
        XCTAssertEqual(config.providers.localModels.hosts.first?.sshTarget, "user@your-mac")
        XCTAssertEqual(config.providers.localModels.hosts.last?.processName, "llama-server")

        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("~/Projects/"))
        XCTAssertNil(text.range(of: #"\b\d{12}\b"#, options: .regularExpression))
    }

    func testRepoHasNoTwelveDigitAccountIdsOutsideTests() throws {
        let root = repoRoot()
        let skipped = Set(["Tests", ".build", ".git", "dist"])
        let allowedSuffixes = ["swift", "md", "json", "yml", "yaml", "sh", "rb", "plist", "txt"]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail("Could not walk repo")
            return
        }
        for case let url as URL in enumerator {
            if skipped.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard allowedSuffixes.contains(url.pathExtension) else { continue }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            XCTAssertNil(
                text.range(of: #"\b\d{12}\b"#, options: .regularExpression),
                "Unexpected 12-digit id in \(url.lastPathComponent)"
            )
        }
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
