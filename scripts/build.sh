#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="LidAwake"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

case "${1:-}" in
  "") UNIVERSAL=false ;;
  --universal) UNIVERSAL=true ;;
  *) echo "Usage: $0 [--universal]" >&2; exit 64 ;;
esac

BUILD_ARGS=(-c release)
if "$UNIVERSAL"; then
  echo "==> Building for Apple silicon and Intel"
  BUILD_ARGS+=(--arch arm64 --arch x86_64 --scratch-path "$ROOT/.build/universal-direct")
else
  echo "==> Building Swift package (release)"
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

if "$UNIVERSAL"; then
  for executable in "$BIN_DIR/LidAwake" "$BIN_DIR/lidawake-ctl"; do
    ARCHITECTURES=" $(lipo -archs "$executable") "
    for chip in arm64 x86_64; do
      if [[ "$ARCHITECTURES" != *" $chip "* ]]; then
        echo "Missing $chip in $executable." >&2
        exit 1
      fi
    done
  done
fi

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/LidAwake" "$CONTENTS/MacOS/$APP_NAME"
cp "$BIN_DIR/lidawake-ctl" "$CONTENTS/Resources/lidawake-ctl"
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
codesign --force --sign - "$CONTENTS/Resources/lidawake-ctl"
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "==> Done: $APP"
if "$UNIVERSAL"; then
  ZIP="$DIST/LidAwake-universal.zip"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "==> Archive: $ZIP"
fi
