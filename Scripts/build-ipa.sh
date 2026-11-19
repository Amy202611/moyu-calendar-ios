#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/output
test "$(uname -s)" = Darwin || { echo "error: macOS and Xcode required"; exit 2; }
python3 Scripts/generate-icons.py
xcodegen generate --spec project.yml
args=(-project MoyuCalendar.xcodeproj -scheme MoyuCalendar -configuration Release
-sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData
ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
'CODE_SIGN_IDENTITY=' 'DEVELOPMENT_TEAM=' "CURRENT_PROJECT_VERSION=${BUILD_NUMBER:-1}" build)
for attempt in 1 2; do
  set +e
  xcodebuild "${args[@]}" 2>&1 | tee "build/xcodebuild-${attempt}.log"
  result="${PIPESTATUS[0]}"
  set -e
  if [ "$result" -eq 0 ]; then break; fi
  if [ "$attempt" -eq 2 ] || ! python3 Scripts/diagnose.py build --retryable; then exit "$result"; fi
  echo "Retry transient dependency failure once"
  xcodegen generate --spec project.yml
  sleep 5
done
app=build/DerivedData/Build/Products/Release-iphoneos/MoyuCalendar.app
test -d "$app"
exe="$app/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Info.plist")"
test "$(xcrun lipo -archs "$exe")" = arm64
rm -rf build/ipa-stage
mkdir -p build/ipa-stage/Payload
ditto "$app" build/ipa-stage/Payload/MoyuCalendar.app
find build/ipa-stage -name embedded.mobileprovision -delete
# A completely unsigned basic package remains available without extensions.
rm -rf build/ipa-stage/Payload/MoyuCalendar.app/PlugIns
(cd build/ipa-stage && ditto -c -k --keepParent Payload ../output/MoyuCalendar-unsigned.ipa)
python3 Scripts/validate-ipa.py build/output/MoyuCalendar-unsigned.ipa
(cd build/output && shasum -a 256 MoyuCalendar-unsigned.ipa > SHA256SUMS.txt)

# App Groups must be carried in the Mach-O signature so SideStore can request
# matching profiles. Ad-hoc signing uses no Apple certificate or paid account.
# This second IPA is explicitly labelled ad-hoc, never reported as unsigned.
rm -rf build/widget-stage
mkdir -p build/widget-stage/Payload
ditto "$app" build/widget-stage/Payload/MoyuCalendar.app
widget_app=build/widget-stage/Payload/MoyuCalendar.app
widget_ext="$widget_app/PlugIns/MoyuCalendarWidgets.appex"
test -d "$widget_ext"
codesign --force --sign - --entitlements Signing/Widget.entitlements "$widget_ext"
codesign --force --sign - --entitlements Signing/App.entitlements "$widget_app"
(cd build/widget-stage && ditto -c -k --keepParent Payload ../output/MoyuCalendar-Widgets-adhoc-SideStore.ipa)
python3 Scripts/validate-ipa.py build/output/MoyuCalendar-Widgets-adhoc-SideStore.ipa --widgets
(cd build/output && shasum -a 256 *.ipa > SHA256SUMS.txt)
