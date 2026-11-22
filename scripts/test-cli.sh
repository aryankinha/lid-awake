#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="${1:-$ROOT/dist/LidAwake.app/Contents/Resources/lidawake-ctl}"
if [ ! -x "$CTL" ]; then
  echo "error: build the app first: $ROOT/scripts/build.sh" >&2
  exit 1
fi

BEFORE=$(mktemp)
AFTER=$(mktemp)
LIVE_BEFORE=$(mktemp)
LIVE_AFTER=$(mktemp)
trap 'rm -f "$BEFORE" "$AFTER" "$LIVE_BEFORE" "$LIVE_AFTER"' EXIT

pmset -g custom > "$BEFORE"
pmset -g > "$LIVE_BEFORE"

FAIL=0
for _ in $(seq 1 20); do
  "$CTL" clamshell on >/dev/null 2>&1 || FAIL=$((FAIL + 1))
  "$CTL" clamshell off >/dev/null 2>&1 || FAIL=$((FAIL + 1))
done

pmset -g custom > "$AFTER"
pmset -g > "$LIVE_AFTER"

echo "LidAwake CLI safety test"
echo "  toggle failures: $FAIL"
if diff -q "$BEFORE" "$AFTER" >/dev/null; then
  echo "  pmset custom settings unchanged: YES"
else
  echo "  pmset custom settings unchanged: NO"
  diff -u "$BEFORE" "$AFTER" || true
  FAIL=$((FAIL + 1))
fi

BEFORE_FLAG=$(grep -i 'SleepDisabled' "$LIVE_BEFORE" | tr -s ' ' | head -1 || true)
AFTER_FLAG=$(grep -i 'SleepDisabled' "$LIVE_AFTER" | tr -s ' ' | head -1 || true)
echo "  SleepDisabled before: ${BEFORE_FLAG:-absent}"
echo "  SleepDisabled after:  ${AFTER_FLAG:-absent}"
if [ "$BEFORE_FLAG" != "$AFTER_FLAG" ]; then
  echo "  system-wide sleep flag changed: FAIL"
  FAIL=$((FAIL + 1))
else
  echo "  system-wide sleep flag unchanged: YES"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "RESULT: PASS"
  exit 0
fi
echo "RESULT: FAIL"
exit 1
