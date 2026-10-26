#!/bin/sh
# Builds "INNO X2.app" next to this script.
#   ./build.sh            build the app
#   ./build.sh install    build, copy to /Applications and (re)launch it
#   ./build.sh package    universal (Apple silicon + Intel) build, zipped and as a .dmg in dist/
set -e
cd "$(dirname "$0")"
VERSION="1.1.0"
APP="INNO X2.app"

if [ "$1" = "package" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/InnoX2"
else
  swift build -c release
  BIN=.build/release/InnoX2
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/InnoX2"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>INNO X2</string>
  <key>CFBundleDisplayName</key><string>INNO X2</string>
  <key>CFBundleIdentifier</key><string>com.xaveit.innox2</string>
  <key>CFBundleExecutable</key><string>InnoX2</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"

case "$1" in
  install)
    osascript -e 'quit app "INNO X2"' 2>/dev/null || true
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    open "/Applications/$APP"
    echo "Installed and launched /Applications/$APP"
    ;;
  package)
    mkdir -p dist
    ZIP="dist/INNO-X2-$VERSION-macOS.zip"
    DMG="dist/INNO-X2-$VERSION-macOS.dmg"
    rm -f "$ZIP" "$DMG"
    ditto -c -k --keepParent "$APP" "$ZIP"
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "INNO X2" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Packaged $ZIP and $DMG"
    ;;
esac
