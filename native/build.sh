#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
APP="build/Kind Mirror.app"
mkdir -p "$APP/Contents/MacOS"
swiftc native/KindMirror.swift -O -o "$APP/Contents/MacOS/KindMirror" -framework Cocoa -framework AVFoundation -framework CoreImage
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KindMirror</string>
<key>CFBundleIdentifier</key><string>local.kindmirror.desktop</string>
<key>CFBundleName</key><string>Kind Mirror</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSCameraUsageDescription</key><string>Show your camera and take a snapshot for a compliment from your local model.</string>
<key>NSCameraUseContinuityCameraDeviceType</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
