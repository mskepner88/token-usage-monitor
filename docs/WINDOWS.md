# Windows port notes

TUM is structured so a Windows UI can reuse the same concepts without sharing Apple frameworks.

## What is already portable

| Piece | Location | Notes |
| --- | --- | --- |
| Models | `TUMCore/Models` | Pure value types |
| Config schema | `config.example.json` / `AppConfig` | Same JSON on every OS |
| Provider contracts | `UsageProvider` + snapshots | Fetch → `ProviderSnapshot` |
| Ollama provider | local HTTP | Works anywhere Ollama runs |
| File secrets | `FileSecretStore` | Default non-macOS path |

`TUMCore` avoids AppKit/SwiftUI. Only `KeychainSecretStore` is Apple-specific; Windows should use DPAPI / Credential Manager behind the same `SecretStore` protocol.

## Suggested Windows shape

1. Keep `config.example.json` as the cross-platform contract.
2. Reimplement UI in WinUI 3, WPF, or Tauri — menu-tray popover mirroring the macOS cards.
3. Either:
   - compile `TUMCore` with [Swift for Windows](https://www.swift.org/documentation/windows/) and call it from a thin shell, or
   - port providers to C#/TypeScript using the same endpoints documented in the providers.

## Provider auth on Windows

| Provider | Source |
| --- | --- |
| Codex | `%USERPROFILE%\.codex\auth.json` + same OAuth refresh |
| Claude | Claude Code credentials file / Credential Manager equivalent |
| Cursor | Session cookie stored via `SecretStore` (never in git) |
| Ollama | `http://127.0.0.1:11434` |
| Gemini, Cerebras, Bedrock, Vercel AI Gateway | Off until the user sets a project path, GCP project id, or AWS SSO profile. No built-in account defaults. |

## Do not commit

- Session cookies
- OAuth refresh tokens
- `config.local.json` / `.env`
- Packaged secrets or exported keychains
