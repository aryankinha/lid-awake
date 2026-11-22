#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="${1:-$ROOT/dist/LidAwake.app/Contents/Resources/lidawake-ctl}"
if [ ! -x "$CTL" ]; then
  echo "error: build the app first: $ROOT/scripts/build.sh" >&2
  exit 1
fi

echo "LidAwake physical lid test"
echo "This will arm clamshell-only mode for 3 minutes (Trip Mode off)."
echo
echo "1. Open the lid if it is currently closed."
echo "2. When the prompt says ARMED, close the lid for about 5 seconds."
echo "3. Reopen the lid. The logger will record the transitions."
echo
read -r -p "Press Return when the lid is open and you are ready... " _

open 'lidawake://off' >/dev/null 2>&1 || true
sleep 1
open 'lidawake://on?minutes=3&trip=0' >/dev/null 2>&1 || true
sleep 2

if ! "$CTL" status | grep -q 'lease:.*present'; then
  echo "Could not arm LidAwake. Is the app installed and the watchdog running?"
  exit 1
fi

echo "ARMED. Close the lid for ~5 seconds, then open it again."
LOG=$(mktemp)
for _ in $(seq 1 180); do
  ioreg -r -n IOPMrootDomain -d 1 2>/dev/null | awk -F' = ' '
    /"AppleClamshellState"/{gsub(/"/,"",$2); printf "lid=%s ", $2}
    /"AppleClamshellCausesSleep"/{gsub(/"/,"",$2); printf "causesSleep=%s ", $2}
    /"SleepDisabled"/{gsub(/"/,"",$2); printf "sleepDisabled=%s", $2}
  ' >> "$LOG"
  printf '\n' >> "$LOG"
  sleep 0.5
done

open 'lidawake://off' >/dev/null 2>&1 || true
"$CTL" disarm >/dev/null 2>&1 || true

echo
echo "Transitions observed:"
sort "$LOG" | uniq -c
PASS_PATTERN='causesSleep=No lid=Yes sleepDisabled=No'
if grep -q "$PASS_PATTERN" "$LOG"; then
  echo
  echo "PASS: with the lid closed, macOS reported clamshell sleep was disabled"
  echo "      while the system-wide SleepDisabled flag was off."
  rm -f "$LOG"
  exit 0
fi
if grep -q 'causesSleep=No lid=Yes' "$LOG"; then
  echo
  echo "PROPERTY PASS, but SleepDisabled was on during the test."
  echo "The selector property changed, but the physical sleep test is confounded."
  echo "Clear it first with: sudo pmset -a disablesleep 0"
else
  echo
  echo "INCONCLUSIVE/FAIL: no closed-lid 'causesSleep=No' sample was recorded."
  echo "The private selector may not be effective on this Mac/macOS. Use the pmset fallback."
fi
rm -f "$LOG"
exit 1
