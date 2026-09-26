#!/bin/bash
# 릴리스 DMG 로 Sparkle appcast.xml 을 만든다. make-dmg.sh 다음, gh release create 전에 돌린다.
#
# 만들어진 appcast.xml 은 brefly-pages 저장소의 public/ 에 넣어 배포해야 한다.
# 앱은 Info.plist 의 SUFeedURL 로 그 주소를 본다.
#
# ⚠️ 서명은 로그인 키체인의 "Private key for signing Sparkle updates" 로 한다.
#    그 키가 없는 맥에서는 서명이 안 되고, 서명 없는 appcast 는 앱이 거부한다.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DIR/Info.plist")"
DMG="$DIR/build/Brefly-$VERSION.dmg"
WORK="$DIR/build/appcast"
TOOLS="${SPARKLE_BIN:-$DIR/vendor/bin}"

[[ -f "$DMG" ]] || { echo "❌ $DMG 가 없습니다. 먼저 ./make-dmg.sh 를 돌리세요."; exit 1; }
[[ -x "$TOOLS/generate_appcast" ]] || { echo "❌ generate_appcast 가 없습니다: $TOOLS"; exit 1; }

# generate_appcast 는 폴더 안의 모든 아카이브를 훑는다. 이번 버전만 담은 폴더를 새로 만든다.
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$DMG" "$WORK/"

# 릴리스 노트가 있으면 같은 이름의 .html 로 두면 appcast 에 실린다.
NOTES="$DIR/build/release-notes.html"
[[ -f "$NOTES" ]] && cp "$NOTES" "$WORK/Brefly-$VERSION.html"

echo "▶ appcast 생성 중… (버전 $VERSION)"
"$TOOLS/generate_appcast" \
  --download-url-prefix "https://github.com/yunuchoiii/brefly/releases/download/v$VERSION/" \
  --link "https://yunuchoiii.github.io/brefly-pages/" \
  --full-release-notes-url "https://github.com/yunuchoiii/brefly/releases" \
  -o "$WORK/appcast.xml" \
  "$WORK"

echo "✅ $WORK/appcast.xml"
echo
echo "다음: 이 파일을 brefly-pages 의 public/appcast.xml 로 복사하고 배포합니다."
grep -E "sparkle:version|sparkle:edSignature|<enclosure" "$WORK/appcast.xml" | sed 's/^[[:space:]]*/  /'
