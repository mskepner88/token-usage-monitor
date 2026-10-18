import Foundation

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async -> ProviderSnapshot
}
