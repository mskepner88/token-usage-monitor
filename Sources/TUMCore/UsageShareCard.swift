import Foundation

/// What a shared snapshot is allowed to reveal. Every flag defaults off.
public struct UsageShareOptions: Codable, Equatable, Sendable {
    public var includeAccountIDs: Bool
    public var includeDollarBudgets: Bool
    public var includeEmails: Bool
    public var includeTokensAndCookies: Bool

    public init(
        includeAccountIDs: Bool = false,
        includeDollarBudgets: Bool = false,
        includeEmails: Bool = false,
        includeTokensAndCookies: Bool = false
    ) {
        self.includeAccountIDs = includeAccountIDs
        self.includeDollarBudgets = includeDollarBudgets
        self.includeEmails = includeEmails
        self.includeTokensAndCookies = includeTokensAndCookies
    }

    public static let `default` = UsageShareOptions()

    private enum CodingKeys: String, CodingKey {
        case includeAccountIDs, includeDollarBudgets, includeEmails, includeTokensAndCookies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includeAccountIDs = try container.decodeIfPresent(Bool.self, forKey: .includeAccountIDs) ?? false
        includeDollarBudgets = try container.decodeIfPresent(Bool.self, forKey: .includeDollarBudgets) ?? false
        includeEmails = try container.decodeIfPresent(Bool.self, forKey: .includeEmails) ?? false
        includeTokensAndCookies = try container.decodeIfPresent(Bool.self, forKey: .includeTokensAndCookies) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(includeAccountIDs, forKey: .includeAccountIDs)
        try container.encode(includeDollarBudgets, forKey: .includeDollarBudgets)
        try container.encode(includeEmails, forKey: .includeEmails)
        try container.encode(includeTokensAndCookies, forKey: .includeTokensAndCookies)
    }
}

public struct UsageShareRow: Equatable, Sendable {
    public var providerName: String
    public var accentHex: String
    /// Remaining percentages, one per meter. Empty when the provider has no meter yet.
    public var percentsLeft: [Int]
    /// Shown instead of percentages when the meters are readings, such as memory.
    public var valueLabel: String?
    /// Extra lines already scrubbed. Empty unless a privacy toggle opted in.
    public var details: [String]

    public init(
        providerName: String,
        accentHex: String,
        percentsLeft: [Int],
        valueLabel: String? = nil,
        details: [String] = []
    ) {
        self.providerName = providerName
        self.accentHex = accentHex
        self.percentsLeft = percentsLeft
        self.valueLabel = valueLabel
        self.details = details
    }

    public var percentLabel: String {
        if let valueLabel, !valueLabel.isEmpty {
            return valueLabel
        }
        return percentsLeft.map { "\($0)%" }.joined(separator: " · ")
    }
}

/// Shareable view of the dashboard. Defaults to provider names and percentages only.
public struct UsageShareCard: Equatable, Sendable {
    public var brandMark: String
    public var rows: [UsageShareRow]

    public init(brandMark: String = SkeptacularBrand.shareCardMark, rows: [UsageShareRow]) {
        self.brandMark = brandMark
        self.rows = rows
    }

    public static func make(
        dashboard: UsageDashboard,
        options: UsageShareOptions = .default
    ) -> UsageShareCard {
        let rows = dashboard.providers.map { snapshot in
            let readings = snapshot.meters.compactMap(\.reading)
            return UsageShareRow(
                providerName: snapshot.id.displayName,
                accentHex: snapshot.id.accentHex,
                percentsLeft: snapshot.meters.map(\.percentLeft),
                valueLabel: readings.isEmpty ? nil : readings.joined(separator: " · "),
                details: Self.details(from: snapshot, options: options)
            )
        }
        return UsageShareCard(rows: rows)
    }

    /// Names, percentages, opted-in details, and the brand mark. This is the text drawn onto the PNG.
    public var plainText: String {
        var lines = ["TUM", SkeptacularBrand.pitch, ""]
        for row in rows {
            if row.percentLabel.isEmpty {
                lines.append(row.providerName)
            } else {
                lines.append("\(row.providerName) \(row.percentLabel)")
            }
            lines.append(contentsOf: row.details)
        }
        lines.append("")
        lines.append(brandMark)
        return lines.joined(separator: "\n")
    }

    private static func details(from snapshot: ProviderSnapshot, options: UsageShareOptions) -> [String] {
        var blobs: [String] = [
            snapshot.planLabel,
            snapshot.detailSummary,
        ]
        if let message = snapshot.message {
            blobs.append(message)
        }
        blobs.append(contentsOf: snapshot.shareOnlyDetails)
        for meter in snapshot.meters {
            if let reset = meter.resetDescription {
                blobs.append(reset)
            }
            if let footnote = meter.footnote {
                blobs.append(footnote)
            }
        }

        var seen = Set<String>()
        var lines: [String] = []
        for blob in blobs {
            guard let line = UsageShareSanitizer.detailLine(from: blob, options: options) else { continue }
            if seen.insert(line).inserted {
                lines.append(line)
            }
        }
        return lines
    }
}

enum UsageShareSanitizer {
    enum Kind {
        case accountID
        case dollar
        case email
        case secret
    }

    struct Finding {
        var kind: Kind
        var range: Range<String.Index>
    }

    static func detailLine(from text: String, options: UsageShareOptions) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return nil }
        let found = findings(in: trimmed)
        guard found.contains(where: { options.allows($0.kind) }) else { return nil }
        let redacted = redact(trimmed, findings: found, options: options)
        let cleaned = collapse(redacted)
        guard !cleaned.isEmpty else { return nil }
        return cleaned
    }

    /// Removes emails, account IDs, dollar amounts, and secrets. Used for the iPhone widget file.
    static func scrubbed(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = redact(trimmed, findings: findings(in: trimmed), options: .default)
        return collapse(redacted)
    }

    static func findings(in text: String) -> [Finding] {
        var found: [Finding] = []
        func add(_ kind: Kind, pattern: String) {
            for range in matchRanges(pattern: pattern, in: text) {
                found.append(Finding(kind: kind, range: range))
            }
        }
        add(.email, pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#)
        add(.dollar, pattern: #"\$\s?\d{1,3}(?:,\d{3})*(?:\.\d+)?|\b\d+(?:\.\d+)?\s*USD\b|\bUSD\s*\$?\s?\d+(?:\.\d+)?"#)
        add(.accountID, pattern: #"\b\d{12}\b|arn:aws:[^\s]+|\b(?:account|gcp):[^\s]+"#)
        add(.secret, pattern: #"sk-[A-Za-z0-9_\-]{8,}|Bearer\s+\S+|eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]+|(?i)(?:cookie|api[_-]?key|token|secret)=[^\s;]+|\b[a-fA-F0-9]{32,}\b"#)
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func redact(_ text: String, findings: [Finding], options: UsageShareOptions) -> String {
        var result = ""
        var cursor = text.startIndex
        var consumedThrough = text.startIndex
        for finding in findings {
            if finding.range.lowerBound < consumedThrough { continue }
            if options.allows(finding.kind) {
                result.append(contentsOf: text[cursor..<finding.range.upperBound])
                cursor = finding.range.upperBound
                consumedThrough = finding.range.upperBound
            } else {
                result.append(contentsOf: text[cursor..<finding.range.lowerBound])
                cursor = finding.range.upperBound
                consumedThrough = finding.range.upperBound
            }
        }
        result.append(contentsOf: text[cursor...])
        return result
    }

    private static func matchRanges(pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            Range(match.range, in: text)
        }
    }

    private static func collapse(_ text: String) -> String {
        var cleaned = text
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        cleaned = cleaned.replacingOccurrences(of: " · · ", with: " · ")
        return cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "·|,")))
    }
}

extension UsageShareOptions {
    func allows(_ kind: UsageShareSanitizer.Kind) -> Bool {
        switch kind {
        case .accountID: includeAccountIDs
        case .dollar: includeDollarBudgets
        case .email: includeEmails
        case .secret: includeTokensAndCookies
        }
    }
}
