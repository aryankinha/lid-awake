#!/usr/bin/env bash
set -euo pipefail

# Optional fallback: lets LidAwake toggle the system-wide SleepDisabled flag
# with a two-command passwordless sudoers rule. Requires administrator access.
# The default clamshell-only path does not need this script.

if [ "$(id -u)" -ne 0 ]; then
  echo "This optional fallback installer must be run with sudo:" >&2
  echo "  sudo $0" >&2
  exit 1
fi

REAL_USER="${SUDO_USER:-$(stat -f%Su /dev/console)}"
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
  echo "Could not resolve the logged-in user." >&2
  exit 1
fi

SUDOERS="/etc/sudoers.d/lidawake-disablesleep"
BOOT_LABEL="com.aryankinha.LidAwake.bootreset"
BOOT_PLIST="/Library/LaunchDaemons/$BOOT_LABEL.plist"
BOOT_SCRIPT="/Library/PrivilegedHelperTools/lidawake-bootreset.sh"

REAL_HOME="$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
REAL_HOME="${REAL_HOME:-/Users/$REAL_USER}"
LEASE_PATH="$REAL_HOME/Library/Application Support/LidAwake/session.json"

echo "Installing the scoped pmset fallback for: $REAL_USER"
echo "Rule: $REAL_USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
echo "Boot reset will clear only a LidAwake-owned pmset session (lease: $LEASE_PATH)"

TMP="$(mktemp)"
printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' "$REAL_USER" > "$TMP"
visudo -cf "$TMP" >/dev/null
install -m 0440 -o root -g wheel "$TMP" "$SUDOERS"
rm -f "$TMP"
visudo -c >/dev/null

echo "Installing boot-time reset (retries until the kernel flag is clear)"
cat > "$BOOT_SCRIPT" <<'SCRIPT'
#!/bin/sh
# Clear a persisted SleepDisabled flag after boot. Run the full five-minute
# window so a late pmconfigd apply cannot slip past a fixed sleep. No user
# input, fixed command only.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
LOG=/var/log/lidawake-bootreset.log
: > "$LOG" 2>/dev/null || true
LEASE_PATH="${LIDAWAKE_LEASE:-}"
i=0
while [ "$i" -lt 20 ]; do
  # Never clear an external user-set flag. Only recover a persisted LidAwake
  # system-mode session (ownsPmset true in its lease).
  if [ -n "$LEASE_PATH" ] && [ -f "$LEASE_PATH" ] &&
     /usr/bin/grep -Eq '"ownsPmset"[[:space:]]*:[[:space:]]*true' "$LEASE_PATH"; then
    if /usr/sbin/ioreg -r -n IOPMrootDomain -d 1 2>/dev/null | /usr/bin/grep -q '"SleepDisabled" = Yes'; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') clearing owned SleepDisabled (iteration $i)" >> "$LOG" 2>/dev/null || true
      /usr/bin/pmset -a disablesleep 0 >> "$LOG" 2>&1 || true
    fi
  fi
  i=$((i + 1))
  /bin/sleep 15
done
exit 0
SCRIPT
chmod 0755 "$BOOT_SCRIPT"
chown root:wheel "$BOOT_SCRIPT"

cat > "$BOOT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BOOT_LABEL</string>
    <key>ProgramArguments</key><array><string>$BOOT_SCRIPT</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>ProcessType</key><string>Background</string>
    <key>EnvironmentVariables</key>
    <dict><key>LIDAWAKE_LEASE</key><string>$LEASE_PATH</string></dict>
</dict>
</plist>
PLIST
chmod 0644 "$BOOT_PLIST"
chown root:wheel "$BOOT_PLIST"

launchctl bootout "system/$BOOT_LABEL" >/dev/null 2>&1 || true
launchctl bootstrap system "$BOOT_PLIST"

echo "✅ Optional pmset fallback installed."
echo "   In LidAwake, choose Mechanism → System-wide (fallback)."
echo "   Remove it with: sudo $(dirname "$0")/uninstall-pmset-fallback.sh"
