#!/bin/zsh
# Breadcrumbs installer: downloads the latest release into ~/Applications and opens it.
#   curl -fsSL https://raw.githubusercontent.com/nishanthappari/breadcrumbs/main/install.sh | zsh
set -euo pipefail

REPO="nishanthappari/breadcrumbs"
DEST="$HOME/Applications"
TMP="$(mktemp -d)"
trap '/bin/rm -rf "$TMP"' EXIT

if (( $(sw_vers -productVersion | cut -d. -f1) < 14 )); then
  echo "Breadcrumbs needs macOS 14 (Sonoma) or later." >&2
  exit 1
fi

echo "Downloading Breadcrumbs…"
curl -fsSL "https://github.com/$REPO/releases/latest/download/Breadcrumbs.zip" -o "$TMP/Breadcrumbs.zip"

# Replace any existing copy (your history and settings are kept; they live elsewhere).
osascript -e 'tell application id "com.opslab.breadcrumbs" to quit' >/dev/null 2>&1 || true
sleep 1
mkdir -p "$DEST"
/bin/rm -rf "$DEST/Breadcrumbs.app"
ditto -x -k "$TMP/Breadcrumbs.zip" "$DEST"
xattr -dr com.apple.quarantine "$DEST/Breadcrumbs.app" 2>/dev/null || true

open "$DEST/Breadcrumbs.app"
echo
echo "Breadcrumbs is installed in ~/Applications and running."
echo "Look for the little box in your menu bar, or press Control-Option-B to start a sprint."
