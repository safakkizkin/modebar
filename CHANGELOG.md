# Changelog

All notable changes to ModeBar are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-15

### Added

- Open-source GitHub layout: contributing guide, security policy, CI, release workflow
- Homebrew cask with published `ModeBar-0.1.0.zip` release artifact

### Added

- Menu bar macOS app (`LSUIElement`) with italic double-bar mark
- Classic Bluetooth RFCOMM BMAP client (channel probe `8 → 2 → 9`)
- Auto-connect to System Settings–paired compatible headphones
- Battery percent in the menu bar title
- Mode list loaded from the device; tap to switch
- Live sync (2s poll + unsolicited STATUS packets)
- Homebrew cask skeleton (`Casks/modebar.rb`) and `scripts/package.sh`

### Notes

- Verified on QuietComfort Headphones (`prince`, product id `0x4075`)
- App Sandbox off (required for IOBluetooth RFCOMM)
- Not affiliated with Bose Corporation
