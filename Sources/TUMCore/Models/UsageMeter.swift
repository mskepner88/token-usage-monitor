import Foundation

public struct UsageMeter: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    /// Fraction remaining in `0...1`. Prefer remaining over used for UI.
    public var remainingFraction: Double
    public var resetDescription: String?
    /// Exact reset time when the provider gives one. Feeds the iPhone widget snapshot.
    public var resetsAt: Date?
    public var footnote: String?
    /// Replaces the "% left" label when the meter is a reading, such as memory in use.
    public var reading: String?

    public init(
        id: String,
        title: String,
        remainingFraction: Double,
        resetDescription: String? = nil,
        resetsAt: Date? = nil,
        footnote: String? = nil,
        reading: String? = nil
    ) {
        self.id = id
        self.title = title
        self.remainingFraction = min(max(remainingFraction, 0), 1)
        self.resetDescription = resetDescription
        self.resetsAt = resetsAt
        self.footnote = footnote
        self.reading = reading
    }

    public var percentLeft: Int {
        Int((remainingFraction * 100).rounded())
    }

    public static func fromUsedPercent(
        id: String,
        title: String,
        usedPercent: Double,
        resetDescription: String? = nil,
        resetsAt: Date? = nil,
        footnote: String? = nil
    ) -> UsageMeter {
        UsageMeter(
            id: id,
            title: title,
            remainingFraction: 1 - (usedPercent / 100),
            resetDescription: resetDescription,
            resetsAt: resetsAt,
            footnote: footnote
        )
    }
}
