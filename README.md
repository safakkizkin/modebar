# BoseQC

Menu bar controller for Bose QuietComfort headphones.

Talks **BMAP over Classic Bluetooth RFCOMM** (channel 8 for QuietComfort Headphones / `prince`, 2 for Ultra — probes `8 → 2 → 9`), same idea as [bosectl](https://github.com/aaronsb/bosectl) and [ANChor](https://github.com/JimmyCalhoun/ANChor).

No dock icon — lives in the macOS menu bar.

## Features

- Auto-connects to the System Settings–connected Bose device on launch
- Battery % in the menu bar title when connected
- Mode list loaded from the headphones; tap to switch
- Live sync every 2s + unsolicited updates (phone / on-ear changes)

## Run

```bash
cd BoseQC
xcodebuild -scheme BoseQC -configuration Debug -derivedDataPath ../.derived build
open ../.derived/Build/Products/Debug/BoseQC.app
```

Look for the headphones icon in the menu bar (top right). Quit from the menu.

## Notes

- Pair headphones in System Settings first.
- If RFCOMM fails, disconnect/reconnect the headphones once (channel lock).
- `LSUIElement` is on — no Dock tile.
