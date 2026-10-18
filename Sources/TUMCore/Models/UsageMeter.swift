import Foundation

public struct UsageMeter: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    /// Fraction remaining in `0...1`. Prefer remaining over used for UI.
    public var remainingFraction: Double
    public var resetDescription: String?
    public var footnote: String?

    public init(
        id: String,
        title: String,
        remainingFraction: Double,
        resetDescription: String? = nil,
        footnote: String? = nil
    ) {
        self.id = id
        self.title = title
        self.remainingFraction = min(max(remainingFraction, 0), 1)
        self.resetDescription = resetDescription
        self.footnote = footnote
    }

    public var percentLeft: Int {
        Int((remainingFraction * 100).rounded())
    }

    public static func fromUsedPercent(
        id: String,
        title: String,
        usedPercent: Double,
        resetDescription: String? = nil,
        footnote: String? = nil
    ) -> UsageMeter {
        UsageMeter(
            id: id,
            title: title,
            remainingFraction: 1 - (usedPercent / 100),
            resetDescription: resetDescription,
            footnote: footnote
        )
    }
}
