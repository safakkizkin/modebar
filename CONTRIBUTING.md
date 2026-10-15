# Contributing to ModeBar

Thanks for helping. ModeBar is a small MIT-licensed menu bar app; keep changes focused and testable on real hardware when you can.

## Ground rules

- English for code, commits, docs, and PR titles.
- Do not add Bose trademarks, official logos, or proprietary assets.
- Do not commit secrets, signing certificates, or personal Bluetooth dumps with customer data.
- Prefer RFCOMM/BMAP behaviour that matches what the headphones already expose (modes, battery) over inventing UI for unsupported products.

## Development

Requirements: macOS 14+, Xcode 16+, headphones paired in System Settings.

```bash
cd ModeBar
xcodebuild -scheme ModeBar -configuration Debug -derivedDataPath ../.derived build
open ../.derived/Build/Products/Debug/ModeBar.app
```

Release zip (for Homebrew / GitHub Releases):

```bash
./scripts/package.sh 0.1.0
```

## Pull requests

1. Fork and branch from `main` (`feat/…`, `fix/…`).
2. Keep one concern per PR.
3. Update `CHANGELOG.md` under `[Unreleased]` when the change is user-visible.
4. If you change the cask artifact name or version scheme, update `Casks/modebar.rb` and the release workflow together.
5. Describe what you tested (build only vs real headphones / product id).

## Protocol notes

See [docs/protocol.md](docs/protocol.md). New BMAP function blocks need a short note there plus a failing-then-passing manual check on at least one device when possible.
