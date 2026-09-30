#!/usr/bin/env bash
# Google Play 업로드 키를 한 번만 만든다. todo.exe · diary.exe · ink.exe 세 앱이 같이 쓴다.
#
#   bash tool/setup_android_signing.sh
#
# 만드는 것 (모두 저장소 밖, 이 Mac 안에만):
#   ~/.isla0x/upload-keystore.jks          서명 키
#   ~/.isla0x/android-upload.properties    키 위치 · 비밀번호 (android/app/build.gradle.kts 가 읽음)
#
# 이 두 파일은 절대 GitHub 에 올리거나 남에게 보내지 마세요. 대신 USB · 클라우드 등에 따로 백업해 두세요.
# (잃어버려도 Play Console 에서 업로드 키 재설정을 요청할 수 있지만 며칠 걸린다)
set -euo pipefail

DIR="$HOME/.isla0x"
KEYSTORE="$DIR/upload-keystore.jks"
PROPS="$DIR/android-upload.properties"

if [ -f "$KEYSTORE" ] && [ -f "$PROPS" ]; then
  echo "이미 있어요: $KEYSTORE"
  echo "다시 만들 필요 없어요. 바로 flutter build appbundle 하면 돼요."
  exit 0
fi

# keytool 찾기: Java 가 깔려 있으면 그것, 없으면 Android Studio 에 들어 있는 것.
KEYTOOL=""
for k in \
  "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
  "$(/usr/libexec/java_home 2>/dev/null)/bin/keytool" \
  "$(command -v keytool 2>/dev/null || true)"; do
  if [ -n "$k" ] && [ -x "$k" ] && "$k" -help >/dev/null 2>&1; then KEYTOOL="$k"; break; fi
done
if [ -z "$KEYTOOL" ]; then
  echo "keytool 을 찾지 못했어요. Android Studio 를 먼저 설치하고 한 번 실행해 주세요."
  echo "  https://developer.android.com/studio"
  exit 1
fi

mkdir -p "$DIR"
chmod 700 "$DIR"

echo "Google Play 업로드 키 비밀번호를 정해 주세요 (6자 이상). 화면에는 안 보여요."
while true; do
  read -r -s -p "비밀번호: " PW; echo
  read -r -s -p "한 번 더: " PW2; echo
  if [ "${#PW}" -lt 6 ]; then echo "6자 이상이어야 해요."; continue; fi
  if [ "$PW" != "$PW2" ]; then echo "두 번 입력한 게 달라요."; continue; fi
  break
done

export ISLA0X_KS_PW="$PW"
# 인증서 이름에는 실명 대신 isla0x 만 넣는다.
"$KEYTOOL" -genkeypair -noprompt \
  -keystore "$KEYSTORE" -storetype PKCS12 \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=isla0x, O=isla0x, C=KR" \
  -storepass:env ISLA0X_KS_PW -keypass:env ISLA0X_KS_PW
unset ISLA0X_KS_PW

umask 077
cat > "$PROPS" <<PROPS
storePassword=${PW//\\/\\\\}
keyPassword=${PW//\\/\\\\}
keyAlias=upload
storeFile=$KEYSTORE
PROPS
chmod 600 "$PROPS" "$KEYSTORE"
unset PW PW2

echo
echo "✓ 업로드 키를 만들었어요: $KEYSTORE"
echo "  이제 각 앱 폴더에서: flutter build appbundle --release"
echo "  꼭 백업: ~/.isla0x 폴더를 통째로 (USB 등). GitHub 에는 절대 올리지 마세요."
