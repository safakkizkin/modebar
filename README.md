# BoseQC

Simple macOS controller for Bose QuietComfort headphones.

Talks **BMAP over Classic Bluetooth RFCOMM channel 2** — the same path as [bosectl](https://github.com/aaronsb/bosectl) and [ANChor](https://github.com/JimmyCalhoun/ANChor). Not a Bose Music UI clone; not BLE GATT.

## Features

- Finds paired Bose headphones (one row per address — no duplicate LE-/classic entries)
- Connects over RFCOMM
- Reads battery + current mode
- Loads mode list **from the device** (AudioModes config), then switches modes

## Requirements

- macOS 14+
- Headphones already paired in System Settings → Bluetooth  
  On this Mac: **Dark Star** / **Onyx Star** (QuietComfort, product `0x4075`)

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

1. Power the headphones and connect them in System Settings if needed.
2. Open BoseQC → **Find headphones** → **Connect**.
3. Modes appear from the device; tap one to switch.

## Why not BLE?

BLE FEBE can show `Device error 0x14` / timeouts on QuietComfort Headphones. ANChor and bosectl use RFCOMM for the same BMAP packets; that is the reliable path here.

## Layout

```
BoseQC/
  BMAP/BmapPacket.swift
  Bluetooth/BoseBluetoothClient.swift   # IOBluetooth RFCOMM
  UI/ContentView.swift
```
