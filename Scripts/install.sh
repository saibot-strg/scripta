#!/bin/zsh
# Builds a Release version of Scripta and installs it to /Applications,
# where Spotlight, Launchpad and Finder pick it up like any other app.
#
# Usage: Scripts/install.sh [--wait | --force]
#   --wait   build first, then wait until the running Scripta is quit (⌘Q),
#            install right away and open the new version
#   --force  quit a running Scripta from /Applications before replacing it
set -euo pipefail
cd "${0:A:h}/.."

APP_NAME=Scripta
DEST="/Applications/$APP_NAME.app"
# The ".noindex" suffix keeps Spotlight from listing build copies next to the installed app.
DERIVED=build/DerivedData.noindex
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "Building $APP_NAME (Release) …"
xcodebuild -project Scripta.xcodeproj -scheme Scripta -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" build -quiet

SRC="$DERIVED/Build/Products/Release/$APP_NAME.app"
codesign --verify --strict "$SRC"

# Never quit the installed app behind the user's back (it might be recording).
WAS_RUNNING=0
if pgrep -f "$DEST/Contents/MacOS/" >/dev/null; then
  WAS_RUNNING=1
  case "${1:-}" in
    --force)
      pkill -f "$DEST/Contents/MacOS/" || true
      ;;
    --wait)
      echo "Waiting until $APP_NAME is quit (⌘Q) …"
      while pgrep -f "$DEST/Contents/MacOS/" >/dev/null; do sleep 0.5; done
      ;;
    *)
      echo "$APP_NAME is running. Quit it first (⌘Q), or run with --wait or --force." >&2
      exit 1
      ;;
  esac
fi

echo "Installing to $DEST …"
rm -rf "$DEST"
ditto "$SRC" "$DEST"
# A fresh modification date makes Finder and the Dock drop their cached icon.
touch "$DEST"

# Register with Launch Services and Spotlight right away instead of waiting for the next scan.
"$LSREGISTER" -f "$DEST"
mdimport "$DEST" 2>/dev/null || true

echo "Done: $APP_NAME is in /Applications and can be found with Spotlight."

# Reopen the new version if the old one was running.
if [[ $WAS_RUNNING == 1 ]]; then
  open "$DEST"
fi
