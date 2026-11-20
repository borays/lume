#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f AppIcon.icns ]; then
    echo "Generating app icon…"
    mkdir -p Brand
    swift Tools/make_icon.swift light /tmp/Lume-icon-1024.png
    swift Tools/make_icon.swift dark Brand/lume-icon-dark.png
    swift Tools/make_icon.swift menubar Brand/lume-menubar.png
    cp /tmp/Lume-icon-1024.png Brand/lume-icon-light.png
    rm -rf /tmp/Lume.iconset
    mkdir -p /tmp/Lume.iconset
    while IFS=' ' read -r pixels name; do
        sips -z "$pixels" "$pixels" /tmp/Lume-icon-1024.png --out "/tmp/Lume.iconset/$name.png" >/dev/null
    done <<'ICONS'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
ICONS
    iconutil -c icns /tmp/Lume.iconset -o AppIcon.icns
fi

swift build -c release
APP="dist/Lume.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Lume "$APP/Contents/MacOS/Lume"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
