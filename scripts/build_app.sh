#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) Breadcrumbs.app, ad-hoc signs it, and installs it.
#   scripts/build_app.sh             build, install to ~/Applications, launch
#   scripts/build_app.sh --package   build and zip to build/Breadcrumbs.zip (for a GitHub release)
set -euo pipefail
cd "${0:A:h}/.."
ROOT=$PWD
APP="$ROOT/build/Breadcrumbs.app"
DEST="$HOME/Applications/Breadcrumbs.app"

echo "Building (arm64 + x86_64)…"
swift build -c release --product Breadcrumbs --triple arm64-apple-macosx14.0
swift build -c release --product Breadcrumbs --triple x86_64-apple-macosx14.0
mkdir -p build
lipo -create -output build/Breadcrumbs \
  .build/arm64-apple-macosx/release/Breadcrumbs \
  .build/x86_64-apple-macosx/release/Breadcrumbs

/bin/rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Breadcrumbs "$APP/Contents/MacOS/Breadcrumbs"
cp Resources/chime.wav Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - --identifier com.opslab.breadcrumbs "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Breadcrumbs"))"

if [[ "${1:-}" == "--package" ]]; then
  /bin/rm -f build/Breadcrumbs.zip
  ditto -c -k --keepParent "$APP" build/Breadcrumbs.zip
  echo "Packaged build/Breadcrumbs.zip"
  exit 0
fi

mkdir -p "$HOME/Applications"
osascript -e 'tell application id "com.opslab.breadcrumbs" to quit' >/dev/null 2>&1 || true
sleep 1
/bin/rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
