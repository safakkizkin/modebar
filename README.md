# ModeBar

[![CI](https://github.com/safakkizkin/modebar/actions/workflows/ci.yml/badge.svg)](https://github.com/safakkizkin/modebar/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Menu bar controller for QuietComfort-class headphones.

Talks **BMAP over Classic Bluetooth RFCOMM** (probes channels `8 → 2 → 9`), same idea as [bosectl](https://github.com/aaronsb/bosectl) and [ANChor](https://github.com/JimmyCalhoun/ANChor).

No Dock icon — lives in the macOS menu bar.

**Not affiliated with Bose Corporation.** Bose, QuietComfort, and related marks belong to their owners.

## Features

- Auto-connects to System Settings–paired compatible headphones on launch
- Battery % next to the menu bar mark when connected
- Mode list loaded from the device; tap to switch
- Live sync every 2s + unsolicited updates (phone app / on-ear changes)

## Supported devices

**Not all Bose products.** ModeBar speaks BMAP/RFCOMM. Verified on QuietComfort Headphones (`prince`, product id `0x4075`). The same channel probe often works on other QuietComfort / Ultra / Earbuds models that bosectl lists. Speakers, soundbars, and non-BMAP gear are out of scope.

See [docs/protocol.md](docs/protocol.md).

## Install (Homebrew)

After a GitHub Release publishes `ModeBar-x.y.z.zip` and `Casks/modebar.rb` has a real `sha256`:

```bash
brew tap safakkizkin/modebar https://github.com/safakkizkin/modebar
brew install --cask modebar
```

From a local checkout:

```bash
brew install --cask ./Casks/modebar.rb
```

Unsigned builds may need:

```bash
xattr -dr com.apple.quarantine /Applications/ModeBar.app
```

Developer ID notarization is recommended before wider distribution. Mac App Store is a poor fit: RFCOMM needs the App Sandbox off.

## Build from source

macOS 14+, Xcode 16+.

```bash
./scripts/package.sh 0.1.0
# or debug:
cd ModeBar
xcodebuild -scheme ModeBar -configuration Debug -derivedDataPath ../.derived build
open ../.derived/Build/Products/Debug/ModeBar.app
```

Look for the italic double-bar mark in the menu bar. Quit from the menu.

## Notes

- Pair headphones in System Settings first.
- If RFCOMM fails, disconnect/reconnect the headphones once (channel lock).
- `LSUIElement` is on — no Dock tile.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Security reports: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Third-party protocol references: [NOTICE](NOTICE).
