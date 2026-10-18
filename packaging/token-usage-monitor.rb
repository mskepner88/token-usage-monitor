# Homebrew cask for the skeptacularapps/tap tap.
# Ship this from a signed, notarized, stapled DMG on a GitHub Release.
# Replace version and sha256 for each release:
#   shasum -a 256 TokenUsageMonitor-<version>.dmg
cask "token-usage-monitor" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/mskepner88/token-usage-monitor/releases/download/v#{version}/TokenUsageMonitor-#{version}.dmg"
  name "Token Usage Monitor"
  desc "One glance at every AI limit before you hit it"
  homepage "https://github.com/mskepner88/token-usage-monitor"

  depends_on macos: ">= :sonoma"

  app "Token Usage Monitor.app"

  zap trash: [
    "~/Library/Application Support/TokenUsageMonitor",
    "~/Library/Preferences/com.skeptacularapps.token-usage-monitor.plist",
  ]
end
