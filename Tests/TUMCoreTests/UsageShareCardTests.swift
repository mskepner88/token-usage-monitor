import XCTest
@testable import TUMCore

final class UsageShareCardTests: XCTestCase {
    func testDefaultCardShowsNamesAndPercentagesOnly() {
        let card = UsageShareCard.make(dashboard: sampleDashboard(), options: .default)
        XCTAssertEqual(card.brandMark, "TUM by Skeptacular Apps")
        XCTAssertEqual(card.rows.map(\.providerName), ["Grok", "Bedrock", "Gemini"])
        XCTAssertEqual(card.rows[0].percentsLeft, [72])
        XCTAssertEqual(card.rows[1].percentsLeft, [40, 88])
        XCTAssertTrue(card.rows.allSatisfy(\.details.isEmpty))

        let text = card.plainText
        XCTAssertTrue(text.contains("Grok 72%"))
        XCTAssertTrue(text.contains("Bedrock 40% · 88%"))
        XCTAssertTrue(text.contains("TUM by Skeptacular Apps"))
        assertPrivateDataAbsent(text)
    }

    func testDollarToggleKeepsMoneyAndStripsEverythingElse() {
        let card = UsageShareCard.make(
            dashboard: sampleDashboard(),
            options: UsageShareOptions(includeDollarBudgets: true)
        )
        let text = card.plainText
        XCTAssertTrue(text.contains("$42"))
        XCTAssertTrue(text.contains("$100"))
        XCTAssertFalse(text.contains("111122223333"))
        XCTAssertFalse(text.contains("person@example.com"))
        XCTAssertFalse(text.contains("sk-live"))
        XCTAssertFalse(text.contains("cookie="))
        XCTAssertFalse(text.contains("gcp:"))
    }

    func testAccountToggleRevealsAccountAndProjectIdsOnly() {
        let card = UsageShareCard.make(
            dashboard: sampleDashboard(),
            options: UsageShareOptions(includeAccountIDs: true)
        )
        let text = card.plainText
        XCTAssertTrue(text.contains("111122223333"))
        XCTAssertTrue(text.contains("gcp:sample-project"))
        XCTAssertFalse(text.contains("$42"))
        XCTAssertFalse(text.contains("person@example.com"))
        XCTAssertFalse(text.contains("sk-live"))
    }

    func testEmailAndSecretTogglesAreIndependent() {
        let emailCard = UsageShareCard.make(
            dashboard: sampleDashboard(),
            options: UsageShareOptions(includeEmails: true)
        )
        XCTAssertTrue(emailCard.plainText.contains("person@example.com"))
        XCTAssertFalse(emailCard.plainText.contains("sk-live-abcdefghijklmnopqrstuvwxyz"))
        XCTAssertFalse(emailCard.plainText.contains("111122223333"))

        let secretCard = UsageShareCard.make(
            dashboard: sampleDashboard(),
            options: UsageShareOptions(includeTokensAndCookies: true)
        )
        XCTAssertTrue(secretCard.plainText.contains("sk-live-abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(secretCard.plainText.contains("cookie=session-token"))
        XCTAssertFalse(secretCard.plainText.contains("person@example.com"))
        XCTAssertFalse(secretCard.plainText.contains("$100"))
    }

    func testAllTogglesKeepEachCategory() {
        let card = UsageShareCard.make(
            dashboard: sampleDashboard(),
            options: UsageShareOptions(
                includeAccountIDs: true,
                includeDollarBudgets: true,
                includeEmails: true,
                includeTokensAndCookies: true
            )
        )
        let text = card.plainText
        XCTAssertTrue(text.contains("$42"))
        XCTAssertTrue(text.contains("111122223333"))
        XCTAssertTrue(text.contains("person@example.com"))
        XCTAssertTrue(text.contains("sk-live-abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(text.contains("gcp:sample-project"))
    }

    private func sampleDashboard() -> UsageDashboard {
        UsageDashboard(providers: [
            ProviderSnapshot(
                id: .grok,
                planLabel: "SuperGrok",
                state: .live,
                meters: [
                    UsageMeter(
                        id: "week",
                        title: "Weekly",
                        remainingFraction: 0.72,
                        footnote: "cookie=session-token sk-live-abcdefghijklmnopqrstuvwxyz"
                    ),
                ],
                detailSummary: "Details",
                message: "Reach person@example.com if this breaks"
            ),
            ProviderSnapshot(
                id: .bedrock,
                planLabel: "$42 MTD",
                state: .live,
                meters: [
                    UsageMeter(
                        id: "total",
                        title: "This month",
                        remainingFraction: 0.40,
                        footnote: "$42 of $100 budget"
                    ),
                    UsageMeter(id: "primary", title: "Primary", remainingFraction: 0.88),
                ],
                detailSummary: "Primary",
                fullWidth: true,
                shareOnlyDetails: ["account:111122223333"]
            ),
            ProviderSnapshot(
                id: .gemini,
                planLabel: "gemini-3.6-flash",
                state: .live,
                meters: [],
                detailSummary: "Google · sample-project",
                shareOnlyDetails: ["gcp:sample-project"]
            ),
        ])
    }

    private func assertPrivateDataAbsent(_ text: String) {
        XCTAssertFalse(text.contains("$"))
        XCTAssertFalse(text.contains("USD"))
        XCTAssertFalse(text.contains("budget"))
        XCTAssertFalse(text.contains("@"))
        XCTAssertFalse(text.contains("111122223333"))
        XCTAssertFalse(text.contains("gcp:"))
        XCTAssertFalse(text.contains("account:"))
        XCTAssertFalse(text.contains("sk-"))
        XCTAssertFalse(text.contains("cookie"))
        XCTAssertFalse(text.contains("sample-project"))
    }
}
