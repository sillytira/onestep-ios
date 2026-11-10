#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_NUMBER="${BUILD_NUMBER:-1}"
if ! [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo 'BUILD_NUMBER must be a positive integer.' >&2
  exit 1
fi
node scripts/generate-project.mjs
node scripts/generate-icon.mjs
mkdir -p build release
xcodebuild -project OneStep.xcodeproj -scheme OneStep -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' build
APP="build/DerivedData/Build/Products/Release-iphoneos/OneStep.app"
test -f "$APP/OneStep"
file "$APP/OneStep" | grep -q arm64
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" | grep -qx 'tech.sillycat.onestep'
if [ -d "$APP/PlugIns" ]; then echo 'Unexpected extension in beta app.' >&2; exit 1; fi
# A fresh staging directory avoids accidentally bundling a previous build.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/onestep-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir "$STAGING/Payload"
ditto "$APP" "$STAGING/Payload/OneStep.app"
IPA="$PWD/release/OneStep-0.1.0-beta-${BUILD_NUMBER}-unsigned.ipa"
(cd "$STAGING" && /usr/bin/zip -qry "$IPA" Payload)
unzip -t "$IPA"
(cd release && shasum -a 256 "$(basename "$IPA")" > "$(basename "$IPA").sha256")
cp INSTALL.md KNOWN-LIMITATIONS.md release/
echo "Built $IPA. AltStore must sign it before installation."
