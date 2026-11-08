#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) Havus.app and packs it as
# build/release/Havus-<version>.zip plus a SHA-256 checksum file, and its debug symbols as
# build/release/Havus.app.dSYM.zip.
#
# Usage: scripts/build-release.sh <version> [build-number]
#
# Signing: when HAVUS_SIGNING_KEYCHAIN points to a keychain that holds the Havus release
# certificate, the app is signed with it. The Release workflow imports that certificate from
# GitHub secrets. macOS ties Full Disk Access to this signature, so users keep the permission
# when they update. Without HAVUS_SIGNING_KEYCHAIN the app stays ad-hoc signed, which is fine
# for testing but makes macOS treat every build as a new app. See docs/maintainer.md.
set -euo pipefail

# SHA-1 of the Havus release certificate. Every release must be signed with this certificate:
# a different one takes Full Disk Access away from every user, so signing fails if it doesn't match.
RELEASE_CERT_SHA1=9e4a60cb751d37f504f5290a9ead326f31e739b5
RELEASE_REQUIREMENT="identifier \"id.nyetok.havus\" and certificate leaf = H\"$RELEASE_CERT_SHA1\""

VERSION="${1:?Usage: scripts/build-release.sh <version> [build-number], e.g. 0.1.0}"
BUILD_NUMBER="${2:-1}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like X.Y.Z (e.g. 0.1.0), got: $VERSION" >&2
  exit 1
fi
if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Build number must be numeric, got: $BUILD_NUMBER" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/Havus.xcarchive"
ZIP="Havus-$VERSION.zip"
# Not Havus-*.zip: havus.web.id offers the first release asset with such a name as the download.
DSYM_ZIP="Havus.app.dSYM.zip"

rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild archive \
  -project "$ROOT/Havus.xcodeproj" \
  -scheme Havus \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  -quiet

APP="$ARCHIVE/Products/Applications/Havus.app"

if [[ -n "${HAVUS_SIGNING_KEYCHAIN:-}" ]]; then
  # The app has no nested code yet. A future helper or framework must be signed with the same
  # certificate before the app itself.
  codesign --force --options runtime --timestamp=none --preserve-metadata=entitlements \
    --keychain "$HAVUS_SIGNING_KEYCHAIN" \
    --sign "$RELEASE_CERT_SHA1" \
    --requirements "=designated => $RELEASE_REQUIREMENT" \
    "$APP"
  codesign --verify --strict --test-requirement "=$RELEASE_REQUIREMENT" "$APP"
  echo "Signed with the Havus release certificate ($RELEASE_CERT_SHA1)."
else
  echo "HAVUS_SIGNING_KEYCHAIN isn't set, so this build stays ad-hoc signed: fine for testing, not for a release." >&2
fi

codesign --verify --strict "$APP"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/Havus")"

# Release builds are stripped, so a crash report shows Havus's own code only as offsets. The
# dSYM turns them into function names and line numbers, but only for the binary it was built
# with: a crash report names the binary by its UUID.
DSYM="$ARCHIVE/dSYMs/Havus.app.dSYM"
APP_UUIDS="$(dwarfdump --uuid "$APP/Contents/MacOS/Havus" | awk '{ print $2, $3 }' | sort)"
DSYM_UUIDS="$(dwarfdump --uuid "$DSYM" | awk '{ print $2, $3 }' | sort)"
if [[ -z "$APP_UUIDS" || "$APP_UUIDS" != "$DSYM_UUIDS" ]]; then
  echo "The dSYM doesn't match the app binary." >&2
  exit 1
fi
echo "Binary UUIDs, matched by the dSYM:"
echo "$APP_UUIDS"

cd "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" > "$ZIP.sha256"
ditto -c -k --keepParent "$DSYM" "$DSYM_ZIP"
echo "Done: build/release/$ZIP and build/release/$DSYM_ZIP"
cat "$ZIP.sha256"
