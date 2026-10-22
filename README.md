# Codex Micro Tablet

A native Bluetooth and rooted USB HID control surface and Flutter dashboard for an Android tablet beside a Mac. Built from `cmwen/min-android-app-template` and the owner's FNK0104B monitor protocol. Android 9 / API 28 or later is required; the Lenovo Tab M8 TB-8505F runs Android 10 / API 29 and exposes `HidDeviceService`.

This is an unofficial compatibility experiment. It is not an official Codex Micro device or app.

## What works independently

- Six large, stable Micro slot controls, AG00–AG05, with host-supplied lighting.
- Fast / Approve / Reject / Fork (ACT06–09), push-to-talk (ACT10), separate Voice (ACT11), Send (ACT12).
- Four radial directions and neutral release, matching the firmware's normalized angles.
- Explicit HID registration, discoverability, paired-host selection and connection diagnostics.
- Optional Wi-Fi dashboard for five-hour/weekly quota, named bridge threads and explicit text submission using the existing FNK0104B bridge.
- Encrypted bridge token storage backed by Android Keystore; no credentials in source.

## Bluetooth transports

**BLE HID is the default.** The app publishes a HID-over-GATT service (`1812`), Device Information service with USB-source PnP identity `303a:8360` (version `00b0`), and vendor report 6. This matches the owner's ESP32 BLE diagnostic. Android's GATT server supplies these values; no system Bluetooth files are changed and BLE mode does not require root.

**Classic HID remains selectable.** Android's `BluetoothHidDevice` API supplies its own PnP identity, so the earlier Classic connection did not establish Desktop Micro discovery. Switching transport disconnects the current host and clears discovery.

The app distinguishes **HID connected** from **Micro handshake received**. Controls remain disabled until a recognized host discovery/status request arrives. Pairing alone does not prove Desktop accepted this device. BLE also needs encrypted report access, input notification subscription, and an ATT MTU of at least 66 for the 63-byte reports. The Mac must negotiate the MTU; the tablet cannot force it as a peripheral. Native Micro discovery, slot status, mapped actions and voice still require verification on the target Mac.

Hold to talk starts on touch-down and stays active until that finger lifts or the touch is canceled. Finger movement on this button does not scroll the dashboard; swipe elsewhere to scroll. It shows **Hold active** while pressed. Hold to talk and Voice send HID gestures to the Mac. They use the **Mac's selected microphone**. BLE mode supplies no audio; USB mode can expose the tablet microphone as described below. Desktop owns mappings and approvals. Review the target app before using Approve or Send.

## Pair with the Mac

1. Open the tablet app and its connection/setup panel. Select **BLE HID** and tap **Start BLE HID**. Grant Bluetooth permissions or enable Bluetooth when requested.
2. Confirm **BLE advertising: active**. In macOS System Settings → Bluetooth, pair with **Codex Micro Tablet**. Forget a previous Classic tablet pairing if macOS caches it. While BLE runs, the app temporarily sets Android's Bluetooth name to Codex Micro Tablet and restores the previous name when BLE stops.
3. Accept any Android pairing dialog. The Mac initiates BLE; the paired-host Connect button is only used in Classic mode.
4. Open Codex's Micro settings. Look for **Micro discovery: received**, report counters, and host lighting. A link with zero protocol reports is not accepted as working.
5. Test Agent 1, a direction (including release), and a harmless mapped action. Verify voice using the Mac microphone.

For Classic comparison, choose **Classic HID**, Start HID, Make discoverable, then pair with the system tablet name and choose the paired Mac.

Keep the tablet app visible. Leaving the app releases held controls and invalidates Micro state. The screen stays awake while the dashboard is visible. This foreground experiment does not promise background or unattended reconnection.

Official retail setup and mappings: [Codex Micro guide](https://learn.chatgpt.com/docs/features/codex-micro). The guide documents the retail hardware, not this tablet.

## Rooted USB HID and microphone (experimental)

On the rooted stock Lenovo TB-8505F, select **USB + mic** in Connection settings and tap **Start USB HID + microphone**. Allow this app in Magisk and grant Android microphone permission. Connect a data cable to the Mac, open Codex Micro settings, and select **Codex Micro Tablet** in macOS Sound → Input if it appears. No Bluetooth pairing is needed for USB. If microphone startup failed before selecting the Mac input, tap **Enable USB microphone** to retry.

This mode temporarily combines vendor HID report 6, the stock kernel's USB audio-source function, and ADB. USB re-enumerates briefly when starting/restoring; charging continues and USB ADB was verified alongside HID. It requires the existing `hid.gs0`, `audio_source.gs3` and `ffs.adb` functions, not a flashed kernel. USB identity is `303a:8360`, valid BCD version `0100`. Other tablets/firmwares are not supported by this device-specific implementation.

Microphone capture uses the built-in mic at 44.1 kHz, duplicates mono to stereo S16_LE, and sends PCM through a private root process pipe to the USB audio ALSA device. Audio is never saved. Its status and frame counter describe tablet-side capture/writes, not proof that the Mac received sound. **Windows enumerated HID and ADB successfully but rejected the audio interface; Mac microphone and USB Micro acceptance remain pending.** BLE operation was previously confirmed by the owner.

**Release controls / restore USB** is available even while disconnected, both in the header and Connection settings. It releases held controls, stops microphone capture and restores the saved gadget configuration. Leaving the dashboard normally also restores USB. Closing a helper's pipe triggers best-effort cleanup; a hard crash can leave USB changed until the app is reopened and recovers, or manual restore is used. Root-only recovery metadata lives in `/data/local/tmp/codex-micro-usb`; do not remove it while a session or recovery is pending. There is no watchdog, boot service, persistent USB property change, SELinux policy change, or partition flashing. Reopening does not automatically resume microphone capture.

## Use the existing Wi-Fi bridge

Run the existing [FNK0104B monitor-server](https://github.com/cmwen/FNK0104B/tree/main/monitor-server) on the Mac in the same environment as its signed-in Codex app-server. Use its existing token and listener if already configured. Otherwise, from that repository:

```sh
MONITOR_HOST=192.168.1.20 MONITOR_PORT=8765 MONITOR_TOKEN='your-local-secret' \
  python3 monitor-server/server.py
```

Use the Mac's actual LAN IP. Allow access on that private network. The tablet and Mac need a mutually reachable network; Bluetooth pairing is independent of this connection. A bridge running in another OS/process may not observe the Mac app's sessions.

In the tablet's bridge settings, enter the origin `http://192.168.1.20:8765` and the same token. Only local IPs, localhost, and `.local` names allow HTTP; remote addresses require HTTPS. Local HTTP is unencrypted on the network, matching the existing bridge. Use a trusted LAN. Tokens are stored encrypted on the tablet and never followed through HTTP redirects.

The **Codex usage** panel sits above the controls in portrait and landscape. It shows five-hour and weekly percentages used and remaining, with progress bars. Each window shows a reset countdown and the exact reset date/time in the tablet's local timezone. Countdown labels update every 30 seconds. Reset values come from the existing bridge's `codex.usage.five_hour/weekly.resets_at` Unix-second timestamps; no bridge change is required. Unknown values remain unavailable, and an elapsed timestamp says “Awaiting bridge reset update” until the bridge supplies a fresh allowance. The app never assumes that a reset restores a particular percentage.

Use the tune button beside **Codex usage** to enter the same bridge origin and Monitor key as the ESP32. The tablet needs Wi-Fi access to the host; the Mac's loopback address `127.0.0.1` is not reachable from the tablet. Saved keys remain in Android Keystore-backed encrypted storage.

The app reads authenticated `GET /v1/status` every five seconds. Snapshot failures clear the displayed live snapshot; an integration state of degraded/unavailable is not shown as fully connected. It submits explicit `POST /v1/commands/text` with `text`, optional `agent_id`, and a fresh `request_id`, with `X-Monitor-Key` authentication. A queued response confirms acceptance, not task completion. Submissions are never automatically retried; after a timeout check Codex before resending. Named bridge threads are separate from host-owned AG00–AG05 slot assignments.

## Build and validate

Use the installed Flutter 3.38.7 / Dart 3.10.7 toolchain and Java 17:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Install only on the intended tablet when multiple ADB devices exist:

```sh
adb -s HGT6JPD3 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s HGT6JPD3 shell am start -n com.cmwen.codex_micro_tablet/.MainActivity
```

Debug APKs use the Android debug key. Release builds require private signing configured as described in [SIGNING.md](SIGNING.md).

## Verified Lenovo installation

The debug APK was installed and launched on the Lenovo Tab M8 on 22 October 2026. Native HID registration and Android discoverability succeeded. Mac pairing and Desktop Micro discovery/action acceptance remain unverified.

If WSL cannot see the reconnected tablet but Windows owns it, use Windows ADB on a separate server port (5038 was used for verification) rather than forcing USB/IP attachment.

## Protocol and evidence

See [implementation and validation](docs/CODEX_MICRO_TABLET.md) for protocol details and the distinction between automated checks, tablet observations, and Mac acceptance.

Reference source inspected: FNK0104B commit `deeaa281a7d842a78c07d18732ee266a6469667c`, particularly `lib/codex_hid/src/codex_hid/{wire,protocol}.hpp` and `lib/fnk0104b/src/codex_ble.cpp`. No ESP32 binary or hardware-specific GPIO/audio code is used by this app.
