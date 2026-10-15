# BoseQC

Minimal open-source macOS controller for Bose QuietComfort headphones. Talks **BMAP over BLE** (service `FEBE`) via CoreBluetooth — scan, connect, read battery / name / noise mode, switch modes.

This is intentionally small. It is not a Bose Music UI clone.

## Requirements

- macOS 14+
- Xcode 16+
- Bose headphones that expose BMAP over BLE (QuietComfort / Ultra class). On this Mac the paired set is **Dark Star** (QuietComfort Headphones, product `0x4075`).

## Run

```bash
cd BoseQC
open BoseQC.xcodeproj
```

Or:

```bash
cd BoseQC
xcodebuild -scheme BoseQC -configuration Debug -derivedDataPath ../.derived build
open ../.derived/Build/Products/Debug/BoseQC.app
```

Grant Bluetooth permission when macOS asks.

## Use

1. Power the headphones and keep them nearby.
2. Tap **Scan**.
3. Select the device → **Connect**.
4. Use Quiet / Aware / Commute (mode indices 0–2 — exact mapping is device-specific) or the raw index stepper.
5. **Refresh** re-queries battery, name, and current mode.

## Layout

```
BoseQC/
  BMAP/BmapPacket.swift          # packet + BLE segmentation
  Bluetooth/BoseBluetoothClient.swift
  UI/ContentView.swift           # one simple window
```

## Limits

- Classic Bluetooth RFCOMM (older QC35 path) is not implemented — BLE only.
- Multipoint / EQ / shortcuts come later.
- Mode index labels are best-effort from AudioModes config; if a preset does nothing, try the raw index after Refresh.
