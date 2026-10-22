# Landscape dashboard visual QA

final result: passed

This is a native Android dashboard adaptation of the owner's ESP32 design,
not a pixel-for-pixel clone or a browser prototype.

## Evidence

- Source visual truth: FNK0104B `apps/codex-monitor/preview.png` and
  `apps/codex-monitor/commands-preview.png`, inspected from the owner's checkout.
- Implementation screenshot: `docs/images/landscape-dashboard.png`.
- Implementation viewport: 853 × 533 logical pixels at 1.5 render density,
  producing 1280 × 800 pixels after rounding; system bars are not simulated.
- Source: approximately 4:3 ESP32 preview; implementation: 16:10 tablet.
  No direct pixel-difference score is meaningful across these intentional layouts.
- State: connected USB HID; sample 74% five-hour and 12% weekly quota remaining;
  three bridge chats in running / needs-attention / idle states.
- Both source and implementation were opened together for full-view comparison.
  Quota labels, segmented fills, chat status text, all command/direction labels,
  and microphone subtitle were readable at the preview resolution; a separate
  focused crop was unnecessary for these standard-icon and text regions.
- This is a real Flutter render from a widget test, not an image-generated mock.
  Standard Roboto and Material Icons were loaded from the Flutter SDK for capture.

## Findings and iteration

1. Initial widget layout exposed compact-control vertical clipping. Reduced
   compact vertical padding and increased minimum control heights. Tests then
   passed at 853 × 533 and 1280 × 800.
2. At 740 × 400, the status area left insufficient room for selecting a chat.
   Short windows now scroll the left status pane independently. The test scrolls
   the chat into view, selects it and opens its message composer.
3. The tablet-sized visual capture showed navigation labels clipped below the
   right pane. Corrected the slot-height calculation to reserve command and
   navigation row space. The final capture shows all four direction labels and
   the complete persistent footer. A regression assertion checks a direction
   button is hit-testable at the normal tablet sizes.
4. Header actions did not align to the trailing edge. Replaced the loose flex
   allocation with a right-aligned expanding status label. Final capture shows
   recovery and connection actions at the upper right.

No actionable P0/P1/P2 visual issues remain within the tested viewport/scope.
The partially visible third chat is inside a scrolling live-workspace list.

## Required surfaces

- Typography: Roboto and Material Icons; explicit section hierarchy, readable
  status text, bounded titles. Switching from the ESP32 bitmap font to native
  Android typography is intentional.
- Spacing/layout: two panes, compact quota, separated control grid and persistent
  bottom actions. All primary tablet controls are fully visible in the final
  capture. Short windows scroll rather than shrinking controls below their minima.
- Color/tokens: dark ink/panels, cyan five-hour quota, mint weekly quota, and
  labelled amber attention state preserve the source design language. Status
  meaning is conveyed in text as well as color.
- Asset quality: native Material icons replace the source's tintable bitmap
  icons intentionally. There are no placeholder or generated illustration assets.
- Copy/content: allowance explicitly means remaining quota; bridge selection is
  separate from Desktop slots. Voice says Mac microphone. Unavailable data is
  never shown as healthy or full allowance.

## Interaction validation

43 Flutter tests passed, including landscape layout, chat selection, missing
selected chat while composing, disabled sending to a missing target, touch and
keyboard holds, cancellation, and immediate release on disconnect. Analyzer,
formatting, diff checks and native Micro protocol checks passed. The debug APK
build passed. Existing USB setup and unsupported-audio tests remain covered.

## Remaining acceptance

Physical tablet/Mac acceptance and actual host mappings have not been rerun for
this layout. System keyboard behaviour, large accessibility font sizes, and
long unattended use still need device checks. These are stated beta limits;
this report does not claim hardware or browser verification.
