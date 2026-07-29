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

# ---- build -------------------------------------------------------------------------------
step "Generating project and building Release"
xcodegen generate
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild -project AgentOasis.xcodeproj -scheme AgentOasis \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$AGENT_OASIS_DEVELOPMENT_TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  clean build

APP=$(find "$BUILD_DIR/DerivedData/Build/Products/Release" -maxdepth 1 -name "*.app" | head -1)
[ -n "$APP" ] || fail "No .app produced."

# ---- verify the signature BEFORE spending a notarization round trip ----------------------
step "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|flags" | sed 's/^/  /'
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "keychain-access-groups" \
  && echo "  keychain-access-groups: present (data protection keychain available)" \
  || echo "  keychain-access-groups: ABSENT - the app will fall back to the legacy keychain"

# Hardened runtime is required for notarization; catching it here saves a failed submission.
codesign -dv --verbose=4 "$APP" 2>&1 | grep -q "flags=.*runtime" \
  || fail "Hardened runtime is not enabled. Notarization will be rejected."

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
  --wait

step "Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# ---- the check that actually matters ------------------------------------------------------
step "Gatekeeper assessment"
# This is what a stranger's Mac does on first open. If it says 'rejected', the download is
# broken for everyone regardless of what every earlier step reported.
spctl -a -vvv -t install "$DMG" 2>&1 | sed 's/^/  /'

printf '\n  DONE: %s\n' "$DMG"
printf '  sha256: %s\n\n' "$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
