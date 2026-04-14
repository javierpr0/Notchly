#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="Notchy"
APP_NAME="Notchly"
SCHEME="Notchy"
BUILD_DIR="$PROJECT_DIR/build-release"
DMG_DIR="$BUILD_DIR/dmg"
APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"
VERSION="${1:-$(date +%Y.%m.%d)}"

echo "==> Building $APP_NAME (Release)..."
xcodebuild -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination "generic/platform=macOS" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    2>&1 | tail -5

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build failed — $APP_PATH not found"
    exit 1
fi

echo "==> Re-signing embedded frameworks..."
find "$APP_PATH/Contents/Frameworks" -type f -perm +111 -o -name "*.dylib" | while read -r binary; do
    codesign --force --sign - --timestamp=none "$binary" 2>/dev/null || true
done
find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d | while read -r fw; do
    codesign --force --sign - --deep --timestamp=none "$fw" 2>/dev/null || true
done
find "$APP_PATH/Contents/Frameworks" -name "*.app" -type d | while read -r subapp; do
    codesign --force --sign - --deep --timestamp=none "$subapp" 2>/dev/null || true
done
find "$APP_PATH/Contents/Frameworks" -name "*.xpc" -type d | while read -r xpc; do
    codesign --force --sign - --deep --timestamp=none "$xpc" 2>/dev/null || true
done
codesign --force --sign - --deep --timestamp=none "$APP_PATH"
echo "    Done"

echo "==> Creating DMG..."
rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_DIR"

echo ""
echo "==> DMG created: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "To create a GitHub release:"
echo "  gh release create v$VERSION '$DMG_PATH' --title '$APP_NAME v$VERSION' --notes 'Release $VERSION'"
