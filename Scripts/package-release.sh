#!/bin/zsh
# Builds an ad-hoc signed Release of Scripta and packages it as a DMG with a
# SHA-256 checksum in dist/. Used by .github/workflows/release.yml and can be
# run locally the same way.
#
# Usage: Scripts/package-release.sh [version]
#   version  marketing version such as 0.2.0
#            (default: MARKETING_VERSION from Config/App.xcconfig)
#   BUILD_NUMBER (environment) sets the bundle version, default 1.
set -euo pipefail
cd "${0:A:h}/.."

APP_NAME=Scripta
VERSION=${1:-$(sed -n 's/^MARKETING_VERSION *= *//p' Config/App.xcconfig)}
BUILD_NUMBER=${BUILD_NUMBER:-1}
# Separate from install.sh's build folder; ".noindex" keeps Spotlight from listing the copy.
DERIVED=build/ReleaseDerivedData.noindex
DIST=dist

if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version '$VERSION', expected e.g. 0.2.0." >&2
  exit 1
fi

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER) …"
# Always ad-hoc: a personal "Apple Development" certificate from Config/Local.xcconfig
# embeds the developer's name and email and must never ship.
xcodebuild -project Scripta.xcodeproj -scheme Scripta -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  build -quiet

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
codesign --verify --strict "$APP"
SIGNATURE=$(codesign -dv "$APP" 2>&1)
if [[ $SIGNATURE != *"Signature=adhoc"* || $SIGNATURE != *"TeamIdentifier=not set"* ]]; then
  echo "$SIGNATURE" >&2
  echo "Expected an ad-hoc signature without a team." >&2
  exit 1
fi
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [[ $BUILT_VERSION != "$VERSION" ]]; then
  echo "Built version is $BUILT_VERSION, expected $VERSION." >&2
  exit 1
fi

echo "Packaging …"
rm -rf "$DIST"
mkdir -p "$DIST/dmg"
ditto "$APP" "$DIST/dmg/$APP_NAME.app"
# Drag-to-install: the DMG window shows the app next to a link to /Applications.
ln -s /Applications "$DIST/dmg/Applications"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
# hdiutil occasionally fails with "Resource busy" on CI machines; retry a few times.
for attempt in 1 2 3; do
  hdiutil create -volname "$APP_NAME" -srcfolder "$DIST/dmg" -ov -format UDZO "$DMG" -quiet && break
  if [[ $attempt == 3 ]]; then exit 1; fi
  sleep 5
done
rm -rf "$DIST/dmg"
(cd "$DIST" && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")

echo "Done: $DMG"
