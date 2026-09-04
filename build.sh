#!/bin/bash
# Sokki 빌드 스크립트 — Xcode 프로젝트 없이 swiftc로 .app 번들을 만든다.
#
#   ./build.sh                            빌드만 (build/Sokki.app)
#   ./build.sh --install                  /Applications 에 설치하고 실행
#   ./build.sh --install --reset-perms    설치 전에 낡은 권한 기록을 지운다
#
# 서명 인증서는 자동으로 찾는다:
#   "Sokki Dev" 인증서가 있으면 그걸 쓰고 (재빌드해도 권한 유지)
#   없으면 애드혹 서명으로 떨어진다 (재빌드마다 권한 재설정 필요)
#   → ./setup-signing.sh 를 한 번 실행해 두면 이 문제가 사라진다
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/build/Sokki.app"
DEST="/Applications/Sokki.app"
BUNDLE_ID="com.sokki.dictation"
CERT_NAME="Sokki Dev"
OLD_CERT_NAME="Sokgi Dev"   # 이름 바꾸기 전에 만든 인증서도 그대로 쓴다

INSTALL=0
RESET_PERMS=0
for arg in "$@"; do
  case "$arg" in
    --install)     INSTALL=1 ;;
    --reset-perms) RESET_PERMS=1 ;;
  esac
done

# --- 사전 확인 -------------------------------------------------------------
if ! command -v swiftc >/dev/null 2>&1; then
  echo "❌ swiftc가 없습니다. 먼저 Xcode 명령줄 도구를 설치하세요:"
  echo "   xcode-select --install"
  exit 1
fi

ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"
echo "▶ 빌드 대상: $TARGET"

# --- 서명 신원 결정 --------------------------------------------------------
# 우선순위: SOKKI_SIGN_ID 지정 > Developer ID Application(배포·공증) > 로컬 고정 인증서 > 애드혹
# Developer ID 는 하드닝 런타임 + entitlements + 타임스탬프로 서명해야 공증이 통과한다.
# 로컬 개발 중에 Developer ID 를 건너뛰려면 SOKKI_LOCAL_SIGN=1.
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
DISTRIBUTION=0
if [[ -n "${SOKKI_SIGN_ID:-}" ]]; then
  SIGN_ID="$SOKKI_SIGN_ID"
  STABLE=1
elif [[ -n "$DEV_ID" && "${SOKKI_LOCAL_SIGN:-0}" != "1" ]]; then
  SIGN_ID="$DEV_ID"
  STABLE=1
  DISTRIBUTION=1
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  SIGN_ID="$CERT_NAME"
  STABLE=1
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$OLD_CERT_NAME"; then
  SIGN_ID="$OLD_CERT_NAME"
  STABLE=1
else
  SIGN_ID="-"
  STABLE=0
fi

# --- 번들 구조 -------------------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# --- 컴파일 ---------------------------------------------------------------
echo "▶ 컴파일 중…"
swiftc \
  -O \
  -swift-version 5 \
  -target "$TARGET" \
  -framework AppKit \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework Speech \
  -framework Carbon \
  -framework ApplicationServices \
  -framework Security \
  -framework ServiceManagement \
  -Xlinker -weak_framework -Xlinker FoundationModels \
  -o "$APP/Contents/MacOS/Sokki" \
  "$DIR/Sources/"*.swift

# --- 앱 아이콘 -------------------------------------------------------------
# 로고를 코드로 그리므로 별도 이미지 파일 없이 바이너리가 iconset 을 만들고 iconutil 로 묶는다.
echo "▶ 앱 아이콘 생성 중…"
ICONSET="$DIR/build/AppIcon.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/Sokki" --render-icon "$ICONSET" 2>/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# --- 서명 -----------------------------------------------------------------
if [[ $DISTRIBUTION -eq 1 ]]; then
  echo "▶ Developer ID 로 서명 중… (하드닝 런타임 · 공증 가능)"
  codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" \
    --options runtime --timestamp \
    --entitlements "$DIR/Sokki.entitlements" "$APP"
  codesign --verify --strict --verbose=1 "$APP"
elif [[ $STABLE -eq 1 ]]; then
  echo "▶ '$SIGN_ID' 인증서로 서명 중… (권한 유지됨)"
  codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
else
  echo "▶ 애드혹 서명 중… (재빌드하면 접근성 권한이 풀립니다)"
  codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
fi

# --- 낡은 권한 기록 정리 ---------------------------------------------------
# tccutil reset은 이 앱 하나의 권한 기록만 지운다. 다른 앱은 건드리지 않는다.
if [[ $RESET_PERMS -eq 1 ]]; then
  echo "▶ Sokki의 기존 권한 기록 삭제 중…"
  tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
  tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
  tccutil reset SpeechRecognition "$BUNDLE_ID" 2>/dev/null || true
  echo "   → 앱을 실행하면 권한을 새로 물어봅니다."
fi

# --- 설치 -----------------------------------------------------------------
if [[ $INSTALL -eq 1 ]]; then
  echo "▶ /Applications 에 설치 중…"
  pkill -x Sokki 2>/dev/null || true
  pkill -x Sokgi 2>/dev/null || true
  sleep 0.5
  rm -rf "$DEST" /Applications/Sokgi.app
  cp -R "$APP" "$DEST"
  FINAL="$DEST"
  echo "✅ 설치 완료: $DEST"
  open "$DEST"
else
  FINAL="$APP"
  echo "✅ 빌드 완료: $APP"
fi

echo ""
if [[ $STABLE -eq 0 ]]; then
  cat <<EOF
⚠️  애드혹 서명으로 빌드했습니다.
    재빌드할 때마다 앱의 신원이 바뀌어서, 손쉬운 사용에 체크가 켜져 있어도
    실제로는 권한이 거부됩니다. 한 번만 아래를 실행하면 영구히 해결됩니다:

      ./setup-signing.sh
      ./build.sh --install --reset-perms

EOF
fi

cat <<EOF
── 실행과 권한 ────────────────────────────────────────────
실행:      open "$FINAL"
로그:      tail -f ~/Library/Logs/Sokki.log

터미널에서 Contents/MacOS/Sokki 를 직접 실행하지 마세요.
권한 주체가 터미널이 되어 붙여넣기가 동작하지 않습니다.

권한이 꼬였을 때:   ./build.sh --install --reset-perms
───────────────────────────────────────────────────────────
EOF
