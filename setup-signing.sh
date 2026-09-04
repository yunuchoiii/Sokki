#!/bin/bash
# 로컬 코드 서명 인증서를 한 번만 만들어 둔다.
#
# 왜 필요한가:
#   애드혹 서명(codesign -s -)은 앱의 신원을 바이너리 해시로 잡는다.
#   재빌드하면 해시가 바뀌므로 macOS가 다른 앱으로 취급하고,
#   손쉬운 사용 권한이 매번 풀린다.
#   고정된 인증서로 서명하면 신원이 "identifier + 인증서 이름"으로 잡혀서
#   몇 번을 다시 빌드해도 권한이 유지된다.
#
# 이 스크립트가 하는 일 (전부 로그인 키체인 안에서만):
#   1. 자체 서명 코드서명 인증서 "Sokki Dev"를 만든다 (유효기간 10년)
#   2. 로그인 키체인에 넣고 codesign이 쓸 수 있게 허용한다
#   3. 그 인증서를 '코드 서명 용도로만' 신뢰하도록 표시한다
#      → 이 단계에서 맥 로그인 암호를 물어본다
#
# 되돌리려면: 키체인 접근 앱에서 "Sokki Dev" 인증서를 삭제하면 끝.
#
# 손으로 하고 싶으면 이 스크립트 대신:
#   키체인 접근 > 메뉴 '인증서 지원' > '인증서 생성'
#   이름 "Sokki Dev", 신원 유형 '자체 서명 루트', 인증서 유형 '코드 서명'

set -euo pipefail

NAME="Sokki Dev"

if security find-identity -v -p codesigning | grep -q "Sokgi Dev"; then
  echo "✅ 예전 이름의 'Sokgi Dev' 인증서가 있습니다. build.sh 가 그대로 씁니다."
  exit 0
fi
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "✅ '$NAME' 인증서가 이미 있습니다. 그대로 쓰면 됩니다."
  echo "   빌드:  ./build.sh --install"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▶ 자체 서명 인증서 '$NAME' 생성 중…"

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[dn]
CN = $NAME
[ext]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -config "$TMP/openssl.cnf" 2>/dev/null

# macOS 키체인은 OpenSSL 3 / LibreSSL 기본값(AES-256 + PBKDF2-SHA256)으로 만든 PKCS12 를
# "MAC verification failed" 로 거부한다. SHA1-3DES 로 명시해야 들어간다.
openssl pkcs12 -export -out "$TMP/id.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout pass:sokki \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null \
|| openssl pkcs12 -export -legacy -out "$TMP/id.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout pass:sokki 2>/dev/null

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "▶ 로그인 키체인에 등록 중…"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P sokki -T /usr/bin/codesign

echo "▶ 코드 서명 용도로 신뢰 설정 중… (맥 로그인 암호를 물어봅니다)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo ""
if security find-identity -v -p codesigning | grep -q "Sokgi Dev"; then
  echo "✅ 예전 이름의 'Sokgi Dev' 인증서가 있습니다. build.sh 가 그대로 씁니다."
  exit 0
fi
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "✅ 완료. 이제 재빌드해도 접근성 권한이 풀리지 않습니다."
  echo ""
  echo "   다음 단계:"
  echo "     ./build.sh --install --reset-perms"
else
  echo "⚠️ 인증서는 만들어졌지만 codesign이 아직 인식하지 못합니다."
  echo "   키체인 접근 앱에서 'Sokki Dev'를 더블클릭 →"
  echo "   '신뢰' 섹션 → '코드 서명'을 '항상 신뢰'로 바꿔 주세요."
fi
