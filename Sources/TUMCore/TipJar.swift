import Foundation

public enum TipJarChoice: String, Codable, Sendable, Equatable {
    case buyCoffee
    case notNow
}

public struct TipJarRecord: Codable, Equatable, Sendable {
    public var firstSeenAt: Date
    /// Set after the user picks "Leave a tip" or "Not now". Either choice hides the nudge forever.
    public var resolved: Bool
    public var choice: TipJarChoice?

    public init(firstSeenAt: Date, resolved: Bool = false, choice: TipJarChoice? = nil) {
        self.firstSeenAt = firstSeenAt
        self.resolved = resolved
        self.choice = choice
    }
}

/// One-time tip-jar nudge. Persistence is a small JSON file; the decision itself is pure.
public struct TipJar: Sendable {
    public static let nudgeDelay: TimeInterval = 14 * 24 * 60 * 60
    public static let nudgeMessage =
        "TUM is free. If it's kept you from hitting a limit, a tip keeps it that way ($5 suggested)."
    public static let buyButtonTitle = "Leave a tip"
    public static let dismissButtonTitle = "Not now"

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        ConfigStore.configDirectory.appendingPathComponent("tip-jar.json")
    }

    public static func shouldShowNudge(
        record: TipJarRecord,
        now: Date,
        delay: TimeInterval = TipJar.nudgeDelay
    ) -> Bool {
        guard !record.resolved else { return false }
        return now.timeIntervalSince(record.firstSeenAt) >= delay
    }

    /// Creates the record on first launch. Later calls keep the original `firstSeenAt`.
    public func loadOrStart(now: Date = .now) throws -> TipJarRecord {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            return try Self.makeDecoder().decode(TipJarRecord.self, from: data)
        }
        let record = TipJarRecord(firstSeenAt: now, resolved: false, choice: nil)
        try save(record)
        return record
    }

    public func shouldShowNudge(now: Date = .now) throws -> Bool {
        let record = try loadOrStart(now: now)
        return Self.shouldShowNudge(record: record, now: now)
    }

    /// Records either nudge button. Both hide the nudge permanently.
    public func resolve(_ choice: TipJarChoice, now: Date = .now) throws {
        var record = try loadOrStart(now: now)
        record.resolved = true
        record.choice = choice
        try save(record)
    }

    private func save(_ record: TipJarRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.makeEncoder().encode(record)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
