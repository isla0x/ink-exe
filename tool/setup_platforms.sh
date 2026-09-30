#!/usr/bin/env bash
# android/ ios/ 폴더가 없으면 만들고, 홈 화면에 보이는 앱 이름을 ink.exe 로 맞춘다.
# 이미 있는 파일은 건드리지 않는다. (flutter create 는 없는 파일만 만든다)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d ios ]; then
  flutter create --org com.isla0x --project-name ink_exe --platforms android,ios .
fi

MANIFEST=android/app/src/main/AndroidManifest.xml
if [ -f "$MANIFEST" ]; then
  sed -i.bak 's/android:label="[^"]*"/android:label="ink.exe"/' "$MANIFEST"
  rm -f "$MANIFEST.bak"
fi

PLIST=ios/Runner/Info.plist
if [ -f "$PLIST" ]; then
  sed -i.bak '/<key>CFBundleDisplayName<\/key>/{n;s/<string>.*<\/string>/<string>ink.exe<\/string>/;}' "$PLIST"
  rm -f "$PLIST.bak"
fi

echo "platform folders ready."
