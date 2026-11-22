#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAIL=0
run() {
  echo
  echo "==> $*"
  "$@" || FAIL=$((FAIL + 1))
}

run swift test
run ./scripts/build.sh
run plutil -lint Resources/Info.plist

for f in scripts/*.sh; do
  bash -n "$f" || FAIL=$((FAIL + 1))
done

codesign --verify --strict "$ROOT/dist/LidAwake.app" || FAIL=$((FAIL + 1))
run ./scripts/test-cli.sh

echo
if [ "$FAIL" -eq 0 ]; then
  echo "VERIFY: PASS"
  exit 0
fi
echo "VERIFY: FAIL ($FAIL failing step(s))"
exit 1
