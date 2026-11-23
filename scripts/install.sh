#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this installer as your logged-in user without sudo." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist/LidAwake.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/LidAwake.app"
SUPPORT="$HOME/Library/Application Support/LidAwake"
CTL="$DEST/Contents/Resources/lidawake-ctl"

check_idle() {
  if [ -e "$SUPPORT/session.json" ]; then
    echo "A LidAwake session is active or restoring sleep. Wait for it to end before installing." >&2
    exit 1
  fi

  # Some Macs omit this line entirely when normal sleep is enabled.
  POWER_SETTINGS="$(/usr/bin/pmset -g)"
  if printf '%s\n' "$POWER_SETTINGS" | awk '$1 == "SleepDisabled" && $2 != "0" { found=1 } END { exit !found }'; then
    echo "System-wide sleep is disabled. Restore normal sleep before installing." >&2
    exit 1
  fi
}

check_idle
"$ROOT/scripts/build.sh" "$@"

echo "==> Preparing the signed app"
mkdir -p "$DEST_DIR" "$ROOT/build"
STAGE="$(mktemp -d "$DEST_DIR/.lidawake-update.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$DIST" "$STAGE/LidAwake.app"
codesign --verify --strict "$STAGE/LidAwake.app"

echo "==> Quitting the running copy"
check_idle
swift -module-cache-path "$ROOT/.build/install-module-cache" -e '
import AppKit
let paths = Set(CommandLine.arguments.dropFirst())
for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.aryankinha.LidAwake") {
    guard let path = app.bundleURL?.path, paths.contains(path), app.terminate() else { exit(1) }
    let deadline = Date().addingTimeInterval(8)
    while !app.isTerminated && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard app.isTerminated else { exit(1) }
}
' "$DIST" "$DEST" || {
  echo "LidAwake did not quit cleanly. Quit it from the menu bar and try again." >&2
  exit 1
}
check_idle

echo "==> Installing to $DEST"
BACKUP=""
if [ -e "$DEST" ]; then
  BACKUP="$(mktemp -d "$ROOT/build/installed-backup.XXXXXX")/LidAwake.app"
  mv "$DEST" "$BACKUP"
  printf 'Previous app saved at %s\n' "$BACKUP"
fi
if ! mv "$STAGE/LidAwake.app" "$DEST"; then
  if [ -n "$BACKUP" ]; then mv "$BACKUP" "$DEST"; fi
  exit 1
fi

echo "==> Starting LidAwake and its safety helper"
codesign --verify --strict "$DEST"
"$CTL" install-watchdog
open "$DEST"

echo "==> Verifying the installation"
cmp "$DIST/Contents/MacOS/LidAwake" "$DEST/Contents/MacOS/LidAwake"
cmp "$CTL" "$SUPPORT/bin/lidawake-ctl"
cmp "$ROOT/README.md" "$DEST/Contents/Resources/README.md"
for attempt in {1..20}; do
  if ps -axo command | awk -v path="$DEST/Contents/MacOS/LidAwake" '$0 == path { found=1 } END { exit !found }' &&
     "$CTL" status | awk '$1 == "watchdogLoaded:" && $2 == "true" { found=1 } END { exit !found }' &&
     [ -s "$SUPPORT/watchdog-health.json" ]; then
    echo "LidAwake is installed and running from $DEST"
    exit 0
  fi
  sleep 0.5
done

echo "LidAwake or its safety helper did not start. The previous app is available at the backup path printed above." >&2
exit 1
