#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
signing_identity="-"
if [[ -f .signing-identity ]]; then
  signing_identity="$(<.signing-identity)"
  if [[ ! "$signing_identity" =~ '^[[:xdigit:]]{40}$' ]]; then
    print -u2 -- "签名证书指纹无效，请检查 .signing-identity"
    exit 1
  fi
fi
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/BarFold.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/BarFold" "$app_path/Contents/MacOS/BarFold"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign "$signing_identity" --timestamp=none "$app_path"
codesign --verify --strict "$app_path"
if [[ "$signing_identity" != "-" ]]; then
  new_requirement="$(codesign -d -r- "$app_path" 2>&1 | sed -n 's/^designated => //p')"
  if [[ -z "$new_requirement" || "$new_requirement" == cdhash* ]]; then
    print -u2 -- "签名未生成稳定的应用身份，安装已停止"
    exit 1
  fi
  if [[ -d /Applications/BarFold.app ]]; then
    installed_requirement="$(codesign -d -r- /Applications/BarFold.app 2>&1 | sed -n 's/^designated => //p')"
    if [[ -n "$installed_requirement" && "$installed_requirement" != cdhash* && "$installed_requirement" != "$new_requirement" ]]; then
      print -u2 -- "签名身份与已安装版本不同，请检查证书配置"
      exit 1
    fi
  fi
else
  print -u2 -- "当前使用临时签名，重新构建后可能需要重新授权"
fi
print -r -- "$app_path"
