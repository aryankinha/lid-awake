# LidAwake Security Notes

## Default path (no administrator access)

- The app calls the private IOKit selector `kPMSetClamshellSleepState` (12) on
  `IOPMrootDomain`. There is no entitlement check in the open-source xnu handler,
  and the app runs as the logged-in user.
- No `sudo`, no `sudoers` file, no root daemon, no kernel extension, no SIP change.
- The user LaunchAgent watchdog runs as the user. Its lease and heartbeat files are
  in `~/Library/Application Support/LidAwake` with user-only permissions.
- The watchdog never turns sleep prevention on. It only clears a session whose
  owner stopped renewing the lease.

Residual risk: any process already running as the user can call the same private
selector and keep the lid-close sleep override set. The impact is limited to power
state (awake/asleep), not root code execution.

## Optional fallback (administrator access)

`scripts/install-pmset-fallback.sh` writes exactly:

```sudoers
<user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

- No wildcard, wrapper script or shell. `visudo -cf` validates before install.
- File is `root:wheel 0440`.
- The boot reset script is root-owned `0755`, fixed `/usr/bin/pmset` command,
  no user input and no network.
- The fallback can be removed with `sudo ./scripts/uninstall-pmset-fallback.sh`.

Residual risk: a process running as the user can toggle the system-wide sleep flag.
The worst case is awake/asleep, not root code execution. The default path does not
need this grant.

## Data and privacy

- No telemetry, analytics, accounts or network requests.
- No reading of documents, browser data, or personal files.
- The app reads only power/lid/thermal state and its own session files.
- Diagnostics copied by the user contain power state and file paths only.

## Private API

The clamshell selector is undocumented and may change in a macOS update. The app
detects call failures and exposes the optional `pmset` fallback. Do not use this app
as the only safety mechanism for a machine that must never sleep (for example, a
medical or life-support system). It is a personal laptop utility.

## Reporting

This is a local personal project. If you publish it, include a security contact and
a clear statement of the residual risks above.
