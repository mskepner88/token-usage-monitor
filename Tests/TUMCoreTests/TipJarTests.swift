import XCTest
@testable import TUMCore

final class TipJarTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testNudgeStaysHiddenUntilFourteenDays() {
        let record = TipJarRecord(firstSeenAt: start)
        let justBefore = start.addingTimeInterval(TipJar.nudgeDelay - 1)
        XCTAssertFalse(TipJar.shouldShowNudge(record: record, now: justBefore))
        XCTAssertTrue(TipJar.shouldShowNudge(record: record, now: start.addingTimeInterval(TipJar.nudgeDelay)))
        XCTAssertTrue(TipJar.shouldShowNudge(record: record, now: start.addingTimeInterval(TipJar.nudgeDelay + 86_400)))
    }

    func testEitherChoiceHidesTheNudgeForever() {
        for choice in [TipJarChoice.buyCoffee, .notNow] {
            var record = TipJarRecord(firstSeenAt: start)
            record.resolved = true
            record.choice = choice
            let later = start.addingTimeInterval(TipJar.nudgeDelay * 4)
            XCTAssertFalse(TipJar.shouldShowNudge(record: record, now: later))
        }
    }

    func testDecisionPersistsAcrossReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tum-tip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let jar = TipJar(fileURL: directory.appendingPathComponent("tip-jar.json"))

        let created = try jar.loadOrStart(now: start)
        XCTAssertEqual(created.firstSeenAt, start)
        XCTAssertFalse(created.resolved)
        XCTAssertFalse(try jar.shouldShowNudge(now: start.addingTimeInterval(TipJar.nudgeDelay - 1)))
        XCTAssertTrue(try jar.shouldShowNudge(now: start.addingTimeInterval(TipJar.nudgeDelay)))

        let again = try jar.loadOrStart(now: start.addingTimeInterval(999_999))
        XCTAssertEqual(again.firstSeenAt, start)

        try jar.resolve(.notNow, now: start.addingTimeInterval(TipJar.nudgeDelay))
        let reloaded = TipJar(fileURL: jar.fileURL)
        XCTAssertFalse(try reloaded.shouldShowNudge(now: start.addingTimeInterval(TipJar.nudgeDelay * 3)))
        let stored = try reloaded.loadOrStart()
        XCTAssertTrue(stored.resolved)
        XCTAssertEqual(stored.choice, .notNow)

        try jar.resolve(.buyCoffee)
        let bought = try TipJar(fileURL: jar.fileURL).loadOrStart()
        XCTAssertEqual(bought.choice, .buyCoffee)
        XCTAssertFalse(try TipJar(fileURL: jar.fileURL).shouldShowNudge(now: .now.addingTimeInterval(TipJar.nudgeDelay)))
    }

    func testTipURLUsesSkeptacularAppsSite() {
        XCTAssertEqual(SkeptacularBrand.tipURL.absoluteString, "https://skeptacularapps.com/tip")
        XCTAssertEqual(SkeptacularBrand.displayName, "Skeptacular Apps")
        XCTAssertEqual(SkeptacularBrand.slug, "skeptacularapps")
        XCTAssertEqual(SkeptacularBrand.bundleID, "com.skeptacularapps.token-usage-monitor")
        XCTAssertEqual(SkeptacularBrand.homebrewTap, "skeptacularapps/tap")
        XCTAssertEqual(SkeptacularBrand.shareCardMark, "TUM by Skeptacular Apps")
        XCTAssertEqual(
            SkeptacularBrand.activeClipboardURL.absoluteString,
            "https://skeptacularapps.com/apps/active-clipboard"
        )
        XCTAssertEqual(TipJar.nudgeMessage, "TUM is free. If it's kept you from hitting a limit, a tip keeps it that way ($5 suggested).")
        XCTAssertEqual(TipJar.buyButtonTitle, "Leave a tip")
        XCTAssertEqual(TipJar.dismissButtonTitle, "Not now")
    }
}
