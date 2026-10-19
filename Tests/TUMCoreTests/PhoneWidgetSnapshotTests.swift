import XCTest
@testable import TUMCore

final class PhoneWidgetSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_400_000)

    func testOffByDefaultAndDecodesMissingKey() throws {
        XCTAssertFalse(AppConfig().phoneWidgetSnapshot)
        let bare = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertFalse(bare.phoneWidgetSnapshot)
        let on = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"phoneWidgetSnapshot":true}"#.utf8))
        XCTAssertTrue(on.phoneWidgetSnapshot)
    }

    func testSchemaShapeAndValues() throws {
        let snapshot = PhoneWidgetSnapshot.make(dashboard: sampleDashboard(), now: now)
        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.providers.map(\.name), ["Claude", "GPT"])
        XCTAssertEqual(snapshot.providers[0].plan, "Max")
        XCTAssertEqual(snapshot.providers[0].limits.map(\.percentLeft), [58, 81])
        XCTAssertEqual(snapshot.providers[0].limits[0].resetsAt, now.addingTimeInterval(7_200))
        XCTAssertNil(snapshot.providers[1].limits[0].resetsAt)

        let json = try JSONSerialization.jsonObject(with: snapshot.jsonData()) as? [String: Any]
        XCTAssertEqual(json?["version"] as? Int, 1)
        XCTAssertNotNil(json?["updatedAt"] as? String)
        let providers = json?["providers"] as? [[String: Any]]
        let limit = (providers?.first?["limits"] as? [[String: Any]])?.first
        XCTAssertEqual(Set(limit?.keys ?? [:].keys), ["label", "percentLeft", "resetsAt"])
        XCTAssertTrue((limit?["resetsAt"] as? String)?.hasSuffix("Z") == true)
    }

    func testReadingMetersAreLeftOut() {
        var dashboard = sampleDashboard()
        dashboard.providers[0].meters.append(
            UsageMeter(id: "mem", title: "Memory", remainingFraction: 0.2, reading: "12 GB")
        )
        dashboard.providers.append(
            ProviderSnapshot(
                id: .localModels,
                planLabel: "2 machines",
                state: .live,
                meters: [UsageMeter(id: "spark", title: "Spark", remainingFraction: 0.81, reading: "41 GB")],
                detailSummary: "Details"
            )
        )
        let snapshot = PhoneWidgetSnapshot.make(dashboard: dashboard, now: now)
        XCTAssertEqual(snapshot.providers.map(\.name), ["Claude", "GPT"])
        XCTAssertEqual(snapshot.providers[0].limits.map(\.label), ["5-hour window", "This week"])
    }

    func testNoPrivateDataInFile() throws {
        let data = try PhoneWidgetSnapshot.make(dashboard: sampleDashboard(), now: now).jsonData()
        let text = String(decoding: data, as: UTF8.self)
        for secret in ["person@example.com", "111122223333", "sk-live", "eyJ", "cookie=", "$42", "Signed in"] {
            XCTAssertFalse(text.contains(secret), "leaked \(secret)")
        }
    }

    func testDestinationPrefersScriptableFolderThenFallback() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("tum-widget-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let snapshot = PhoneWidgetSnapshot.make(dashboard: sampleDashboard(), now: now)
        let fallback = try PhoneWidgetSnapshotWriter.write(snapshot, home: home)
        XCTAssertEqual(
            fallback.path,
            home.appendingPathComponent(
                "Library/Mobile Documents/com~apple~CloudDocs/TokenUsageMonitor/tum-snapshot.json"
            ).path
        )

        let scriptable = PhoneWidgetSnapshotWriter.scriptableFolder(home: home)
        try FileManager.default.createDirectory(at: scriptable, withIntermediateDirectories: true)
        let preferred = try PhoneWidgetSnapshotWriter.write(snapshot, home: home)
        XCTAssertEqual(preferred.path, scriptable.appendingPathComponent("tum-snapshot.json").path)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let roundTrip = try decoder.decode(PhoneWidgetSnapshot.self, from: Data(contentsOf: preferred))
        XCTAssertEqual(roundTrip, snapshot)
    }

    private func sampleDashboard() -> UsageDashboard {
        UsageDashboard(providers: [
            ProviderSnapshot(
                id: .claude,
                planLabel: "Max person@example.com",
                state: .live,
                meters: [
                    .fromUsedPercent(
                        id: "5h", title: "5-hour window", usedPercent: 42,
                        resetDescription: "Resets in 2 hours", resetsAt: now.addingTimeInterval(7_200)
                    ),
                    .fromUsedPercent(id: "week", title: "This week", usedPercent: 19),
                ],
                detailSummary: "Signed in as person@example.com",
                shareOnlyDetails: ["sk-live-abcdefghijklmnop", "cookie=abc123"]
            ),
            ProviderSnapshot(
                id: .codex,
                planLabel: "Plus 111122223333",
                state: .live,
                meters: [.fromUsedPercent(id: "w", title: "Weekly $42 eyJabcdefghij.klmno", usedPercent: 10)],
                detailSummary: "Details"
            ),
            .unavailable(.cursor, state: .needsAuth, message: "Sign in"),
        ])
    }
}
