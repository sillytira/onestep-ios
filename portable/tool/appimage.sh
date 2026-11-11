#!/usr/bin/env bash
set -euo pipefail
mkdir -p release/OneStep.AppDir/usr
cp -a portable/build/linux/x64/release/bundle/. release/OneStep.AppDir/usr/
cp OneStep/Assets.xcassets/AppIcon.appiconset/AppIcon.png release/OneStep.AppDir/onestep.png
cat > release/OneStep.AppDir/onestep.desktop <<'EOF'
[Desktop Entry]
Name=OneStep
Exec=onestep
Icon=onestep
Type=Application
Categories=Office;Utility;
EOF
cat > release/OneStep.AppDir/AppRun <<'EOF'
#!/bin/sh
appdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$appdir/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$appdir/usr/onestep" "$@"
EOF
chmod +x release/OneStep.AppDir/AppRun
curl -fL --retry 3 https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-x86_64.AppImage -o build/appimagetool.AppImage
chmod +x build/appimagetool.AppImage
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 build/appimagetool.AppImage release/OneStep.AppDir release/OneStep-0.3.0-x86_64.AppImage
release/OneStep-0.3.0-x86_64.AppImage --appimage-extract >/dev/null
timeout 12s xvfb-run -a squashfs-root/AppRun > build/linux-smoke.log 2>&1 &
PID=$!
sleep 8
if ! kill -0 "$PID" 2>/dev/null; then cat build/linux-smoke.log; exit 1; fi
wait "$PID" || test "$?" = 124
sha256sum release/OneStep-0.3.0-x86_64.AppImage > release/OneStep-0.3.0-x86_64.AppImage.sha256
