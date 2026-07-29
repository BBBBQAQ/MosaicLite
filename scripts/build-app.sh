#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
work_dir="$project_dir/work"
output_dir="$project_dir/outputs"
app_dir="$output_dir/MosaicLite.app"
asset_build_dir="$work_dir/compiled-assets"

mkdir -p \
  "$work_dir/swift-cache" \
  "$work_dir/swift-config" \
  "$work_dir/swift-security" \
  "$work_dir/release-build" \
  "$work_dir/module-cache" \
  "$asset_build_dir" \
  "$output_dir"

CLANG_MODULE_CACHE_PATH="$work_dir/module-cache" \
swift build \
  --disable-sandbox \
  --configuration release \
  --package-path "$project_dir" \
  --cache-path "$work_dir/swift-cache" \
  --config-path "$work_dir/swift-config" \
  --security-path "$work_dir/swift-security" \
  --scratch-path "$work_dir/release-build" \
  -Xswiftc -module-cache-path \
  -Xswiftc "$work_dir/module-cache"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$work_dir/release-build/release/MosaicLite" "$app_dir/Contents/MacOS/MosaicLite"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

xcrun actool \
  --compile "$asset_build_dir" \
  --platform macosx \
  --minimum-deployment-target 15.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$work_dir/asset-info.plist" \
  "$project_dir/Resources/Assets.xcassets"

cp "$asset_build_dir/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$asset_build_dir/Assets.car" "$app_dir/Contents/Resources/Assets.car"
chmod +x "$app_dir/Contents/MacOS/MosaicLite"
xattr -cr "$app_dir"
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true

codesign --force --deep --sign - "$app_dir"
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
echo "$app_dir"
