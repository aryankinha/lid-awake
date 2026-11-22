#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${LIDAWAKE_APP:-$HOME/Applications/LidAwake.app}"
CTL="$APP/Contents/Resources/lidawake-ctl"
if [ ! -x "$CTL" ]; then
  APP="$ROOT/dist/LidAwake.app"
  CTL="$APP/Contents/Resources/lidawake-ctl"
fi
if [ ! -x "$CTL" ]; then
  echo "error: install the app first" >&2
  exit 1
fi

echo "LidAwake app crash/force-quit test"
open 'lidawake://off' >/dev/null 2>&1 || true
sleep 1
open 'lidawake://on?minutes=5' >/dev/null 2>&1 || true
sleep 2

if ! "$CTL" status | grep -q 'lease:.*present'; then
  echo "RESULT: FAIL (could not arm via URL)"
  exit 1
fi

APP_PID=$(pgrep -f '/LidAwake.app/Contents/MacOS/LidAwake' | head -1)
HELPER=$(pgrep -f 'caffeinate -i -w' | head -1)
echo "  app_pid=${APP_PID:-none} helper_pid=${HELPER:-none}"
[ -n "$APP_PID" ] || { echo "RESULT: FAIL (app not running)"; exit 1; }

kill -9 "$APP_PID" 2>/dev/null || true
sleep 10

if "$CTL" status | grep -q 'lease:.*none'; then
  echo "  lease cleared: YES"
else
  echo "  lease cleared: NO"
  "$CTL" status
  echo "RESULT: FAIL"
  exit 1
fi
if pgrep -f 'caffeinate -i -w' >/dev/null; then
  echo "  caffeinate helper still alive: FAIL"
  echo "RESULT: FAIL"
  exit 1
fi
echo "  caffeinate helper gone: YES"

if tail -20 "$HOME/Library/Application Support/LidAwake/lidawake.log" 2>/dev/null | grep -q 'WATCHDOG cleared'; then
  echo "  watchdog recovery logged: YES"
else
  echo "  watchdog recovery logged: NO"
  echo "RESULT: FAIL"
  exit 1
fi

open "$APP" >/dev/null 2>&1 || true
sleep 1
echo "RESULT: PASS"
