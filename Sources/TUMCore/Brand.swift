import Foundation

/// Public brand for TUM.
/// Display copy uses "Skeptacular Apps". Slugs, bundle ids, taps, and URLs use `skeptacularapps`.
public enum SkeptacularBrand {
    public static let displayName = "Skeptacular Apps"
    public static let slug = "skeptacularapps"
    public static let bundleID = "com.skeptacularapps.token-usage-monitor"
    public static let homebrewTap = "skeptacularapps/tap"
    public static let pitch = "One glance at every AI limit before you hit it."
    public static let shareCardMark = "TUM by Skeptacular Apps"

    /// The only payment link in the app (the Skeptacular Apps tip page).
    public static let tipURL = URL(string: "https://skeptacularapps.com/tip")!

    public static let activeClipboardURL = URL(string: "https://skeptacularapps.com/apps/active-clipboard")!
}
