#!/bin/bash
# Sokki.dmg 를 만든다. 열면 Sokki 아이콘을 Applications 로 끌어 넣는 화면이 나온다.
#
#   ./make-dmg.sh                 build/Sokki.dmg
#   VERSION=0.2.0 ./make-dmg.sh   build/Sokki-0.2.0.dmg
#
# 서명: SOKGI_SIGN_ID 나 'Sokki Dev'/'Sokgi Dev' 인증서가 있으면 build.sh 가 그걸 쓴다.
# 애플 개발자 계정이 있으면 아래 NOTARIZE 절차를 켜서 "확인되지 않은 개발자" 경고를 없앨 수 있다.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/build/Sokki.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DIR/Info.plist")}"
DMG="$DIR/build/Sokki-$VERSION.dmg"
STAGE="$DIR/build/dmg-stage"

"$DIR/build.sh"

echo "▶ DMG 구성 중…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 처음 여는 사람을 위한 안내 (Gatekeeper 경고 대응)
cat > "$STAGE/처음 열 때 읽어주세요.txt" <<'TXT'
Sokki 설치

1. 왼쪽의 Sokki 를 오른쪽 Applications 폴더로 끌어 넣습니다.
2. 응용 프로그램 폴더에서 Sokki 를 엽니다.
3. "확인되지 않은 개발자" 경고가 뜨면:
   시스템 설정 > 개인정보 보호 및 보안 > 아래로 내려서 "그래도 열기" 를 누릅니다.
   (한 번만 하면 됩니다. 애플 공증을 받지 않은 앱이라 뜨는 안내입니다.)
4. 메뉴바 오른쪽에 파형 아이콘이 생기면 설치 끝. 마이크·음성 인식 권한을 물으면 허용해 주세요.
TXT

hdiutil create -volname "Sokki" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

# 공증: Developer ID 로 서명됐고 notarytool 프로필 'sokki' 가 있으면 자동으로 한다. NOTARIZE=0 으로 끌 수 있다.
#   프로필 저장(한 번): xcrun notarytool store-credentials sokki --apple-id <애플ID> --team-id <팀ID>
if [[ "${NOTARIZE:-1}" == "1" ]] \
   && codesign -dv "$APP" 2>&1 | grep -q "Developer ID Application" \
   && xcrun notarytool history --keychain-profile sokki >/dev/null 2>&1; then
  echo "▶ 공증 요청 중… (보통 1~5분)"
  xcrun notarytool submit "$DMG" --keychain-profile sokki --wait
  xcrun stapler staple "$DMG"
  echo "▶ 공증 완료 — 다른 맥에서 경고 없이 열립니다"
  spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | tail -1 || true
else
  echo "ℹ️  공증 생략 (Developer ID 서명 + notarytool 프로필 'sokki' 가 있어야 합니다)"
fi

echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
