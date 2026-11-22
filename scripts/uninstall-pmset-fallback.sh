#!/usr/bin/env bash
set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

SUDOERS="/etc/sudoers.d/lidawake-disablesleep"
BOOT_LABEL="com.aryankinha.LidAwake.bootreset"
BOOT_PLIST="/Library/LaunchDaemons/$BOOT_LABEL.plist"
BOOT_SCRIPT="/Library/PrivilegedHelperTools/lidawake-bootreset.sh"

echo "Removing boot-time reset"
launchctl bootout "system/$BOOT_LABEL" >/dev/null 2>&1 || true
rm -f "$BOOT_PLIST" "$BOOT_SCRIPT"

if [ -f "$SUDOERS" ]; then
  echo "Removing scoped sudoers rule"
  rm -f "$SUDOERS"
  visudo -c >/dev/null && echo "    sudoers parses cleanly"
fi

echo "Restoring normal sleep"
pmset -a disablesleep 0
pmset -g | grep -i SleepDisabled || echo "SleepDisabled is not set (normal sleep)."

echo "✅ Optional pmset fallback removed."
