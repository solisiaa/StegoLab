#!/bin/zsh
# Собирает нормальный StegoLab.app, чтобы запускать двойным кликом без Терминала
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP="StegoLab.app/Contents/MacOS"
mkdir -p "$APP"
cp -f .build/release/StegoLab "$APP/StegoLab"
cat > StegoLab.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>StegoLab</string>
    <key>CFBundleIdentifier</key><string>lab.stego</string>
    <key>CFBundleName</key><string>StegoLab</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
echo "OK: StegoLab.app собран. Открываю..."
open StegoLab.app
