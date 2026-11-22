#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$HOME/Applications/LidAwake.app"
CTL="$APP/Contents/Resources/lidawake-ctl"
WATCHDOG_PLIST="$HOME/Library/LaunchAgents/com.aryankinha.LidAwake.watchdog.plist"
LOGIN_PLIST="$HOME/Library/LaunchAgents/com.aryankinha.LidAwake.login.plist"
SUPPORT="$HOME/Library/Application Support/LidAwake"
SUDOERS="/etc/sudoers.d/lidawake-disablesleep"
BOOT_PLIST="/Library/LaunchDaemons/com.aryankinha.LidAwake.bootreset.plist"
BOOT_SCRIPT="/Library/PrivilegedHelperTools/lidawake-bootreset.sh"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this uninstaller as your logged-in user, not with sudo." >&2
  echo "It will ask for admin authorization only for the optional fallback." >&2
  exit 1
fi

echo "LidAwake uninstaller"

# Stop the GUI first. If it is hung, pkill ensures the watchdog is the only
# remaining safety layer before we remove it.
echo "==> Stopping LidAwake"
osascript -e 'quit app "LidAwake"' >/dev/null 2>&1 || true
sleep 1
pkill -f "LidAwake.app/Contents/MacOS/LidAwake" 2>/dev/null || true

if [ -x "$CTL" ]; then
  echo "==> Clearing owned sleep state"
  if ! "$CTL" disarm; then
    echo "REFUSING to remove recovery: the restore command failed." >&2
    echo "Keep the watchdog/app installed and fix the error first." >&2
    exit 1
  fi
  if ! "$CTL" uninstall-watchdog >/dev/null 2>&1; then
    echo "REFUSING to remove recovery: watchdog did not exit." >&2
    exit 1
  fi
else
  echo "REFUSING to remove recovery: lidawake-ctl is missing." >&2
  echo "Restore the app or clear the clamshell bit manually, then retry." >&2
  exit 1
fi

echo "==> Removing login item and watchdog launch agents"
launchctl bootout "gui/$(id -u)/com.aryankinha.LidAwake.login" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/com.aryankinha.LidAwake.watchdog" >/dev/null 2>&1 || true
rm -f "$LOGIN_PLIST" "$WATCHDOG_PLIST"

if [ -f "$SUDOERS" ] || [ -f "$BOOT_PLIST" ] || [ -f "$BOOT_SCRIPT" ]; then
  echo "==> Removing optional system-wide fallback (admin required)"
  sudo launchctl bootout "system/com.aryankinha.LidAwake.bootreset" >/dev/null 2>&1 || true
  sudo rm -f "$SUDOERS" "$BOOT_PLIST" "$BOOT_SCRIPT"
  sudo visudo -c >/dev/null 2>&1 && echo "    sudoers still parses cleanly"
  sudo pmset -a disablesleep 0 >/dev/null 2>&1 || true
fi

echo "==> Removing app"
rm -rf "$APP"
if [ -d "/Applications/LidAwake.app" ]; then
  echo "    /Applications/LidAwake.app exists; remove it manually or with sudo."
fi

echo "==> Removing local support files and preferences"
rm -rf "$SUPPORT"
rm -rf "$HOME/Library/Caches/com.aryankinha.LidAwake"
rm -rf "$HOME/Library/Saved Application State/com.aryankinha.LidAwake.savedState"
defaults delete com.aryankinha.LidAwake >/dev/null 2>&1 || true

echo "==> Current system no-sleep state"
pmset -g | grep -i SleepDisabled || echo "    SleepDisabled is not set (normal sleep)."

cat <<EOF

LidAwake has been removed.

If the line above says "SleepDisabled 1", a system-wide flag is still set
outside LidAwake. Restore normal sleep with:

  sudo pmset -a disablesleep 0
EOF
