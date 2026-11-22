#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="${1:-$ROOT/dist/LidAwake.app/Contents/Resources/lidawake-ctl}"
if [ ! -x "$CTL" ]; then
  echo "error: build the app first: $ROOT/scripts/build.sh" >&2
  exit 1
fi

JSON=$("$CTL" status --json)
IOPM=$(ioreg -r -n IOPMrootDomain -d 1 2>/dev/null)
I_SLEEP=$(printf '%s\n' "$IOPM" | grep '"SleepDisabled"' | grep -q 'Yes' && echo true || echo false)
I_LID=$(printf '%s\n' "$IOPM" | grep '"AppleClamshellState"' | grep -q 'Yes' && echo true || echo false)
BATT=$(pmset -g batt)
B_PERCENT=$(printf '%s\n' "$BATT" | sed -n 's/.*[[:space:]]\([0-9][0-9]*\)%.*/\1/p' | head -1)
B_POWER=$(printf '%s\n' "$BATT" | grep -q "'AC Power'" && echo true || echo false)

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  $name: OK ($actual)"
  else
    echo "  $name: MISMATCH (expected $expected, got $actual)"
    return 1
  fi
}

FAIL=0
echo "LidAwake monitor integration test"
S_SLEEP=$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["sleepDisabled"]).lower())')
S_LID=$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["lidClosed"]).lower())')
S_POWER=$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["onAC"]).lower())')
S_PERCENT=$(printf '%s' "$JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("batteryPercent",""))')

check "SleepDisabled vs ioreg" "$I_SLEEP" "$S_SLEEP" || FAIL=$((FAIL + 1))
check "lidClosed vs ioreg" "$I_LID" "$S_LID" || FAIL=$((FAIL + 1))
check "onAC vs pmset" "$B_POWER" "$S_POWER" || FAIL=$((FAIL + 1))
if [ -n "$B_PERCENT" ]; then
  check "batteryPercent vs pmset" "$B_PERCENT" "$S_PERCENT" || FAIL=$((FAIL + 1))
else
  echo "  batteryPercent: no battery percentage in pmset output (skipped)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "RESULT: PASS"
  exit 0
fi
echo "RESULT: FAIL"
exit 1
