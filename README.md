# ModeBar

Menu bar controller for QuietComfort-class headphones.

Talks **BMAP over Classic Bluetooth RFCOMM** (probes channels `8 → 2 → 9`), same idea as [bosectl](https://github.com/aaronsb/bosectl) and [ANChor](https://github.com/JimmyCalhoun/ANChor).

No Dock icon — lives in the macOS menu bar. Not affiliated with Bose Corporation.

## Features

- Auto-connects to the System Settings–paired compatible headphones on launch
- Battery % in the menu bar title when connected
- Mode list loaded from the device; tap to switch
- Live sync every 2s + unsolicited updates (phone app / on-ear changes)

## Supported devices

**Not all Bose products.** ModeBar speaks BMAP/RFCOMM. Verified locally on QuietComfort Headphones (`prince`, product id `0x4075`, names like Dark Star / Onyx Star). The same channel probe often works on other QuietComfort / Ultra / Earbuds models that bosectl lists, but speakers, soundbars, and non-BMAP gear are out of scope.

## Install (Homebrew)

After the first GitHub Release of `ModeBar-0.1.0.zip` exists on a public repo that contains this tap:

```bash
brew tap <owner>/modebar
brew install --cask modebar
```

Or install the cask from a local checkout:

```bash
brew install --cask ./Casks/modebar.rb
```

Update `url`, `homepage`, and `sha256` in `Casks/modebar.rb` from `scripts/package.sh` output before publishing.

Unsigned builds may need:

```bash
xattr -dr com.apple.quarantine /Applications/ModeBar.app
```

Apple notarization (Developer ID) is recommended before wider Homebrew distribution. Mac App Store is a poor fit: RFCOMM needs the sandbox off.

## Build from source

```bash
./scripts/package.sh 0.1.0
# or debug:
cd ModeBar
xcodebuild -scheme ModeBar -configuration Debug -derivedDataPath ../.derived build
open ../.derived/Build/Products/Debug/ModeBar.app
```

Look for the headphones icon in the menu bar. Quit from the menu.

## Notes

- Pair headphones in System Settings first.
- If RFCOMM fails, disconnect/reconnect the headphones once (channel lock).
- `LSUIElement` is on — no Dock tile.
