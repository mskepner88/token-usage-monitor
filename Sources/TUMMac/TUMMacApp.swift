import SwiftUI

@main
struct TUMMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Status item + popover are owned by AppDelegate (more reliable than MenuBarExtra).
        Settings {
            EmptyView()
        }
    }
}
