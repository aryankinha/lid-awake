#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="${1:-$ROOT/dist/LidAwake.app/Contents/Resources/lidawake-ctl}"
LOG="$HOME/Library/Application Support/LidAwake/lidawake.log"
if [ ! -x "$CTL" ]; then
  echo "error: build the app first: $ROOT/scripts/build.sh" >&2
  exit 1
fi

echo "LidAwake crash-recovery test"
open 'lidawake://off' >/dev/null 2>&1 || true
sleep 1
"$CTL" disarm >/dev/null 2>&1 || true

"$CTL" arm --minutes 1 > /tmp/lidawake-crash-test-arm.log 2>&1 &
ARM_PID=$!
sleep 2

if ! "$CTL" status | grep -q 'lease:.*present'; then
  echo "RESULT: FAIL (arm did not create a lease)"
  cat /tmp/lidawake-crash-test-arm.log || true
  kill -9 "$ARM_PID" 2>/dev/null || true
  exit 1
fi
echo "  lease created for pid $ARM_PID"

kill -9 "$ARM_PID" 2>/dev/null || true
wait "$ARM_PID" 2>/dev/null || true
echo "  killed owner; waiting up to 25s for watchdog"
sleep 23

if "$CTL" status | grep -q 'lease:.*none'; then
  echo "  lease cleared: YES"
else
  echo "  lease cleared: NO"
  "$CTL" status
  echo "RESULT: FAIL"
  exit 1
fi

if tail -20 "$LOG" 2>/dev/null | grep -q 'WATCHDOG cleared'; then
  echo "  watchdog recovery logged: YES"
else
  echo "  watchdog recovery logged: NO"
  tail -20 "$LOG" 2>/dev/null || true
  echo "RESULT: FAIL"
  exit 1
fi

echo "RESULT: PASS"
