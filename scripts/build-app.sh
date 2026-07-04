#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Translate"
BUNDLE_ID="com.mactranslatespikes.translate-app"
CONFIG="release"
APP_DIR="dist/${APP_NAME}.app"

echo "Building translate-app (${CONFIG})..."
swift build -c "${CONFIG}" --product translate-app

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp ".build/${CONFIG}/translate-app" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "app/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Used to convert your speech into text before translating it.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Used to convert your speech into text before translating it.</string>
</dict>
</plist>
PLIST

echo "Code-signing (ad-hoc)..."
codesign --force --deep --sign - "${APP_DIR}"

echo ""
echo "Built ${APP_DIR}"
echo "Run it with: open \"${APP_DIR}\""
echo "Or drag it into /Applications, then use the menu bar item \"Launch at Login\" to start it automatically."
echo ""
echo "The first time you use the microphone/speech-to-text feature, macOS will prompt for"
echo "Microphone and Speech Recognition access — approve both. Translation and clipboard-copy"
echo "need no special permissions at all."
