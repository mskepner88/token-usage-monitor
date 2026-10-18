import Foundation

public enum TUMFormatting {
    private static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "HH:mm"
        return f
    }()

    public static func time(_ date: Date) -> String {
        shortTime.string(from: date)
    }

    /// How long until `date`, e.g. "Resets in 1 day, 18 hours".
    /// `includeTime` is kept so existing call sites stay source-compatible.
    public static func resetLabel(from date: Date, includeTime _: Bool = true) -> String {
        remainingUntil(date)
    }

    public static func remainingUntil(_ date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 60 { return "Resets now" }

        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 {
                return "Resets in \(spell(days, "day")), \(spell(hours, "hour"))"
            }
            return "Resets in \(spell(days, "day"))"
        }
        if hours > 0 {
            if minutes > 0 {
                return "Resets in \(spell(hours, "hour")), \(spell(minutes, "minute"))"
            }
            return "Resets in \(spell(hours, "hour"))"
        }
        return "Resets in \(spell(max(minutes, 1), "minute"))"
    }

    /// Next midnight in Pacific time (Gemini daily quotas).
    public static func nextPacificMidnight(from now: Date = .now) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")
            ?? TimeZone(secondsFromGMT: -8 * 3600)
            ?? .current
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
    }

    private static func spell(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }

    public static func resetLabel(unixSeconds: Int?, includeTime: Bool = true) -> String? {
        guard let unixSeconds else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        return resetLabel(from: date, includeTime: includeTime)
    }

    public static func bytesLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    public static func expandHome(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return (NSHomeDirectory() as NSString).appendingPathComponent(String(path.dropFirst(2)))
        }
        if path == "~" {
            return NSHomeDirectory()
        }
        return path
    }
}
