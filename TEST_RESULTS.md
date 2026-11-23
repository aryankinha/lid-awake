# LidAwake Test Results

Date: 2026-11-22/23 (IST)
Machine: MacBook Pro `Mac15,3`, Apple M3, 8 GB
OS: macOS 27.2 (26B123)
FileVault: Off
Screen-lock delay at test time: 300 seconds
Initial system state at the start of testing: `SleepDisabled 1` (set outside
LidAwake; later cleared). Final state: `SleepDisabled 0`, no lease, watchdog running.
Final UI verification: live first-open, ON/OFF, Advanced, Diagnostics reuse and
focus-restore tests passed; evidence is in 2c. The earlier lock-screen note is
historical.

Legend: **A** = automated, **S** = simulated in unit tests, **R** = real hardware.

---

## 1. Build, icon and signing — A/R

The app icon is a generated 1024px macOS rounded-square asset, copied into
`Contents/Resources/LidAwake.icns` and referenced by `CFBundleIconFile`. The
16/32/64/128/256/512/1024 variants render legibly; the 64px and 32px previews were
visually inspected. `codesign --verify --strict` passes.

The current panel is captured live from the running `NSPopover` at 2×. The images
are in `docs/`: `ui-dark-collapsed.png`, `ui-dark-active.png` and
`ui-dark-advanced.png` (386 pt including the system popover chrome). They show the
normal off, active and Advanced states. Light mode uses the same semantic system
tokens; a separate light capture was not taken.

## 1b. Build and signing — A/R

```text
$ ./scripts/build.sh
==> Building Swift package (release)
...
==> Assembling app bundle
==> Ad-hoc signing
dist/LidAwake.app: valid on disk
dist/LidAwake.app: satisfies its Designated Requirement
==> Done: .../dist/LidAwake.app
```

`codesign --verify --strict` passes. No third-party dependencies.

---

## 2. Unit tests — A/S

```text
$ swift test
Executed 68 tests, with 0 failures (0 unexpected)
```

The current suite is 68 tests: 61 core (3 lease, 21 session, 27 presentation, 10 watchdog) plus 7 app/popover tests. The original 30 core tests still pass; the additional presentation and safety cases cover
the redesigned copy and state logic: off/on, lid open/closed, system mode with
Trip Mode on, clamshell-block warning, external session, restoring, low battery,
charging exception, thermal pressure, unknown battery, external sleep flag,
watchdog states, persistent last-stop messages, last-stop suppression while active,
external stopping recovery, thermal-guard-off behavior, missing battery percentage,
active battery/thermal risk notes, Trip Mode before/after the first close, unknown
system sleep state, and loss of the system-wide flag during a system session.

Earlier review-driven tests remain: failed-disarm lease stopping, system-mode
external-flag refusal, exact battery floor, thermal `.critical` with guard on,
no-timer 8h cap, watchdog stored-deadline enforcement, corrupt-lease and
clear-failure cases.

Covered:

- arm writes lease before toggling
- system-mode flag verification
- arm failure clears lease
- disarm restores and clears lease
- disarm failure keeps the recovery lease
- timer expiry
- battery floor on battery / not on AC / not while charging
- unreadable battery fails safe
- thermal `.serious`, `.critical`, disabled guard
- Trip Mode waits for close then disarms on open
- Trip Mode does not disarm if the lid never closed
- hard max-duration cap
- lease renewal timestamps
- watchdog fresh/expired/dead-PID/old-boot/corrupt-lease behavior
- watchdog never clears external state with no lease
- file lease round-trip and health round-trip

---

## 2b. Earlier MenuBarExtra redesign — historical

> This section describes the earlier SwiftUI `MenuBarExtra` iteration. The current
> app uses a custom `NSStatusItem` + `NSPopover` (`MenuBarController`); current
> evidence is in 2c below.

Code and static evidence:

- **Scrolling:** the panel has a fixed header/footer and a measured `ScrollView`
  with a finite viewport capped to the hosting screen, `.scrollIndicators(.visible)`,
  and a "Scroll" hint whenever measured content exceeds the viewport. On this
  982 pt display the expanded Advanced panel is ~615 pt and shows all three rows
  without scrolling; smaller displays scroll.
- **Advanced hitbox:** `DisclosureGroup` was replaced with a full-width `Button`
  (44 pt high, `contentShape(Rectangle())`, chevron rotation, expanded/collapsed
  accessibility value). The empty row area is now clickable.
- **Icon flicker:** the `MenuBarExtra` label observes only `MenuBarIconModel`, not
  `AppModel`. The model updates only when the symbol or accessibility label
  changes; the label has a fixed 18×18 frame, monochrome rendering, and no
  inherited animation. The accessibility label no longer contains a per-second
  countdown. Recent `syncMenuIcon()` output is deduplicated.
- **State truth:** active and external sessions show a read-only summary built from
  the real session config; saved defaults are not presented as active settings.
  Thermal guard now gates the switch and status, missing battery percentages are
  unavailable, external leases use PID liveness/stopping state, Trip Mode copy
  waits for the first close, and the last-stop note clears only after a successful
  arm. A system session that loses the global flag is detected on the next tick.
- **Edge cases:** low battery/thermal/external-flag/watchdog states block the switch
  with a plain-language reason; automatic stops leave a persistent last-stop note.
- **Motion/accessibility:** spring-based primary-state and Advanced transitions,
  hover/press states, visible focus rings on the main custom buttons, Reduce Motion
  gating, labelled live status, and labels/values/hints on the main switch,
  battery/timer pickers, toggles, Advanced and Quit. An external sleep warning is
  stated once in the primary module with one Clear action.

Live click/scroll/flicker capture was pending during that earlier iteration; the
current live evidence is in 2c below.

At that time an external `SleepDisabled 1` flag was set, so that iteration showed
the warning and disabled the switch. The current environment has `SleepDisabled 0`;
the warning remains an intentional edge-case path.

## 2c. Popover jitter, key-window paint, and Apple palette — A/R

- **First open:** the controller seeds the screen height synchronously, premeasures
  the SwiftUI fitting size before `popover.show`, and applies the cached/measured
  height before the first visible frame. A sampler was started and printed `READY`
  **before** the status-item click; the first visible frame was already the final
  collapsed height:

  ```text
  READY
  t=0.257 frame=839.0,28.0 386.0x497.0 FIRST
  t=1.565 frame=839.0,28.0 386.0x617.0 deltaY=0.00 deltaH=120.00
  samples=243
  ```

  The first visible frame was already the final collapsed height; expanding Advanced
  produced exactly one step to 617 pt with the top edge fixed. There were no
  intermediate sizes, so the panel does not load low and pull upward. The fallback
  seed is the measured 497 pt collapsed height, capped before show on short displays;
  `PopoverLayout` has tests for both.
- **Key-window paint:** `showPopover` asks for app activation as a best effort (for
  older macOS) and makes the popover window key. On macOS 27 the accessory app stays
  inactive while another app is frontmost, but the key popover already paints the
  active accent controls. The first **inside** click still activates LidAwake; that
  is normal for this accessory app. `popoverDidClose` returns focus to the
  previously frontmost app when the dismissal leaves LidAwake active (verified with
  Escape returning to Brave).
- **Diagnostics reuse:** minimizing `LidAwake Diagnostics` and reopening it from
  Advanced deminiaturized the existing window (`AXMinimized=0`) instead of creating a
  duplicate; `Done` closed it. Verified live via the Accessibility tree.
- **ON/OFF:** the stable logs cover the active-to-off transition at `y = 28`:
  `545 → 497` pt with `deltaY=0.00`; the active-line/footer content accounts for the
  height difference. The earlier `497 → 545 → 497` wording was not supported by the
  log's start time and has been corrected.
- **Palette:** fixed-RGB brown/green text tokens were removed. Text uses native
  label/secondary/tertiary hierarchy; controls use `controlAccentColor`; status
  dots/glyphs use system green/orange/red; hairlines use `separatorColor`; group
  fills are neutral. The active card wash was removed. The status footer hides the
  normal `Nominal` thermal word, leaving e.g. `60% · Battery · Lid open`.
- **Progress:** the native linear `ProgressView` drew a stray red dot at its leading
  edge on macOS 27.2; replaced with a thin accent capsule bar.
- **Evidence:** live 2× captures `docs/ui-dark-collapsed.png` (386×497 pt including
  chrome), `docs/ui-dark-active.png` (386×545) and `docs/ui-dark-advanced.png`
  (386×617); frame logs `/tmp/lidawake-final-open-idle2.log` and
  `/tmp/lidawake-frame-final.log`. The active capture is a live 2-minute
  `lidawake://on` session; it was disarmed with `lidawake://off`, and the final
  status showed `lease: none`, `SleepDisabled 0`, no `caffeinate`, and the watchdog
  still loaded.
- **Install/cleanup:** installed executable hash equals `dist`; the bundled README
  matches the repo; the disposable `build/ui-check`, `build/anchor-check` and
  `build/interaction-check` harnesses and the stale rollback bundle were removed.
  One current rollback bundle is retained.

## 3. CLI status and selector call — A/R

```text
$ lidawake-ctl status
LidAwake status
  sleepDisabled:        true
  lidClosed:            true
  clamshellCausesSleep: true
  power:                AC 80%
  charging:             false
  thermalState:         0
  lease:                none
  watchdogLoaded:       true
```

```text
$ lidawake-ctl probe
before:  sleepDisabled=true lidClosed=true clamshellCausesSleep=true
afterOn: sleepDisabled=true lidClosed=true clamshellCausesSleep=true
afterOff:sleepDisabled=true lidClosed=true clamshellCausesSleep=true
exit=0
```

The private selector call returns `KERN_SUCCESS`. The property is expected to remain
`true` while the lid is already closed and no new clamshell notification is emitted;
the definitive effect needs a physical lid open/close or an actual sleep test.

### Real physical selector test — PASS (R)

The user cleared the external flag and ran `scripts/test-lid.sh` with the lid
physically closed and reopened. The script's original pass detector was checking
the field order backwards; the raw transitions were:

```text
153 causesSleep=No lid=No sleepDisabled=No
 21 causesSleep=No lid=Yes sleepDisabled=No
  6 causesSleep=Yes lid=No sleepDisabled=No
```

`causesSleep=No lid=Yes sleepDisabled=No` appeared **21 times**. That is the
successful case: lid closed, selector active, system-wide `SleepDisabled` off, and
macOS reporting that clamshell close would not sleep. The detector has been fixed
to match that field order. Selector effectiveness is physically verified on this
M3/macOS 27.2.

The test logger itself continued writing **21 samples while the lid was closed**,
so this is also evidence that a process kept running through the closed-lid period.
It was not a heavy agent workload. A separate heavy-workload continuity test remains
pending, as does the Trip Mode open/close test (`scripts/test-trip.sh`).

---

## 3b. Monitor integration — A/R

```text
$ ./scripts/test-monitor.sh
LidAwake monitor integration test
  SleepDisabled vs ioreg: OK (true)
  lidClosed vs ioreg: OK (true)
  onAC vs pmset: OK (true)
  batteryPercent vs pmset: OK (80)
RESULT: PASS
```

This compares the app's IOKit reader with `ioreg` and `pmset` rather than trusting
only the app's own JSON.

## 3c. Revocable idle-sleep helper — A/R

```text
armed:
pid 18355 /usr/bin/caffeinate -i -w 18298
pid 18355(caffeinate): PreventUserIdleSystemSleep ...
Details: caffeinate asserting on behalf of Process ID 18298

after disarm:
none
no caffeinate assertion
```

The helper is a child process, so it can be killed by the watchdog if the GUI
hangs. `-w <app pid>` also makes it exit if the app dies.

## 3d. Physical Trip Mode + live background workload — PASS (R)

With `SleepDisabled=0`, the lid open, and Trip Mode armed via
`lidawake://on?minutes=5&trip=1`, a Python CPU/heartbeat workload ran continuously
while the lid was physically closed and reopened.

```text
lid transitions:
 71  causesSleep=No lid=Yes sleepDisabled=No lease: present
 29  causesSleep=No lid=No  sleepDisabled=No lease: none
126  causesSleep=No lid=No  sleepDisabled=No lease: present

workload ticks: 672
timestamp gaps >1s: none

LidAwake log:
2026-11-22T17:25:15Z ARM mode=clamshell ... trip=true floor=20
2026-11-22T17:27:17Z DISARM reason=lidOpened
```

This proves, on the target M3/macOS 27.2:

1. The selector keeps clamshell sleep disabled while the lid is physically closed.
2. A background CPU workload continued with no timestamp gaps.
3. Trip Mode disarmed on reopening the lid.
4. Normal sleep was left enabled: current `SleepDisabled=0`, lease none.

## 4. Repeated toggling / no unintended settings — A/R

```text
$ ./scripts/test-cli.sh
LidAwake CLI safety test
  toggle failures: 0
  pmset custom settings unchanged: YES
  SleepDisabled before:  SleepDisabled		1
  SleepDisabled after:   SleepDisabled		1
  system-wide sleep flag unchanged: YES
RESULT: PASS
```

20 on/off cycles completed without touching `pmset -g custom`.

---

## 5. Crash recovery — A/R

### CLI owner killed

```text
$ ./scripts/test-crash-recovery.sh
LidAwake crash-recovery test
  lease created for pid 97683
  killed owner; waiting up to 25s for watchdog
  lease cleared: YES
  watchdog recovery logged: YES
RESULT: PASS
```

### App SIGKILL

```text
armed via app:
  lease deadline: 2026-11-22T14:57:00Z
  app_pid=95771
kill -9 95771
after 23 s:
  lease: none
  watchdogLoaded: true
log:
  2026-11-22T14:52:06Z WATCHDOG cleared reason=owning process 95771 is gone mode=clamshell
```

Recovery occurred ~6 seconds after the last lease renewal.

```text
$ ./scripts/test-app-crash.sh
LidAwake app crash/force-quit test
  app_pid=18298 helper_pid=18478
  lease cleared: YES
  caffeinate helper gone: YES
  watchdog recovery logged: YES
RESULT: PASS
```

The separate `caffeinate` assertion is gone after the GUI is killed; the watchdog
also killed it by PID before clearing the clamshell bit.

---

## 5b. Heartbeat-gated arming — A/R

With the watchdog heartbeat file removed, `lidawake://on` did **not** create a
lease:

```text
--- arm with missing heartbeat ---
  lease:                none
  watchdogLoaded:       true
--- heartbeat restored by watchdog (<7 s) ---
  lease:                none
```

The app now requires a fresh watchdog heartbeat (and a matching watchdog `kind`
in the health file), not merely a loaded LaunchAgent.

After the heartbeat returned, a normal arm succeeded:

```text
--- post-restore arm ---
  lease:                present
  watchdogLoaded:       true
  lease.mode:           clamshell
```

This distinguishes “watchdog not healthy” from “watchdog recovered.”

## 6. Watchdog restart — A/R

```text
old_watchdog_pid=94375
kill -9 94375
new_watchdog_pid=95895
launchctl state = running
heartbeat pid = 95895
```

launchd restarted the watchdog via `KeepAlive`.

---

## 7. Timer — A/R

```text
$ ./scripts/test-timer.sh
LidAwake timer test (1 minute)
  armed with a one-minute deadline
  lease cleared: YES
  timer disarm logged: YES
RESULT: PASS

log:
2026-11-22T14:48:36Z ARM ... deadline=14:49:36Z
2026-11-22T14:49:37Z DISARM reason=timer
```

---

## 8. Launch at login — A/R

```text
$ lidawake-ctl install-login .../LidAwake.app
login item installed
launchctl path = ~/Library/LaunchAgents/com.aryankinha.LidAwake.login.plist
state = running
program = /usr/bin/open
$ lidawake-ctl uninstall-login
login item removed
```

---

## 9. Install / uninstall — A/R

```text
$ ./scripts/install.sh
Installing to ~/Applications/LidAwake.app (no administrator access needed)
Installing the user-level safety watchdog
Launching LidAwake
```

An earlier uninstall test was run while a session was armed and an external flag was present:

```text
$ ~/Applications/LidAwake.app/Contents/Resources/uninstall.sh
LidAwake uninstaller
==> Stopping LidAwake
==> Clearing owned sleep state
==> Removing login item and watchdog launch agents
==> Removing app
==> Removing local support files
Current system no-sleep state: SleepDisabled 1
```

Verification after uninstall:

```text
app_removed
watchdog_removed
support_removed
helper_gone
SleepDisabled 1
```

At that time the external `SleepDisabled 1` was intentionally left alone and the
uninstaller printed the exact command to clear it. This is correct ownership
behavior, not an uninstall failure. The uninstaller now stops the GUI before
removing the watchdog and removes the optional boot daemon/script even if only one
fallback file exists. The current environment was re-checked after the final
install: `SleepDisabled 0`, no lease.

---

## 9b. Clean Quit — PASS (R)

```text
$ ./scripts/test-clean-quit.sh
LidAwake clean-quit test
  armed; quitting with lidawake://quit
  app process gone: YES
  caffeinate helper gone: YES
  watchdog process gone: YES
  watchdog plist gone: YES
  support directory gone: YES
  app bundle preserved: YES
  normal sleep restored: YES
  CLI status did not recreate cache: YES
RESULT: PASS (app relaunched)
```

This also verifies that a read-only `lidawake-ctl status` does not recreate the
support directory after a clean quit. Relaunching the app reinstalls the watchdog.

### Foreign-session quit guard — PASS (R)

```text
$ ./scripts/... external guard test
cli_pid=48175
--- status before app quit ---
  lease: present
  lease.mode: clamshell
--- app quit attempt ---
app_still_running=YES
  lease: present
--- kill CLI, watchdog clears ---
  lease: none
  watchdogLoaded: true
--- second app quit ---
app_after_second_quit=GONE
support=gone
```

Saved log: `/tmp/lidawake-external-cli.log`.

A clean quit cannot destroy a live CLI-owned session or its watchdog. It refuses with
an error until the foreign session ends.

## 10. Permission failure — A/R

```text
$ lidawake-ctl arm --mode system --minutes 1
error: The scoped pmset permission is not installed.
exit=1

$ lidawake-ctl status
sleepDisabled: true
lease: none
```

No lease was left behind, and the external flag was not touched.

---

## 11. Battery and thermal — S, real pending

The battery and thermal guards are covered by unit tests with injected snapshots.
Real battery-floor and real thermal-pressure tests require unplugging/draining or
inducing thermal pressure and were not performed unattended.

The live battery reader was corrected to capture percentage while on AC:

```text
before fix: power: AC n/a
after fix:  power: AC 80%
```

The thermal reader uses `ProcessInfo.thermalState`; `pmset -g therm` produced only
"No thermal warning level has been recorded" on this machine and was not used.

---

## 12. Background assertion / energy — A/R

`pmset -g assertions` shows the separate helper while armed:

```text
PreventUserIdleSystemSleep named: "caffeinate command-line tool"
Details: caffeinate asserting on behalf of Process ID 18298
```

The helper is terminated on disarm and killed by the watchdog after a GUI crash.
The app uses IOKit reads rather than shelling
out every second; the watchdog sleeps 5 seconds between checks.

---

## 13. Physical tests still required

Current state after the user test: `SleepDisabled 0`, lid open, no lease, normal
sleep restored. These remaining checks cannot be claimed from unit tests:

1. **Selector property with lid physically closed: PASS** (21 closed-lid
   `causesSleep=No` samples, `SleepDisabled=No`).
2. **Background CPU workload continuity: PASS** (672 ticks, no gap >1s).
3. **Lid-open Trip Mode: PASS** (`DISARM reason=lidOpened`).
4. **Real low-battery cutoff** on battery.
5. **Real thermal cutoff** under load.
6. **Reboot/login-window** behavior for the optional `pmset` fallback (requires admin).

The system is now at `SleepDisabled 0` (normal sleep restored), lid open, no lease.
The next physical test should run a heartbeat/background process with the lid closed
and then verify the process continued and Trip Mode disarmed on open.

### Exact manual sequence

```sh
# 1. Open the lid and unlock the Mac.
sudo pmset -a disablesleep 0          # remove the external flag

# 2. Run the interactive selector test. It arms LidAwake for 3 minutes,
#    asks you to close the lid for ~5 seconds, then reopen it.
~/Downloads/LidAwake/scripts/test-lid.sh

# 3. For Trip Mode, use the app UI: arm with Trip Mode, close the lid,
#    reopen. The app should show OFF and write DISARM reason=lidOpened.

# 4. Restoration check:
pmset -g | grep -i SleepDisabled      # should be absent/0 after OFF
```

If the test prints no `lid=Yes causesSleep=No` sample, the private selector is
not effective on this Mac/macOS. Use the optional `pmset` fallback and re-test.
The physical result must be recorded here before claiming production readiness.
