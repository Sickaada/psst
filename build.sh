#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64 --product AlienPing
swift build -c release --arch x86_64 --product AlienPing
APP="${APP_OUTPUT:-../Psst.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/arm64-apple-macosx/release/AlienPing .build/x86_64-apple-macosx/release/AlienPing -output "$APP/Contents/MacOS/AlienPing"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/mascots.json "$APP/Contents/Resources/mascots.json"
python3 scripts/copy_resources.py "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Psst</string>
<key>CFBundleDisplayName</key><string>Psst</string>
<key>CFBundleIdentifier</key><string>local.alienping.mac</string>
<key>CFBundleExecutable</key><string>AlienPing</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.7.0</string>
<key>CFBundleVersion</key><string>15</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 scripts/sign_app.py "$APP"
printf 'Built %s\n' "$APP"
