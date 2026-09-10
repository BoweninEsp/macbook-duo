#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
rm -rf build/AppIcon.iconset
mkdir -p build/AppIcon.iconset
for spec in "16x16:16" "32x32:32" "128x128:128" "256x256:256" "512x512:512"; do
  name=${spec%%:*}; size=${spec##*:}
  sips -z "$size" "$size" MacBook-Duo-logo-source.png --out "build/AppIcon.iconset/icon_${name}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" MacBook-Duo-logo-source.png --out "build/AppIcon.iconset/icon_${name}@2x.png" >/dev/null
done
APP="$PWD/dist/MacBook Duo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MacBookDuo "$APP/Contents/MacOS/MacBookDuo"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacBookDuo</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>local.bon.macbookduo</string>
<key>CFBundleName</key><string>MacBook Duo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
