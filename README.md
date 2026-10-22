# Codex Micro Tablet

A native Bluetooth HID control surface and Flutter dashboard for an Android tablet beside a Mac. Built from `cmwen/min-android-app-template` and the owner's FNK0104B monitor protocol. Android 9 / API 28 or later is required; the Lenovo Tab M8 TB-8505F runs Android 10 / API 29 and exposes `HidDeviceService`.

This is an unofficial compatibility experiment. It is not an official Codex Micro device or app.

## What works independently

- Six large, stable Micro slot controls, AG00–AG05, with host-supplied lighting.
- Fast / Approve / Reject / Fork (ACT06–09), push-to-talk (ACT10), separate Voice (ACT11), Send (ACT12).
- Four radial directions and neutral release, matching the firmware's normalized angles.
- Explicit HID registration, discoverability, paired-host selection and connection diagnostics.
- Optional Wi-Fi dashboard for five-hour/weekly quota, named bridge threads and explicit text submission using the existing FNK0104B bridge.
- Encrypted bridge token storage backed by Android Keystore; no credentials in source.

## Bluetooth transports

**BLE HID is the default.** The app publishes a HID-over-GATT service (`1812`), Device Information service with USB-source PnP identity `303a:8360` (version `00b0`), and vendor report 6. This matches the owner's ESP32 BLE diagnostic. Android's GATT server supplies these values; no system Bluetooth files are changed and the app does not execute root commands.

**Classic HID remains selectable.** Android's `BluetoothHidDevice` API supplies its own PnP identity, so the earlier Classic connection did not establish Desktop Micro discovery. Switching transport disconnects the current host and clears discovery.

The app distinguishes **HID connected** from **Micro handshake received**. Controls remain disabled until a recognized host discovery/status request arrives. Pairing alone does not prove Desktop accepted this device. BLE also needs encrypted report access, input notification subscription, and an ATT MTU of at least 66 for the 63-byte reports. The Mac must negotiate the MTU; the tablet cannot force it as a peripheral. Native Micro discovery, slot status, mapped actions and voice still require verification on the target Mac.

Hold to talk and Voice send HID gestures to the Mac. They use the **Mac's selected microphone**; this app does not stream the tablet microphone or impersonate a Bluetooth headset. Desktop owns mappings and approvals. Review the target app before using Approve or Send.

## Pair with the Mac

1. Open the tablet app and its connection/setup panel. Select **BLE HID** and tap **Start BLE HID**. Grant Bluetooth permissions or enable Bluetooth when requested.
2. Confirm **BLE advertising: active**. In macOS System Settings → Bluetooth, pair with **Codex Micro Tablet**. Forget a previous Classic tablet pairing if macOS caches it. While BLE runs, the app temporarily sets Android's Bluetooth name to Codex Micro Tablet and restores the previous name when BLE stops.
3. Accept any Android pairing dialog. The Mac initiates BLE; the paired-host Connect button is only used in Classic mode.
4. Open Codex's Micro settings. Look for **Micro discovery: received**, report counters, and host lighting. A link with zero protocol reports is not accepted as working.
5. Test Agent 1, a direction (including release), and a harmless mapped action. Verify voice using the Mac microphone.

For Classic comparison, choose **Classic HID**, Start HID, Make discoverable, then pair with the system tablet name and choose the paired Mac.

Keep the tablet app visible. Leaving the app releases held controls and invalidates Micro state. The screen stays awake while the dashboard is visible. This foreground experiment does not promise background or unattended reconnection.

Official retail setup and mappings: [Codex Micro guide](https://learn.chatgpt.com/docs/features/codex-micro). The guide documents the retail hardware, not this tablet.

## Use the existing Wi-Fi bridge

Run the existing [FNK0104B monitor-server](https://github.com/cmwen/FNK0104B/tree/main/monitor-server) on the Mac in the same environment as its signed-in Codex app-server. Use its existing token and listener if already configured. Otherwise, from that repository:

```sh
MONITOR_HOST=192.168.1.20 MONITOR_PORT=8765 MONITOR_TOKEN='your-local-secret' \
  python3 monitor-server/server.py
```

Use the Mac's actual LAN IP. Allow access on that private network. The tablet and Mac need a mutually reachable network; Bluetooth pairing is independent of this connection. A bridge running in another OS/process may not observe the Mac app's sessions.

In the tablet's bridge settings, enter the origin `http://192.168.1.20:8765` and the same token. Only local IPs, localhost, and `.local` names allow HTTP; remote addresses require HTTPS. Local HTTP is unencrypted on the network, matching the existing bridge. Use a trusted LAN. Tokens are stored encrypted on the tablet and never followed through HTTP redirects.

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
