#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=PerfectC.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/PerfectC"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.ashf.perfect-c</string>
  <key>CFBundleName</key><string>PerfectC</string>
  <key>CFBundleExecutable</key><string>PerfectC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Listens for someone singing a perfect C.</string>
</dict></plist>
PLIST
# Ad-hoc sign so macOS ties the mic permission to this bundle.
codesign --force -s - "$APP"
echo "Built $APP. Run: open $APP"
