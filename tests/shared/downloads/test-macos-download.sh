#!/usr/bin/env bash
# Shared characterization test for the active macOS download workflow.
#
# This test covers:
# - help output and argument handling
# - parsing Apple's official macOS IPSW catalog for direct ARM downloads
# - parsing official softwareupdate full-installer listings for ARM and X86 downloads
# - grouping macOS download options by ARM and X86 sections
# - marking only officially downloadable entries as selectable
# - downloading either a chosen IPSW or a chosen full installer
# - documentation headers for the macOS download script and test file
#
# It uses a temporary fake repo plus stubbed source files and commands so
# behavior can be verified without depending on live Apple network responses.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_SOURCE="$ROOT/scripts/macos/downloads/macos-download"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file_path="$1"
  local expected="$2"
  local message="$3"

  if ! grep -Fq -- "$expected" "$file_path"; then
    printf 'Expected to find: %s\n' "$expected" >&2
    fail "$message"
  fi
}

assert_not_contains() {
  local file_path="$1"
  local unexpected="$2"
  local message="$3"

  if grep -Fq -- "$unexpected" "$file_path"; then
    printf 'Did not expect to find: %s\n' "$unexpected" >&2
    fail "$message"
  fi
}

assert_matches() {
  local file_path="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -Eq -- "$pattern" "$file_path"; then
    printf 'Expected to match: %s\n' "$pattern" >&2
    fail "$message"
  fi
}

selector_for_output_line() {
  local file_path="$1"
  local pattern="$2"
  local selector

  selector="$(grep -E -- "$pattern" "$file_path" | sed -E 's/^([0-9]+)\..*/\1/' | sed -n '1p')"
  [[ -n "$selector" ]] || fail "could not resolve selector for pattern: $pattern"
  printf '%s\n' "$selector"
}

assert_starts_with_comment() {
  local file_path="$1"
  local message="$2"
  local first_non_shebang

  first_non_shebang="$(grep -v '^#!' "$file_path" | grep -v '^[[:space:]]*$' | sed -n '1p')"
  case "$first_non_shebang" in
    \#*|\\#*) return 0 ;;
  esac
  fail "$message"
}

make_fake_repo() {
  local temp_dir="$1"

  mkdir -p \
    "$temp_dir/scripts/macos/downloads" \
    "$temp_dir/libs/shared/shared" \
    "$temp_dir/configs/shared/shared" \
    "$temp_dir/configs/macos/downloads" \
    "$temp_dir/fake-bin"
  cp "$SCRIPT_SOURCE" "$temp_dir/scripts/macos/downloads/macos-download"
  cp "$ROOT/libs/shared/shared/common.sh" "$temp_dir/libs/shared/shared/common.sh"
  cp "$ROOT/configs/shared/shared/logging-shared.conf" "$temp_dir/configs/shared/shared/logging-shared.conf"
  cp "$ROOT/configs/macos/downloads/macos-download-shared.conf" "$temp_dir/configs/macos/downloads/macos-download-shared.conf"
  chmod +x "$temp_dir/scripts/macos/downloads/macos-download"
}

write_catalog_sample() {
  local path="$1"

  cat > "$path" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>MobileDeviceSoftwareVersionsByVersion</key>
  <dict>
    <key>1</key>
    <dict>
      <key>MobileDeviceSoftwareVersions</key>
      <dict>
        <key>VirtualMac2,1</key>
        <dict>
          <key>25E253</key>
          <dict>
            <key>Restore</key>
            <dict>
              <key>BuildVersion</key>
              <string>25E253</string>
              <key>FirmwareURL</key>
              <string>https://updates.cdn-apple.com/2026Spring/fullrestores/111-11111/AAAA/UniversalMac_26.4.1_25E253_Restore.ipsw</string>
              <key>ProductVersion</key>
              <string>26.4.1</string>
            </dict>
          </dict>
        </dict>
        <key>Macmini9,1</key>
        <dict>
          <key>25E253</key>
          <dict>
            <key>Restore</key>
            <dict>
              <key>BuildVersion</key>
              <string>25E253</string>
              <key>FirmwareURL</key>
              <string>https://updates.cdn-apple.com/2026Spring/fullrestores/111-11111/AAAA/UniversalMac_26.4.1_25E253_Restore.ipsw</string>
              <key>ProductVersion</key>
              <string>26.4.1</string>
            </dict>
          </dict>
        </dict>
        <key>MacBookAir10,1</key>
        <dict>
          <key>25D125</key>
          <dict>
            <key>Restore</key>
            <dict>
              <key>BuildVersion</key>
              <string>25D125</string>
              <key>FirmwareURL</key>
              <string>https://updates.cdn-apple.com/2026Winter/fullrestores/122-22222/BBBB/UniversalMac_26.3_25D125_Restore.ipsw</string>
              <key>ProductVersion</key>
              <string>26.3</string>
            </dict>
          </dict>
        </dict>
        <key>Mac-7BA5B2DFE22DDD8C</key>
        <dict>
          <key>22H123</key>
          <dict>
            <key>Restore</key>
            <dict>
              <key>BuildVersion</key>
              <string>22H123</string>
              <key>FirmwareURL</key>
              <string>https://updates.cdn-apple.com/2024Example/fullrestores/333-33333/CCCC/IntelMac_13.7.4_22H123_Restore.ipsw</string>
              <key>ProductVersion</key>
              <string>13.7.4</string>
            </dict>
          </dict>
        </dict>
        <key>MacBookPro16,1</key>
        <dict>
          <key>22H124</key>
          <dict>
            <key>Restore</key>
            <dict>
              <key>BuildVersion</key>
              <string>22H124</string>
              <key>FirmwareURL</key>
              <string>https://updates.cdn-apple.com/2024Example/fullrestores/333-33333/DDDD/IntelMac_13.7.5_22H124_Restore.ipsw</string>
              <key>ProductVersion</key>
              <string>13.7.5</string>
            </dict>
          </dict>
        </dict>
      </dict>
    </dict>
  </dict>
</dict>
</plist>
EOF
}

write_same_version_build_catalog_sample() {
  local path="$1"

  cat > "$path" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>MobileDeviceSoftwareVersionsByVersion</key>
  <dict>
    <key>1</key>
    <dict>
      <key>MobileDeviceSoftwareVersions</key>
      <dict>
        <key>VirtualMac2,1</key>
        <dict>
          <key>25A99</key>
          <dict>
            <key>Restore</key>
            <dict>
              <key>BuildVersion</key>
              <string>25A99</string>
              <key>FirmwareURL</key>
              <string>https://updates.cdn-apple.com/example/UniversalMac_26.1_25A99_Restore.ipsw</string>
              <key>ProductVersion</key>
              <string>26.1</string>
            </dict>
          </dict>
          <key>25A100</key>
          <dict>
            <key>Restore</key>
            <dict>
              <key>BuildVersion</key>
              <string>25A100</string>
              <key>FirmwareURL</key>
              <string>https://updates.cdn-apple.com/example/UniversalMac_26.1_25A100_Restore.ipsw</string>
              <key>ProductVersion</key>
              <string>26.1</string>
            </dict>
          </dict>
        </dict>
      </dict>
    </dict>
  </dict>
</dict>
</plist>
EOF
}

write_command_stub() {
  local path="$1"
  local body="$2"

  printf '%s\n' "$body" > "$path"
  chmod +x "$path"
}

setup_common_stubs() {
  local temp_dir="$1"
  local fake_bin="$temp_dir/fake-bin"

  write_command_stub "$fake_bin/uname" '#!/usr/bin/env bash
printf "%s\n" "${TEST_UNAME:-Darwin}"'

  write_command_stub "$fake_bin/curl" '#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/curl.log"

if [[ "$1" == "-fsSL" ]]; then
  /bin/cat "${TEST_CATALOG_FILE:?}"
  exit 0
fi

if [[ "$1" == "-fL" && "$2" == "-o" ]]; then
  printf "%s\n" "$4" > "$3"
  exit 0
fi

exit 1'

  write_command_stub "$fake_bin/softwareupdate" '#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/softwareupdate.log"

if [[ "$1" == "--list-full-installers" ]]; then
  printf "%s\n" "* Title: macOS Tahoe, Version: 26.4.1, Size: 20485760KiB, Build: 25E253, Deferred: NO" "* Title: macOS Tahoe, Version: 26.3, Size: 20100000KiB, Build: 25D125, Deferred: NO" "* Title: macOS Sonoma, Version: 14.8.5, Size: 14000000KiB, Build: 23J423, Deferred: NO" "* Title: macOS Monterey, Version: 12.7.6, Size: 12000000KiB, Build: 21H1320, Deferred: NO"
  exit 0
fi

if [[ "$1" == "--fetch-full-installer" ]]; then
  printf "%s\n" "$*" > "$STATE_DIR/fetched-installer.log"
  exit 0
fi

exit 1'
}

write_download_config() {
  local temp_dir="$1"
  local download_dir_relative="${2:-downloads/macos/downloads}"

  cat > "$temp_dir/configs/macos/downloads/macos-download-shared.conf" <<EOF
# Shared macOS download runtime defaults for all account names.
MACOS_DOWNLOAD_CATALOG_URL="https://mesu.apple.com/assets/macos/com_apple_macOSIPSW/com_apple_macOSIPSW.xml"
MACOS_DOWNLOAD_DIR_RELATIVE="$download_dir_relative"
MACOS_DOWNLOAD_ARM_SECTION_LABEL="ARM"
MACOS_DOWNLOAD_X86_SECTION_LABEL="X86"
MACOS_DOWNLOAD_IPSW_LABEL="Apple Silicon Mac restore image"
MACOS_DOWNLOAD_INSTALLER_LABEL="macOS full installer"
MACOS_DOWNLOAD_ARM_INSTALLER_MIN_VERSION="11.0"
MACOS_DOWNLOAD_IPSW_ARTIFACT_TOKEN="IPSW"
MACOS_DOWNLOAD_INSTALLER_ARTIFACT_TOKEN="Installer"
MACOS_DOWNLOAD_STATUS_AVAILABLE="Download available"
MACOS_DOWNLOAD_STATUS_UNAVAILABLE="Download unavailable"
MACOS_DOWNLOAD_SELECTION_PROMPT="Select a downloadable item, or q to quit: "
MACOS_DOWNLOAD_QUIT_TOKEN="q"
MACOS_DOWNLOAD_WARNING_NO_DOWNLOADS="WARNING: No official Apple macOS downloads are currently available."
MACOS_DOWNLOAD_WARNING_NO_SELECTION="WARNING: No selection received. Exiting."
MACOS_DOWNLOAD_ERROR_INVALID_SELECTION="ERROR: Invalid selection."
MACOS_DOWNLOAD_SUCCESS_IPSW_PREFIX="Downloaded"
MACOS_DOWNLOAD_SUCCESS_INSTALLER_PREFIX="Requested installer"
MACOS_DOWNLOAD_INSTALLER_DESTINATION_NOTE="softwareupdate chooses the final installer location."
EOF
}

write_download_config_with_custom_runtime_text() {
  local temp_dir="$1"

  cat > "$temp_dir/configs/macos/downloads/macos-download-shared.conf" <<'EOF'
# Shared macOS download runtime defaults for all account names.
MACOS_DOWNLOAD_CATALOG_URL="https://mesu.apple.com/assets/macos/com_apple_macOSIPSW/com_apple_macOSIPSW.xml"
MACOS_DOWNLOAD_DIR_RELATIVE="downloads/macos/downloads"
MACOS_DOWNLOAD_ARM_SECTION_LABEL="Apple Silicon"
MACOS_DOWNLOAD_X86_SECTION_LABEL="Intel"
MACOS_DOWNLOAD_IPSW_LABEL="Restore image"
MACOS_DOWNLOAD_INSTALLER_LABEL="Full installer"
MACOS_DOWNLOAD_ARM_INSTALLER_MIN_VERSION="11.0"
MACOS_DOWNLOAD_IPSW_ARTIFACT_TOKEN="Restore"
MACOS_DOWNLOAD_INSTALLER_ARTIFACT_TOKEN="Installer package"
MACOS_DOWNLOAD_STATUS_AVAILABLE="Ready"
MACOS_DOWNLOAD_STATUS_UNAVAILABLE="Hidden"
MACOS_DOWNLOAD_SELECTION_PROMPT="Choose an item, or leave with x: "
MACOS_DOWNLOAD_QUIT_TOKEN="x"
MACOS_DOWNLOAD_WARNING_NO_DOWNLOADS="WARNING: No Apple downloads found."
MACOS_DOWNLOAD_WARNING_NO_SELECTION="WARNING: No choice received. Leaving."
MACOS_DOWNLOAD_ERROR_INVALID_SELECTION="ERROR: Pick a valid item."
MACOS_DOWNLOAD_SUCCESS_IPSW_PREFIX="Saved"
MACOS_DOWNLOAD_SUCCESS_INSTALLER_PREFIX="Queued installer"
MACOS_DOWNLOAD_INSTALLER_DESTINATION_NOTE="softwareupdate decides the final installer location."
EOF
}

test_help_output() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_download_config "$temp_dir"

  if ! "$temp_dir/scripts/macos/downloads/macos-download" --help > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should show help successfully'
  fi

  assert_contains "$output_file" 'Usage: macos-download' 'shows macos-download help usage'
  assert_contains "$output_file" 'IPSW' 'documents IPSW artifact type'
  assert_contains "$output_file" 'Installer' 'documents installer artifact type'
}

test_rejects_positional_arguments() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_download_config "$temp_dir"

  if "$temp_dir/scripts/macos/downloads/macos-download" unexpected > "$output_file" 2>&1; then
    fail 'macos-download should fail when given positional arguments'
  fi

  assert_contains "$output_file" 'ERROR: macos-download takes no arguments. Use --help for usage.' 'macos-download should use the aligned invalid-argument message'
}

test_requires_macos() {
  local temp_dir
  local output_file
  local catalog_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir"
  mkdir -p "$temp_dir/state"

  if printf 'q\n' | TEST_UNAME=Linux TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    fail 'macos-download should fail outside macOS'
  fi

  assert_contains "$output_file" 'ERROR: This script is for macOS only' 'macos-download should fail with a clear macOS-only message'
}

test_honours_configured_section_labels() {
  local temp_dir
  local output_file
  local catalog_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  mkdir -p "$temp_dir/state"

  cat > "$temp_dir/configs/macos/downloads/macos-download-shared.conf" <<'EOF'
# Shared macOS download runtime defaults for all account names.
MACOS_DOWNLOAD_CATALOG_URL="https://mesu.apple.com/assets/macos/com_apple_macOSIPSW/com_apple_macOSIPSW.xml"
MACOS_DOWNLOAD_DIR_RELATIVE="downloads/macos/downloads"
MACOS_DOWNLOAD_ARM_SECTION_LABEL="Apple Silicon"
MACOS_DOWNLOAD_X86_SECTION_LABEL="Intel"
MACOS_DOWNLOAD_IPSW_LABEL="Apple Silicon Mac restore image"
MACOS_DOWNLOAD_INSTALLER_LABEL="macOS full installer"
MACOS_DOWNLOAD_ARM_INSTALLER_MIN_VERSION="11.0"
MACOS_DOWNLOAD_IPSW_ARTIFACT_TOKEN="IPSW"
MACOS_DOWNLOAD_INSTALLER_ARTIFACT_TOKEN="Installer"
MACOS_DOWNLOAD_STATUS_AVAILABLE="Download available"
MACOS_DOWNLOAD_STATUS_UNAVAILABLE="Download unavailable"
MACOS_DOWNLOAD_SELECTION_PROMPT="Select a downloadable item, or q to quit: "
MACOS_DOWNLOAD_QUIT_TOKEN="q"
MACOS_DOWNLOAD_WARNING_NO_DOWNLOADS="WARNING: No official Apple macOS downloads are currently available."
MACOS_DOWNLOAD_WARNING_NO_SELECTION="WARNING: No selection received. Exiting."
MACOS_DOWNLOAD_ERROR_INVALID_SELECTION="ERROR: Invalid selection."
MACOS_DOWNLOAD_SUCCESS_IPSW_PREFIX="Downloaded"
MACOS_DOWNLOAD_SUCCESS_INSTALLER_PREFIX="Requested installer"
MACOS_DOWNLOAD_INSTALLER_DESTINATION_NOTE="softwareupdate chooses the final installer location."
EOF

  if ! printf 'q\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should respect configured section labels'
  fi

  assert_contains "$output_file" 'Apple Silicon' 'prints configured ARM section label'
  assert_contains "$output_file" 'Intel' 'prints configured X86 section label'
  assert_not_contains "$output_file" 'Traceback' 'configured labels should not break installer grouping'
}

test_honours_configured_operational_text() {
  local temp_dir
  local output_file
  local listing_file
  local catalog_file
  local selector

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  listing_file="$temp_dir/listing.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config_with_custom_runtime_text "$temp_dir"
  mkdir -p "$temp_dir/state"

  if ! printf 'x\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$listing_file" 2>&1; then
    cat "$listing_file" >&2
    fail 'macos-download should honour configured listing text and quit token'
  fi

  assert_contains "$listing_file" 'Apple Silicon' 'prints configured ARM section label'
  assert_contains "$listing_file" 'Intel' 'prints configured X86 section label'
  assert_matches "$listing_file" '^[0-9]+\. 26\.4\.1 \(25E253\) \| Restore \| Restore image \| Ready$' 'prints configured IPSW artifact token and status'
  assert_matches "$listing_file" '^[0-9]+\. 26\.4\.1 \| Installer package \| Full installer \| Ready$' 'prints configured installer artifact token and status'
  assert_contains "$listing_file" 'Choose an item, or leave with x: ' 'prints configured selection prompt'

  selector="$(selector_for_output_line "$listing_file" '^[0-9]+\. 26\.4\.1 \(25E253\) \| Restore \| Restore image \| Ready$')"

  if ! printf '99\n%s\n' "$selector" | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should honour configured invalid-selection and success text'
  fi

  assert_contains "$output_file" 'ERROR: Pick a valid item.' 'prints configured invalid-selection error'
  assert_contains "$output_file" 'Saved 26.4.1 (25E253)' 'prints configured IPSW success prefix'
}

test_lists_ipsw_and_installers_by_architecture() {
  local temp_dir
  local output_file
  local catalog_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir"
  mkdir -p "$temp_dir/state"

  if ! printf 'q\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should allow quitting after listing entries'
  fi

  assert_contains "$output_file" 'ARM' 'prints ARM section'
  assert_contains "$output_file" 'X86' 'prints X86 section'
  assert_matches "$output_file" '^[0-9]+\. 26\.4\.1 \(25E253\) \| IPSW \| Apple Silicon Mac restore image \| Download available$' 'lists newest ARM IPSW entry'
  assert_matches "$output_file" '^[0-9]+\. 26\.4\.1 \| Installer \| macOS full installer \| Download available$' 'lists newest ARM installer entry'
  assert_matches "$output_file" '^[0-9]+\. 26\.3 \(25D125\) \| IPSW \| Apple Silicon Mac restore image \| Download available$' 'lists older ARM IPSW entry'
  assert_matches "$output_file" '^[0-9]+\. 26\.3 \| Installer \| macOS full installer \| Download available$' 'lists older ARM installer entry'
  assert_matches "$output_file" '^[0-9]+\. 14\.8\.5 \| Installer \| macOS full installer \| Download available$' 'lists Ventura-and-later installer coverage'
  assert_matches "$output_file" '^[0-9]+\. 12\.7\.6 \| Installer \| macOS full installer \| Download available$' 'lists Monterey installer coverage'
  assert_not_contains "$output_file" '13.7.4 (22H123) | IPSW' 'does not show non-actionable Intel IPSW rows in default output'
  assert_not_contains "$output_file" '13.7.5 (22H124) | IPSW' 'does not show comma-style Intel model IPSW rows in default output'
  assert_not_contains "$output_file" 'Intel Mac restore image' 'does not show non-actionable Intel IPSW rows in default output'
}

test_does_not_require_pmv_feed() {
  local temp_dir
  local output_file
  local catalog_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir"
  mkdir -p "$temp_dir/state"

  if ! printf 'q\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should not depend on the PMV feed when listing actionable downloads'
  fi

  assert_contains "$output_file" 'ARM' 'still lists downloads without PMV data'
  assert_not_contains "$output_file" 'Traceback' 'pmv-free path should stay clean'
}

test_downloads_selected_ipsw() {
  local temp_dir
  local output_file
  local catalog_file
  local download_target
  local selector

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  download_target="$temp_dir/26.4.1-25E253.ipsw"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir" 'ipsw-downloads'
  mkdir -p "$temp_dir/state"

  if ! printf 'q\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$temp_dir/listing.log" 2>&1; then
    cat "$temp_dir/listing.log" >&2
    fail 'macos-download should allow listing IPSW choices before selection'
  fi

  selector="$(selector_for_output_line "$temp_dir/listing.log" '^[0-9]+\. 26\.4\.1 \(25E253\) \| IPSW \| Apple Silicon Mac restore image \| Download available$')"

  if ! printf '%s\n' "$selector" | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should download the selected IPSW item'
  fi

  assert_contains "$temp_dir/state/curl.log" '-fL -o' 'uses curl download mode for selected IPSW entry'
  assert_contains "$temp_dir/state/curl.log" 'https://updates.cdn-apple.com/2026Spring/fullrestores/111-11111/AAAA/UniversalMac_26.4.1_25E253_Restore.ipsw' 'downloads the official Apple IPSW URL'
  assert_contains "$output_file" 'Downloaded 26.4.1 (25E253)' 'reports successful IPSW download'
  assert_contains "$temp_dir/ipsw-downloads/26.4.1-25E253.ipsw" 'https://updates.cdn-apple.com/2026Spring/fullrestores/111-11111/AAAA/UniversalMac_26.4.1_25E253_Restore.ipsw' 'writes downloaded IPSW content to target file in test stub'
}

test_defaults_ipsw_downloads_to_repo_downloads_dir() {
  local temp_dir
  local output_file
  local catalog_file
  local download_target
  local selector

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  download_target="$temp_dir/downloads/macos/downloads/26.4.1-25E253.ipsw"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir"
  mkdir -p "$temp_dir/state"

  if ! printf 'q\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$temp_dir/listing.log" 2>&1; then
    cat "$temp_dir/listing.log" >&2
    fail 'macos-download should allow listing IPSW choices before default-path selection'
  fi

  selector="$(selector_for_output_line "$temp_dir/listing.log" '^[0-9]+\. 26\.4\.1 \(25E253\) \| IPSW \| Apple Silicon Mac restore image \| Download available$')"

  if ! printf '%s\n' "$selector" | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should default IPSW downloads into the repo downloads directory'
  fi

  assert_contains "$output_file" "$download_target" 'reports the repo downloads target path'
  assert_contains "$download_target" 'https://updates.cdn-apple.com/2026Spring/fullrestores/111-11111/AAAA/UniversalMac_26.4.1_25E253_Restore.ipsw' 'writes the IPSW into the repo downloads directory'
}

test_does_not_create_default_download_dir_when_listing_only() {
  local temp_dir
  local output_file
  local catalog_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir"
  mkdir -p "$temp_dir/state"

  if ! printf 'q\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should allow quitting after listing entries'
  fi

  if [[ -d "$temp_dir/downloads/macos/downloads" ]]; then
    fail 'macos-download should not create the default downloads directory when only listing entries'
  fi
}

test_downloads_selected_installer() {
  local temp_dir
  local output_file
  local listing_file
  local catalog_file
  local selector

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  listing_file="$temp_dir/listing.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir"
  mkdir -p "$temp_dir/state"

  if ! printf 'q\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$listing_file" 2>&1; then
    cat "$listing_file" >&2
    fail 'macos-download should allow listing installer choices before selection'
  fi

  selector="$(selector_for_output_line "$listing_file" '^[0-9]+\. 14\.8\.5 \| Installer \| macOS full installer \| Download available$')"

  if ! printf '%s\n' "$selector" | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should fetch the selected installer item'
  fi

  assert_contains "$temp_dir/state/softwareupdate.log" '--fetch-full-installer --full-installer-version 14.8.5' 'uses softwareupdate fetch for selected installer entry'
  assert_contains "$output_file" 'Requested installer 14.8.5' 'reports successful installer fetch request'
  assert_contains "$output_file" 'softwareupdate chooses the final installer location.' 'clarifies installer destination ownership'
}

test_honours_configured_installer_success_text() {
  local temp_dir
  local output_file
  local listing_file
  local catalog_file
  local selector

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  listing_file="$temp_dir/listing.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config_with_custom_runtime_text "$temp_dir"
  mkdir -p "$temp_dir/state"

  if ! printf 'x\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$listing_file" 2>&1; then
    cat "$listing_file" >&2
    fail 'macos-download should allow listing installer choices with custom text before selection'
  fi

  selector="$(selector_for_output_line "$listing_file" '^[0-9]+\. 14\.8\.5 \| Installer package \| Full installer \| Ready$')"

  if ! printf '%s\n' "$selector" | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should honour configured installer success text'
  fi

  assert_contains "$output_file" 'Queued installer 14.8.5' 'prints configured installer success prefix'
  assert_contains "$output_file" 'softwareupdate decides the final installer location.' 'prints configured installer destination note'
}

test_reprompts_after_invalid_selection() {
  local temp_dir
  local output_file
  local catalog_file
  local download_target
  local listing_file
  local selector

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  download_target="$temp_dir/26.4.1-25E253.ipsw"
  listing_file="$temp_dir/listing.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir" 'ipsw-downloads'
  mkdir -p "$temp_dir/state"

  if ! printf 'q\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$listing_file" 2>&1; then
    cat "$listing_file" >&2
    fail 'macos-download should allow listing IPSW choices before retry selection'
  fi

  selector="$(selector_for_output_line "$listing_file" '^[0-9]+\. 26\.4\.1 \(25E253\) \| IPSW \| Apple Silicon Mac restore image \| Download available$')"

  if ! printf '99\n%s\n' "$selector" | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should re-prompt and then accept a valid selection'
  fi

  assert_contains "$output_file" 'ERROR: Invalid selection.' 'shows an error for invalid selection'
  assert_contains "$output_file" 'Downloaded 26.4.1 (25E253)' 'continues to a successful download after retry'
  assert_contains "$temp_dir/ipsw-downloads/26.4.1-25E253.ipsw" 'https://updates.cdn-apple.com/2026Spring/fullrestores/111-11111/AAAA/UniversalMac_26.4.1_25E253_Restore.ipsw' 'downloads the selected IPSW after retry'
}

test_exits_cleanly_on_eof() {
  local temp_dir
  local output_file
  local catalog_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir"
  mkdir -p "$temp_dir/state"

  if ! TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" < /dev/null > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should exit cleanly when stdin closes before selection'
  fi

  assert_not_contains "$output_file" 'Traceback' 'EOF should not print a Python traceback'
  assert_contains "$output_file" 'WARNING: No selection received. Exiting.' 'prints configured EOF warning'
}

test_sorts_same_version_builds_newest_first() {
  local temp_dir
  local output_file
  local catalog_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_same_version_build_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir"
  mkdir -p "$temp_dir/state"

  if ! printf 'q\n' | TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'macos-download should sort same-version builds without error'
  fi

  if [[ "$(grep -n '26.1 (25A100) | IPSW' "$output_file" | cut -d: -f1)" -ge "$(grep -n '26.1 (25A99) | IPSW' "$output_file" | cut -d: -f1)" ]]; then
    fail 'macos-download should sort newer same-version builds before older ones'
  fi
}

test_documentation_headers() {
  assert_starts_with_comment "$ROOT/scripts/macos/downloads/macos-download" 'macos download script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/downloads/test-macos-download.sh" 'macos download test should start with a header comment after shebang'
}

test_requires_download_config_file() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  mkdir -p "$temp_dir/state"
  rm -f "$temp_dir/configs/macos/downloads/macos-download-shared.conf"

  if TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    fail 'macos-download should fail when the required download config file is missing'
  fi

  assert_contains "$output_file" 'ERROR: Required config not found:' 'download workflow should fail clearly when the config file is missing'
}

test_requires_download_config_values_from_config_file() {
  local temp_dir
  local output_file
  local catalog_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  catalog_file="$temp_dir/catalog.xml"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_catalog_sample "$catalog_file"
  setup_common_stubs "$temp_dir"
  mkdir -p "$temp_dir/state"

  cat > "$temp_dir/configs/macos/downloads/macos-download-shared.conf" <<'EOF'
# Shared macOS download runtime defaults for all account names.
MACOS_DOWNLOAD_CATALOG_URL="https://mesu.apple.com/assets/macos/com_apple_macOSIPSW/com_apple_macOSIPSW.xml"
MACOS_DOWNLOAD_ARM_SECTION_LABEL="ARM"
MACOS_DOWNLOAD_X86_SECTION_LABEL="X86"
MACOS_DOWNLOAD_IPSW_LABEL="Apple Silicon Mac restore image"
MACOS_DOWNLOAD_INSTALLER_LABEL="macOS full installer"
MACOS_DOWNLOAD_ARM_INSTALLER_MIN_VERSION="11.0"
MACOS_DOWNLOAD_IPSW_ARTIFACT_TOKEN="IPSW"
MACOS_DOWNLOAD_INSTALLER_ARTIFACT_TOKEN="Installer"
MACOS_DOWNLOAD_STATUS_AVAILABLE="Download available"
MACOS_DOWNLOAD_STATUS_UNAVAILABLE="Download unavailable"
MACOS_DOWNLOAD_SELECTION_PROMPT="Select a downloadable item, or q to quit: "
MACOS_DOWNLOAD_QUIT_TOKEN="q"
MACOS_DOWNLOAD_WARNING_NO_DOWNLOADS="WARNING: No official Apple macOS downloads are currently available."
MACOS_DOWNLOAD_WARNING_NO_SELECTION="WARNING: No selection received. Exiting."
MACOS_DOWNLOAD_ERROR_INVALID_SELECTION="ERROR: Invalid selection."
MACOS_DOWNLOAD_SUCCESS_IPSW_PREFIX="Downloaded"
MACOS_DOWNLOAD_SUCCESS_INSTALLER_PREFIX="Requested installer"
MACOS_DOWNLOAD_INSTALLER_DESTINATION_NOTE="softwareupdate chooses the final installer location."
EOF

  if MACOS_DOWNLOAD_DIR_RELATIVE='downloads/macos/downloads' TEST_CATALOG_FILE="$catalog_file" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    fail 'macos-download should fail when a required config value is missing from the config file even if exported in the environment'
  fi

  assert_contains "$output_file" 'ERROR: Required config value is not set: MACOS_DOWNLOAD_DIR_RELATIVE' 'download workflow should require config values to come from the config file itself'
}

test_cleans_up_temp_files_when_setup_fails() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_download_config "$temp_dir"
  mkdir -p "$temp_dir/state" "$temp_dir/tmp"

  write_command_stub "$temp_dir/fake-bin/mktemp" '#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${TEST_STATE_DIR:?}"
count_file="$STATE_DIR/mktemp-count"
count=0
if [[ -f "$count_file" ]]; then
  count="$(/bin/cat "$count_file")"
fi
count=$((count + 1))
printf "%s\n" "$count" > "$count_file"

if [[ "$count" -eq 1 ]]; then
  path="${TMPDIR:?}/macos-download-test-1"
  : > "$path"
  printf "%s\n" "$path"
  exit 0
fi

exit 1'

  if TMPDIR="$temp_dir/tmp" TEST_STATE_DIR="$temp_dir/state" PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/downloads/macos-download" > "$output_file" 2>&1; then
    fail 'macos-download should fail when temporary file setup fails'
  fi

  assert_not_contains "$output_file" 'Traceback' 'temp-file setup failure should stay in shell error handling'
  if [[ -n "$(ls -A "$temp_dir/tmp")" ]]; then
    fail 'macos-download should clean up temporary files when setup fails after creating an earlier temp file'
  fi
}

test_help_output
test_rejects_positional_arguments
test_requires_macos
test_honours_configured_section_labels
test_honours_configured_operational_text
test_lists_ipsw_and_installers_by_architecture
test_does_not_require_pmv_feed
test_downloads_selected_ipsw
test_defaults_ipsw_downloads_to_repo_downloads_dir
test_does_not_create_default_download_dir_when_listing_only
test_downloads_selected_installer
test_honours_configured_installer_success_text
test_reprompts_after_invalid_selection
test_exits_cleanly_on_eof
test_sorts_same_version_builds_newest_first
test_documentation_headers
test_requires_download_config_file
test_requires_download_config_values_from_config_file
test_cleans_up_temp_files_when_setup_fails

printf 'PASS: tests/shared/downloads/test-macos-download.sh\n'
