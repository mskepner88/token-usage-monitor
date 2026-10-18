# Releasing TUM

TUM is a free app from Skeptacular Apps (`skeptacularapps`). Tags named `vX.Y.Z` run [`.github/workflows/release.yml`](../.github/workflows/release.yml) on a macOS runner.

The workflow always packages with [`scripts/package-app.sh`](../scripts/package-app.sh). What happens next depends on whether the signing secrets below are set on the repository.

## Version

1. Set `CFBundleShortVersionString` in `Sources/TUMMac/Resources/Info.plist` to the version you are shipping (`0.2.0`, not `v0.2.0`).
2. Commit that change.
3. Tag the commit and push the tag:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Do not force-push `main` to publish a release. The tag is the release.

## Signed release

When every secret in this list is present, the workflow imports the Developer ID certificate, signs the app, submits it with `notarytool`, staples the ticket, builds `TokenUsageMonitor-<version>.dmg`, and attaches that DMG to a GitHub Release.

| Secret | What it is |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application `.p12`, base64-encoded |
| `APPLE_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `APPLE_SIGNING_IDENTITY` | Certificate common name, for example `Developer ID Application: Skeptacular Apps (TEAMID)` |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_ID` | Apple ID enrolled in the developer program |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password used by `notarytool` |

Create the values in the Apple Developer account and store them as GitHub Actions secrets. Do not commit certificates, passwords, or `.p12` files.

Notarization uses `xcrun notarytool submit --apple-id --password --team-id --wait`.

## Unsigned artifact

If any of those secrets is missing, the workflow does not sign, notarize, or open a GitHub Release. It uploads `TokenUsageMonitor-<version>-unsigned.zip` as a GitHub Actions artifact. That zip is the ad-hoc signed app from `scripts/package-app.sh`. It is not notarized.

## Homebrew

The cask template lives at [`packaging/token-usage-monitor.rb`](../packaging/token-usage-monitor.rb). The tap name is `skeptacularapps/tap`.

After a signed DMG is attached to the GitHub Release:

1. Replace `version` and `sha256` in the cask (`shasum -a 256 TokenUsageMonitor-<version>.dmg`).
2. Commit the cask to the `skeptacularapps/tap` repository (a separate repo from this app).
3. Users install with:

```bash
brew tap skeptacularapps/tap
brew install --cask token-usage-monitor
```

The app bundle id is `com.skeptacularapps.token-usage-monitor`.

## Check the build locally

```bash
swift test
./scripts/package-app.sh
```

`swift test` covers TUMCore (config defaults, the tip-jar nudge, and share-card redaction). The menu-bar app itself builds on macOS.
