# LidAwake Architecture

## Goals

- Keep a MacBook awake with the lid closed without changing unrelated power settings.
- Make the menu bar status reflect the real system state.
- Never leave sleep permanently disabled after a crash, force-quit, timer or uninstall.
- Use the least privilege possible: no admin access on the default path.

## Components

```text
┌─────────────────────────────────────────────────────────────┐
│ LidAwake.app (SwiftUI MenuBarExtra, LSUIElement)             │
│                                                             │
│  AppModel (ObservableObject)                                │
│    ├─ SessionController                                     │
│    │    ├─ ClamshellSelector (IOKit selector 12)            │
│    │    └─ PmsetController (optional fallback)              │
│    ├─ IOKitSystemMonitor (truthful state)                   │
│    ├─ FileLeaseStore (session.json + watchdog-health.json)  │
│    ├─ WatchdogInstaller (user LaunchAgent)                  │
│    ├─ LoginItemInstaller (user LaunchAgent)                 │
│    └─ NotificationService                                   │
│                                                             │
│  caffeinate -i -w <app pid> (revocable helper)              │
│    └─ prevents idle sleep; watchdog can kill it by PID      │
└─────────────────────────────────────────────────────────────┘
                         │ lease file
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ lidawake-ctl watchdog (user LaunchAgent, KeepAlive)         │
│  every 5 s:                                                 │
│    - write heartbeat                                        │
│    - read lease                                             │
│    - clear ONLY owned state if PID/deadline/stale/boot bad  │
│    - never enables sleep prevention                         │
└─────────────────────────────────────────────────────────────┘
```

## Why two mechanisms?

| | Clamshell selector (default) | `pmset disablesleep` (fallback) |
|---|---|---|
| Root needed | No | Yes, one scoped sudo rule |
| Scope | Lid-close only | All sleep |
| Idle sleep | Revocable `caffeinate` helper while armed | Blocked |
| Low battery/thermal sleep | Still works | Blocked before OS safeguards |
| Persists across reboot | No (kernel bit resets) | Yes (persistent preference) |
| Boot cleanup | Not needed | Required |
| Private/undocumented | Yes | Yes (not in `man pmset`) |

The private selector is the safer default. It only sets
`kClamshellSleepDisablePowerd`; the OS remains free to sleep for low-battery or
thermal reasons. While a session is armed, a separate revocable `caffeinate -i`
helper prevents idle sleep. The helper is recorded in the lease and killed by the
watchdog on recovery, so a hung GUI cannot hold an unreleasable assertion. The
fallback is available for machines where the selector is unavailable or ineffective.

## Session lifecycle

```text
OFF
 │ user arms / lidawake://on
 ▼
ARMED (lease written, selector set, caffeinate helper launched)
 │
 │ lid closes
 ▼
ACTIVE (clamshell sleep blocked)
 │
 ├─ user turns off ───────────────► OFF
 ├─ timer/deadline ──────────────► OFF
 ├─ battery <= floor ────────────► OFF
 ├─ thermal .serious/.critical ──► OFF
 ├─ Trip Mode: lid reopens ──────► OFF
 ├─ app quit/crash/forced quit ──► watchdog clears
 └─ fallback pmset failure ──────► error; watchdog retries
```

The lease is written **before** the kernel flag is set, so the watchdog always has
an ownership record. If arming fails, the mechanism is rolled back and the lease is
cleared. If rollback itself fails, a `stopping: true` lease is retained so the
watchdog can retry rather than leaving an anonymous awake state.

## Truthful status

`IOKitSystemMonitor` reads:

- `IOPMrootDomain.SleepDisabled` — global pmset flag.
- `IOPMrootDomain.AppleClamshellState` — lid state.
- `IOPMrootDomain.AppleClamshellCausesSleep` — whether clamshell close would sleep.
- `IOPSCopyPowerSourcesInfo` — AC/battery, percentage, charging.
- `ProcessInfo.thermalState` / `isLowPowerModeEnabled`.

No localized `pmset` text is parsed. If `AppleClamshellCausesSleep` is `Yes` while a
clamshell-only session is active and the lid is closed, the UI shows a warning
instead of claiming success.

## Lease and watchdog protocol

`session.json`:

```json
{
  "version": 1,
  "pid": 1234,
  "bootID": "…",
  "mode": "clamshell",
  "startedAt": "…",
  "updatedAt": "…",
  "deadline": "…",
  "tripMode": true,
  "batteryFloor": 20,
  "thermalGuard": true,
  "ownsPmset": false,
  "stopping": false,
  "helperPID": 4567
}
```

- App renews every 5 s.
- Watchdog TTL is 20 s; it checks every 5 s.
- If `pid` is gone, the lease is older than TTL, `stopping` is true, the boot ID
  differs, or the JSON is corrupt, the watchdog clears the owned state.
- The watchdog does not clear an external `SleepDisabled` flag when no lease exists.
- The watchdog itself is relaunched by launchd (`KeepAlive`).

## Privilege model

### Default

None. The app opens `IOPMrootDomain` and calls selector 12. The user LaunchAgent runs
as the user. There is no `sudo`, no `sudoers` file, no root daemon and no boot job.

### Optional fallback

`scripts/install-pmset-fallback.sh` runs as root once and writes:

```sudoers
<user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

It also installs a boot-time reset script that retries until the kernel flag is
clear. The grant cannot be widened to other `pmset` arguments. The script is
idempotent and prints exactly what it installs.

## Timers and energy

- IOKit reads are event/interval-based; the UI refresh is 1 s, lease renewal 5 s.
- The watchdog is a tiny Swift process sleeping 5 s between checks.
- No polling of shell commands.
- A separate `caffeinate -i -w <app pid>` helper prevents idle sleep/App Nap while
  active. It exits automatically if the app dies and is killed by the watchdog if
  the app hangs.

## Failure behavior

| Failure | Behavior |
|---|---|
| App crash/force-quit | Watchdog clears within ~20 s |
| Watchdog crash | launchd restarts; heartbeat updates |
| Corrupt lease | Watchdog clears selector |
| Battery unreadable on battery | App disarms (fail safe) |
| Thermal serious/critical | App disarms |
| External `SleepDisabled 1` | UI warns; app does not claim ownership |
| Selector ineffective | UI warns; user can switch to fallback |
| `pmset` permission missing | Arm fails with a clear error; no lease |
| Uninstall while ON | Uninstaller clears first; then removes files |
| Reboot | Selector resets; fallback boot-reset daemon retries clear |

## Non-goals

- App Store distribution (root/private power control).
- Kernel extensions, SIP changes, hibernation changes.
- Web dashboard or network telemetry.
- Making a closed Mac in a bag thermally safe; the app can only guard and warn.
