#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="${1:-$ROOT/dist/LidAwake.app/Contents/Resources/lidawake-ctl}"
LOG="$HOME/Library/Application Support/LidAwake/lidawake.log"
if [ ! -x "$CTL" ]; then
  echo "error: build the app first: $ROOT/scripts/build.sh" >&2
  exit 1
fi

echo "LidAwake Trip Mode physical test"
echo "Arming for 3 minutes with Trip Mode ON."
open 'lidawake://off' >/dev/null 2>&1 || true
sleep 1
open 'lidawake://on?minutes=3&trip=1' >/dev/null 2>&1 || true
sleep 2

if ! "$CTL" status | grep -q 'lease:.*present'; then
  echo "Could not arm Trip Mode. Is the app installed and the watchdog running?"
  exit 1
fi

echo "Close the lid for ~5 seconds, then open it again. Waiting up to 30s..."
for _ in $(seq 1 30); do
  sleep 1
  if "$CTL" status | grep -q 'lease:.*none'; then
    if tail -10 "$LOG" 2>/dev/null | grep -q 'DISARM reason=lidOpened'; then
      echo "PASS: Trip Mode disarmed when the lid reopened."
      exit 0
    fi
    echo "Lease cleared, but lidOpened reason not found. Log:"
    tail -10 "$LOG" 2>/dev/null
    exit 1
  fi
done

echo "Timed out; Trip Mode did not disarm. Current status:"
"$CTL" status
tail -10 "$LOG" 2>/dev/null || true
exit 1
