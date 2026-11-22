#!/usr/bin/env bash
set -uo pipefail

APP="${LIDAWAKE_APP:-$HOME/Applications/LidAwake.app}"
CTL="$APP/Contents/Resources/lidawake-ctl"
SUPPORT="$HOME/Library/Application Support/LidAwake"
if [ ! -x "$CTL" ]; then
  echo "error: install LidAwake first" >&2
  exit 1
fi

echo "LidAwake clean-quit test"
open 'lidawake://on?minutes=5' >/dev/null 2>&1 || true
sleep 2
if ! "$CTL" status | grep -q 'lease:.*present'; then
  echo "RESULT: FAIL (could not arm)"
  exit 1
fi
echo "  armed; quitting with lidawake://quit"
open 'lidawake://quit' >/dev/null 2>&1 || true
sleep 4

FAIL=0
if pgrep -f '/Applications/LidAwake.app/Contents/MacOS/LidAwake' >/dev/null; then
  echo "  app process still running: FAIL"; FAIL=$((FAIL + 1))
else
  echo "  app process gone: YES"
fi
if pgrep -f 'caffeinate -i -w' >/dev/null; then
  echo "  caffeinate helper still running: FAIL"; FAIL=$((FAIL + 1))
else
  echo "  caffeinate helper gone: YES"
fi
if pgrep -f '/LidAwake/bin/lidawake-ctl watchdog' >/dev/null; then
  echo "  watchdog process still running: FAIL"; FAIL=$((FAIL + 1))
else
  echo "  watchdog process gone: YES"
fi
if [ -f "$HOME/Library/LaunchAgents/com.aryankinha.LidAwake.watchdog.plist" ]; then
  echo "  watchdog plist still present: FAIL"; FAIL=$((FAIL + 1))
else
  echo "  watchdog plist gone: YES"
fi
if [ -e "$SUPPORT" ]; then
  echo "  support directory still present: FAIL"; FAIL=$((FAIL + 1))
else
  echo "  support directory gone: YES"
fi
if [ -d "$APP" ]; then
  echo "  app bundle preserved: YES"
else
  echo "  app bundle missing: FAIL"; FAIL=$((FAIL + 1))
fi
if pmset -g | grep -qi 'SleepDisabled.*1'; then
  echo "  system-wide SleepDisabled still 1: FAIL"; FAIL=$((FAIL + 1))
else
  echo "  normal sleep restored: YES"
fi

# A read-only CLI status must not recreate the support directory.
"$CTL" status >/dev/null 2>&1 || true
if [ -e "$SUPPORT" ]; then
  echo "  CLI status recreated cache: FAIL"; FAIL=$((FAIL + 1))
else
  echo "  CLI status did not recreate cache: YES"
fi

open "$APP" >/dev/null 2>&1 || true
sleep 2
if [ "$FAIL" -eq 0 ]; then
  echo "RESULT: PASS (app relaunched)"
  exit 0
fi
echo "RESULT: FAIL"
exit 1
