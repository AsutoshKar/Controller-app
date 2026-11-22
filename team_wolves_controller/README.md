# Team Wolves — Wolve Bot Pro Controller

Prototype (Phase 4) Android + iOS controller for the Wolve Bot RoboRace robot.
Flutter/Dart, one project, no firmware changes, no extra runtime packages.

Status: **prototype for owner review — not race ready.** No `flutter analyze`,
`flutter test`, or build has been run in this delivery (see
[Verification](#verification-result)).

---

## 1. What is in this tree

```
team_wolves_controller/
├── lib/
│   ├── main.dart                       app entry, landscape + immersive
│   ├── protocol/                       PURE DART, no Flutter imports
│   │   ├── crc8.dart                   CRC-8 poly 0x07 init 0x00
│   │   └── protocol.dart               frame encode / telemetry decode
│   ├── transport/
│   │   ├── robot_transport.dart        contract + listener + status
│   │   ├── udp_transport.dart          RawDatagramSocket, ephemeral port
│   │   └── ble_transport.dart          flutter_blue_plus, write coalescing
│   ├── controller/
│   │   ├── drive_shaper.dart           expo / scale / cap / decel / trim
│   │   ├── energy_estimator.dart       duty-based pack estimate
│   │   └── drive_controller.dart       timing, link/arm state, diagnostics
│   └── ui/
│       ├── splash_screen.dart
│       ├── console_screen.dart
│       ├── connection_popup.dart
│       ├── settings_sheet.dart
│       └── widgets/  hud_widgets.dart · pro_joystick.dart · wolve_watermark.dart
├── test/                               unit + widget tests, fake transport
├── android/                            Gradle project + manifest + Kotlin host
├── ios/                                Xcode project + Info.plist + Swift host
├── pubspec.yaml
└── analysis_options.yaml
```

Layering is enforced by imports: `ui/` never writes a packet, `protocol/` has
no platform imports, `transport/` owns sockets and BLE, `controller/` owns
timing and safety state.

---

## 2. Quota result

| Item | Value |
|---|---|
| Audit root | `/home/user` (the quota-metered workspace root) |
| Measured size | **298,187 bytes (0.298 MB)** |
| Measured files | **65** |
| Limit | ≤ 125,000,000 bytes and < 10,000 files |
| Result | **PASS** — 0.24 % of the byte budget, 0.65 % of the file budget |

The audit counted every regular file including hidden and untracked files, and
failed on any symlink or special file. No SDK, Gradle distribution, `build/`,
`.dart_tool/`, `ios/Pods/`, or APK/AAB/IPA is present.

Re-run the audit from the workspace root:

```bash
python3 -I -B - <<'PY'
import os, stat
limit_bytes = 125_000_000
file_count = 0
total_bytes = 0
directories = [os.getcwd()]
while directories:
    with os.scandir(directories.pop()) as entries:
        for entry in entries:
            info = entry.stat(follow_symlinks=False)
            if stat.S_ISDIR(info.st_mode):
                directories.append(entry.path)
            elif stat.S_ISREG(info.st_mode):
                file_count += 1
                total_bytes += info.st_size
            else:
                raise SystemExit(f"FAIL: unsupported file or link: {entry.path}")
print(f"{total_bytes:,} bytes ({total_bytes / 1_000_000:.3f} MB)")
print(f"{file_count:,} files")
if total_bytes > limit_bytes or file_count >= 10_000:
    raise SystemExit("FAIL: workspace exceeds the delivery budget")
print("PASS: workspace is at most 125 MB and below 10,000 files")
PY
```

The platform's own meter was not available to this session; only the
filesystem audit above was run.

---

## 3. Verification result

| Check | Status |
|---|---|
| `flutter pub get` | **NOT RUN** — no Flutter SDK in the delivery environment |
| `flutter analyze` | **NOT RUN** |
| `flutter test` | **NOT RUN** |
| Android build | **NOT RUN** |
| iOS build / signing | **NOT RUN** |
| On-device UDP link, BLE link, E-STOP | **NOT RUN** |
| `pubspec.lock` | **Not supplied** — never fabricate a lockfile. `flutter pub get` on the Mac produces the real one. |
| Platform quota meter | **NOT AVAILABLE** to this session |

What *was* done: every Dart file was hand-reviewed for type and API
correctness, bracket/quote balance was machine-checked across all 23 Dart
files, and the pure-Dart protocol math was checked against the published
CRC-8 test vector in `test/crc8_test.dart`.

Do not read this as "zero errors". Run the commands in section 4 before
trusting anything.

---

## 4. Build and run on the owner's Mac

Requires: Flutter SDK on macOS, Xcode, Android Studio (or the Android SDK) for
the Android build.

```bash
cd team_wolves_controller

# If ios/Runner.xcodeproj is ever replaced or Xcode reports a project error:
#   rm -rf ios/Runner.xcodeproj
#   flutter create --platforms=ios --no-pub .
#   then re-apply the Info.plist / AppDelegate.swift in this tree.
# The shipped project already contains a complete scaffold, so this is only
# a recovery path.

flutter pub get          # creates pubspec.lock and ios/Flutter/Generated.xcconfig
flutter analyze          # must report no errors before building
flutter test             # unit + widget tests
flutter run --release    # release build, real timing
```

Optional: `flutter create --platforms=android,ios --no-pub .` inside the
project adds any missing template file without overwriting the delivered
source (`--overwrite` is off by default).

### Android first run

1. Enable Developer options → USB debugging on the phone.
2. `flutter devices`, confirm the phone, then `flutter run --release`.
3. Grant Nearby Devices / Bluetooth when prompted (Android 12+).
4. Join the robot AP in the phone's Wi-Fi settings: SSID `ROBORACE_ESP32`,
   password `race2025`. When Android asks, choose **"Stay connected without
   internet"** — otherwise Android may drop the AP or route over cellular.
5. Open the app → tap the status pill → **Wi-Fi UDP → CONNECT**.
6. A link is only live when the HUD shows `WIFI LIVE` and telemetry values
   appear. `NO TELEMETRY` means the socket is bound but the robot has not
   answered.

Android permissions are pre-declared in
`android/app/src/main/AndroidManifest.xml`: `INTERNET`, `ACCESS_NETWORK_STATE`,
`ACCESS_WIFI_STATE`, `VIBRATE`, `BLUETOOTH_SCAN` (`neverForLocation`),
`BLUETOOTH_CONNECT`, plus legacy `BLUETOOTH`/`BLUETOOTH_ADMIN`/
`ACCESS_FINE_LOCATION` capped at `maxSdkVersion=30`.

Minimum SDK is `max(flutter.minSdkVersion, 21)`. Disclose any change the
toolchain forces.

### iOS first run

1. `open ios/Runner.xcworkspace` (or let `flutter run` do it) and set your
   signing team under *Runner → Signing & Capabilities*.
2. On the device, allow **Bluetooth** and **Local Network** when prompted.
   `NSLocalNetworkUsageDescription` and `NSBluetoothAlwaysUsageDescription`
   are already set in `ios/Runner/Info.plist`.
3. Join the robot AP in iOS Settings → Wi-Fi, then **Wi-Fi UDP → CONNECT**.
4. `Local Network` must be allowed or UDP to `192.168.4.1` silently fails.

### Switching to BLE

Tap the status pill → **Bluetooth LE → SCAN** → pick `ROBORACE_ESP32` →
**CONNECT**. This is a **manual** switch: the UDP link is closed, all input and
link state is cleared, and a deliberate new arm is required. There is no
automatic failover and no hot takeover.

---

## 5. Controls

| Control | Action |
|---|---|
| Left vertical stick | Throttle. Up = forward, down = reverse. |
| Right horizontal stick | Steering. Left/right. |
| **BOOST 100%** (hold) | Requests M3, removes speed scaling, near-linear throttle expo 0.05. Release restores the prior selection. |
| **ZERO PIVOT** (hold) | Throttle forced to zero, steering retained at expo 0.15 for counter-rotation. |
| **35% / 65% / 100%** | Power preset. |
| **TORQUE / SPEED** | Profile. Torque is amber, Speed is cyan. |
| **TERRAIN** | Tap to cycle NORMAL → SAND/PEBBLES → PLY/SLICK → FIRE SPRINT. |
| **OFF / ON (ARMED)** | Arm/disarm. Arming requires a live link and both sticks within ±5%. |
| **E-STOP** | Fires on pointer-down. Sends `0x06` immediately and latches. |

Sticks spring to zero on pointer-up and pointer-cancel. Hold paddles release on
pointer-up and pointer-cancel, and are cleared by disarm, E-STOP, link loss,
transport change and app backgrounding. Two sticks and both paddles can be held
at the same time — each control owns its own pointer ID.

Colour is always paired with text: green = confirmed armed/live, amber =
warning/connecting, red = E-STOP/lost.

---

## 6. Settings (in memory only)

Straight-line trim (−0.15…+0.15 with reset) · throttle expo (0.00–0.70) ·
steering expo (0.00–0.70) · reverse cap (0.30–1.00) · smooth decel (OFF by
default) · fixed/floating sticks · haptics · **NEW PACK** reset · telemetry
inspector.

Selecting a terrain replaces the default throttle expo, steering expo and
high-speed turn factor; the sliders then adjust from that baseline.

Nothing is persisted. There are no accounts, analytics, cloud sync, race logs,
lap timing or CSV export in the prototype.

---

## 7. Diagnostics

Top HUD: link pill, ESP32 state, L/R **motor output** percent, confirmed
M1/M2/M3, echo RTT, cumulative firmware drops, estimated pack use, Settings gear.

Connection dialog: transport detail, RTT, drops, TX/RX counts, and the
distinction between **radio connected** and **live telemetry**. Settings →
telemetry inspector adds telemetry age, last sequence, malformed-frame count and
TX/RX byte counts.

- RTT is a coarse phone → ESP32 → phone echo estimate, **not** input-to-wheel
  latency. It shows `--` until a valid sample exists.
- The pack estimate is duty-based. It is **not** measured charge, voltage, or a
  low-voltage cutoff.
- Telemetry older than **650 ms** is treated as stale and triggers the red
  `LINK LOST` notice and a heavy haptic. This is separate from the ESP32's
  **250 ms** DRIVE watchdog.

---

## 8. Bench review checklist

Secure the robot with all wheels clear. Keep motors unpowered for the first
communications checks. Confirm the actual E-STOP protocol against
`sketch_nov22a` before relying on the app's stop button. Verify stopping paths
at low output **before** testing BOOST or driving on the ground.

Mark each line **OKAY / NOT OKAY / NEEDS CHANGE**.

### Minimum prototype tests

| ID | Test | Pass condition | Result |
|---|---|---|---|
| PTC-01 | Boot twitch | Five power cycles with no phone; wheels stay still. Record any GPIO14 twitch. | ☐ |
| PTC-02 | Direction | At 35% with wheels clear, forward commands drive both sides forward. Record any inversion needed. | ☐ |
| PTC-03 | Steering | Centre throttle, steer right: left moves forward, right moves backward. | ☐ |
| PTC-04 | Link-loss failsafe | At low output, turn Wi-Fi off. Measure last accepted DRIVE → stopped output, plus physical wheel stop. Target ~250 ms. Reconnect alone must not restart motion. | ☐ |
| PTC-05 | E-STOP | At low output, press E-STOP while holding throttle. Confirm command receipt, firmware ESTOP state, stopped outputs, deliberate recovery. | ☐ |
| PTC-06 | Lifecycle stop | Background the app while driving on the bench. DRIVE stops, watchdog trips, resume does not re-arm. | ☐ |
| PTC-07 | UDP link | Joined to the AP, valid telemetry shows WIFI LIVE, DISARMED, M2, L/R 0% before arming. RTT appears only after a valid sample. | ☐ |
| PTC-08 | BLE fallback | Manually switch UDP → BLE. No overlap, no auto-arm. Confirm notifications, measured usable rate, low-output control. | ☐ |
| PTC-09 | Race controls | After stop checks pass: BOOST and restoration, pivot zero throttle, each terrain's shaping. Release/cancel can never leave an override active. | ☐ |

### Console and tuning review

| Feature | Result |
|---|---|
| Splash: 2.2 s bar, tap-to-skip, auto entry ~2.4 s, no connect/arm | ☐ |
| Landscape layout, safe areas, no scrolling to drive or stop | ☐ |
| Wolf watermark at low opacity, non-interactive | ☐ |
| Two sticks operable at once, spring to zero on release/cancel | ☐ |
| Fixed-origin and floating-origin sticks | ☐ |
| BOOST hold/release and profile restoration | ☐ |
| ZERO PIVOT hold/release and throttle zeroing | ☐ |
| 35 / 65 / 100 presets and TORQUE/SPEED mapping | ☐ |
| "TORQUE LIMITED" indicator at 65/100 in Torque | ☐ |
| Terrain quick-cycle changes shaping | ☐ |
| ON/OFF with ±5% centring interlock and ESP32-confirmed ARMED | ☐ |
| E-STOP on pointer-down, latched, no confirmation delay | ☐ |
| Haptics at deadband, 50%, 95%+, mode changes, link loss | ☐ |
| HUD values never show stale data as live | ☐ |
| Connection dialog: UDP/BLE cards, spinner, statuses, counters | ☐ |
| Settings: trim, expo, reverse cap, smooth decel, floating, haptics | ☐ |
| NEW PACK resets the estimate and the pack timer | ☐ |
| Telemetry inspector readable during a bench run | ☐ |

---

## 9. Known limitations and open questions

**Unconfirmed — do not assume:**

- `0x06 E_STOP` and `0x07 HEARTBEAT` payload lengths. The prior prototype used
  LEN 0; **verify against `sketch_nov22a`** before powered testing.
- Owner's Flutter version and first test phone: **[FILL]**.
- Event date year and remaining days; the "supply 250v 50hz" rule is
  unexplained — ask the organisers, do not interpret it.
- Kill-switch presence, fuse adoption, wheel/tire fit, GPIO14 boot twitch.
- `INVERT_LEFT` / `INVERT_RIGHT` direction.
- Whether Serial Monitor shows `AP IP: 192.168.4.1` and
  `RoboRace receiver ready: DISARMED` at 115200 after EN.
- Battery runtime. The 10–18 minute figure on one 2200 mAh pack was rough and
  unmeasured; 30 minutes is a test target, not a guarantee.

**Deliberate non-features:** no autonomous navigation, GPS/IMU, encoders,
camera/AI, current-based limiting, battery voltage, traction control, Classic
Bluetooth SPP, JSON packets, or a second simultaneous controller.

**Known prototype limits:**

- 5–10 ms at 50–75 m is a test target, not a guarantee. Measure it.
- The BLE path is slower (~45 Hz scheduling target) and has no per-packet
  confirmation when using write-without-response.
- `flutter_lints: ^3.0.0` is kept as specified. If the installed SDK is newer
  and `flutter analyze` reports lint-version friction, bump it deliberately and
  note the change.

---

## 10. Decisions, open questions, next step

**Decisions taken in this build**

1. One transport, one driver. Manual switch only; no failover, no hot takeover.
2. App-side speed ratios are nominal command scaling. The firmware still owns
   deadband, expo, slew, breakaway floor and mixing, so 35% is not a guaranteed
   wheel duty.
3. Terrain selection overwrites the default expo/damping values; the sliders
   adjust from that baseline.
4. The local E-STOP latch clears only on a deliberate OFF, and the app re-latches
   if the ESP32 reports ESTOP. Telemetry returning never clears it or re-arms.
5. No `pubspec.lock` is shipped rather than shipping a fabricated one.
6. Android/iOS scaffolds are hand-authored and therefore **unverified** until
   the Mac build runs.

**Open questions for the owner**

1. Flutter version and first test phone?
2. Confirm the E-STOP and HEARTBEAT payload lengths in `sketch_nov22a`.
3. Confirm the deliberate OFF → ON recovery path is what the firmware does.
4. Android first, or iOS first?
5. Is the event outdoors on all four surfaces in one run, or is the fire
   section a separate stage?

**Next step**

Run `flutter pub get && flutter analyze && flutter test` on the Mac, then
`flutter run --release` and work down PTC-01 → PTC-09 in order. Stay in Phase 4
until the owner has marked the console, tuning and connection features. Report
back with the changed files, why, and the exact retest for each change.
