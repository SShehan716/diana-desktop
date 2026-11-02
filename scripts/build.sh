#!/bin/bash
set -euo pipefail
DIANA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIANA_ROOT"
DIANA_CONFIGURATION="${1:-release}"
if [[ "$DIANA_CONFIGURATION" != "release" && "$DIANA_CONFIGURATION" != "debug" ]]; then
    echo "Usage: scripts/build.sh [release|debug]" >&2
    exit 1
fi
swift build -c "$DIANA_CONFIGURATION"
DIANA_BIN_DIR="$(swift build -c "$DIANA_CONFIGURATION" --show-bin-path)"
mkdir -p "$DIANA_ROOT/build"
DIANA_DESTINATION="$DIANA_ROOT/build/Diana.app"
DIANA_WORK="$(mktemp -d "$DIANA_ROOT/build/.Diana-build-XXXXXX")"
DIANA_APP="$DIANA_WORK/Diana.app"
cleanup() {
    if [[ ! -e "$DIANA_DESTINATION" && -d "$DIANA_WORK/previous.app" ]]; then
        mv "$DIANA_WORK/previous.app" "$DIANA_DESTINATION"
    fi
    rm -rf "$DIANA_WORK"
}
trap cleanup EXIT
mkdir -p "$DIANA_APP/Contents/MacOS" "$DIANA_APP/Contents/Resources/Models"
cp "$DIANA_BIN_DIR/Diana" "$DIANA_APP/Contents/MacOS/Diana"
cp Config/Info.plist "$DIANA_APP/Contents/Info.plist"
cp Sources/DianaApp/Resources/Models/*.usdz "$DIANA_APP/Contents/Resources/Models/"
if [[ -f Config/AppIcon.icns ]]; then
    cp Config/AppIcon.icns "$DIANA_APP/Contents/Resources/AppIcon.icns"
fi
DIANA_IDENTITY="${DIANA_SIGN_IDENTITY:-}"
if [[ -z "$DIANA_IDENTITY" && -f "$DIANA_ROOT/.Codex/signing-identity" ]]; then
    DIANA_IDENTITY="$(cat "$DIANA_ROOT/.Codex/signing-identity")"
fi
codesign --force --sign "${DIANA_IDENTITY:--}" "$DIANA_APP"
codesign --verify --deep --strict "$DIANA_APP"
if [[ -e "$DIANA_DESTINATION" ]]; then
    mv "$DIANA_DESTINATION" "$DIANA_WORK/previous.app"
fi
mv "$DIANA_APP" "$DIANA_DESTINATION"
echo "Built $DIANA_DESTINATION"
