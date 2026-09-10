#!/bin/bash
# Sokki.dmg 를 만든다. 열면 배경 그림 위에 Sokki 아이콘(왼쪽)과 Applications(오른쪽)이 화살표로 이어진 화면이 나온다.
# 배경은 앱이 그린다(--render-dmg-background). 아이콘 위치는 Finder 로 심으므로 터미널에 Finder 자동화 권한이 필요하다.
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
RW="$DIR/build/Sokki-$VERSION-rw.dmg"
STAGE="$DIR/build/dmg-stage"

"$DIR/build.sh"

echo "▶ DMG 구성 중…"
# 이전에 열어 둔 Sokki 볼륨이 남아 있으면 새 이미지가 "Sokki 1" 로 붙고 Finder 배치가 엉뚱한 볼륨을 잡아 조용히 실패한다.
if [[ -d /Volumes/Sokki ]]; then
  echo "▶ 남아 있던 /Volumes/Sokki 를 먼저 내립니다"
  hdiutil detach /Volumes/Sokki -quiet || hdiutil detach /Volumes/Sokki -force -quiet || true
fi
rm -rf "$STAGE" "$DMG" "$RW"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
"$APP/Contents/MacOS/Sokki" --render-dmg-background "$STAGE/.background/bg.png" >/dev/null

# 읽기·쓰기 이미지로 만들어 Finder 로 창 크기·배경·아이콘 위치를 심은 뒤(.DS_Store) 압축한다.
hdiutil create -volname "Sokki" -srcfolder "$STAGE" -ov -format UDRW -quiet "$RW"
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -oE '/Volumes/.*$' | tail -1)"
echo "▶ Finder 배치 중… ($MOUNT)"
osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Sokki"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set the bounds of container window to {400, 200, 1060, 600}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:bg.png"
    set position of item "Sokki.app" of container window to {165, 190}
    set position of item "Applications" of container window to {495, 190}
    close
    open
    -- Finder 는 창을 닫을 때 크기를 .DS_Store 에 쓴다. 한 번 닫았다 연 뒤 닫기 직전에 다시 지정해야 660×400 이 남는다.
    set the bounds of container window to {400, 200, 1060, 600}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -quiet -o "$DMG"
rm -rf "$STAGE" "$RW"

# DMG 자체도 서명한다. 안 하면 spctl -t open 검사가 "no usable signature" 로 떨어진다.
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
if [[ -n "$DEV_ID" ]]; then
  codesign --force --sign "$DEV_ID" --timestamp "$DMG"
fi

# 공증: Developer ID 로 서명됐고 notarytool 프로필 'sokki' 가 있으면 자동으로 한다. NOTARIZE=0 으로 끌 수 있다.
#   프로필 저장(한 번): xcrun notarytool store-credentials sokki --apple-id <애플ID> --team-id <팀ID>
# (grep -q 는 파이프를 일찍 닫아 pipefail 에 걸리므로 변수로 받아 비교한다)
SIGNATURE="$(codesign -dvv "$APP" 2>&1 || true)"
if [[ "${NOTARIZE:-1}" == "1" && "$SIGNATURE" == *"Developer ID Application"* ]] \
   && xcrun notarytool history --keychain-profile sokki >/dev/null 2>&1; then
  echo "▶ 공증 요청 중… (보통 1~5분)"
  xcrun notarytool submit "$DMG" --keychain-profile sokki --wait
  xcrun stapler staple "$DMG"
  echo "▶ 공증 완료 — 다른 맥에서 경고 없이 열립니다"
  spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | tail -1 || true
  spctl -a -t exec -v "$APP" 2>&1 | tail -1 || true
else
  echo "ℹ️  공증 생략 (Developer ID 서명 + notarytool 프로필 'sokki' 가 있어야 합니다)"
fi

# README 의 바로 받기 링크(releases/latest/download/Sokki.dmg)용 고정 이름 사본. 공증·스테이플이 끝난 뒤 복사해야 한다.
cp "$DMG" "$DIR/build/Sokki.dmg"
echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
echo "   릴리스: gh release create v$VERSION \"$DMG\" \"$DIR/build/Sokki.dmg\""
