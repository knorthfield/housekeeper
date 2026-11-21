#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./build.sh dev
  ./build.sh test
  ./build.sh package [version] [--sign] [--notarize]

Commands:
  dev       Build in debug mode and run Housekeeper from a debug .app bundle
  test      Run the Swift test suite
  package   Build Housekeeper.app and Housekeeper.zip for Apple silicon in dist/release

Options:
  version     Release version like v1.2.3 (default: the current git tag)
  --sign      Sign with the Developer ID Application certificate in the keychain
              (or the identity in CODE_SIGN_IDENTITY)
  --notarize  Notarise and staple. Needs NOTARY_KEY_FILE (path to the .p8 file),
              NOTARY_KEY_ID and NOTARY_ISSUER_ID
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dist_dir="$repo_root/dist/release"
temp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
bundle_root="$temp_root/Housekeeper.app"
dev_bundle="$temp_root/Housekeeper-dev.app"
icon_source="$repo_root/AppIcon.icon"
entitlements_path="$repo_root/Housekeeper.entitlements"
code_sign_identity="${CODE_SIGN_IDENTITY:-}"

# Compiles the Liquid Glass icon into Assets.car and AppIcon.icns in the
# Resources folder $1. Info.plist names it with CFBundleIconName/File.
compile_icon() {
  local partial_plist
  partial_plist="$(mktemp "$temp_root/Housekeeper-icon.XXXXXX")"
  xcrun actool "$icon_source" --compile "$1" --app-icon AppIcon --platform macosx \
    --minimum-deployment-target 14.0 --output-partial-info-plist "$partial_plist" >/dev/null
  rm -f "$partial_plist"
}

# Copies the binaries and resources from SwiftPM's exact product directory
# into a fresh "$dest_app/Contents/{MacOS,Resources}". Shared by
# `dev` and `package` so the two don't drift out of sync.
assemble_app_bundle() {
  local products_dir="$1" dest_app="$2"
  local binary_path resource_bundle contents_dir macos_dir resources_dir

  binary_path="$products_dir/HousekeeperApp"
  if [[ ! -f "$binary_path" ]]; then
    echo "Could not find HousekeeperApp in $products_dir after swift build" >&2
    exit 1
  fi
  resource_bundle="$products_dir/Housekeeper_HousekeeperApp.bundle"

  contents_dir="$dest_app/Contents"
  macos_dir="$contents_dir/MacOS"
  resources_dir="$contents_dir/Resources"
  rm -rf "$dest_app"
  mkdir -p "$macos_dir" "$resources_dir"

  cp "$binary_path" "$macos_dir/HousekeeperApp"
  chmod +x "$macos_dir/HousekeeperApp"
  # The command-line tool for coding agents. The Homebrew cask links it as
  # `housekeeper`. `codesign --deep` signs it with the app.
  cp "$products_dir/HousekeeperCLI" "$macos_dir/housekeeper"
  chmod +x "$macos_dir/housekeeper"
  if [[ -d "$resource_bundle" ]]; then
    cp -R "$resource_bundle" "$resources_dir/"
  fi
}

# macOS 26 and later only give an app the current system design (control
# sizes and shapes, segmented controls, etc.) when its binary records an SDK
# of 26 or later. SwiftPM's default build system in Xcode 27 records the
# deployment target (14.0) there instead of the SDK it compiled against, so a
# local dev build would look like an old app.
minimum_design_sdk_major=26

recorded_sdk_versions() {
  vtool -show-build "$1" | awk '$1 == "sdk" { print $2 }'
}

# Rewrites the SDK version recorded in every architecture of binary $1 to the
# SDK it was built with, keeping its minimum macOS version. No-op when they
# already match, e.g. once SwiftPM records it correctly.
record_real_sdk_version() {
  local binary="$1" sdk_version minimum_os recorded needs_fix=false
  sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
  minimum_os="$(vtool -show-build "$binary" | awk '$1 == "minos" { print $2; exit }')"
  while read -r recorded; do
    if [[ "$recorded" != "$sdk_version" ]]; then
      needs_fix=true
    fi
  done < <(recorded_sdk_versions "$binary")

  if [[ "$needs_fix" == true ]]; then
    vtool -set-build-version macos "$minimum_os" "$sdk_version" -replace \
      -output "$binary.sdk-fixed" "$binary" >/dev/null
    mv "$binary.sdk-fixed" "$binary"
    chmod +x "$binary"
  fi
}

# Fails (or only warns, with "warn" as $2) when binary $1 records an SDK too
# old for the current system design, so a release can't ship the old look.
verify_design_sdk() {
  local binary="$1" mode="${2:-fail}" recorded
  while read -r recorded; do
    if (( ${recorded%%.*} < minimum_design_sdk_major )); then
      echo "HousekeeperApp records macOS SDK $recorded. macOS only applies its current design to apps built with SDK $minimum_design_sdk_major or later; build with Xcode $minimum_design_sdk_major or later." >&2
      if [[ "$mode" != "warn" ]]; then
        exit 1
      fi
      return
    fi
  done < <(recorded_sdk_versions "$binary")
}

# Writes Info.plist into $1, with $2 as both CFBundleShortVersionString and
# CFBundleVersion, plus any extra keys (already-indented <key>/<value> XML)
# passed as $3. Shared by `dev` and `package`, which pass only their
# build-specific extras on top of the identical boilerplate and privacy keys.
write_info_plist() {
  local contents_dir="$1" version_number="$2" extra_keys="${3:-}"
  cat > "$contents_dir/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Housekeeper</string>
  <key>CFBundleExecutable</key>
  <string>HousekeeperApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.krisnorthfield.housekeeper</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Housekeeper</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version_number}</string>
  <key>CFBundleVersion</key>
  <string>${version_number}</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Lab421 and Kris Northfield</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSArchitecturePriority</key>
  <array>
    <string>arm64</string>
  </array>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPhotoLibraryUsageDescription</key>
  <string>Housekeeper can import images and videos into your Photos library as part of automated rules.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Housekeeper uses automation to add files to the Music and TV libraries as part of automated rules.</string>
${extra_keys}
</dict>
</plist>
EOF
}

notarize_and_staple() {
  local target="$1" submission="$1" work=""
  if [[ "$target" == *.app ]]; then
    work="$(mktemp -d "$temp_root/Housekeeper-notary.XXXXXX")"
    submission="$work/$(basename "$target").zip"
    /usr/bin/ditto -c -k --keepParent "$target" "$submission"
  fi
  echo "Submitting $(basename "$target") to Apple for notarization..."
  xcrun notarytool submit "$submission" --key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait
  [[ -z "$work" ]] || rm -rf "$work"
  xcrun stapler staple "$target"
  xcrun stapler validate "$target"
}

icon_keys='  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>'

command="${1:-package}"
[[ $# -eq 0 ]] || shift

sign_requested=false
notarize_requested=false
version=""
for arg in "$@"; do
  case "$arg" in
    --sign) sign_requested=true ;;
    --notarize) notarize_requested=true ;;
    -*) echo "Unknown option: $arg" >&2; usage; exit 1 ;;
    *) version="$arg" ;;
  esac
done

cd "$repo_root"

case "$command" in
  -h|--help)
    usage
    ;;

  dev)
    # Build and run from inside a debug .app bundle rather than the bare
    # `swift run` binary. macOS attributes TCC checks (Photos, Automation) to
    # the bundle identity declared in Info.plist; an unbundled binary has none,
    # so those checks get misattributed to whatever launched it.
    swift build
    assemble_app_bundle "$(swift build --show-bin-path)" "$dev_bundle"
    contents_dir="$dev_bundle/Contents"
    record_real_sdk_version "$contents_dir/MacOS/HousekeeperApp"
    verify_design_sdk "$contents_dir/MacOS/HousekeeperApp" warn
    compile_icon "$contents_dir/Resources"
    write_info_plist "$contents_dir" "0.0.0-dev" "$icon_keys"
    # Ad-hoc sign so TCC has a stable bundle identity to attach grants to.
    codesign --force --deep --sign - "$dev_bundle" >/dev/null 2>&1
    # Exec the binary (not `open`) so stdout/stderr stay in this terminal.
    exec "$contents_dir/MacOS/HousekeeperApp"
    ;;

  test)
    swift test
    ;;

  package)
    if [[ "$notarize_requested" == true ]]; then
      if [[ "$sign_requested" != true ]]; then
        echo "--notarize requires --sign" >&2
        exit 1
      fi
      if [[ ! -f "${NOTARY_KEY_FILE:-}" || -z "${NOTARY_KEY_ID:-}" || -z "${NOTARY_ISSUER_ID:-}" ]]; then
        echo "Notarization requires NOTARY_KEY_FILE, NOTARY_KEY_ID, and NOTARY_ISSUER_ID" >&2
        exit 1
      fi
    fi
    if [[ "$sign_requested" == true && -z "$code_sign_identity" ]]; then
      code_sign_identity="$(
        security find-identity -v -p codesigning |
          awk '/Developer ID Application:/ && !identity { identity=$2 } END { print identity }'
      )"
      if [[ -z "$code_sign_identity" ]]; then
        echo "No valid Developer ID Application identity was found in the keychain" >&2
        exit 1
      fi
    fi

    if [[ -z "$version" ]]; then
      version="$(git describe --tags --exact-match 2>/dev/null || echo v0.0.0-local)"
    fi
    version="v${version#v}"
    version_number="${version#v}"

    swift build -c release --arch arm64
    assemble_app_bundle "$(swift build -c release --arch arm64 --show-bin-path)" "$bundle_root"
    contents_dir="$bundle_root/Contents"
    record_real_sdk_version "$contents_dir/MacOS/HousekeeperApp"
    verify_design_sdk "$contents_dir/MacOS/HousekeeperApp"
    compile_icon "$contents_dir/Resources"
    write_info_plist "$contents_dir" "$version_number" "$icon_keys"'
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>'

    if [[ "$sign_requested" == true ]]; then
      xattr -cr "$bundle_root"
      codesign --force --deep --options runtime --timestamp \
        --entitlements "$entitlements_path" --sign "$code_sign_identity" "$bundle_root"
      codesign --verify --deep --strict --verbose=2 "$bundle_root"
      if [[ "$notarize_requested" == true ]]; then
        notarize_and_staple "$bundle_root"
      fi
    fi

    mkdir -p "$dist_dir"
    rm -rf "$dist_dir/Housekeeper.app" "$dist_dir/Housekeeper.zip"
    /usr/bin/ditto --noextattr --noqtn "$bundle_root" "$dist_dir/Housekeeper.app"
    /usr/bin/ditto -c -k --keepParent "$dist_dir/Housekeeper.app" "$dist_dir/Housekeeper.zip"
    echo "Created $dist_dir/Housekeeper.zip"
    ;;

  *)
    usage
    exit 1
    ;;
esac
