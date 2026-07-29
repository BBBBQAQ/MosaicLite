#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/outputs"
staging_dir="$project_dir/work/release-staging"
app_source="$output_dir/MosaicLite.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")"
app_name="MosaicLite-$version.app"
app_archive="$output_dir/MosaicLite-$version-macos.zip"
source_archive="$output_dir/MosaicLite-$version-source.zip"
checksum_file="$output_dir/SHA256SUMS.txt"

"$project_dir/scripts/build-app.sh"

rm -rf "$staging_dir"
mkdir -p "$staging_dir"
cp -R "$app_source" "$staging_dir/$app_name"
xattr -cr "$staging_dir/$app_name"
codesign --verify --deep --strict --verbose=2 "$staging_dir/$app_name"

rm -f "$app_archive" "$source_archive" "$checksum_file"
(
  cd "$staging_dir"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry "$app_archive" "$app_name"
)
(
  cd "$project_dir"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry "$source_archive" \
    Package.swift Sources Tests Resources scripts docs .github \
    README.md CHANGELOG.md CONTRIBUTING.md LICENSE \
    -x '*.DS_Store' '*/._*'
)

if unzip -Z1 "$app_archive" | grep -Eq '(^|/)\._'; then
  echo "错误：安装包中发现 AppleDouble 文件" >&2
  exit 1
fi

verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/mosaiclite-release.XXXXXX")"
trap 'rm -rf "$verify_dir"' EXIT
unzip -q "$app_archive" -d "$verify_dir"
codesign --verify --deep --strict --verbose=2 "$verify_dir/$app_name"

(
  cd "$output_dir"
  shasum -a 256 "$(basename "$app_archive")" "$(basename "$source_archive")" > "$checksum_file"
)

echo "$app_archive"
echo "$source_archive"
echo "$checksum_file"
