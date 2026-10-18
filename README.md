# Token Usage Monitor (TUM)

A Mac menu bar app that shows how much of each AI plan you have left.

![Token Usage Monitor showing usage meters for six AI services](docs/screenshot.png)

*Screenshot uses sample numbers.*

TUM is a free, open-source app from [Skeptacular Apps](https://skeptacularapps.com).

## What it shows

- Grok, Claude, ChatGPT (Codex), Cursor, and Ollama Cloud, using the logins those tools already keep on your Mac.
- Gemini, Cerebras, Amazon Bedrock, and Vercel AI Gateway, if you turn them on and point them at your own project or account in Settings. They are off by default.
- A share button that copies a picture of your meters. It leaves out emails, account IDs, dollar amounts, and tokens unless you turn those on.

## Build and run

You need macOS 14 or later and Swift 6 (Xcode 16 or the Swift toolchain).

```bash
git clone https://github.com/mskepner88/token-usage-monitor.git
cd token-usage-monitor
./scripts/run.sh
```

To build the app bundle without opening it:

```bash
./scripts/package-app.sh
open "dist/Token Usage Monitor.app"
```

Run the tests:

```bash
swift test
```

Open **Settings** from the menu bar popover to turn services on or off, change their order, and add your own paths or accounts. An example config is in [`config.example.json`](config.example.json).

Settings are saved in `~/Library/Application Support/TokenUsageMonitor/`. Pasted cookies and keys go in a local `secrets.json` there, or in the Keychain if you choose that in Settings.

## Privacy

- Local-first. Everything runs on your Mac.
- No telemetry, no analytics, no TUM server.
- Your logins and keys are only sent to the service they belong to, to read your usage.

## Notes

Some services don't have an official way to read usage, so a meter may stop working when they change things. The card shows an error when that happens. TUM is not affiliated with any of the services it reads.

Release and packaging notes are in [docs/RELEASING.md](docs/RELEASING.md).

## License

MIT. See [LICENSE](LICENSE).

Website: [skeptacularapps.com](https://skeptacularapps.com)
