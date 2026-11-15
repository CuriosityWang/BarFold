#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
test_dir=$(mktemp -d /Applications/BarFoldSmoke.XXXXXX)
export BARFOLD_TEST_PREFIX="local.barfold.fixture.$(uuidgen | tr '[:upper:]' '[:lower:]')."
cleanup() {
  pkill -TERM -f "^$test_dir/(visible|collapsed|hidden).app/Contents/MacOS/Fixture$" 2>/dev/null || true
  rm -rf -- "$test_dir"
}
trap cleanup EXIT INT TERM
xcrun swiftc Tests/NativeFixture/main.swift -o "$test_dir/Fixture"
python3 - "$test_dir" <<'PY'
import os, pathlib, plistlib, shutil, sys
root = pathlib.Path(sys.argv[1])
for name in ['visible', 'collapsed', 'hidden']:
    contents = root / (name + '.app') / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    shutil.copy2(root / 'Fixture', contents / 'MacOS/Fixture')
    with (contents / 'Info.plist').open('wb') as file:
        plistlib.dump(dict(CFBundleIdentifier=os.environ['BARFOLD_TEST_PREFIX']+name, CFBundleExecutable='Fixture', CFBundleName='BF '+name, CFBundlePackageType='APPL', LSUIElement=True), file)
PY
for fixture_name in visible collapsed hidden; do
  codesign --force --sign - "$test_dir/$fixture_name.app"
  open -n "$test_dir/$fixture_name.app"
done
xcrun clang -fobjc-arc -framework AppKit -framework ApplicationServices \
  -I Sources/MenuBarBridge/include Sources/MenuBarBridge/MenuBarBridge.m Tests/NativeSmoke/main.m -o "$test_dir/smoke"
"$test_dir/smoke"
