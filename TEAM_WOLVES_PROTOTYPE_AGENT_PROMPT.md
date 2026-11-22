# Team Wolves — Wolve Bot Pro Controller
## Complete prototype build brief with a strict 125 MB workspace budget

You are the senior Flutter, mobile UX, and robotics-control engineer responsible for building the Team Wolves RoboRace prototype. Produce a complete, maintainable Android and iOS controller for Wolve Bot. Build it for the owner to test and mark **OKAY / NOT OKAY / NEEDS CHANGE**. Do not advance to the final app or claim race readiness on the basis of a build alone.

The quality target is to outperform generic phone controllers and feel like a ₹50,000–₹100,000 professional RC transmitter, even when competing against teams using ₹5,000–₹10,000 controllers. Treat that as a bar for responsiveness, predictable control, ergonomics, and clear feedback—not a claim that a phone can match dedicated radio hardware in every respect.

## 1. Hard workspace limits — read before running any command

A prior session created **561.4 MB and 30,452 files** against a platform limit of **128.0 MB and 10,000 files**. **28,203 files were not saved.** Do not assume that the earlier project or even all of its handwritten source files survived.

**Acceptance limits:**
- Entire saved workspace: **≤ 125,000,000 bytes**, uncompressed.
- Entire saved workspace: **< 10,000 files**; 9,999 is the maximum.
- Count hidden, ignored, and untracked files. Do not measure only `lib/` or only Git-tracked files.
- If the platform also meters files or bytes created during the session, stay within the same budget throughout. Deleting files afterward is not a solution.
- Aim to finish well below either limit. Do not pad to 125 MB, minify readable source, reduce app functionality, omit tests, or remove Android/iOS support to fit.
- These limits apply to the saved workspace. An APK, AAB, or IPA built separately is a different artifact and must not be copied back into the saved workspace.

**Execution rules:**
1. Identify the actual quota-metered root and audit it **before writing files**. Inspect any surviving source and owner assets. Do not delete unrecognized files, user work, or Git history. If the existing workspace is already over budget, report it and use a clean, authorized workspace for the source handoff.
2. Save only the complete authored Flutter source, required Android/iOS project scaffolding and configuration, small source assets, tests, real lockfiles where available, and concise documentation. Keep Gradle wrapper/project files required by the scaffold; do not include a Gradle distribution.
3. Do **not** install or copy SDKs, emulators, dependency trees, Flutter engines, Gradle or Pub caches, CocoaPods installations, or generated artifacts into the saved workspace. Examples: `build/`, `.dart_tool/`, `.gradle/`, `.pub-cache/`, `ios/Pods/`, `ios/.symlinks/`, `ios/Flutter/ephemeral/`, `DerivedData/`, generated machine-specific Flutter/Xcode config, and `android/local.properties`. Do not store duplicate project copies, large logs, signing secrets, dependency archives, or APK/AAB/IPA files there. Add appropriate ignore rules for normal development, but **ignoring a file does not exempt it from quota**.
4. Do not run `flutter create`, `flutter pub get`, `flutter analyze`, `flutter test`, Gradle, CocoaPods, or a build inside the quota-metered workspace. Use an existing minimal scaffold or generate and verify it **only in an authorized build environment confirmed to be outside both workspace and session quotas**. Do not assume `/tmp` is exempt. Do not work around quota using symlinks, archives, or hidden directories.
5. If no separate build environment is available, complete the source handoff and provide the exact scaffold/setup/build commands for the owner's Mac. If you cannot produce verified platform scaffolding in that environment, say exactly which template files the Mac setup must generate and where to apply the supplied source/configuration. Mark checks **NOT RUN**, not passed. Never fabricate a lockfile or analyzer output.
6. Copy back an allowlisted set of source and project files only—not an entire post-build project directory. Audit again after staging and after the last write. If the gate fails, report the cause and move out only reproducible artifacts where permitted. Do not remove app content to pass. The platform's own meter must also pass if available.

Run this read-only audit from the **quota-metered root** before changes and once the final saved files are in place. It uses Python's standard library and writes no project files:

```bash
python3 -I -B - <<'PY'
import os
import stat

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

The budget changes how you build and package the project. It does **not** change any requirement below.

## 2. Project status, authority, and constraints

- Project: **Team Wolves — Wolve Bot Pro Controller**. Event date: **28 November**; year and remaining days are unconfirmed. The event is outdoors, in an open field. Surfaces include normal ground, cardboard/ply, sand/stones/pebbles, and a fire section. Size limit: **30 × 30 × 15 cm**. The rule **"supply 250v 50hz"** is unexplained; ask organizers, do not interpret it. No specific failsafe or frequency rules were reported; verify event rules separately.
- Driver goals: 5–10 ms latency, ideally ≤5 ms, at 50–75 m, and 30 minutes of driving. These are **test targets, not guarantees**. The previous 10–18 minute estimate on one 2200 mAh pack was rough and unmeasured. A pack-swap plan and any alternative battery arrangement are not approved hardware changes.
- Workflow: **1 Information → 2 Blueprint → 3 Keep/Change → 4 Prototype → 5 Testing → 6 Final App**. Phases 1–3 were delivered; Phase 3 did not get a standalone formal approval. Phase 4 had M1–M6, initial firmware/app code and TC-01–TC-09. The owner subsequently approved the expanded prototype direction with **"1 -5 approved."** Build/rework Phase 4 now. No successful app analysis, phone build, bench test, or Phase 5/6 completion is established.
- Current prototype baseline: **Option A, no firmware reflash; Wi-Fi UDP primary and manual BLE fallback; 35/65/100 UI presets; separate ARM and E-STOP; built-in wolf emblem; full approved console and tuning features below.** Approval is not evidence that the firmware payloads, radio range, or runtime behavior have been verified.
- Constraints precede required outputs, examples, and preferences. Never assume hardware or silently resolve a conflict. Mark unknowns **UNCONFIRMED** or **[FILL: …]**. Proceed with all unblocked work and ask only about conflicts that change approved behavior or prevent safe verification. End each phase with decisions, open questions, and the next step.

### Hardware and firmware reference

- ESP32-WROOM-32, ESP32-D0WD-V3, PCB antenna only. Two BTS7960 drivers. On both, `VCC`, `R_EN`, and `L_EN` are hardwired to 5 V; `R_IS` and `L_IS` are unconnected. The ESP32 cannot open the EN circuit, cut motor power, or command coast through EN. The intended software brake is both PWM inputs LOW; verify the real stopping behavior on the bench.
- Four 12 V, 300 RPM geared motors, two in parallel per driver, 4WD skid-steer. Gear ratio and stall current unknown. Current wheel recommendation: four individual soft knobby tires, 85–105 mm diameter, 40–50 mm width, with foam inserts.
- Main pack: 11.1 V 3S, 2200 mAh, 35C/70C burst, 24.42 Wh. LiPo is assumed, not verified; the earlier "1.21 V LiFeO" was treated as a typo. A 5 V buck feeds ESP32 and driver logic, with common ground. No fuse fitted; a 30–40 A fuse was previously discussed, not adopted or validated. Kill-switch presence unknown.
- No wheel encoders, IMU, current sensor, or battery voltage sensor. The app can shape commands, not measure wheel slip, actual road speed, motor torque, or battery state of charge.
- Confirmed pin map: left `RPWM=25`, `LPWM=26`; right `RPWM=27`, `LPWM=14`. Verify `INVERT_LEFT` and `INVERT_RIGHT` on the bench. GPIO14 boot twitch is unconfirmed. 10 kΩ pull-downs, or moving the right signal to GPIO33 if necessary, were discussed as separate hardware/firmware decisions; do not apply them in the app task.
- Latest firmware is the separate single Arduino C++ sketch **`sketch_nov22a`**. It was rewritten twice and is not included in this brief. Board: **ESP32 Dev Module**, default partition, Arduino IDE only, no non-Arduino libraries, no `delay()`, inline comments and explicit placeholders. macOS serial port: `/dev/cu.usbserial-0001`.
- Compile record on esp32 core 4.0.0: **974,247 / 1,310,720 bytes (74%)**, globals **50,644 bytes (15%)**. The old 921600-baud upload hit `A fatal error occurred: Invalid head of packet (0xFF)` after the boot components verified, with main image verification incomplete. The owner subsequently reported a successful upload. Do not reflash unnecessarily. If reflashing later is approved, the recovery procedure uses 115200 and a short data cable with the motor battery disconnected. Opening Serial Monitor at 115200 and pressing EN should show `AP IP: 192.168.4.1` and `RoboRace receiver ready: DISARMED`; these runtime observations are not yet confirmed.
- Firmware settings/placeholders: `WIFI_PASS`, `WIFI_CHANNEL`, `INVERT_LEFT`, `INVERT_RIGHT`, `MODES`. Do not change them in this app task.
- Keep failsafe, E-STOP latch, motor clamping, arming interlock, and direction reversal protection on the ESP32. Reference behavior: 1 kHz control loop, 10-bit LEDC channels 0–3, `enableLoopWDT()`, callbacks update shared state under `portMUX`, and only the control loop writes PWM. Accepted DRIVE frames feed the nominal **250 ms** watchdog; HEARTBEAT does not. Failsafe stays latched until re-armed. Arming needs a live link and both inputs within **±50**. Sequence acceptance is expected to resync after a link gap. BLE disconnect alone must not stop a robot being driven over Wi-Fi.
- Firmware pipeline: rescaled 5% deadband → expo and turn damping → skid-steer mix with separate linear/turn caps → slew → breakaway floor → 15 ms reverse guard → PWM. Reference cap correction: `(cap - floorDuty) / (1 - floorDuty)` for each axis. These are firmware behaviors, not a reason to add a second app-side motor safety system.

| Firmware mode | Linear cap | Turn cap | Floor | Expo | PWM Hz | Accel ms | Decel ms | Turn damping |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| M1 | 0.45 | 0.85 | 0.25 | 0.65 | 2000 | 125 | 60 | 0.15 |
| M2 — default | 0.65 | 0.90 | 0.20 | 0.80 | 4000 | 250 | 100 | 0.30 |
| M3 | 1.00 | 1.00 | 0.18 | 1.00 | 4000 | 80 | 50 | 0.25 |

## 3. Where and how to build

- Use **Flutter/Dart**, one project for **Android and iOS**. Project directory: `team_wolves_controller`. Use the Flutter CLI on macOS or in an authorized build environment. Arduino IDE is for the ESP32 only. Do not require VS Code. Owner's installed Flutter version and first test phone are **[FILL]**; Android is a practical first test and iOS requires macOS/Xcode signing.
- Use Flutter and the approved `flutter_blue_plus: ^1.32.12`; use Flutter's SDK test tooling. The previous baseline used Dart `>=3.2.0 <4.0.0` and `flutter_lints: ^3.0.0` as a dev dependency. Verify compatibility with the real installed SDK and resolved plugin API. Do not add runtime packages or silently change versions to make old snippets work. Commit a real app `pubspec.lock` when resolved externally.
- Use a four-layer design. Existing code is a reference, **not** a requirement to preserve its bugs. Deliver complete files, not edits that assume an unsaved previous file exists.

```text
lib/
  main.dart
  protocol/
    crc8.dart
    protocol.dart
  transport/
    robot_transport.dart
    udp_transport.dart
    ble_transport.dart
  controller/
    drive_controller.dart
    drive_shaper.dart
    energy_estimator.dart
  ui/
    splash_screen.dart
    console_screen.dart
    connection_popup.dart
    settings_sheet.dart
    widgets/
      hud_widgets.dart
      pro_joystick.dart
      wolve_watermark.dart
test/
android/
ios/
pubspec.yaml
README.md
```

`protocol/` is pure Dart. `transport/` owns sockets, BLE scanning/subscriptions, and writes. `controller/` owns input, drive timing, link/arm state, diagnostics, and tuning. `ui/` renders state and forwards driver intent; it must not write packets directly.

### Radio specification

- Wi-Fi SoftAP/UDP primary: SSID `ROBORACE_ESP32`, current test password `race2025`, IP `192.168.4.1`, UDP port `4210`, firmware channel 1, maximum 2 clients, 19.5 dBm configured power. Use `RawDatagramSocket` with an ephemeral local IPv4 port; receive replies on the same socket. Join the AP in the phone's Wi-Fi settings. The app's Connect button opens the UDP link; a bound socket alone is not a live robot link.
- BLE manual fallback: device `ROBORACE_ESP32`, service `0000abcd-0000-1000-8000-00805f9b34fb`, control `0000ab01-0000-1000-8000-00805f9b34fb` (`WRITE | WRITE_NR`), telemetry `0000ab03-0000-1000-8000-00805f9b34fb` (`NOTIFY`). Verify the peripheral and both required characteristics; handle real adapter and permission failures. Use write-without-response when supported; never allow writes to accumulate.
- One transmitting transport and one driver at a time. Manual switch closes the old link, clears old input and link state, and requires a deliberate new arm. A backup phone may be available but its app stays closed while the primary phone is driving. No automatic failover or hot takeover.
- Android: configure `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `VIBRATE`; `BLUETOOTH_SCAN` with `neverForLocation` and `BLUETOOTH_CONNECT` for Android 12+, with runtime permission handling; legacy `BLUETOOTH`, `BLUETOOTH_ADMIN`, and `ACCESS_FINE_LOCATION` with `maxSdkVersion=30` where applicable. Minimum SDK baseline is 21 or higher if the actual toolchain requires it; disclose any change. Show the **"Stay connected without internet"** instruction when joining the AP.
- iOS: add `NSLocalNetworkUsageDescription` for local UDP and `NSBluetoothAlwaysUsageDescription` for BLE. Explain that local network access and Bluetooth permission must be allowed. Use the required signing setup; do not save certificates or provisioning secrets.

### Binary protocol

Frame: `[0xA5][TYPE][SEQ][LEN][PAYLOAD...][CRC8]`. CRC-8 polynomial `0x07`, init `0x00`, over `TYPE` through the end of payload; exclude SOF and CRC. Use an unsigned 8-bit sequence counter that wraps at 255.

| Type | Frame | Payload |
|---|---|---|
| `0x01` | DRIVE, LEN 5 | flags: `0x01` armed, `0x02` E-STOP; throttle signed int16 LE; steering signed int16 LE. Both axes −1000…1000. |
| `0x02` | SET_MODE, LEN 1 | Mode ID 1–3. |
| `0x05` | ARM, LEN 1 | `1` arm, `0` disarm. |
| `0x06` | E_STOP | Prior prototype uses LEN 0. **[FILL: verify in `sketch_nov22a`]**. |
| `0x07` | HEARTBEAT | Prior prototype uses LEN 0. **[FILL: verify in `sketch_nov22a`]**. Never use it in place of DRIVE. |
| `0x81` | TELEMETRY, LEN 6, 11 bytes total | Header sequence is the echo. Payload: state `uint8`, L% `int8`, R% `int8`, mode `uint8`, dropped low byte, dropped high byte. `dropped = lo | (hi << 8)`. |

State codes: `0 BOOT`, `1 DISARMED`, `2 ARMED`, `3 FAILSAFE`, `4 ESTOP`. Reject malformed frames with bad SOF, TYPE, length or CRC; do not use them to make the link appear live. Telemetry has roughly 100 ms minimum spacing for immediate echoes and a roughly 250 ms periodic update. Verify protocol assumptions against the actual sketch before powered testing; never mark E-STOP verified from a successful Flutter build.

## 4. Approved user experience

### Splash and console

- Start in landscape with a dark tactical carbon-grid/radial-gradient background and a built-in geometric wolf emblem. Display **"TEAM WOLVES"**, **"ROBO RACE"**, and **"STARTING WOLVE BOT"**. A cosmetic progress bar animates for about 2.2 s, with tap-to-skip and automatic entry at about 2.4 s. The startup status can read `INITIALIZING 100HZ TACTICAL LINK...`; it is not proof of a radio connection. Do not connect or arm on the splash.
- Main console: two-handed landscape, immersive where supported, keep-screen-awake race experience, no scrolling required to drive or stop. Do not claim that immersive mode blocks all OS gestures. Handle safe areas and small displays. Reuse the emblem as a non-interactive low-opacity **Wolve watermark** (~0.10–0.13); optional future asset `assets/wolve_logo.png`. The first run needs no external asset.
- Reference layout: ~38–40 logical-pixel top HUD; main area ~34% left, 32% center, 34% right. Left has **BOOST 100%** and vertical throttle. Right has **ZERO PIVOT** and horizontal steering. Center has **35% / 65% / 100%**, **TORQUE / SPEED**, terrain, **ON/OFF (ARM/DISARM)**, and the separate oversized red **E-STOP**. Keep the safety controls reachable instead of shrinking them to preserve a layout ratio.
- Default fixed-origin sticks, optional floating-origin sticks. Raw `Listener` pointer IDs support two sticks and other controls at the same time. Spring each raw stick to zero on pointer-up/cancel; a floating-stick touchdown starts at neutral. Hold paddles must release on pointer-up/cancel and clear on safety/lifecycle transitions.
- Cyan/teal for primary and speed; amber for torque, boost, and warnings; green for confirmed armed/live; red for E-STOP/lost. Use text as well as color. Optional haptics default ON: leaving deadband, ~50%, ~95–100%, mode/switch changes, link loss, and distinct heavy feedback for BOOST/E-STOP. Avoid repeated haptic triggers around thresholds.

### HUD, radio popup, and Settings

- HUD: Wi-Fi/BLE status pill; ESP32 state; L/R **motor output** percentages; confirmed M1/M2/M3; echo RTT estimate; cumulative firmware drops; estimated pack usage; Settings gear. Never show stale values as live or report local arm intent as `ARMED`.
- Status pill opens a connection dialog with **Wi-Fi UDP (primary)** and **Bluetooth LE (backup)** cards, connect/disconnect, spinner while connecting, device/address/rate details, **CONNECTED / NO TELEMETRY / DISCONNECTED** statuses, RTT, drops and TX/RX counts. Show Android no-internet and iOS local-network hints. BLE radio connection and live robot telemetry are separate facts.
- Settings drawer: L/R straight-line trim slider and reset, throttle expo, steering expo, reverse cap, optional smooth decel, fixed/floating sticks, haptics, **NEW PACK** timer/estimate reset, and telemetry inspector (state, mode, L/R, drops, RTT and telemetry age). Leave tuning out of the cockpit except for agreed quick controls.
- Session-only state: active link, latest valid telemetry and sequence/time, link freshness, bounded RTT samples, TX/RX counters, selected speed/torque/terrain, input and arm/stop intent, notice text, tuning, elapsed time, and estimated duty usage. No accounts, analytics, cloud sync, persistence, race logs, lap timing, or CSV in the prototype.

### Speed mapping — Option A, no firmware changes

| Driver selection | Firmware and app behavior |
|---|---|
| Torque + 35% | M1; multiply shaped throttle by `35/45`. |
| Torque + 65% or 100% | M1; no extra throttle scaling. The firmware still has its lower torque-mode cap. |
| Speed + 35% | M2; multiply shaped throttle by `35/65`. |
| Speed + 65% | M2, unscaled. This is the default. |
| Speed + 100% | M3, unscaled. |
| BOOST held | Request M3; temporarily remove normal speed scaling and use near-linear throttle expo `0.05`. Releasing restores the prior selection. |
| ZERO PIVOT held | Set throttle command to zero; retain driver steering with expo `0.15` for counter-rotation. Release restores normal input shaping. |

Torque is left/amber; Speed is right/cyan. Do not add a 45% preset. Use a **Torque limited** indicator when appropriate so 65% or 100% selected in Torque does not imply that output. The app-side ratios are nominal throttle-command scaling: firmware deadband, expo, slew, breakaway floor and mixing mean they do **not** guarantee an exact wheel-duty percentage or road speed. "Torque" is a profile name, not measured torque. Do not implement Option B or change firmware caps without approval.

### Input shaping and terrain

- Outside pivot: apply throttle and steering expo, speed mapping, reverse cap, optional smooth decel, terrain steering damping and trim, in that order. Clamp axes to `[-1,1]`, use `(1-e)*x + e*x*x*x` for expo, and clamp final signed commands to `[-1000,1000]`. Do not use `math.pow` in the transmit path.
- Reverse cap: range `0.30–1.00`, default `0.60`, for negative throttle outside BOOST. Straight-line trim: `−0.15…+0.15`, default zero; add `throttle * trim` to steering only above `abs(throttle) > 0.04`. This is an open-loop steering bias, not automatic calibration. Expo sliders: `0.00–0.70`.
- Smooth decel defaults OFF. When enabled, limit only decreases in throttle magnitude; previous reference step is `0.08` per nominal 10 ms UDP tick. It is a driving feel adjustment, not a substitute for firmware braking. Never let it retain a command through disarm, E-STOP, loss of link, transport change, pause, or pivot entry. Clear shaper history on those transitions.
- Steering multiplier: `1 - (1 - highSpeedTurnFactor) * abs(shapedThrottle)`. Terrain quick-cycle changes the app's default expo and damping:

| Preset | Throttle expo | Steering expo | High-speed turn factor |
|---|---:|---:|---:|
| NORMAL | 0.20 | 0.30 | 0.90 |
| SAND / PEBBLES | 0.45 | 0.35 | 0.72 |
| PLY / SLICK | 0.35 | 0.55 | 0.65 |
| FIRE SPRINT | 0.05 | 0.15 | 1.00 |

These are driver-selected profiles, not surface detection or closed-loop traction control. Test the sprint profile on a safe straight before any event obstacle. The competitive advantages to validate are repeatable low-speed lines, deliberate pivots at tight gates, stable steering on slick sections, well-timed straightaway boost, straight-line trim, clean radio diagnostics, and planned pack swaps. Do not promise a win, guaranteed range, or a measured advantage before testing.

### Pack estimator

Use valid L/R telemetry and elapsed time to integrate `((abs(L) + abs(R))/2 + 3) * dtSeconds`. Use `60,000` %-seconds as the previous tunable budget; clamp the resulting estimate and reset it and the pack timer on **NEW PACK**. Do not integrate stale gaps as if measured. Label this as a **duty-based estimate**, not measured battery charge or voltage. Never use it as a low-voltage cutoff or a pack safety indicator.

## 5. Controller correctness, timing, and safety

- Use a `ChangeNotifier`-based controller with a periodic TX scheduler: nominal **100 Hz UDP** (10 ms), **~45 Hz BLE** (22 ms). These are scheduling targets, not hard real-time guarantees. Input events update the latest values; do not queue past stick movements. Keep TX independent of widget rebuilds. Measure performance in release mode.
- Use bounded memory, monotonic elapsed time and a fixed-size sequence/timestamp lookup for RTT. There are only 256 sequence IDs. Clear diagnostics on session change; reject stale or ambiguous echoes. Report echo RTT as a coarse round-trip estimate, not input-to-wheel latency. Do not display `0 ms` when no sample exists.
- Reuse buffers where ownership permits; do not mutate a buffer still used by an asynchronous BLE write. Serialize BLE writes, prioritize stop/disarm, and drop obsolete DRIVE commands rather than growing a queue. Store and cancel socket and BLE subscriptions, timers, and in-flight connection work. Prevent old callbacks from changing a new session. Keep getters valid Dart declarations; do not copy the earlier grouped-getter syntax. Avoid per-TX `notifyListeners()` and unnecessary repainting.
- Clear stale link and arm state on transport changes. Treat telemetry at about **650 ms** age as stale/lost in the app; provide the visual alert and optional heavy haptic. This is a UI freshness threshold, separate from the ESP32's **250 ms DRIVE watchdog**. A recovered link must not auto-rearm.
- Send `SET_MODE` when attaching or when the requested mode changes (including BOOST press/release). Do not send it every DRIVE tick. Distinguish requested mode from telemetry-confirmed mode; handle a dropped mode command instead of indefinitely assuming it arrived.
- **ON** requests `ARM=1` only with a live link and both sticks centered within ±5%. If off-center, show **"Center both joysticks (±5%) before turning ON."** **OFF** clears drive intent and sends `ARM=0`. Await ESP32 state before showing `ON (ARMED)`. Clear arm intent on failsafe or ESTOP. The app's switch does not switch battery power.
- **E-STOP** acts on pointer-down, without an animation or confirmation delay: clear stick/hold/arm intent and shaper history, send `0x06` at the first available transport opportunity, and include the E-STOP flag on subsequent DRIVE frames while locally latched. No zero-radio-latency promise. Distinguish "stop command sent" from ESP32-confirmed ESTOP. Use the deliberate OFF/re-arm recovery only if confirmed in the firmware. Do not clear E-STOP or re-arm merely because telemetry returns.
- On inactive/background/detached: zero inputs, clear holds and arm intent, reset shaping, cancel the DRIVE timer. An async connect finishing in the background must not restart driving. On resume, restart only the unarmed session if the transport remains usable. Keep safety enforcement on the ESP32.

## 6. Rejected paths and deferred work

Do not reintroduce Classic Bluetooth SPP, BLE-only operation, a Rust firmware rewrite, JSON/text packets, a giant monolithic `main.dart`, two simultaneous controllers, or forced motor stop in the BLE disconnect callback. Do not advertise guaranteed 5 ms at 50–75 m. No autonomous navigation, GPS/IMU, wheel encoders, camera/AI, current-based limiting, fabricated battery voltage, or fake traction control.

Do not revert to old GPIO `18/19/22/23`, GPIO-controlled EN on `21/25`, Huge APP, the 921600-baud upload recommendation, or the old 200 Hz firmware. The rejected old firmware also had ineffective arming checks, app restart sequence problems, PWM writes in BLE callbacks, reverse-guard bypass, breakaway-floor cap overshoot, and a `getValue()` core 2.x compile issue. Do not revive tracks for this build: pebble jamming, heat exposure, higher turning current, and less speed were the tradeoffs.

Phase 6 only: persistent driver/tuning profiles, per-track saved profiles, logging/CSV, backup phone hot takeover, and dedicated calibration wizard. The original Phase 6 joystick phrase **"properly rotate the…"** was truncated; ask later rather than inventing a new behavior. Settings sliders specified here are approved **in memory** for the prototype.

## 7. External build, bench tests, and handoff

Provide these commands for the owner's Mac or the confirmed separate build environment. Use `flutter create` only to initialize a **fresh** Android/iOS scaffold if one is needed; then merge the delivered files and platform settings before analyzing or building. Replace the default Flutter widget test if it refers to the template app.

```bash
flutter create --platforms=android,ios --no-pub team_wolves_controller
cd team_wolves_controller
# Apply the supplied source, platform configuration, and tests.
flutter pub get
flutter analyze
flutter test
flutter run --release
```

Document Android USB debugging, iOS Xcode signing and permissions, how to join the robot's AP, how to select BLE, and which diagnostics indicate a real link. If verification was run, report the SDK, resolved dependency version, host/target, results and any warnings. If it wasn't run, say so explicitly.

Include unit tests for CRC, frame lengths and signed little-endian fields, malformed telemetry, sequence wrap, mode mapping, shaping and neutral input. Test controller transitions with a fake transport where feasible: stale link, background/resume, transport switch, rejected arm, E-STOP priority, and no automatic re-arm. Those tests do not replace hardware validation.

**Bench prerequisites:** Secure the robot with all wheels clear. Verify Serial startup and no unexpected motion. Confirm the actual E-STOP protocol before relying on the app's stop button. Keep motors unpowered for initial communications tests and use a controlled bench setup for powered checks. Verify stopping paths at low output **before** testing BOOST or driving on the ground.

The original TC-01–TC-09 definitions are not available in full. Use these **PTC** IDs for the reconstructed minimum tests:

| Test | Pass condition |
|---|---|
| PTC-01 Boot twitch | Five power cycles with no phone; wheels remain still. Record any GPIO14 twitch. |
| PTC-02 Direction | At 35% with wheels clear, forward commands both sides forward. Record any inversion needed; app task does not change firmware. |
| PTC-03 Steering | Center throttle and steer right; left moves forward and right moves backward. |
| PTC-04 Link-loss failsafe | At low output, turn Wi-Fi off. Measure time from last accepted DRIVE to stopped output, alongside physical wheel stop. Target is the nominal ~250 ms watchdog; reconnection alone must not restart movement. |
| PTC-05 E-STOP | At low output, press E-STOP while holding throttle. Confirm command receipt, firmware ESTOP state, stopped outputs, and deliberate recovery. |
| PTC-06 Lifecycle stop | Background the app while driving on the bench. DRIVE stops; watchdog trips; resuming does not re-arm. |
| PTC-07 UDP link | Joined to Wolve Bot AP, valid telemetry shows WIFI LIVE, DISARMED, M2 and L/R 0% before arming. RTT appears only after a valid sample. |
| PTC-08 BLE fallback | Manually switch from UDP to BLE. No overlap or auto-arm. Confirm notifications, measured usable rate and low-output control. |
| PTC-09 Race controls | After stop checks pass, test BOOST mode and restoration, pivot zero throttle, and each terrain's shaping. Button release/cancel cannot leave an override active. |

Future field verification: document phone/OS, firmware version and serial output, range/echo RTT/drops at 1 m, 10 m and 50–75 m where safe, link behavior under normal arena congestion, battery runtime, and handling on approved surfaces. Channel 6 or 11 was discussed as a separate firmware tuning option, not authorization to change channel now. Keep unconfirmed hardware facts, fire-section behavior, race rules and battery strategy open until verified.

### Final response to the owner

Deliver the complete source tree, platform configuration, dependencies, tests, and short README. Include:
1. **Quota result:** measured bytes, file count, audit root, and PASS/FAIL; note whether the platform meter was available. Do not state "125 MB exactly."
2. **Verification result:** what was analyzed, tested or built, where it ran, and what is **NOT RUN** or **UNCONFIRMED**. Do not claim zero errors without evidence.
3. **Review checklist:** the bench tests and a way for the owner to mark each console, tuning and connection feature **OKAY / NOT OKAY / NEEDS CHANGE**.
4. **Decisions, open questions, and next step.** After feedback, report the files changed, why, and the exact retest needed. Stay in Phase 4 until the owner reviews the prototype.

Do not trade away completeness to fit the budget. Keep the full controller and its tests; keep reproducible toolchains, caches, and build outputs out of the saved workspace.
