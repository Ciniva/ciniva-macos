#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

# VERSION and BUILD set the bundle version; BUNDLE_LIBS=1 copies libmpv and its dependencies into the app so it runs
# without Homebrew; SIGN_IDENTITY picks the code signing identity (ad hoc by default).
CONFIG=${1:-release}
APP=build/Ciniva.app
VERSION=${VERSION:-$(tr -d "[:space:]" < VERSION)}
BUILD=${BUILD:-1}

swift build -c "$CONFIG" --product Ciniva
BIN=$(swift build -c "$CONFIG" --show-bin-path)/Ciniva

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ciniva"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Ciniva</string>
    <key>CFBundleDisplayName</key><string>Ciniva</string>
    <key>CFBundleIdentifier</key><string>org.ciniva.mac</string>
    <key>CFBundleExecutable</key><string>Ciniva</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSLocalNetworkUsageDescription</key><string>Ciniva connects to your Ciniva server on the local network.</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

if [[ ${BUNDLE_LIBS:-0} == 1 ]]; then
    dylibbundler -of -cd -b -x "$APP/Contents/MacOS/Ciniva" -d "$APP/Contents/Frameworks" \
        -p @executable_path/../Frameworks/ -s "$(brew --prefix)/lib" >/dev/null
    # dyld refuses images with a repeated LC_RPATH, which dylibbundler can leave behind.
    for f in "$APP/Contents/MacOS/Ciniva" "$APP"/Contents/Frameworks/*.dylib; do
        otool -l "$f" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }' | sort | uniq -c | while read -r n rp; do
            for ((i = 1; i < n; i++)); do install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null; done
        done
    done
    if otool -L "$APP/Contents/MacOS/Ciniva" "$APP"/Contents/Frameworks/*.dylib | grep -E '^\s+/(opt/homebrew|usr/local)/'; then
        echo "error: the app still links Homebrew libraries" >&2
        exit 1
    fi
fi

IDENTITY=${SIGN_IDENTITY:--}
if [[ -d "$APP/Contents/Frameworks" ]]; then
    find "$APP/Contents/Frameworks" -name '*.dylib' -exec codesign --force --sign "$IDENTITY" {} + >/dev/null
fi
codesign --force --sign "$IDENTITY" "$APP" >/dev/null
echo "Built $APP"
