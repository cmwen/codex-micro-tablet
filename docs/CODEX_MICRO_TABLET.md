# Implementation and validation

## Scope

Flutter dashboard and native Android BLE HID-over-GATT plus Classic Bluetooth HID adapters, package `com.cmwen.codex_micro_tablet`, API 28+. This app is independent of the template, Personal Data Bridge and Personal Health Vault repositories. Work was implemented in workspace Run `R-20261021121825-46255e39` and must be reviewed and integrated through `ws`.

The owner-provided reference is https://cmwen.dev/FNK0104B/monitor/. Firmware source inspected at commit `deeaa281a7d842a78c07d18732ee266a6469667c`. Its BLE implementation is a diagnostic, while its normal monitor uses USB Micro and BLE settings. The app now supports BLE HID-over-GATT with the diagnostic identity and retains Classic HID as a fallback. Identical application reports do not establish Desktop transport/identity acceptance.

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


## BLE transport and rooted tablet follow-up — 22 October 2026

USB ADB verified `su -c id` returns uid=0 on the same stock build. The factory reset removed the earlier app; the BLE build was reinstalled. Root is available for diagnostics, but this implementation uses Android's public GATT server and advertising APIs. No Bluetooth system file, Magisk module, SELinux policy, or partition was modified.

The default transport is BLE HOGP: HID service 1812, HID information 0111/country0/flags1, report map from MicroWire, input/output/feature report 6 and 63-byte bodies. Each report has reference descriptor 2908; input has encrypted CCCD 2902. Device Information 180a publishes PnP characteristic 2a50 with bytes `02 3a 30 60 83 b0 00` (USB-source VID303a/PID8360/version00b0), matching the owner's ESP32 BLE diagnostic. Battery service 180f publishes the capacity sampled at startup. No keyboard or audio report is added.

Service registration is serialized and advertising begins after successful callbacks. Advertising includes HID1812 and a scan response name Codex Micro Tablet. Android's adapter name is temporarily changed while BLE runs and restored on stop. One peer is accepted; report access and CCCD require encryption. Notifications are serialized with bounded timeout, MTU >=66, input subscription, and suspend gating. Unsupported prepared writes are rejected. Offset reads support report-map discovery. Disconnect clears decoder/lighting/held-key state and resumes advertising. A connection with an outstanding notification recreates the GATT server to prevent late callbacks from entering a subsequent connection.

BLE keeps verified discovery across a system pairing dialog if the same connection survives. Releases are queued after partially transmitted messages; failure to finish releases disconnects the peer. Switching transports disconnects and invalidates discovery. The app remains a foreground dashboard, without a background service or root daemon. Final validation passed: Flutter analyzer, all 21 Flutter tests, native MicroWire checks, debug APK build, and diff whitespace checks.

Tablet logs confirmed registration of services 1812, 180a and 180f with status0, followed by successful BLE advertising. End-to-end Mac pairing, PnP enumeration, encrypted report access, negotiated MTU, discovery exchange and actual mapped controls remain hardware acceptance checks until observed. Artifact evidence is kept in the workspace artifact directory, outside this Git repository.


### macOS report framing follow-up

The Mac recognized the tablet but reported connected with limited functionality. Tablet logs confirmed MTU517, encrypted input CCCD subscription, and repeated 64-byte output writes; the original BLE length check rejected these before protocol decoding. The BLE boundary now accepts a 64-byte report only when it carries report ID6 before a 63-byte body, or a zero-padded 63-byte body. Other IDs, nonzero excess data and oversized writes remain rejected. Standard BLE bodies and Classic reports retain their existing format. Native regression checks cover these cases. Header-only diagnostics record the first three bytes without JSON payload logging. End-to-end recovery must be verified after reconnecting the Mac.


## Prominent usage and reset schedule

The existing FNK0104B GET /v1/status contract supplies five-hour and weekly used_percent/resets_at fields. Usage is now a dedicated panel above the control area, with used/remaining percentages, responsive columns, progress, relative countdowns and full local reset dates/times including timezone. The countdown refreshes every30seconds independently of the5second bridge poll. Past resets retain reported usage and show awaiting update. Failed bridge reads already clear the snapshot, preventing old percentages/reset dates from appearing live. Unknown windows are unavailable rather than0percent. A bridge setup button is accessible near the top of the screen; chat submission remains in Live workspace.

Validation: analyzer clean,29Fluttertests passed, debug APK built. New tests cover both windows/exact dates,zero vsunknown,elapsed resets,no-network countdown updates,loss of snapshot and320/533/853width layouts. The existing disabled-control test now scrolls the target into view so its tap assertion remains meaningful after moving usage above controls. Lenovo Wi-Fi is connected; real bridge usage needs the user's URL and shared token.


## Push-to-talk touch ownership

Hold to talk (ACT10) now claims its pointer immediately in a dedicated touch region. Unlike a tap recognizer inside a scroll view, finger drift cannot let scrolling cancel an active microphone hold. The primary finger owns the press until up/cancel; other fingers and periodic dashboard rebuilds do not release it. The card keeps its dimensions and shows Hold active / Release to finish while held. Other controls retain tap/scroll arbitration. This deliberately prevents starting a scroll on the microphone button; swipe elsewhere to scroll.

Real cancellation, readiness loss, app pause or disposal still releases controls. Native keyup is accepted for an already-held key after readiness changes; if its neutral report cannot complete the transport times out/disconnects. Native logs record push-to-talk down/up and lifecycle release reasons without voice or report payloads. No recording audio is captured on the tablet.

Validation: analyzer clean,34Fluttertests passed, native wire checks passed, debug APK built. New tests cover immediate hold and100pixel movement without scrolling/release,secondary pointers,cancellation,20seconds of repeated parent refreshes,readiness loss,and disabled controls. End-to-end Mac dictation stability still requires reconnecting Micro and a physical hold test. The user reported Codex Micro disconnected during troubleshooting; disabled controls are expected until discovery succeeds.

## Rooted USB composite experiment — 22 October 2026

The USB transport is explicitly selected and started by the owner. `UsbRootMain` runs from the installed APK under Magisk and uses configfs `/config/usb_gadget/g1`, configuration `b.1`, controller `musb-hdrc`. It snapshots gadget attributes, function links, controller and temporary USB properties to an atomic root-only recovery file before mutation, preserving `ffs.adb`. An exclusive session lock rejects concurrent helpers. It never changes persistent USB properties, installs a boot service, changes SELinux, or writes partitions.

HID uses the same MicroWire descriptor/report 6, 63-byte bodies and 64-byte USB reports. OUT framing accepts the same optional leading report ID as BLE. USB VID/PID is 303a:8360, but bcdDevice is 0100: the BLE reference version 00b0 is invalid USB BCD and the stock kernel rejects it. Function links must be created with absolute configfs targets. Unbinding uses a newline, not the string `none`. Startup waits at most ten seconds for ADB FunctionFS to settle after disconnect; it does not repair the gadget in the background.

The stock kernel has HID and legacy Android `audio_source` built in; generic configfs UAC1/UAC2 are absent. USB microphone capture runs in the foreground app with RECORD_AUDIO permission. A finite root child loads the packaged JNI adapter and the stock tinyalsa library, opens audio_source playback PCM, and writes stereo S16_LE at 44100 Hz. Mono tablet microphone samples are duplicated into left/right channels. Only status, PID and frame counts return; no audio files or payload logs are created. A session-specific process name guards root-child termination against reused PIDs.

Normal stop, leaving the dashboard, manual restore and reopening with a recovery marker stop capture and restore the original gadget. EOF cleanup is best effort, not a guarantee after a hard kill; there is deliberately no watchdog. ADB authorization remains required. Root must be granted to the application itself, separately from shell root: a denied Magisk app policy caused recovery timeouts until corrected in Magisk's Superuser screen.

Hardware evidence: finite helper runs bound HID + audio_source + ADB, `/dev/hidg0` appeared, `/proc/asound` listed the USB audio-source PCM, Windows enumerated VID303a/PID8360 HID and ADB successfully, and USB ADB remained usable. Helper EOF restored the original VID17ef/PID201c ADB configuration and removed recovery state. The actual app registered/connected its USB HID profile and manual restore succeeded after app root authorization. Windows marked the legacy audio interface with a driver error; opening its PCM succeeds, but writing without a host audio stream fails with an I/O error. Mac USB Micro discovery and audible microphone capture still require physical validation on the target Mac.

Validation for this USB change: `flutter analyze` clean; all 38 Flutter tests passed, including USB selection/status/manual-restore coverage; Dart formatting check and `git diff --check` clean; `scripts/check-hid-protocol.sh` passed; debug APK builds with JNI `-Wall -Wextra -Werror`. The packaged tablet build exercised app root access, USB registration and manual restore. The final diagnostic-only rebuild additionally clears stale restore errors and prefers native PCM errors over EPIPE.
