#!/bin/bash
# Package Shelly as a self-contained macOS app bundle

set -e

APP_NAME="Shelly"
BUNDLE_ID="com.shelly.app"
VERSION="1.0.0"

cd "$(dirname "$0")"
PROJECT_DIR="$(dirname "$(pwd)")"

echo "Building Shelly Manager..."
swift build -c release

echo "Building shellyd daemon..."
cd "$PROJECT_DIR/shellyd"
swift build -c release

echo "Building ShellyPairingUI..."
cd "$PROJECT_DIR/ShellyPairingUI"
bash bundle.sh

cd "$PROJECT_DIR/ShellyInstaller"

# Create app bundle structure
APP_DIR="$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy main executable
cp .build/release/ShellyInstaller "$APP_DIR/Contents/MacOS/$APP_NAME"

# Bundle shellyd daemon
cp "$PROJECT_DIR/shellyd/.build/release/shellyd" "$APP_DIR/Contents/Resources/shellyd"

# Bundle ShellyPairingUI.app
cp -R "$PROJECT_DIR/ShellyPairingUI/ShellyPairingUI.app" "$APP_DIR/Contents/Resources/"

echo "Bundled shellyd and ShellyPairingUI.app into Resources"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

echo "✅ Created: $APP_DIR"
echo ""
echo ""
echo "To use on another Mac:"
echo "  Just copy '$APP_NAME.app' - everything is bundled inside!"
echo ""
echo "Or create a DMG for distribution:"
echo "   hdiutil create -volname 'Shelly' -srcfolder '$APP_DIR' -ov -format UDZO Shelly.dmg"
