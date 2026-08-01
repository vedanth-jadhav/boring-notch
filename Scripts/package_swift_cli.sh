#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="boringNotch"
APP_DISPLAY_NAME="boring.notch"
BUNDLE_ID="theboringteam.boringnotch"
HELPER_NAME="BoringNotchXPCHelper"
HELPER_BUNDLE_ID="${BUNDLE_ID}.${HELPER_NAME}"
BUILD_ROOT="${ROOT}/build/swift-cli"
APP="${BUILD_ROOT}/${APP_NAME}.app"

cd "$ROOT"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/boring-notch-clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/private/tmp/boring-notch-swiftpm-cache}"

if ! command -v swift >/dev/null 2>&1; then
  echo "ERROR: swift CLI not found." >&2
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "ERROR: codesign not found." >&2
  exit 1
fi

patch_keyboardshortcuts_previews() {
  local recorder="${ROOT}/.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift"

  if [[ ! -f "$recorder" ]]; then
    return
  fi

  chmod u+w "$recorder"

  ruby - "$recorder" <<'RUBY'
path = ARGV.fetch(0)
lines = File.readlines(path)
first_preview = lines.index { |line| line.start_with?("#Preview") }
final_endif = lines.rindex { |line| line.strip == "#endif" }

exit 0 if first_preview.nil? || final_endif.nil? || final_endif <= first_preview
exit 0 if lines[first_preview - 1]&.include?("SwiftPM CLI")

patched = lines[0...first_preview] +
  ["// SwiftPM CLI: Xcode preview macros need Xcode's PreviewsMacros plugin.\n"] +
  lines[final_endif..]

File.write(path, patched.join)
RUBY
}

patch_keyboardshortcuts_resource_lookup() {
  local utilities="${ROOT}/.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Utilities.swift"

  if [[ ! -f "$utilities" ]]; then
    return
  fi

  chmod u+w "$utilities"

  ruby - "$utilities" <<'RUBY'
path = ARGV.fetch(0)
text = File.read(path)
exit 0 if text.include?('keyboardShortcutsResources')

anchor = "extension String {\n"
lookup = <<~SWIFT
private let keyboardShortcutsResources: Bundle = {
\tguard
\t\tlet resourcesURL = Bundle.main.resourceURL,
\t\tlet bundle = Bundle(url: resourcesURL.appendingPathComponent("KeyboardShortcuts_KeyboardShortcuts.bundle"))
\telse {
\t\treturn .main
\t}

\treturn bundle
}()


SWIFT

unless text.include?(anchor) && text.include?('NSLocalizedString(self, bundle: .module, comment: self)')
  warn "ERROR: KeyboardShortcuts resource lookup source changed; update the packaging patch"
  exit 1
end

text = text.sub(anchor, lookup + anchor)
text = text.sub(
  'NSLocalizedString(self, bundle: .module, comment: self)',
  'NSLocalizedString(self, bundle: keyboardShortcutsResources, comment: self)'
)
File.write(path, text)
RUBY
}

swift package --disable-sandbox resolve
patch_keyboardshortcuts_previews
patch_keyboardshortcuts_resource_lookup

swift build --disable-sandbox -c "$CONFIGURATION" --product "$APP_NAME"
swift build --disable-sandbox -c "$CONFIGURATION" --product "$HELPER_NAME"

PRODUCT_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)"
APP_BINARY="${PRODUCT_DIR}/${APP_NAME}"
HELPER_BINARY="${PRODUCT_DIR}/${HELPER_NAME}"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "ERROR: missing built app binary at ${APP_BINARY}" >&2
  exit 1
fi

if [[ ! -x "$HELPER_BINARY" ]]; then
  echo "ERROR: missing built XPC helper binary at ${HELPER_BINARY}" >&2
  exit 1
fi

MARKETING_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/boringNotch/Info.plist" 2>/dev/null || echo "1.0")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ROOT/boringNotch/Info.plist" 2>/dev/null || echo "1")

rm -rf "$APP"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources" \
  "$APP/Contents/Frameworks" \
  "$APP/Contents/XPCServices/${HELPER_NAME}.xpc/Contents/MacOS"

cp "$APP_BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp "$HELPER_BINARY" "$APP/Contents/XPCServices/${HELPER_NAME}.xpc/Contents/MacOS/$HELPER_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>This app uses AppleEvents to control and display music playback.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>boring.notch uses Bluetooth to show connected OnePlus buds battery and noise controls.</string>
  <key>SUEnableDownloaderService</key>
  <true/>
  <key>SUEnableInstallerLauncherService</key>
  <true/>
  <key>SUFeedURL</key>
  <string>https://TheBoredTeam.github.io/boring.notch/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>B1Y47t8C/v8ImurYA+9arEsuCrpxwJSviekiflMElbI=</string>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict/>
  </array>
</dict>
</plist>
PLIST

cat > "$APP/Contents/XPCServices/${HELPER_NAME}.xpc/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${HELPER_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${HELPER_BUNDLE_ID}</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>XPCService</key>
  <dict>
    <key>ServiceType</key>
    <string>Application</string>
  </dict>
</dict>
</plist>
PLIST

shopt -s nullglob
for bundle in "$PRODUCT_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
for framework in "$PRODUCT_DIR"/*.framework; do
  cp -R "$framework" "$APP/Contents/Frameworks/"
done
shopt -u nullglob

cp -R "$ROOT/mediaremote-adapter/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
cp "$ROOT/mediaremote-adapter/MediaRemoteAdapterTestClient" "$APP/Contents/Resources/"
cp "$ROOT/mediaremote-adapter/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

if [[ -d "$ROOT/boringNotch/Assets.xcassets" ]]; then
  cp -R "$ROOT/boringNotch/Assets.xcassets" "$APP/Contents/Resources/"
fi
if [[ -f "$ROOT/boringNotch/Localizable.xcstrings" ]]; then
  cp "$ROOT/boringNotch/Localizable.xcstrings" "$APP/Contents/Resources/"
fi
if [[ -f "$ROOT/boringNotch/boring.m4a" ]]; then
  cp "$ROOT/boringNotch/boring.m4a" "$APP/Contents/Resources/"
fi
chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

for bundle in "$PRODUCT_DIR"/*.bundle; do
  bundle_name="$(basename "$bundle")"
  if [[ ! -d "$APP/Contents/Resources/$bundle_name" ]]; then
    echo "ERROR: missing packaged SwiftPM resource bundle ${bundle_name}" >&2
    exit 1
  fi
done

codesign --force --sign - \
  --entitlements "$ROOT/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements" \
  "$APP/Contents/XPCServices/${HELPER_NAME}.xpc"

find "$APP/Contents/Frameworks" -type f -perm -111 -print0 | while IFS= read -r -d '' binary; do
  codesign --force --sign - "$binary" || true
done

find "$APP/Contents/Frameworks" -name '*.framework' -maxdepth 1 -print0 | while IFS= read -r -d '' framework; do
  codesign --force --sign - "$framework" || true
done

codesign --force --sign - \
  --entitlements "$ROOT/boringNotch/boringNotch.entitlements" \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

echo "Created ${APP}"
