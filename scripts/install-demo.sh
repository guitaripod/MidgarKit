#!/bin/bash
# Builds Examples/MidgarDemo with the development profile from the Midgar vault, installs it on the
# iPhone Air and launches it with MIDGAR_SELFTEST=1, then pulls the self-test report and screenshots
# into .scratch/selftest. The phone has to be unlocked to launch. Needs xcodegen.
#   scripts/install-demo.sh            build, install, launch, collect
#   scripts/install-demo.sh --no-run   build and install only
# A locked phone is retried every 20 seconds for up to 30 minutes.
# The development identity lives in a temporary keychain that is put first in the search list and
# removed afterwards, because the login keychain is locked in an agent shell.

set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH
DEVICE=00008150-00096C392208401C
BUNDLE=com.marcusziade.MidgarDemo
SIGN=$HOME/.config/midgar/signing
cd "$(dirname "$0")/.." || exit 1
REPO=$PWD
DEMO=$REPO/Examples/MidgarDemo
SCRATCH=$REPO/.scratch
KEYCHAIN=$SCRATCH/device.keychain-db
ORIGINAL_KEYCHAINS=$(security list-keychains -d user | tr -d '"' | xargs)
APP=$SCRATCH/dd-demo/Build/Products/Debug-iphoneos/MidgarDemo.app

restore() {
  security list-keychains -d user -s $ORIGINAL_KEYCHAINS
  security delete-keychain "$KEYCHAIN" 2>/dev/null
  rm -f "$KEYCHAIN"
}
trap restore EXIT

mkdir -p "$SCRATCH" "$HOME/Library/MobileDevice/Provisioning Profiles"
rm -f "$KEYCHAIN"
PASSWORD=$(uuidgen)
security create-keychain -p "$PASSWORD" "$KEYCHAIN" || exit 1
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$SIGN/midgar_distribution.p12" -k "$KEYCHAIN" -P "$(cat "$SIGN/midgar_distribution.p12.password")" -T /usr/bin/codesign -T /usr/bin/security > /dev/null || exit 1
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" > /dev/null 2>&1
security list-keychains -d user -s "$KEYCHAIN" $ORIGINAL_KEYCHAINS

uuid=$(security cms -D -i "$SIGN/midgardemo-dev-2026.mobileprovision" | plutil -extract UUID raw -o - -)
cp "$SIGN/midgardemo-dev-2026.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$uuid.mobileprovision"

(cd "$DEMO" && xcodegen generate > "$SCRATCH/xcodegen.log" 2>&1) || { tail -20 "$SCRATCH/xcodegen.log"; exit 1; }
xcodebuild -project "$DEMO/MidgarDemo.xcodeproj" -scheme MidgarDemo -configuration Debug -destination generic/platform=iOS \
  -derivedDataPath "$SCRATCH/dd-demo" -skipPackagePluginValidation -skipMacroValidation build > "$SCRATCH/demo-build.log" 2>&1
code=$?
echo "BUILD EXIT $code"
[ $code -eq 0 ] || { grep -E "error:|errSec" "$SCRATCH/demo-build.log" | head -10; exit 1; }

xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | tail -3
[ "${1:-}" = "--no-run" ] && exit 0

launched=0
for attempt in $(seq 1 90); do
  if DEVICECTL_CHILD_MIDGAR_SELFTEST=1 xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE" > "$SCRATCH/launch.log" 2>&1; then
    launched=1
    break
  fi
  grep -q "Locked" "$SCRATCH/launch.log" || { tail -5 "$SCRATCH/launch.log"; break; }
  echo "phone is locked, retrying in 20 s ($attempt/90)"
  sleep 20
done
[ $launched -eq 1 ] || { echo "LAUNCH FAILED"; exit 1; }
sleep 34
rm -rf "$SCRATCH/selftest" && mkdir -p "$SCRATCH/selftest"
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source Documents/midgar-selftest --destination "$SCRATCH/selftest" 2>&1 | tail -3
ls "$SCRATCH/selftest"
[ -f "$SCRATCH/selftest/selftest.json" ] && cat "$SCRATCH/selftest/selftest.json"
