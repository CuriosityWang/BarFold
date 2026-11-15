#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"

release_dir="$PWD/dist/release-v${version}"
stage_dir="$release_dir/stage"
app_path="$stage_dir/BarFold.app"

rm -rf "$release_dir"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

cp "$bin_dir/BarFold" "$app_path/Contents/MacOS/BarFold"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"

# Use clean ad-hoc signature for public distribution (never embed machine-local untrusted certs)
codesign --force --deep --sign - --timestamp=none "$app_path"
codesign --verify --strict "$app_path"

zip_path="$release_dir/BarFold-v${version}-macOS-arm64.zip"
dmg_path="$release_dir/BarFold-v${version}-macOS-arm64.dmg"
checksum_path="$release_dir/SHA256SUMS.txt"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

dmg_root="$release_dir/dmg-root"
mkdir -p "$dmg_root"
cp -R "$app_path" "$dmg_root/BarFold.app"
cp Resources/AppIcon.icns "$dmg_root/.VolumeIcon.icns"
ln -s /Applications "$dmg_root/Applications"
if xcrun -f SetFile >/dev/null 2>&1; then
  xcrun SetFile -a V "$dmg_root/.VolumeIcon.icns"
  xcrun SetFile -a C "$dmg_root"
fi

hdiutil create -volname "BarFold" \
  -srcfolder "$dmg_root" \
  -ov -format UDZO \
  "$dmg_path" >/dev/null

rm -rf "$stage_dir" "$dmg_root"

(
  cd "$release_dir"
  shasum -a 256 "$(basename "$dmg_path")" "$(basename "$zip_path")" > "$(basename "$checksum_path")"
)

print -r -- "Packaged release v${version}:"
ls -lh "$dmg_path" "$zip_path" "$checksum_path"
cat "$checksum_path"
