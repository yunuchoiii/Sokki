#!/bin/bash
# 더블클릭하면 Sokki를 빌드해서 /Applications 에 설치하고 실행한다.
# 터미널에 아무것도 안 쳐도 된다.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
SRC="$(pwd)"
DEST="$HOME/Sokki"

echo "══════════════════════════════════"
echo "  Sokki 빌드"
echo "══════════════════════════════════"
echo ""

if ! command -v swiftc >/dev/null 2>&1; then
  echo "❌ Xcode 명령줄 도구가 없습니다."
  echo ""
  echo "   설치 창을 띄웁니다. 설치가 끝나면 이 파일을 다시 더블클릭하세요."
  xcode-select --install 2>/dev/null
  echo ""
  read -n 1 -s -r -p "아무 키나 누르면 닫힙니다..."
  exit 1
fi

# 소스를 홈 폴더로 복사 (이 폴더는 대화가 끝나면 사라질 수 있음)
if [[ "$SRC" != "$DEST" ]]; then
  echo "▶ 소스를 ~/Sokki 로 복사 중…"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  cp -R "$SRC/." "$DEST/"
fi

cd "$DEST" || exit 1
chmod +x ./*.sh ./*.command 2>/dev/null

# 빌드 출력을 로그로도 남긴다. 실패하면 Claude가 직접 읽고 원인을 잡을 수 있다.
BUILD_LOG="$HOME/Library/Logs/Sokki-build.log"
mkdir -p "$HOME/Library/Logs"

echo ""
if ./build.sh --install 2>&1 | tee "$BUILD_LOG"; then
  echo ""
  echo "══════════════════════════════════"
  echo "  ✅ 끝났습니다"
  echo ""
  echo "  메뉴바 오른쪽에 🎙 아이콘이 있습니다."
  echo ""
  echo "  쓰는 법:"
  echo "    1. ⌃⌥Space  누르고 말하기"
  echo "    2. ⌃⌥Space  다시 누르기"
  echo "    3. '띵' 소리가 나면 ⌘V 로 붙여넣기"
  echo "══════════════════════════════════"
else
  echo ""
  echo "══════════════════════════════════"
  echo "  ❌ 빌드 실패"
  echo ""
  echo "  전체 내용이 여기에 저장됐습니다:"
  echo "    ~/Library/Logs/Sokki-build.log"
  echo ""
  echo "  Claude에게 '빌드 실패했어' 라고만 하면"
  echo "  이 로그를 직접 읽고 고칩니다."
  echo "══════════════════════════════════"
fi

echo ""
read -n 1 -s -r -p "아무 키나 누르면 이 창이 닫힙니다..."
echo ""
