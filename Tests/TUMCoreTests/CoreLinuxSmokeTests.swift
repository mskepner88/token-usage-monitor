import XCTest
@testable import TUMCore

/// Verifies TUMCore types compile and work on non-macOS platforms,
/// confirming the `#if canImport(...)` guards do not break core logic.
final class CoreLinuxSmokeTests: XCTestCase {
    func testProviderIDCaseIterableAndDisplayNames() {
        XCTAssertEqual(ProviderID.allCases.count, 10)
        XCTAssertEqual(Set(ProviderID.allCases.map(\.id)), Set(ProviderID.allCases.map(\.rawValue)))
        XCTAssertEqual(ProviderID.codex.displayName, "GPT")
        XCTAssertEqual(ProviderID.vercelGateway.displayName, "AI Gateway")
        for provider in ProviderID.allCases {
            XCTAssertFalse(provider.accentHex.isEmpty)
            if provider != .localModels {
                XCTAssertNotNil(provider.dashboardURL)
            }
        }
    }

    func testDefaultOrderCoversAllProviders() {
        XCTAssertEqual(Set(ProviderID.defaultOrder), Set(ProviderID.allCases))
    }

    func testUsageMeterClampsAndPercents() {
        let meter = UsageMeter(id: "m", title: "Weekly", remainingFraction: 1.4)
        XCTAssertEqual(meter.remainingFraction, 1)
        XCTAssertEqual(meter.percentLeft, 100)
        let used = UsageMeter.fromUsedPercent(id: "u", title: "Used", usedPercent: 37.5)
        XCTAssertEqual(used.percentLeft, 63)
        let negative = UsageMeter(id: "n", title: "N", remainingFraction: -0.5)
        XCTAssertEqual(negative.remainingFraction, 0)
        XCTAssertEqual(negative.percentLeft, 0)
    }

    func testProviderSnapshotUnavailable() {
        let snapshot = ProviderSnapshot.unavailable(.ollama, state: .offline, message: "Unreachable")
        XCTAssertEqual(snapshot.id, .ollama)
        XCTAssertEqual(snapshot.state, .offline)
        XCTAssertTrue(snapshot.meters.isEmpty)
        XCTAssertEqual(snapshot.planLabel, "—")
    }

    func testFormattingRemainingUntil() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(TUMFormatting.remainingUntil(now.addingTimeInterval(30), now: now), "Resets now")
        XCTAssertEqual(TUMFormatting.remainingUntil(now.addingTimeInterval(5 * 60), now: now), "Resets in 5 minutes")
        XCTAssertEqual(TUMFormatting.remainingUntil(now.addingTimeInterval(1 * 3600), now: now), "Resets in 1 hour")
        XCTAssertEqual(
            TUMFormatting.remainingUntil(now.addingTimeInterval(2 * 86_400 + 3 * 3600), now: now),
            "Resets in 2 days, 3 hours"
        )
    }

    func testNextPacificMidnightIsNextDay() {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        let midnight = TUMFormatting.nextPacificMidnight(from: noon)
        XCTAssertGreaterThan(midnight.timeIntervalSince(noon), 0)
        XCTAssertLessThanOrEqual(midnight.timeIntervalSince(noon), 24 * 3600)
    }
}
