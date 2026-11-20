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

## Monitor sources and LAN discovery

The monitor reads one of two separate read-only contracts. They are never mixed, and
each has its own endpoint and validating parser:

- **FNK0104B bridge** — `GET /v1/status` with the shared `X-Monitor-Key`. Enter the
  address manually: the bridge advertises no DNS-SD record. This source also carries
  the explicit follow-up prompt path (`POST /v1/commands/text`), which stays on the
  bridge only.
- **Agent Deck (LAN)** — `GET /api/snapshot` over the HTTPS origin the service publishes
  in its DNS-SD TXT record. It is read-only and carries no key, so prompt delivery and
  approvals are unavailable while it is active. Codex quota, Codex and T3 Code entries
  and source health are normalized into the same monitor model; unsupported values stay
  explicit rather than being filled in.

`Monitor source` offers a bounded DNS-SD browse (`_http._tcp`, one shot, foreground
only, never in the background). Results are untrusted endpoint candidates: the instance
name, host and port identify nothing, a service without a public HTTPS origin is shown
as unsupported, and nothing is saved until the user picks a candidate and that origin
answers the Agent Deck contract over verified TLS. No credential is ever sent to a
discovered name, and the bridge key is never stored for a read-only source. Manual
entry remains the fallback when nothing is advertised, which is also the only way to
reach the bridge contract.

A browser tab cannot browse DNS-SD; this discovery is native and applies to the
installed app only. Choosing either source changes display data only; HID transport,
mappings, approvals and host microphone gestures keep their existing behavior. The
ambient clock is compact (local hour/minute beside a short date) so quota and source
detail keep the available height.


When Agent Deck receives a desktop companion feed, its sessions appear under Codex
through the same HTTPS snapshot. Standalone mode shows running sessions from a
fresh partial snapshot with the source warning, including when another harness is
unavailable. Only the visible sessions contribute to the displayed running count.
