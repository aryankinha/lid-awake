#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="LidAwake"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "==> Building Swift package (release)"
swift build -c release --product LidAwake
swift build -c release --product lidawake-ctl

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_BIN="$BIN_DIR/LidAwake"
CTL_BIN="$BIN_DIR/lidawake-ctl"
[ -x "$APP_BIN" ] || { echo "missing $APP_BIN" >&2; exit 1; }
[ -x "$CTL_BIN" ] || { echo "missing $CTL_BIN" >&2; exit 1; }

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$APP_BIN" "$CONTENTS/MacOS/$APP_NAME"
cp "$CTL_BIN" "$CONTENTS/Resources/lidawake-ctl"
chmod +x "$CONTENTS/MacOS/$APP_NAME" "$CONTENTS/Resources/lidawake-ctl"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/LidAwake.icns" "$CONTENTS/Resources/LidAwake.icns"
cp "$ROOT/README.md" "$CONTENTS/Resources/README.md" 2>/dev/null || true
cp "$ROOT/LICENSE" "$CONTENTS/Resources/LICENSE" 2>/dev/null || true
cp "$ROOT/scripts/uninstall.sh" "$CONTENTS/Resources/uninstall.sh" 2>/dev/null || true
cp "$ROOT/scripts/install-pmset-fallback.sh" "$CONTENTS/Resources/install-pmset-fallback.sh" 2>/dev/null || true
cp "$ROOT/scripts/uninstall-pmset-fallback.sh" "$CONTENTS/Resources/uninstall-pmset-fallback.sh" 2>/dev/null || true
chmod +x "$CONTENTS/Resources/uninstall.sh" "$CONTENTS/Resources/install-pmset-fallback.sh" "$CONTENTS/Resources/uninstall-pmset-fallback.sh" 2>/dev/null || true

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "==> Done: $APP"
