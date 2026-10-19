import Foundation

/// The small file the free iPhone widget reads (`widgets/scriptable/token-usage-monitor.js`).
/// Provider names, plan names, percentages, and reset times only. Never tokens, cookies,
/// emails, account IDs, or dollar amounts.
public struct PhoneWidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct Limit: Codable, Equatable, Sendable {
        public var label: String
        public var percentLeft: Int
        public var resetsAt: Date?

        public init(label: String, percentLeft: Int, resetsAt: Date? = nil) {
            self.label = label
            self.percentLeft = percentLeft
            self.resetsAt = resetsAt
        }
    }

    public struct Provider: Codable, Equatable, Sendable {
        public var name: String
        public var plan: String
        public var limits: [Limit]

        public init(name: String, plan: String, limits: [Limit]) {
            self.name = name
            self.plan = plan
            self.limits = limits
        }
    }

    public var version: Int
    public var updatedAt: Date
    public var providers: [Provider]

    public init(version: Int = currentVersion, updatedAt: Date, providers: [Provider]) {
        self.version = version
        self.updatedAt = updatedAt
        self.providers = providers
    }

    /// Providers without a meter (signed out, errors) are left out.
    public static func make(dashboard: UsageDashboard, now: Date = .now) -> PhoneWidgetSnapshot {
        let providers: [Provider] = dashboard.providers.compactMap { snapshot in
            guard !snapshot.meters.isEmpty else { return nil }
            let limits = snapshot.meters.map { meter in
                Limit(
                    label: UsageShareSanitizer.scrubbed(meter.title),
                    percentLeft: meter.percentLeft,
                    resetsAt: meter.resetsAt
                )
            }
            let plan = UsageShareSanitizer.scrubbed(snapshot.planLabel)
            return Provider(
                name: snapshot.id.displayName,
                plan: plan == "—" ? "" : plan,
                limits: limits
            )
        }
        return PhoneWidgetSnapshot(updatedAt: now, providers: providers)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public enum PhoneWidgetSnapshotWriter {
    public static let fileName = "tum-snapshot.json"

    /// Scriptable's own iCloud folder. Shows up once Scriptable is installed on an iPhone signed in to the same iCloud.
    public static func scriptableFolder(home: URL) -> URL {
        home.appendingPathComponent(
            "Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents",
            isDirectory: true
        )
    }

    /// Fallback when Scriptable's folder is not there yet: iCloud Drive › TokenUsageMonitor.
    public static func fallbackFolder(home: URL) -> URL {
        home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/TokenUsageMonitor",
            isDirectory: true
        )
    }

    public static func destination(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL {
        var isDir: ObjCBool = false
        let scriptable = scriptableFolder(home: home)
        if fileManager.fileExists(atPath: scriptable.path, isDirectory: &isDir), isDir.boolValue {
            return scriptable.appendingPathComponent(fileName)
        }
        return fallbackFolder(home: home).appendingPathComponent(fileName)
    }

    /// Writes atomically (temp file, then rename) so iCloud never syncs half a file.
    @discardableResult
    public static func write(
        _ snapshot: PhoneWidgetSnapshot,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = destination(home: home, fileManager: fileManager)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try snapshot.jsonData().write(to: url, options: .atomic)
        return url
    }
}
