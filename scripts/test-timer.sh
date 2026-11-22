#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="${1:-$ROOT/dist/LidAwake.app/Contents/Resources/lidawake-ctl}"
LOG="$HOME/Library/Application Support/LidAwake/lidawake.log"
if [ ! -x "$CTL" ]; then
  echo "error: build the app first: $ROOT/scripts/build.sh" >&2
  exit 1
fi

echo "LidAwake timer test (1 minute)"
open 'lidawake://off' >/dev/null 2>&1 || true
sleep 1
open 'lidawake://on?minutes=1' >/dev/null 2>&1 || true
sleep 3

if ! "$CTL" status | grep -q 'lease:.*present'; then
  echo "RESULT: FAIL (lease not present after URL arm)"
  exit 1
fi
echo "  armed with a one-minute deadline"
sleep 65

if "$CTL" status | grep -q 'lease:.*none'; then
  echo "  lease cleared: YES"
else
  echo "  lease cleared: NO"
  "$CTL" status
  echo "RESULT: FAIL"
  exit 1
fi

if tail -15 "$LOG" 2>/dev/null | grep -Eq 'DISARM reason=timer|stored deadline expired'; then
  echo "  timer disarm logged: YES"
else
  echo "  timer disarm logged: NO"
  tail -15 "$LOG" 2>/dev/null || true
  echo "RESULT: FAIL"
  exit 1
fi

echo "RESULT: PASS"
