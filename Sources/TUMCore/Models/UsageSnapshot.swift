import Foundation

public enum ProviderLiveState: String, Sendable, Equatable {
    case live
    case stale
    case offline
    case needsAuth
    case error
}

public struct ProviderSnapshot: Identifiable, Sendable, Equatable {
    public var id: ProviderID
    public var planLabel: String
    public var state: ProviderLiveState
    public var meters: [UsageMeter]
    public var detailSummary: String
    public var message: String?
    public var fetchedAt: Date
    /// When true, the card spans the full popover width (e.g. multi-account spend).
    public var fullWidth: Bool
    /// Strings the in-app card does not render. The share card may include them only when the matching privacy toggle is on.
    public var shareOnlyDetails: [String]

    public init(
        id: ProviderID,
        planLabel: String,
        state: ProviderLiveState,
        meters: [UsageMeter],
        detailSummary: String,
        message: String? = nil,
        fetchedAt: Date = .now,
        fullWidth: Bool = false,
        shareOnlyDetails: [String] = []
    ) {
        self.id = id
        self.planLabel = planLabel
        self.state = state
        self.meters = meters
        self.detailSummary = detailSummary
        self.message = message
        self.fetchedAt = fetchedAt
        self.fullWidth = fullWidth
        self.shareOnlyDetails = shareOnlyDetails
    }

    public static func unavailable(
        _ id: ProviderID,
        state: ProviderLiveState,
        message: String,
        planLabel: String = "—",
        fullWidth: Bool = false
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            planLabel: planLabel,
            state: state,
            meters: [],
            detailSummary: "Details",
            message: message,
            fullWidth: fullWidth
        )
    }
}

public struct UsageDashboard: Sendable, Equatable {
    public var providers: [ProviderSnapshot]
    public var refreshedAt: Date

    public init(providers: [ProviderSnapshot], refreshedAt: Date = .now) {
        self.providers = providers
        self.refreshedAt = refreshedAt
    }
}
