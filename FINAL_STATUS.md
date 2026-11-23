# LidAwake Final Status

## Deliverables

- App: `~/Downloads/LidAwake/dist/LidAwake.app`
- Installed copy: `~/Applications/LidAwake.app`
- Source: `~/Downloads/LidAwake`
- Delivery zip: `~/Downloads/LidAwake-1.0.0.zip`
- README / architecture / security / test results / checklist / critic reviews are in
  the project root.

## Working / verified

- Native SwiftUI menu bar app, no Dock icon.
- Custom 1024px app icon with 16–1024px `.icns` variants in the bundle.
- Redesigned 344 pt panel: one "Keep this Mac awake" primary module, one grouped
  stop-condition surface, a live power/thermal/lid line, flat notices, and a
  full-width Advanced disclosure.
- Active and external sessions show a read-only summary from the real session
  configuration; automatic stops leave a persistent last-stop explanation.
- External sleep is stated once in the primary module with one Clear action;
  active battery/thermal risk is surfaced before the automatic stop.
- On a normal display the expanded Advanced panel fits all rows without scrolling;
  smaller displays scroll with a visible scrollbar and hint.
- Popover takes key on open for active controls; the pre-show measurement makes the
  first visible frame the final 497 pt collapsed height, and the top edge stays fixed
  through ON/OFF and Advanced content changes. App-level activation is best effort
  on older macOS and is not claimed on macOS 27; focus is restored if the app becomes
  active.
- Apple semantic palette: system accent controls, native label hierarchy, semantic
  green/orange/red status dots and glyphs only, separator hairlines, neutral cards.
- The custom app is installed at `~/Applications/LidAwake.app`; disposable build
  harness binaries were removed and one rollback bundle is retained.
- Measured, screen-capped scrolling with a visible scrollbar and overflow hint.
- Menu bar icon observes a dedicated icon model (fixed frame, no inherited
  animation), so the once-per-second safety refresh cannot make it flicker.
- Separate AppKit diagnostics window; clear/repair/Open-at-Login actions run off
  the main thread with busy states.
- Cmd-Q/quit cleanup respects restore/watchdog failures; system-wide flag loss is
  detected during a system session; wake grace prevents false watchdog stops.
- Clean Quit removes helper, watchdog, lease, logs and support directory; app
  bundle/settings/login preference remain.
- ON/OFF via menu bar, `lidawake://` URL, and `lidawake-ctl`.
- IOKit truth: `SleepDisabled`, `AppleClamshellState`, `AppleClamshellCausesSleep`,
  battery/AC/charging, thermal.
- Default no-admin backend: private clamshell selector 12.
- Revocable `caffeinate -i -w <pid>` idle-sleep helper; watchdog can kill it.
- User LaunchAgent watchdog with lease, boot ID, PID, TTL, stopping intent,
  deadline/battery/thermal enforcement, read-back verification.
- Mismatched heartbeat cannot arm; watchdog-only heartbeat `kind`.
- External `SleepDisabled` is detected and not silently adopted; system fallback
  refuses an existing external flag.
- Trip Mode, battery floor, thermal guard, timer, max 8h cap.
- Launch at login via user LaunchAgent.
- Native notifications.
- Install/uninstall no-admin; optional pmset fallback scripts with exact sudoers
  rule and retrying boot reset.
- 68 unit tests pass (61 core + 7 app).
- Monitor integration test (ioreg/pmset) passes.
- CLI 20-toggle/no-unintended-settings test passes.
- App and CLI SIGKILL recovery pass; caffeinate helper disappears; watchdog clears.
- Timer test passes.
- **Physical selector test passes** (21 closed-lid `causesSleep=No` samples).
- **Physical background workload continuity passes** (672 ticks, no >1s gap).
- **Physical Trip Mode passes** (`DISARM reason=lidOpened` on reopen).
- Uninstall while armed removes app, both agents, support files, and helper; external
  flag is reported, not silently changed.
- No root artifacts on the default path: `/etc/sudoers.d` empty, no `.bootreset`
  LaunchDaemon, no PrivilegedHelperTool, no setuid files.

## Current environment note

At final verification the Mac was unlocked, `SleepDisabled 0`, lid open, no active
lease, and the watchdog running. A pre-click sampler proved the first visible frame
was the final 497 pt collapsed height, and Advanced produced one 497→617 step with
the top edge fixed at `y=28`. Escape returned focus to the previous app. The panel
was left closed with no session. The dark popover captures are in `docs/`; light
mode uses the same semantic system tokens. The earlier lock-screen/external-flag
note is historical.
- App bundle is ~1 MB, ad-hoc signed, `codesign --verify --strict` passes.

## Pending manual/hardware evidence

1. **Selector property with lid physically closed: PASS.** 21 closed-lid samples
   showed `causesSleep=No` with `SleepDisabled=0`.
2. **Background CPU workload continuity: PASS.** 672 workload ticks, no gap >1s,
   while the lid was closed.
3. **Trip Mode lid-open disarm: PASS.** Log shows `DISARM reason=lidOpened`.
4. **Real low-battery floor** on battery.
5. **Real thermal-pressure cutoff** under load.
6. Logout/login-window behavior and optional fallback boot reset with admin access.
7. Notification permission/visual test.
8. App UI screenshot/visual inspection while the lid is open.

## Exact physical test

The selector test has already passed. Repeat with:

```sh
# Open the lid and unlock first.
sudo pmset -a disablesleep 0
~/Downloads/LidAwake/scripts/test-lid.sh
```

For Trip Mode:

```sh
~/Downloads/LidAwake/scripts/test-trip.sh
```

Close the lid for ~5 seconds when prompted, reopen, and read the result. If the
Trip Mode script does not log `DISARM reason=lidOpened`, report it.

## Current system state

After the user test: `SleepDisabled 0` (normal sleep restored), lid open, no active
lease, watchdog running, selector off. No administrator-created LidAwake files are
installed.

## Critic scores

Core app review scores improved to an overall **7/10** after round-2 fixes. The
separate polish review (icon, clean quit, minimal UI) reached **8.3/10** in round 3:
icon 8, clean quit 8.5, UI 8.5. No 10 is claimed because a real full-control
screenshot and the remaining battery/thermal/admin physical tests are unavailable.
Full details are in `CRITIC_REVIEWS.md`.
