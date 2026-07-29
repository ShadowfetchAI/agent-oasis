#!/usr/bin/env bash
#
# Build, sign, notarize and staple a distributable Agent Oasis.
#
# Everything here is refused rather than guessed. A release script that "helpfully" falls back
# to an ad-hoc signature produces a .dmg that dies at a Gatekeeper warning on the first
# stranger's Mac, and the failure surfaces to THEM rather than to you. Each precondition is
# checked up front and the script stops with an instruction you can act on.
#
# Usage:
#   AGENT_OASIS_DEVELOPMENT_TEAM=ABCDE12345 \
#   AGENT_OASIS_BUNDLE_PREFIX=com.yourdomain \
#   AGENT_OASIS_PROVISIONING_PROFILE=/path/to/DeveloperID.provisionprofile \
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
#   ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8 \
#   scripts/release.sh
#
set -euo pipefail

VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*: *"\(.*\)"/\1/')}"
BUILD_DIR="${BUILD_DIR:-build/release}"
APP_NAME="Agent Oasis"
DMG="$BUILD_DIR/Agent-Oasis-$VERSION.dmg"

fail() { printf '\n  ERROR: %s\n\n' "$1" >&2; exit 1; }
step() { printf '\n==> %s\n' "$1"; }

# ---- preconditions -----------------------------------------------------------------------
step "Checking preconditions"

[ -n "${AGENT_OASIS_DEVELOPMENT_TEAM:-}" ] || fail \
  "AGENT_OASIS_DEVELOPMENT_TEAM is not set. Find your Team ID at developer.apple.com > Membership."
[ -n "${AGENT_OASIS_BUNDLE_PREFIX:-}" ] || fail \
  "AGENT_OASIS_BUNDLE_PREFIX is not set."
[ -n "${AGENT_OASIS_PROVISIONING_PROFILE:-}" ] || fail \
  "AGENT_OASIS_PROVISIONING_PROFILE is not set. A Developer ID profile is required for the data protection keychain."

PROFILE_PATH="${AGENT_OASIS_PROVISIONING_PROFILE/#\~/$HOME}"
[ -f "$PROFILE_PATH" ] || fail \
  "AGENT_OASIS_PROVISIONING_PROFILE does not exist: $AGENT_OASIS_PROVISIONING_PROFILE"

PROFILE_NAME=$(security cms -D -i "$PROFILE_PATH" | plutil -extract Name raw -o - -)
PROFILE_UUID=$(security cms -D -i "$PROFILE_PATH" | plutil -extract UUID raw -o - -)
PROFILE_APP_ID=$(security cms -D -i "$PROFILE_PATH" \
  | plutil -extract 'Entitlements.com\.apple\.application-identifier' raw -o - -)
EXPECTED_APP_ID="$AGENT_OASIS_DEVELOPMENT_TEAM.$AGENT_OASIS_BUNDLE_PREFIX.AgentOasis"
[ "$PROFILE_APP_ID" = "$EXPECTED_APP_ID" ] || fail \
  "Provisioning profile authorizes $PROFILE_APP_ID, expected $EXPECTED_APP_ID."

PROFILE_INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_INSTALL_DIR"
cp "$PROFILE_PATH" "$PROFILE_INSTALL_DIR/$PROFILE_UUID.provisionprofile"
echo "  profile: $PROFILE_NAME ($PROFILE_UUID)"

# Developer ID Application is the ONLY identity Gatekeeper accepts for direct distribution.
# 'Apple Development' works on your own Mac and nowhere else; 'Apple Distribution' is for the
# App Store. Shipping either to strangers produces a download that will not open.
IDENTITY=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
[ -n "$IDENTITY" ] || fail \
  "No 'Developer ID Application' certificate found.
  Create one at developer.apple.com > Certificates > + > Developer ID Application,
  download it, and double-click to install. 'Apple Development' and 'Apple Distribution'
  are NOT substitutes - Gatekeeper rejects both for direct distribution."
echo "  identity: $IDENTITY"

for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  [ -n "${!v:-}" ] || fail "$v is not set. Notarization needs an App Store Connect API key."
done
[ -f "${ASC_KEY_PATH/#\~/$HOME}" ] || fail "ASC_KEY_PATH does not exist: $ASC_KEY_PATH"

command -v xcodegen >/dev/null || fail "xcodegen not found. brew install xcodegen"

case "$BUILD_DIR" in
  build/*) ;;
  *) fail "BUILD_DIR must stay below build/ so release cleanup cannot touch source files." ;;
esac

# ---- build -------------------------------------------------------------------------------
step "Generating project and building universal Release"
xcodegen generate
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild -project AgentOasis.xcodeproj -scheme AgentOasis \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$AGENT_OASIS_DEVELOPMENT_TEAM" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  clean build

APP=$(find "$BUILD_DIR/DerivedData/Build/Products/Release" -maxdepth 1 -name "*.app" | head -1)
[ -n "$APP" ] || fail "No .app produced."

# ---- verify the signature BEFORE spending a notarization round trip ----------------------
step "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
CODESIGN_DETAILS=$(codesign -dv --verbose=4 "$APP" 2>&1)
printf '%s\n' "$CODESIGN_DETAILS" | grep -E "Authority|TeamIdentifier|flags" | sed 's/^/  /'
[ -f "$APP/Contents/embedded.provisionprofile" ] || fail \
  "The signed app is missing its Developer ID provisioning profile."
EMBEDDED_UUID=$(security cms -D -i "$APP/Contents/embedded.provisionprofile" \
  | plutil -extract UUID raw -o - -)
[ "$EMBEDDED_UUID" = "$PROFILE_UUID" ] || fail \
  "The app embedded provisioning profile $EMBEDDED_UUID, expected $PROFILE_UUID."

SIGNED_ENTITLEMENTS=$(codesign -d --entitlements :- "$APP" 2>/dev/null)
SIGNED_KEYCHAIN_GROUP=$(printf '%s\n' "$SIGNED_ENTITLEMENTS" \
  | plutil -extract keychain-access-groups.0 raw -o - -)
EXPECTED_KEYCHAIN_GROUP="$AGENT_OASIS_DEVELOPMENT_TEAM.$AGENT_OASIS_BUNDLE_PREFIX.AgentOasis"
[ "$SIGNED_KEYCHAIN_GROUP" = "$EXPECTED_KEYCHAIN_GROUP" ] || fail \
  "Signed keychain group is $SIGNED_KEYCHAIN_GROUP, expected $EXPECTED_KEYCHAIN_GROUP."
echo "  keychain-access-groups: $SIGNED_KEYCHAIN_GROUP"

if grep -q "get-task-allow" <<< "$SIGNED_ENTITLEMENTS"; then
  fail "Release app contains com.apple.security.get-task-allow."
fi

# Hardened runtime is required for notarization; catching it here saves a failed submission.
grep -q "flags=.*runtime" <<< "$CODESIGN_DETAILS" \
  || fail "Hardened runtime is not enabled. Notarization will be rejected."

ARCHITECTURES=$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")
echo "  architectures: $ARCHITECTURES"
case " $ARCHITECTURES " in
  *" arm64 "*) ;;
  *) fail "Release executable is missing arm64." ;;
esac
case " $ARCHITECTURES " in
  *" x86_64 "*) ;;
  *) fail "Release executable is missing x86_64." ;;
esac

# Notarize the app before placing it in the DMG. This gives the dragged-out app its own
# stapled ticket, so it still opens when the destination Mac is offline.
step "Notarizing the app"
APP_ZIP="$BUILD_DIR/Agent-Oasis-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" \
  --key "${ASC_KEY_PATH/#\~/$HOME}" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait \
  --output-format json | tee "$BUILD_DIR/notary-app-result.json"

APP_NOTARY_STATUS=$(/usr/bin/python3 -c \
  'import json, sys; print(json.load(open(sys.argv[1]))["status"])' \
  "$BUILD_DIR/notary-app-result.json")
[ "$APP_NOTARY_STATUS" = "Accepted" ] || fail \
  "Apple app notarization returned $APP_NOTARY_STATUS."

step "Stapling the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"

# ---- package ------------------------------------------------------------------------------
step "Building $DMG"
STAGE="$BUILD_DIR/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

# ---- notarize ------------------------------------------------------------------------------
step "Notarizing (this uploads to Apple and usually takes a few minutes)"
xcrun notarytool submit "$DMG" \
  --key "${ASC_KEY_PATH/#\~/$HOME}" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait \
  --output-format json | tee "$BUILD_DIR/notary-result.json"

NOTARY_STATUS=$(/usr/bin/python3 -c \
  'import json, sys; print(json.load(open(sys.argv[1]))["status"])' \
  "$BUILD_DIR/notary-result.json")
[ "$NOTARY_STATUS" = "Accepted" ] || fail \
  "Apple notarization returned $NOTARY_STATUS."

step "Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# ---- the check that actually matters ------------------------------------------------------
step "Gatekeeper assessment"
# This is what a stranger's Mac does on first open. If it says 'rejected', the download is
# broken for everyone regardless of what every earlier step reported.
spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | sed 's/^/  /'

printf '\n  DONE: %s\n' "$DMG"
printf '  sha256: %s\n\n' "$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
