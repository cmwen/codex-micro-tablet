# Agent Control read-only display

The native standalone monitor follows the shared navy/cyan/violet live/ambient
references using the existing Codex monitor bridge. The large count is scoped to
visible bridge chats. Attention stays prominent while other chats run. Stale and
unavailable observations are labelled; empty results do not imply all desktop agents
are idle. A quiet clock appears for fresh visible chats with no running/attention or
unknown states; otherwise the clock is accompanied by an explicit activity warning.

Codex 5-hour and weekly cards emphasize remaining quota, including matching progress
bars and accessible remaining-value labels. Reset countdowns/exact local times stay
available. Missing readings have no progress fill. The legacy bridge input supplies no
verified OpenRouter account balance or T3 usage; those cards are omitted rather than
filled with sample data. The web dashboard supports those independent sources.

The clock uses local time and updates while foregrounded. Pixel-shift and clock timers
pause with the app and are disposed when leaving the display. Settings and Exit remain
above the scrollable content. Landscape control mode retains HID controls and its
monitor layout; the standalone monitor is available in both orientations.

Existing HID connections, mappings, approvals, host microphone gestures, bridge
credentials, native provisioning and transport behavior are unchanged. Ambient denotes
an idle UI, with BLE transport work deferred. A generated local horizon raster is
bundled with the app, not downloaded at runtime. No new dashboard network/auth path is
introduced. Formatting/analyzer/widget tests and debug build evidence are recorded in
the workspace candidate report; physical tablet acceptance remains separate.


Standalone display permits the platform's portrait and landscape orientations after
loading its saved mode, including on cold start. Returning to the controller restores
its landscape policy. This distinction is checked at the app navigation/platform
boundary, rather than inferred from portrait-only widget layout tests. Device evidence
and APK identity are recorded separately from this behavior description.
