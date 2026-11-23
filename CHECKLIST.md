# LidAwake Checklist

Status legend: [x] implemented/verified, [~] implemented but not fully verified on
hardware, [ ] not done.

## Core features

- [x] One-click ON/OFF (menu bar app + `lidawake://` + CLI)
- [x] Live status from IOKit (`SleepDisabled`, clamshell, battery, thermal)
- [x] Lid detection
- [x] Trip Mode: implementation + unit tests + physical lid-open test passed
- [~] Battery protection: implementation + simulated tests; real battery-floor run pending
- [~] Thermal protection: implementation + simulated tests; real thermal event pending
- [x] Configurable timer with automatic shutdown (1-minute real test passed)
- [x] Crash protection/watchdog (app and CLI SIGKILL recovery passed; revocable caffeinate helper verified)
- [x] Launch at login (user LaunchAgent install/uninstall tested)
- [~] Notifications (native; permission path implemented, visual permission not yet tested)
- [x] Heartbeat-gated arming and stale-watchdog fail-closed logic
- [x] External/CLI session detection and ownership reconciliation

## Polish / delivery

- [x] Custom app icon (1024px master, 16-1024px variants, `.icns` in bundle)
- [x] Primary-module IA: one "Keep this Mac awake" switch, one grouped stop-condition surface, flat notices, live status line
- [x] Active/external sessions show a read-only summary from the real session config
- [x] External sleep warning stated once in the primary module with one Clear action
- [x] Active battery/thermal risk surfaced before the automatic stop
- [x] Thermal guard respected by the switch/status; missing battery percentage and external lease liveness handled
- [x] Cmd-Q and quit cleanup respect restore/watchdog failures; corrupt leases cancel cleanup
- [x] System-wide flag loss detected during a system session; wake grace avoids false watchdog stops
- [x] Developer render URL inert without `LIDAWAKE_RENDER=1`
- [x] Persistent last-stop explanation for battery, thermal, timer, lid, watchdog and error stops
- [x] Native menu pickers/toggles; Apple semantic text and accent colors
- [x] Full-width Advanced disclosure with `contentShape` and expanded/collapsed accessibility value
- [x] Measured ScrollView with screen cap; Advanced fits on this display and scrolls on shorter displays
- [x] NSStatusItem button observes a separate icon model; template laptop glyph, state-only updates
- [x] Separate AppKit diagnostics window; reuses/deminiaturizes an existing window; async clear/repair/Open-at-Login actions
- [x] Live dark popover captures (collapsed/active/Advanced) in `docs/`
- [x] 68 unit tests pass (61 core + 7 app)
- [x] Pre-click first-open sampler, ON/OFF, Advanced and top-edge frame capture; no session left behind
- [x] Prior polish pass: 8.3/10 (icon 8, clean quit 8.5, UI 8.5)
- [~] Redesign critic score: 7.0 first pass; fixes applied, re-review in progress

## Technology and architecture

- [x] Native Swift + SwiftUI
- [x] Menu bar only, no Dock icon (`LSUIElement`)
- [x] Private clamshell selector investigated; call accepted on this Mac
- [x] Private selector reliability with physical lid close: **PASS** (21 closed-lid
  samples, `causesSleep=No`, `SleepDisabled=No`)
- [x] Background CPU workload continuity: **PASS** (672 ticks, no >1s gap)
- [x] `pmset` fallback with a narrowly scoped two-command sudoers rule (scripts)
- [x] No unrelated power settings changed (custom `pmset` diff passed)
- [x] Lightweight, no third-party dependencies
- [x] Status reflects actual system state (IOKit; external flag warning)
- [x] Complete uninstall script; verified removal of app, watchdog, login item, support files
- [x] Clean Quit removes helper, watchdog, lease, heartbeat, logs and support dir;
  read-only status does not recreate cache
- [x] Optional fallback uninstall script

## Multi-agent development

- [x] Research agent: macOS APIs, sleep behaviour, existing solutions
- [x] Architecture review agent
- [x] Core review agent
- [x] UI review agent
- [x] Safety review agent
- [x] Testing review agent (prior phase)
- [x] Final critic review with score (prior polish: 8.3/10)
- [x] Fix review blockers and re-review (prior phase)
- [x] Redesign discovery: interaction-bug investigator, functional state audit, Apple design direction
- [x] Redesign regression audit
- [x] Popover takes key on show for active controls; app-level activation not claimed; focus restored if app becomes active
- [x] Cached height applied before show; closed-window measurements ignored; top edge fixed
- [x] Apple semantic palette: system accent controls, neutral labels, semantic dots/icons
- [x] Custom thin progress bar removes the native red-dot artifact
- [x] Installed app hash matches dist; disposable harness binaries removed
- [~] Redesign critic score: 7/10; round 3 fixes applied, re-review pending

## Mandatory testing

- [x] ON/OFF and system-state verification (selector call + lease/status; external flag unchanged)
- [x] Physical lid-close selector property (manual test passed)
- [x] Background CPU workload continuity with lid closed (672 ticks, no >1s gap)
- [x] Lid reopening and Trip Mode (`DISARM reason=lidOpened`)
- [~] Battery protection (simulated; real run pending)
- [~] Thermal protection (simulated; real event pending)
- [x] Timer expiration (real 1-minute test)
- [x] App crash and force-quit recovery (SIGKILL test; lease cleared in ~6 s)
- [x] Watchdog restart after SIGKILL
- [x] Login startup wiring (LaunchAgent install/uninstall)
- [x] Permission failure (system fallback without sudoers fails cleanly, no lease)
- [x] Repeated toggling and restoration of normal sleep (20 cycles; custom settings unchanged)
- [x] No unintended system setting changes
- [x] Uninstall while ON restores/clears owned state and removes files
- [ ] Reboot/login-window physical behavior (fallback boot reset script not admin-tested)
- [ ] Real thermal event (documented as simulated)
- [ ] Real low-battery floor (documented as simulated)

## Delivery

- [x] Fully working app bundle in `dist/LidAwake.app`
- [x] Install and usage instructions (README)
- [x] Source code
- [x] Test results/evidence (`TEST_RESULTS.md`)
- [x] Critic scores (`CRITIC_REVIEWS.md`; update as reviews complete)
- [x] Known limitations
- [x] Normal sleep restoration instructions and uninstall

## Open blockers before claiming "finished"

1. Physical lid-close test with the selector active, on battery, no external display,
   with a heartbeat/background workload.
2. Physical lid-open Trip Mode test.
3. Optional fallback admin install/test if the selector is ineffective.
4. Complete independent testing critic and final critic score.
