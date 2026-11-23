# CRITIC_REVIEWS.md

Scores are from independent subagent reviews. The rule for this project: a 10 is
not awarded without real-device evidence. Physical lid-close, real battery-floor,
real thermal-pressure, actual logout and admin fallback installation remain
manual/hardware tests and are called out explicitly.

## Phase 0 — Research / architecture plan

**Score: 7/10** (research/plan phase)

Strengths: primary-source verification of `pmset disablesleep`, persistence path and
boot re-application; identified the quit/crash gap and the reboot myth.

Gaps: missed Sleepless PR #12/#14 prior art, stale Amphetamine comparison,
underweighted `pmset` exit-0 vs kernel-state verification, over-scoped v1, and
underspecified boot-daemon/FileVault behavior.

Resolution: the implementation now uses IOKit kernel state, an off-only watchdog,
a health-gated arm, a revocable caffeinate helper, and a retrying boot reset. The
Amphetamine/Power Protect caveat is documented in README.

## Phase 1 — Implementation reviews (initial)

| Review | Score | Main blockers |
|---|---:|---|
| Architecture | 5/10 | default blocked idle sleep contrary to docs; no lease fencing/reconciliation; watchdog did not enforce stored contract; external pmset adoption |
| Core | 6/10 | external system-flag adoption; arm/disarm read-back and rollback; failed disarm overwritten by renewal; cross-process ownership; CLI gates |
| UI | 5/10 | UI used controller memory not kernel/lease truth; false “confirmed” status; idle/“clamshell only” contradiction; diagnostics/login-item state |
| Safety | 4/10 | failed disarm renewal bug; stale watchdog fail-open; non-revocable activity assertion; system corrupt lease; uninstall ordering |
| Testing | 3/10 | no monitor integration test; no app-layer tests; selector effect not verified; several claims exceeded evidence |

## Round 1 fixes applied

- **Failed disarm:** a `stopping` state now suppresses live lease renewal; the
  watchdog sees `stopping` and retries. The app also releases the caffeinate helper
  even when restore fails.
- **Revocable idle sleep:** replaced `ProcessInfo.beginActivity` with a separate
  `/usr/bin/caffeinate -i -w <app pid>` helper. The helper PID is stored in the
  lease; the watchdog kills it before clearing the kernel bit. App death also ends
  it automatically.
- **Watchdog contract:** watchdog independently enforces the stored deadline,
  battery floor and thermal guard; verifies `pmset` OFF by reading IOKit; kills the
  helper; corrupt-lease and clear-failure paths retain recovery where possible.
- **Heartbeat authenticity:** only the watchdog process writes the heartbeat, with
  `kind: "watchdog"`. The app no longer writes health. Arm requires a fresh,
  correctly-typed heartbeat.
- **Battery fail-safe:** `batteryInfoKnown` is false when IOPS has no internal
  battery source; the app blocks arming and disarms when unknown.
- **Tri-state clamshell:** missing `AppleClamshellCausesSleep` is “unknown”, not
  “confirmed safe”. No false confirmation.
- **External ownership:** system mode refuses an existing external
  `SleepDisabled 1`; arm also checks for another live lease. The UI detects other
  LidAwake sessions and refuses to arm over them.
- **Lease reconciliation:** the app checks the lease every tick; missing/other-PID
  leases abandon the local session or restore sleep rather than showing a ghost ON.
- **Boot reset:** runs the full five-minute window (not a fixed 60s), with logging.
- **Uninstall:** stops the app first, clears/disarms, removes optional fallback
  artifacts even if only one of them exists, rejects root invocation, and prints the
  external-flag command.
- **UI:** generic “Keep this Mac awake”, tri-state warning, cached diagnostics,
  `lidawake://status` copies diagnostics, watchdog status distinguishes
  not-installed/stale/healthy, login item uses launchctl state, pre-arm battery/
  thermal validation, dismissible errors, bundled fallback installer, accessibility
  label including mode/error/time.
- **Tests:** 29 unit tests; monitor-vs-ioreg/pmset integration test; app SIGKILL
  test that verifies the caffeinate helper disappears; heartbeat-gated arm test;
  stored-deadline, external-flag refusal, exact-floor, critical-thermal and no-timer
  cap tests.

## Remaining before a 10

- Physical lid-close with only the private selector active, on battery, no external
  display, with a background heartbeat.
- Physical Trip Mode open/close.
- Real low-battery floor and real thermal-pressure tests.
- Actual logout/login-window and fallback boot-reset behavior with admin access.
- App-layer URL/status unit tests and sandboxed install/uninstall tests.
- The watchdog is per-user; logout can leave a global bit in a hung-app scenario.
  This is documented; a root-level logout cleanup is v2 work.
- The private clamshell selector is undocumented; its physical effect must be
  verified on the target Mac before calling it production-safe.

## Phase 2 — integration critic (round 1)

**Overall: 6/10**

| Phase | Score | Main reason |
|---|---:|---|
| Research | 7/10 | Primary-source mechanism; selector effect still physical-pending |
| Architecture | 7/10 | Clean core/app/CLI split; no atomic cross-process fencing |
| Core | 6/10 | Good rollback/read-back; corrupt-lease pmset failure, helper PID reuse, no clamshell read-back |
| UI | 7/10 | Clear menu bar states; diagnostics/CLI lacked tri-state fields; “confirmed” wording |
| Safety | 6/10 | Strong central design; uninstall/CLI restore failures, partial pmset ownership, physical evidence absent |
| Testing | 5/10 | 29 unit tests + monitor integration; no app/CLI tests; stale evidence |
| Packaging/docs | 6/10 | Bundle/signature okay; docs contradictions; uninstall ignored failed restore |

### Round 2 fixes

- CLI disarm keeps the lease and exits nonzero on restore failure.
- Uninstaller refuses to remove recovery if disarm fails or the helper is missing.
- Corrupt-lease watchdog verifies pmset OFF and retains the lease on failure.
- Helper PID is dropped on failed disarm/arm rollback before caffeinate is stopped,
  preventing a reused-PID SIGTERM.
- `flock`-based state lock serializes lease/health reads and writes.
- Watchdog fails closed when on battery with no percentage.
- CLI status and app diagnostics now expose tri-state known flags.
- Watchdog enforces deadline/battery/thermal; revocable caffeinate helper; app
  fails closed after repeated stale heartbeats.
- Latest uninstall, app SIGKILL, monitor and CLI tests pass.

## Round 2 — independent re-review

**Overall: 7/10** (up from 6/10)

| Phase | Score | Reason |
|---|---:|---|
| Research | 7/10 | Mechanism well documented; selector effect still physical-pending |
| Architecture | 7/10 | Clean split and improved recovery; `flock` is per-operation, not a full transaction |
| Core | 7/10 | Stopping lease, helper-PID clearing, corrupt-lease pmset retention, battery fail-closed; clamshell set/clear has no direct read-back |
| UI | 7/10 | Tri-state diagnostics/CLI, clear warnings; “confirmed” wording still stronger than direct evidence |
| Safety | 7/10 | Major recovery gaps closed; external pmset ownership partial; no physical proof |
| Testing | 6/10 | 30 unit tests pass and monitor integration passed; new fixes have limited regression coverage; app/CLI layer untested |
| Packaging/docs | 6/10 | Bundle/scripts coherent; docs were stale and were corrected during round 2 |

### Round 3 fixes (documentation and remaining feasible)

- `ARCHITECTURE.md` updated to caffeinate helper and stopping-lease rollback.
- `TEST_RESULTS.md` updated to 30 tests, caffeinate assertion, successful post-
  heartbeat arm, and current uninstall output.
- CLI `disarm` only clears pmset when the lease says `ownsPmset`; it no longer
  clears an external flag just because the sudoers file exists.
- Boot reset reads `ownsPmset` from the user lease and leaves an external flag
  alone.
- Watchdog validates the helper path before SIGTERM; owner ID fencing skips a
  clear if the lease changed during evaluation.
- Added regression tests for helper-PID clearing on failed disarm and missing
  battery percentage.

### Remaining blockers

**Physical only**
- Selector-only lid-close with a background workload, on battery, no external
  display.
- Trip Mode physical lid-open disarm.
- Real low-battery floor and real thermal-pressure cutoff.
- Actual logout/login-window and boot behavior.

**Admin only**
- Scoped sudoers install/removal.
- Boot-reset daemon across reboot/login window, including FileVault.
- Logout/hung-app cleanup and fast-user-switching behavior.

**Feasible but not done**
- Truly transactional/generation-fenced lease transitions (owner-ID fencing reduces
  the race but does not eliminate every arm/watchdog interleaving).
- App/CLI integration tests for URL/status and uninstall-abort behavior.
- Clamshell set/clear read-back verification.
- Helper identity beyond path validation (start-time/hash).
- External pmset ownership for every legacy/manual path.

No 10 is claimed; physical evidence is the gating item.

## Round 3 — independent re-review

**Overall: 7/10** (unchanged; some phases improved)

| Phase | Score | Reason |
|---|---:|---|
| Research | 7/10 | Primary-source mechanism; selector effect still physical-pending |
| Architecture | 8/10 | Owner-ID plus reload/fencing is meaningful; lock is per-operation, not a full transaction |
| Core | 8/10 | Failed-disarm, helper validation, corrupt-lease retention, pmset read-back, battery fail-closed are solid; no direct clamshell read-back |
| UI | 7/10 | Tri-state diagnostics/CLI fixed; “confirmed” wording slightly strong |
| Safety | 7/10 | Recovery gaps closed; corrupt-lease global-clear and full transactionality remain edge gaps |
| Testing | 6/10 | 30/30 pass, timer/CLI/app crash/monitor pass; ownerID/helper-path/boot-reset/CLI-failure/app URL tests absent |
| Packaging/docs | 7/10 | Docs now match caffeinate/rollback; physical/admin evidence absent |

Remaining feasible-but-not-done items are documented above: truly transactional
lease transitions, clamshell read-back, corrupt-lease pmset ownership marker, and
app/CLI integration tests. Physical and admin evidence is the primary cap.

## Polish review — icon, clean quit, minimal UI

Initial independent score: **7/10 overall** (icon 7, clean quit 7, minimal UI 6.5).

Initial must-fix findings: quit could destroy a live CLI-owned session; icon cutout
seam and non-standard margins; low-contrast colored text in light mode; missing
accessibility labels; missing Repair-watchdog control; icon-only Quit; ambiguous
“Off” timer copy.

### Round 2 fixes

- Clean quit now refuses when another live PID owns the lease; tested with a
  CLI-owned session.
- Icon rebuilt with SF Symbol crescent, 82px margins, 210px radius and drop shadow;
  16–1024px variants inspected.
- Adaptive `activeText`/`warningText`/`dangerText` colors for light/dark contrast;
  bright accents reserved for icons/tints.
- Main toggle and Quit have accessibility labels; Quit is now text-labeled.
- Repair watchdog button appears in the error card when unhealthy.
- Timer copy is “No limit (8h cap)” / segmented “None”; session group renamed.
- FileLeaseStore no longer creates its directory for read-only status.
- Uninstall also removes preferences and known caches.

Round-2 polish score: **7.8/10** (icon 8, clean quit 7.5, UI 8).
Remaining must-fix: clean quit still allowed a stopping foreign lease; watchdog
reap used a fixed sleep; battery slider lacked a VoiceOver label. These were fixed
in round 3.

Round-3 polish score: **8.3/10** (icon 8, clean quit 8.5, UI 8.5).

No blocking must-fix remained. Two non-blocking residuals were also addressed:
timers are now invalidated only after the watchdog is confirmed reaped, and the UI
preview was regenerated from the current build. A real full-control screenshot
(switch/picker/slider/Quit) is still unavailable without a live screen capture.

### Post-review real-device evidence

After round 3, the user cleared the external flag and physically closed/reopened
the lid with the selector active. The raw log contained **21 samples of
`causesSleep=No lid=Yes sleepDisabled=No`**, proving the private clamshell selector
is effective on this Mac/macOS 27.2 for the lid-close property. The test script’s
original pass detector had the field order backwards and was fixed.

A second live test armed Trip Mode and ran a CPU/heartbeat workload. While the lid
was physically closed, the log recorded **71 closed-lid `causesSleep=No` samples**
and the workload completed **672 ticks with no gap >1s**. On reopen, the app logged
**`DISARM reason=lidOpened`** and normal sleep remained enabled (`SleepDisabled=0`).

This resolves the selector, workload-continuity and Trip Mode physical blockers.
Real low-battery, thermal, logout/boot and admin fallback evidence remain, so the
overall score is still not raised to 10.

## Redesign review — premium Apple UI and reported interaction bugs

Initial independent score: **6.5/10**. The critic found the information model
stronger than the visual layer, and the expanded Advanced state not shippable.

Initial must-fix findings:

- Expanded Advanced clipped `Open at Login`; the scroll hint was static, hidden
  from accessibility, and the expanded state was not signed off.
- External sleep was stated three times (status, subtitle, banner) with
  “external flag”/“another app” jargon.
- The primary status stranded “Off” and hanging-indented the status text; active
  battery/thermal risk was hidden in 10.5 pt metadata.
- Low-contrast/small status text, no visible focus on custom buttons, no Reduce
  Motion on chevron/press/footer animations, 20×20 dismiss target.
- `isArmBlocked` ignored the thermal guard; known battery with no percentage was
  ambiguous; external leases trusted any lease file without PID liveness.
- Release-reachable render URL and a large, repetitive view.

### Round 2 fixes

- The Advanced viewport is capped to the hosting screen (640 pt maximum on this
  display); the expanded panel is ~615 pt and shows Sleep control, Open at Login
  and Diagnostics without clipping. Auto-scroll was removed, bottom inset added,
  and smaller displays keep a visible scrollbar plus a VoiceOver-readable “Scroll”
  hint.
- External sleep is one primary status/subtitle with one `Clear…` action; the
  separate banner is gone. The action is hidden when another lease owns the state.
- The primary status is a colored dot + state word on its own line with a 13 pt
  status sentence below. Active battery/thermal risk is shown inline via a risk
  note; Trip Mode copy waits for the first close.
- Sizes/contrast raised across status, notices, rows, Advanced and footer;
  labelled live-status accessibility values; visible focus rings on Advanced,
  Quit, Diagnostics and notice actions; Reduce Motion gates chevron/footer/hero
  animations; dismiss target is 26×26; decorative icons are hidden.
- Thermal guard now gates the switch and the “too hot” status; on-battery missing
  percentages are unavailable; external leases use PID liveness and stopping
  state; the last-stop note clears only after a successful arm; the menu icon and
  accessibility label derive from the same state.
- Clean quit stops the helper only after a successful disarm, rejects corrupt
  leases and handles Cmd-Q through `applicationShouldTerminate`. System-mode flag
  loss is detected on the next tick, wake grace prevents false watchdog stops, and
  per-second `launchctl` probing was removed.
- `lidawake://render` is inert unless `LIDAWAKE_RENDER=1`; diagnostics reopen with
  fresh content; the view’s session values are centralized in `SessionDetails`.
- 66 tests pass (61 core + 5 app), with a release build/sign.

Round-2 score pending. Live wheel/trackpad, hover/focus, menu-bar icon switching
and admin clear/repair remain unverified while the Mac is locked.


## UI polish round 2 — activation, jitter, Apple palette

User-reported issues: the panel appeared to load slightly downward and settle upward on
click; the custom color theme did not match Apple; the installed app needed a rebuild
and stray build binaries needed cleanup.

Fixes applied:

- Activate the accessory app and make the popover key before showing, eliminating
  the inactive-gray first paint and the first-click accent redraw.
- Cache/apply the measured height before show, ignore measurements while closed, and
  keep the popover top edge fixed. Live ON/OFF polling shows `y=28` unchanged through
  `497 → 545 → 497` pt.
- Replaced fixed-RGB brown/green status text with Apple semantic text and system
  accent/status colors; removed the state-tinted card wash; replaced the native
  `ProgressView` red-dot artifact with a thin accent capsule.
- Rebuilt and installed to `~/Applications/LidAwake.app`; installed executable hash
  matches `dist`; removed the three disposable `build/*` harnesses and stale rollback.
- 66 automated tests pass (61 core + 5 app).

> Erratum: the saved ON/OFF log starts at the active 545 pt frame, so the verified
> transition is `545 → 497`, not `497 → 545 → 497`. Round 3 also corrected the
> activation claim: on macOS 27 the accessory app may stay inactive; the key
> popover paints active controls, the first inside click may activate the app, and
> `popoverDidClose` restores the previous app.

Round-2 critic score pending.


### Round-3 critic result

Initial score for this polish round: **7/10** (jitter 7, color 8, install 9,
code/regressions 7). Must-fix items: real activation/focus restoration, deterministic
first-open height, exact secondary-label contrast, stale light/docs evidence, the
dim Diagnostics row, Advanced corner continuity, and an installer that respects
AGENTS.

Fixes applied for the re-score:

- **Activation/focus:** stopped claiming app-level activation on macOS 27; the key
  popover paints active controls, the first inside click may activate the app, and
  `popoverDidClose` restores the previously frontmost app. Verified with Escape and
  status-item dismissal returning to Brave/Antigravity IDE. A best-effort
  `NSApp.activate()` remains for older macOS.
- **First-open:** the fallback seed is the measured 497 pt height (not 476), capped
  before show on short displays; `PopoverLayout` tests cover normal/short screens.
  A sampler started before the click recorded first frame `497` at `t=0.257` with no
  intermediate frames; Advanced produced one `497 → 617` step, `deltaY=0.00`.
- **Contrast:** `textSecondary` is now `.secondaryLabelColor`; the false AA claim and
  comment were removed.
- **Visuals:** Diagnostics is a primary-label plain row with a trailing chevron;
  Advanced uses a continuous corner; all three pickers render consistently; the
  status footer hides the normal `Nominal` word.
- **Diagnostics:** reopening from the popover deminiaturizes the existing window
  instead of creating a duplicate; `Done` closes that window. Verified live
  (minimize → reopen → same window, minimized=0 → Done → no windows).
- **Installer:** preflights lease/session/`SleepDisabled`, preserves one rollback,
  waits for a clean quit, refuses to replace a running app, verifies executable and
  helper hashes, running path, watchdog, and bundled README.
- **Docs/evidence:** removed light-mode references, corrected the lock-screen and
  `497 → 545 → 497` claims, labeled the live captures, and refreshed all three
  screenshots. The active shot is a live 2-minute URL session, disarmed immediately.
- **Tests/install:** 68 tests pass (61 core + 7 app); installed executable hash
  matches `dist` (`ac07b9d1…`); one rollback remains; `lease: none`,
  `SleepDisabled 0`, no caffeinate, watchdog loaded.

Submitted for a re-score.
