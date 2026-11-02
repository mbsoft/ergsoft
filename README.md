# ErgSoft

iOS + watchOS app for Rogue Echo (and any FTMS) rowers and bikes. Connects over Bluetooth
(FTMS, Fitness Machine Service), shows live metrics, runs interval workouts, records sessions,
exports to Apple Health, and receives live heart rate from an Apple Watch companion app.

## License

GPL-3.0-or-later — see LICENSE.

## Build

```
brew install xcodegen
cd ~/workspace/ergsoft
xcodegen generate
open ErgSoft.xcodeproj
```

In Xcode: select the `ErgSoft` scheme, set your Team under Signing & Capabilities for both
targets (or put your Team ID in `project.yml` and re-run `xcodegen`). Bluetooth and HealthKit
need a real device — the simulator has neither.

## Layout

- `ErgSoft/Bluetooth` — CoreBluetooth manager, FTMS packet decoders (Rower Data 0x2AD1,
  Indoor Bike Data 0x2AD2), BLE heart-rate strap (0x180D).
- `ErgSoft/Workout` — workout engine (timeline, intervals, sample recording) and live UI.
- `ErgSoft/Models` — SwiftData session storage and interval plans.
- `ErgSoft/Health` — HealthKit export.
- `ErgSoft/Watch` — WatchConnectivity receiver for watch heart rate.
- `ErgSoftWatch` — watchOS app: starts an HKWorkoutSession and streams HR to the phone.

## Heart rate priority

Watch HR (via WatchConnectivity) > BLE chest strap > HR reported in the FTMS packet.
