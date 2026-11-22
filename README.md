# LidAwake

A native macOS menu bar app that keeps a MacBook awake while its lid is closed,
so background agents, builds, downloads and scripts can keep running.

**Built and tested on:** MacBook Pro `Mac15,3` (Apple M3), macOS 27.2 (26B123).
**Default backend:** Apple's private clamshell-sleep selector — **no administrator
access, no sudoers rule, no persistent disk flag.**
**Fallback:** `pmset -a disablesleep` through a two-command scoped sudoers rule.

---

## What it does

- One-click ON/OFF from the menu bar.
- Live status read from IOKit, not from a cached app state.
- **Trip Mode:** turns itself off when you reopen the lid.
- Battery floor: defaults to 20%, configurable 10–50%.
- Thermal protection: turns off at `ProcessInfo.thermalState == .serious` or `.critical`.
- Timer: 1h, 2h, 4h, or the 8-hour maximum; every session is capped at 8 hours.
- Crash protection: an independent user LaunchAgent watchdog clears the override
  if the app quits, crashes or is force-quit.
- Launch at login via a user LaunchAgent.
- Notifications for arm/disarm and safety shutdowns.
- Clean Quit: disarms, stops the helper, removes the watchdog, lease, heartbeat,
  logs and support directory. The app bundle, preferences and an intentionally
  enabled Launch at login setting remain.
- Menu bar only; no Dock icon.
- Optional system-wide `pmset` fallback, installed separately with explicit admin
  approval.

LidAwake does **not** change `sleep`, `displaysleep`, `standby`, `hibernatemode`,
SIP, kernel extensions, or any unrelated power setting.

---

## Interface

The panel is deliberately small and has one primary control:

- **Keep this Mac awake** — a single switch with a plain-language status line.
  It explains when the app is armed, running with the lid closed, blocked by an
  external flag, below the battery limit, too hot, restoring sleep, or managed by
  another session.
- **When to stop** — one grouped surface with four native rows: Turn off after,
  Stop at battery, Stop if the Mac runs hot, and Turn off when I reopen the lid.
  While a session is active, the same rows become an accurate read-only summary
  of that session's real configuration.
- **Live system line** — power/battery, thermal state and lid state, in one quiet
  line rather than a row of chips.
- **Advanced** — sleep control, Open at Login, and a separate Diagnostics window.
  The whole row is a 44 pt hit target; the chevron is not the only clickable part.
- **Flat notices** — one warning or error at a time, with a single action. Safety
  failures cannot be dismissed; routine messages can.
- **Last stop** — an automatic battery, thermal, timer, lid or watchdog stop stays
  explained in the primary module until the next session starts.

The panel uses one system material, one primary surface, one grouped settings
surface, and native controls. An external sleep flag is stated once in the primary
module with one Clear action, not repeated in a banner. Active battery/thermal risk
is shown inline before the session stops. Status colours adapt to light and dark
appearances.
The content is measured and capped to the visible screen. On a normal display the
expanded Advanced panel fits all three rows without scrolling; smaller displays
scroll with a visible scrollbar and a "Scroll" hint.
The menu bar label observes a separate icon model and uses a fixed 18×18 frame, so
the once-per-second safety refresh cannot make the sun/moon icon flicker.

Screenshots (offscreen AppKit capture, 2×; the warning state shows an external
system sleep flag and the intentionally disabled switch):

- `docs/ui-dark-collapsed.png`, `docs/ui-dark-advanced.png`
- `docs/ui-light-collapsed.png`, `docs/ui-light-advanced.png`

---

## How it works

```text
SwiftUI MenuBarExtra app
  ├─ SessionController ── IOKit selector 12 (default, no root)
  ├─ caffeinate -i -w PID ─ revocable idle-sleep helper
  ├─ SystemMonitor ───── IOKit: SleepDisabled, clamshell, battery
  ├─ Session lease ───── ~/Library/Application Support/LidAwake/session.json
  └─ User LaunchAgent watchdog
        └─ clears only LidAwake-owned state after a stale/dead lease
```

### Default: clamshell-only selector

The app calls the private IOKit selector `kPMSetClamshellSleepState` (12) on
`IOPMrootDomain`. It sets the `kClamshellSleepDisablePowerd` bit, which suppresses
**lid-close sleep**. While a session is armed, the app also starts a separate,
revocable `/usr/bin/caffeinate -i -w <app pid>` helper so idle sleep does not stop
the agent. The watchdog can kill that helper by PID if the app hangs. Low-battery
and thermal sleep are not overridden.

It is undocumented/private. The app verifies the call succeeds and always keeps the
`pmset` fallback available. It does not survive a reboot (the kernel bit resets).

### Fallback: system-wide `pmset`

If the selector is unsuitable on a machine, install the optional fallback:

```sh
sudo ./scripts/install-pmset-fallback.sh
```

That creates exactly:

```sudoers
<you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

and a boot-time reset LaunchDaemon that retries until the kernel flag is clear.
The fallback is optional; the default path requires no admin access.

---

## Requirements

- macOS 13 or later (tested on macOS 27.2).
- Apple Silicon MacBook (tested on M3). Intel builds are source-build only and untested.
- Xcode / Command Line Tools with Swift 5.9+ (Swift 6.4.2 used here).
- No third-party dependencies.

---

## Build and install

```sh
cd ~/Downloads/LidAwake
./scripts/build.sh
./scripts/install.sh
```

`install.sh` installs to `~/Applications/LidAwake.app`, installs the user LaunchAgent
watchdog, and launches the app. It does **not** use `sudo` and does **not** modify
system-wide sleep settings.

Open the menu bar icon to:

1. Turn LidAwake ON.
2. Optionally choose a timer and Trip Mode.
3. Close the lid.

The first launch shows any existing `SleepDisabled 1` as **external**. LidAwake does
not silently take ownership of a flag set by another tool. Use the warning card to
clear it with admin approval if you want LidAwake to own the state.

---

## Usage

| Control | Meaning |
|---|---|
| Toggle | Arm/disarm a sleep session |
| Mechanism | Lid-close + idle (default, no admin) or system-wide manual fallback |
| Auto-off | 1h/2h/4h/8h/off; hard cap 8h |
| Trip Mode | Disarm after the lid has closed and then reopened |
| Battery floor | On battery, disarm when percentage reaches the floor |
| Thermal protection | Disarm at `.serious`/`.critical` thermal pressure |
| Launch at login | Start LidAwake automatically at login |
| Diagnostics | Copy live state, lease and watchdog health |

### Automation

The app registers the `lidawake://` URL scheme:

```sh
open 'lidawake://on?minutes=120&trip=1'
open 'lidawake://off'
open 'lidawake://toggle'
# status copies the diagnostics JSON to the clipboard
open 'lidawake://status'
```

A command-line tool is included inside the app bundle:

```sh
"/Users/you/Applications/LidAwake.app/Contents/Resources/lidawake-ctl" status
"/Users/you/Applications/LidAwake.app/Contents/Resources/lidawake-ctl" status --json
"/Users/you/Applications/LidAwake.app/Contents/Resources/lidawake-ctl" arm --minutes 120 --trip
"/Users/you/Applications/LidAwake.app/Contents/Resources/lidawake-ctl" disarm
```

`arm` holds the session in the foreground and exits when the timer/battery/thermal/
Trip Mode condition fires. It requires the watchdog to be installed.

---

## Safety behavior

- **Watchdog:** the app renews a lease every 5 seconds; the watchdog checks every
  5 seconds and clears a session after 20 seconds of no renewal, or immediately if
  the owner PID is gone. It also enforces the stored deadline, battery floor and
  thermal guard independently.
- **Never enables:** the watchdog only clears; it never turns sleep prevention on.
  It also kills the revocable caffeinate helper before clearing the kernel bit.
- **No lease, no clearing:** an external `SleepDisabled 1` is left alone.
- **Battery fail-safe:** if battery state cannot be read at all, the app disarms
  rather than assuming AC/100%. Arming is blocked when battery state is unknown.
- **Thermal:** uses `ProcessInfo.thermalState`; `pmset -g therm` was not useful on
  this machine.
- **Unreadable/corrupt lease:** the watchdog clears the clamshell override rather
  than leaving it on.
- **Uninstall:** clears the override, removes both LaunchAgents and the app, and
  reports any remaining system-wide flag.

### Heat and theft warning

A closed Mac in a bag is a **heat and battery risk**. LidAwake can enforce a battery
floor, a thermal cutoff and a timer, but it cannot add airflow. Use a hard,
ventilated surface; avoid heavy sustained CPU/GPU work in a closed bag.

When `disablesleep`/clamshell sleep is blocked, the display still turns off, but the
screen may remain unlocked for the configured delay. On this Mac the delay was 300
seconds and FileVault was off. Set **Require password immediately** and lock before
leaving.

---

## Quit behavior

A normal Quit (menu bar power button or `lidawake://quit`) disarms first. If the
restore command fails, it refuses to quit and leaves the watchdog in place.

On a successful quit it removes:

- the `caffeinate` helper
- the watchdog process and its LaunchAgent
- `session.json`, `watchdog-health.json`, `lidawake.log`
- the `~/Library/Application Support/LidAwake` directory

It preserves the app bundle, `UserDefaults`, and an explicitly enabled Launch at
login item. A force-quit cannot run cleanup; the watchdog remains and clears the
lease, then stays available until the app is reopened or uninstalled.

## Testing

Automated:

```sh
swift test
./scripts/test-monitor.sh
./scripts/test-cli.sh
./scripts/test-crash-recovery.sh
./scripts/test-app-crash.sh
./scripts/test-timer.sh
./scripts/test-lid.sh   # interactive: close/reopen the lid when prompted
./scripts/test-trip.sh  # interactive: Trip Mode close/open disarm
./scripts/test-clean-quit.sh
```

See `TEST_RESULTS.md` for the exact outputs and which tests are automated, simulated
or physical.

Physical lid-close/reopen testing is a manual step because the lid is hardware.
The selector passed a real lid-close test on this Mac (21 closed-lid
`causesSleep=No` samples with `SleepDisabled=0`). A live CPU workload continued
with no timestamp gaps while the lid was closed (672 ticks), and Trip Mode disarmed
on reopen (`DISARM reason=lidOpened`). Real battery/thermal cutoffs and admin/boot
behavior are still pending; see `TEST_RESULTS.md`.

---

## Troubleshooting

**Menu bar icon is missing.** The app is menu-bar-only. Check `pgrep -fl LidAwake`.
If macOS 27 hides it in the menu bar overflow, use `lidawake://status` or the CLI.

**"Watchdog starting" or "not running".** Open Diagnostics, then click **Repair
watchdog**. Check:

```sh
launchctl print "gui/$(id -u)/com.aryankinha.LidAwake.watchdog"
tail -20 "$HOME/Library/Application Support/LidAwake/lidawake.log"
```

**System-wide no-sleep is ON (external).** Another tool or a manual `pmset` command
set `SleepDisabled 1`. LidAwake shows it rather than hiding it. Clear it from the
warning card (admin approval) or:

```sh
sudo pmset -a disablesleep 0
```

**The Mac slept with the lid closed.** Check Diagnostics: if
`clamshellCausesSleep` is `Yes` while LidAwake is active, the private selector did
not take effect on this Mac/macOS. Use the optional `pmset` fallback.

**App was deleted while ON.** The copied watchdog remains in
`~/Library/Application Support/LidAwake/bin/` and will clear a stale lease. Run the
uninstaller if available, or remove the LaunchAgents manually.

---

## Uninstall

```sh
~/Applications/LidAwake.app/Contents/Resources/uninstall.sh
```

It:

1. Clears the clamshell override.
2. Removes the watchdog and login LaunchAgents.
3. Removes the app and local support files.
4. Removes the optional sudoers rule and boot-reset daemon if installed.
5. Prints the current `SleepDisabled` state.

If it prints `SleepDisabled 1`, the flag was set outside LidAwake. Restore normal
sleep with:

```sh
sudo pmset -a disablesleep 0
```

To remove the optional fallback separately:

```sh
sudo ./scripts/uninstall-pmset-fallback.sh
```

---

## Project layout

```text
LidAwake/
├── Package.swift
├── Sources/
│   ├── LidAwakeCore/       # IOKit, session, watchdog, presentation, installers
│   ├── LidAwakeApp/        # SwiftUI menu bar app + design system
│   └── LidAwakeCtl/        # CLI helper/watchdog
├── Tests/                  # XCTest unit tests (58)
├── Resources/              # Info.plist + LidAwake.icns
├── scripts/                # build, icon, install, uninstall, tests
├── docs/                   # UI screenshots (light/dark, collapsed/advanced)
├── dist/LidAwake.app       # built app
├── ARCHITECTURE.md
├── CHECKLIST.md
├── TEST_RESULTS.md
├── CRITIC_REVIEWS.md
├── SECURITY.md
├── FINAL_STATUS.md
└── README.md
```

---

## Known limitations

- The clamshell selector is private/undocumented; Apple can change it. The fallback
  exists for that reason.
- The private selector disables clamshell sleep only; the display still sleeps.
- No iOS companion, no web dashboard, no telemetry.
- Ad-hoc signed for local use; distribution would need Developer ID + notarization.
- App Store distribution is not possible with root/privileged sleep control.
- The selector property passed a real lid-close test on this Mac; background
  workload continuity, Trip Mode, real thermal/battery-floor tests and admin/boot
  behavior are documented separately in `TEST_RESULTS.md`.
- Multiple keep-awake tools must not run at once; they can fight over the same
  kernel state.
- With FileVault enabled, the optional fallback's boot-reset LaunchDaemon may not
  run until the Data volume is unlocked; it cannot cover the pre-login window. The
  default clamshell selector resets on reboot and does not need a boot daemon.
- The watchdog is a per-user LaunchAgent. A logout or forced logout removes it;
  the app normally clears on termination, but a hung app can leave the kernel state
  until the next login/boot. This is a single-user tool; do not use it with
  fast-user-switching sessions that both try to own the global state.
- The Amphetamine comparison in early research is intentionally not used as a
  build-vs-buy decision here; its current closed-display mode and Power Protect
  behavior should be tested on the target Mac if you choose that route.
