#!/bin/bash
# Builds build/BMSWidget.app (menu bar app + WidgetKit extension) without Xcode:
# swiftc from the Command Line Tools, a hand-assembled bundle and an ad-hoc signature.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD

# Shared with project.yml so both build paths stay in sync.
yml() { sed -n "s/^ *$1: *\"\{0,1\}\([^\"# ]*\)\"\{0,1\}.*/\1/p" project.yml | head -1; }
BUNDLE_PREFIX=$(yml BUNDLE_PREFIX)
VERSION=$(yml MARKETING_VERSION)
BUILD=$(yml CURRENT_PROJECT_VERSION)
MIN_OS=14.0
SHARED_DIR="/Library/Application Support/BMSWidget/"   # see Shared/SnapshotStore.swift

APP=build/BMSWidget.app
APPEX=$APP/Contents/PlugIns/BMSWidgetExtension.appex
TMP=build/intermediates

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS" "$TMP"

SDK=$(xcrun --show-sdk-path)
SWIFTC=(swiftc -O -wmo -sdk "$SDK" -target "arm64-apple-macos$MIN_OS" -swift-version 5)

# Some Command Line Tools installs keep a stale usr/include/swift/module.modulemap next to
# bridging.modulemap; both define SwiftBridging and break every import. Hide the stale one.
CLT_SWIFT_INCLUDE=/Library/Developer/CommandLineTools/usr/include/swift
if [[ -f $CLT_SWIFT_INCLUDE/module.modulemap && -f $CLT_SWIFT_INCLUDE/bridging.modulemap ]]; then
    : > "$TMP/empty.modulemap"
    cat > "$TMP/clt-overlay.yaml" <<EOF
{
  "version": 0,
  "roots": [{
    "type": "directory",
    "name": "$CLT_SWIFT_INCLUDE",
    "contents": [{ "type": "file", "name": "module.modulemap", "external-contents": "$ROOT/$TMP/empty.modulemap" }]
  }]
}
EOF
    SWIFTC+=(-vfsoverlay "$TMP/clt-overlay.yaml" -Xcc -ivfsoverlay -Xcc "$TMP/clt-overlay.yaml")
fi

echo "Compiling app…"
"${SWIFTC[@]}" -module-name BMSWidget App/*.swift Shared/*.swift \
    -o "$APP/Contents/MacOS/BMSWidget"

echo "Compiling widget extension…"
# Like Xcode: extensions start in NSExtensionMain, which then runs the @main Widget.
"${SWIFTC[@]}" -module-name BMSWidgetExtension -application-extension \
    -Xlinker -e -Xlinker _NSExtensionMain \
    Widget/*.swift Shared/*.swift \
    -o "$APPEX/Contents/MacOS/BMSWidgetExtension"

PLIST_HEAD='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">'

cat > "$APP/Contents/Info.plist" <<EOF
$PLIST_HEAD
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>BMS Widget</string>
    <key>CFBundleExecutable</key><string>BMSWidget</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_PREFIX.bmswidget</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>BMSWidget</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
    <key>LSUIElement</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key><string>Потрібен, щоб зчитувати стан акумулятора з BMS.</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

cat > "$APPEX/Contents/Info.plist" <<EOF
$PLIST_HEAD
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>BMS Widget</string>
    <key>CFBundleExecutable</key><string>BMSWidgetExtension</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_PREFIX.bmswidget.widget</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>BMSWidgetExtension</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
EOF

cat > "$TMP/App.entitlements" <<EOF
$PLIST_HEAD
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.device.bluetooth</key><true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
    <array><string>$SHARED_DIR</string></array>
</dict>
</plist>
EOF

cat > "$TMP/Widget.entitlements" <<EOF
$PLIST_HEAD
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
    <array><string>$SHARED_DIR</string></array>
</dict>
</plist>
EOF

echo "Signing (ad-hoc)…"
codesign --force --sign - --options runtime --entitlements "$TMP/Widget.entitlements" "$APPEX"
codesign --force --sign - --options runtime --entitlements "$TMP/App.entitlements" "$APP"
codesign --verify --strict --deep "$APP"

echo "Built $ROOT/$APP"
