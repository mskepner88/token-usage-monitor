import XCTest
@testable import TUMCore

final class CodexParseTests: XCTestCase {
    func testParsesWeeklyWindowAndResets() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 1,
              "limit_window_seconds": 604800,
              "reset_at": 1792492728
            }
          },
          "rate_limit_reset_credits": { "available_count": 3 }
        }
        """.data(using: .utf8)!

        let snapshot = try CodexProvider.parse(data: json)
        XCTAssertEqual(snapshot.id, .codex)
        XCTAssertEqual(snapshot.state, .live)
        XCTAssertEqual(snapshot.planLabel, "Plus")
        XCTAssertEqual(snapshot.meters.count, 1)
        XCTAssertEqual(snapshot.meters[0].percentLeft, 99)
        XCTAssertEqual(snapshot.meters[0].footnote, "3 quota resets available.")
    }
}

final class OllamaParseSmokeTests: XCTestCase {
    func testMeterBounds() {
        let meter = UsageMeter(id: "x", title: "t", remainingFraction: 1.5)
        XCTAssertEqual(meter.remainingFraction, 1)
        XCTAssertEqual(meter.percentLeft, 100)
    }
}
