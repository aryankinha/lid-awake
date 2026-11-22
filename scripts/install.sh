#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this installer as your logged-in user, not with sudo." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist/LidAwake.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/LidAwake.app"

if [ ! -d "$DIST" ]; then
  "$ROOT/scripts/build.sh"
fi

echo "==> Installing to $DEST (no administrator access needed)"
mkdir -p "$DEST_DIR"
osascript -e 'quit app "LidAwake"' >/dev/null 2>&1 || true
rm -rf "$DEST"
cp -R "$DIST" "$DEST"

echo "==> Installing the user-level safety watchdog"
"$DEST/Contents/Resources/lidawake-ctl" install-watchdog

echo "==> Launching LidAwake"
open "$DEST"

cat <<EOF

LidAwake is installed at:
  $DEST

It uses the private clamshell-only selector by default (no administrator
access). The optional system-wide pmset fallback is not installed.

To remove everything:
  $DEST/Contents/Resources/uninstall.sh
EOF
