# BMAP over RFCOMM (ModeBar)

ModeBar controls QuietComfort-class headphones with the Bose Message Access
Protocol (**BMAP**) on **Classic Bluetooth RFCOMM**, not BLE GATT.

## Why RFCOMM

BLE service `FEBE` (segmented 20-byte writes) was tried on QuietComfort
Headphones (`prince`, product id `0x4075`) and returned `Device error 0x14` /
timeouts. The working path matches [ANChor](https://github.com/JimmyCalhoun/ANChor)
and [bosectl](https://github.com/aaronsb/bosectl): raw BMAP on RFCOMM.

| Product class (examples) | Typical RFCOMM channel |
| --- | --- |
| QuietComfort Headphones (`prince`, `0x4075`) | **8** |
| QC Ultra / many earbuds | **2** |
| Fallback probe | **9** |

ModeBar probes `8 → 2 → 9` and keeps the first channel that answers a BMAP smoke query.

## Packet shape

4-byte header + payload (no BLE segment byte):

`[function_block, function_id, op_byte, length] + payload`

Ops used today: GET (`0x01`), START (`0x05`), plus unsolicited STATUS handling.

## Features ModeBar speaks

| Feature | Block / function | Notes |
| --- | --- | --- |
| Battery | Status `0x02` / `0x02` | Polled + unsolicited |
| Product name | Settings `0x01` / `0x02` | |
| Current mode | AudioModes `0x1F` / `0x03` | GET + START |
| Capabilities / labels | AudioModes `0x02`, `0x06` | Mode list from device |

Unauthenticated GET/START is enough for these everyday controls; cloud ECDH is
not required for the current feature set.

## Platform constraints

- macOS `IOBluetooth` RFCOMM needs **App Sandbox off** (see entitlements).
- RFCOMM open/write runs on a dedicated background thread with an active RunLoop
  (main-thread sync opens hang).
- Headphones should already be paired (and preferably connected) in System Settings.
- A stuck channel often clears after disconnect/reconnect of the headphones.

## Out of scope (for now)

Speakers, soundbars, non-BMAP gear, and legacy ANR-only paths (e.g. older QC35
Settings ANR without AudioModes `0x1F`) are not first-class yet.
