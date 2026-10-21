# Implementation and validation

## Scope

Flutter dashboard and native Android Classic Bluetooth HID adapter, package `com.cmwen.codex_micro_tablet`, API 28+. This app is independent of the template, Personal Data Bridge and Personal Health Vault repositories. Work was implemented in workspace Run `R-20261021121825-46255e39` and must be reviewed and integrated through `ws`.

The owner-provided reference is https://cmwen.dev/FNK0104B/monitor/. Firmware source inspected at commit `deeaa281a7d842a78c07d18732ee266a6469667c`. Its BLE implementation is a diagnostic, while its normal monitor uses USB Micro and BLE settings. Android Classic HID is a third transport; identical application reports do not establish Desktop transport/identity acceptance.

## Protocol

- Vendor usage page `0xff00`, report ID 6, 63-byte input/output/feature bodies.
- Body prefix `[2, payloadLength]`, up to 61 bytes of JSON per fragment, CRLF after each outgoing message.
- Bounded balanced-object decoding, UTF-8 decoded after reassembly, escaped quotes/braces, malformed-report recovery and fragment timeout.
- `device.status` / `sys.version` replies; actual Android battery and charging state; layer 1, profile 0.
- Six `v.oai.thstatus` lighting slots; preserve slot position rather than equating it with a named bridge thread.
- `v.oai.rgbcfg`, `lights.preview`, `host.focused_app` compatibility acknowledgments; no desktop remapping API is claimed.
- Keys `AG00`–`AG05` use `v.oai.hid` with `act` 1/0 and `ag` index; commands `ACT06`–`ACT12` use the same method.
- Directions use `v.oai.rad`: up .75, down .25, right 0, left .5; distance 1 on press and angle/distance 0 on release.
- Controls require a physical link, HID registration and a valid Micro discovery/status exchange. Pairing alone does not unlock them.

## Lifecycle and privacy

Registration begins only after the user chooses Start HID. Android owns Bluetooth visibility and pairing dialogs. Leaving the activity releases held keys, clears discovery and discards host lighting. Output callbacks use a connection generation to prevent old queued work from reaching a new host. Pending JSON fragments complete before key releases; failure disconnects rather than leaving a held key active. The dashboard keeps the screen awake while visible.

Bridge tokens are AES/GCM encrypted using a non-exportable Android Keystore key, with ciphertext/IV in private preferences; app backups are disabled. No tablet microphone permission is requested. HID voice gestures operate the Mac's selected microphone. The bridge uses the existing shared-key protocol; HTTP on a trusted private LAN remains unencrypted in transit. HTTPS is required for remote origins. HTTP redirects are not followed. Bridge responses are bounded and validated, and failed snapshots clear live data. Changing the bridge invalidates in-flight results. Text submissions are explicit and never retried automatically.

A disappeared bridge thread remains an unavailable selected destination; it is never silently replaced by a new chat. The user must choose another destination before sending.

## Automated validation

Completed checks: `flutter analyze --no-pub` clean; all **20 Flutter tests passed**; `bash scripts/check-hid-protocol.sh` passed; `flutter build apk --debug --no-pub` succeeded; `git diff --check` passed. HTTP contract tests use a deterministic transport; live bridge connectivity is still a hardware/network acceptance check.

Reproduce checks:

```sh
flutter analyze
flutter test
bash scripts/check-hid-protocol.sh
flutter build apk --debug
```

The Dart suites cover responsive portrait/landscape layouts, HID handshake gating, balanced presses/releases/cancellation, keyboard and pointer behavior, bridge private-origin validation, authenticated status/text request shapes, rejection of redirects, invalid responses, and no automatic submission retries. Native wire checks cover fragmentation, UTF-8, malformed/oversized recovery, all key IDs and directional neutral releases. These tests do not simulate macOS Bluetooth SDP discovery or Desktop HID filtering.

## Device evidence and open acceptance

Read-only ADB inspection on the actual Lenovo TB-8505F confirmed Android 10 / SDK29, Bluetooth enabled, and `Profile: HidDeviceService`. Physical screen: 800×1280 at density240 (approximately 533×853 logical pixels portrait). Multiple ADB devices exist; all mutating tablet commands target serial `HGT6JPD3` explicitly.

On 22 October 2026 (Australia/Sydney), the previously built debug APK installed successfully on Lenovo serial `HGT6JPD3`. Windows retained the USB connection after reconnection; WSL USB/IP reported the device busy. Windows ADB on port 5038 reached it directly, and a non-streamed install completed with `Success` (165,745,260 bytes). No phone was used as a substitute.

The actual dashboard rendered on the tablet in portrait. Opening Set up and choosing Start HID changed the native state to **HID profile: registered** without an app crash. Choosing Make discoverable opened Android's 120-second visibility permission dialog; after allowing it, `dumpsys bluetooth_manager` reported `SCAN_MODE_CONNECTABLE_DISCOVERABLE` and the system name **Lenovo Tab M8**. Screenshots are retained in workspace artifacts. No Mac was paired during this verification, and report counters remained RX0/TX0. The debug cold launch took approximately 15 seconds on this older tablet; automated widget timing is not a device performance measurement.

Mac acceptance is still required: pair the tablet, confirm Desktop sends report-6 discovery, inspect host lighting, test AG00–AG05, command mappings, all four directions and neutral release, push-to-talk/Voice using the Mac microphone, reconnect and foreground/background behavior. Android's public API cannot set the PnP VID/PID expected by a host filter; if the Mac does not initiate discovery, successful Android registration alone cannot resolve that limitation. The Wi-Fi bridge remains independent.
