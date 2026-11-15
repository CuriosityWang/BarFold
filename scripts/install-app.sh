#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
zsh scripts/build-app.sh
python3 - "$PWD" <<'PY'
import os, pathlib, plistlib, signal, subprocess, sys, time
root = pathlib.Path(sys.argv[1])
target = pathlib.Path('/Applications/BarFold.app')
if target.exists():
    with (target/'Contents/Info.plist').open('rb') as file:
        if plistlib.load(file).get('CFBundleIdentifier') != 'local.barfold.app':
            raise SystemExit('目标位置已有其他应用，安装已停止。')
executables = {str(root/'dist/BarFold.app/Contents/MacOS/BarFold'), str(target/'Contents/MacOS/BarFold')}
for line in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) == 2 and parts[1] in executables:
        pid = int(parts[0])
        os.kill(pid, signal.SIGTERM)
        for _ in range(50):
            try: os.kill(pid, 0)
            except ProcessLookupError: break
            time.sleep(0.1)
        else: raise SystemExit('应用尚未退出，请退出后重新安装。')
subprocess.run(['ditto', str(root/'dist/BarFold.app'), str(target)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(target)], check=True)
os.utime(target, None)
subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-f', str(target)], check=True)
print(target)
PY
open /Applications/BarFold.app
