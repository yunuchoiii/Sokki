# Sokki — 작업 규칙

macOS 메뉴바 음성 받아쓰기·요약 앱. Xcode 프로젝트 없이 `swiftc` 로 빌드한다.
git 규칙(브랜치·커밋·PR)은 전역 `git-workflow` 스킬을 따른다. 여기엔 이 프로젝트에만 있는 것만 적는다.

## 빌드 · 검증 · 배포

```bash
./build.sh                  # build/Sokki.app (서명: Developer ID > 로컬 'Sokgi Dev' > 애드혹 순으로 자동)
./build.sh --install        # /Applications 에 설치하고 실행 (실행 중인 Sokki 는 죽인다)
./make-dmg.sh               # 빌드 → DMG → Developer ID 서명 → 공증 → 스테이플 (notarytool 프로필 'sokki' 필요)
```

- **화면 확인**: `build/Sokki.app/Contents/MacOS/Sokki --render-previews <dir>` 가 팝오버·설정 창 각 상태를
  PNG 로 뽑는다(실제 NSHostingView 경로). 화면에 영향 있는 변경은 이걸로 보고 나서 보고한다.
  실제 팝오버는 화면 캡처 권한이 없어 직접 못 본다 — 사용자에게 확인을 부탁한다.
- **요약 확인**: `… --polish "원문"` 이 녹음 없이 정리만 돌린다. AI 모델·프롬프트를 건드렸으면 설치 전에
  반드시 실제로 돌려 본다. 한 번 이걸 안 해서 사용자가 "한 번도 성공한 적 없다"를 겪었다.
- 로그: `~/Library/Logs/Sokki.log`. "자동 모드: ○○ 채택 (n초)" 줄로 어느 모델이 이겼는지 본다.
- 배포: Info.plist 버전 올림 → `./make-dmg.sh` → dev→main PR(사람이 머지) → **머지 후** 태그 →
  `gh release create vX.Y.Z build/Sokki-X.Y.Z.dmg`. 태그를 머지 전에 찍으면 첫 커밋을 가리킨다(v0.1.0 에서 실수).
  GitHub Actions 워크플로는 인증서가 없어 공증이 안 되므로 수동 실행 전용.

## 구조에서 안 보이는 결정들

- **AI 모델 기본값 AUTO**: Apple 온디바이스(macOS 26 FoundationModels)와 Gemini 를 동시에 부르고, 온디바이스가
  끝난 뒤 2초 안에 Gemini 가 오면 그걸 쓴다. Gemini 무료 티어는 저녁에 503/타임아웃이 잦다(2026-09-04 실측).
- **온디바이스 프롬프트는 예시 없는 압축판**(`Prompts.systemCompact`). 3B급 모델은 예시 문장을 출력에 베껴 넣고,
  가끔 문장을 통째로 빼먹는다. 용어 교정("들린 말 → 표기")은 모델에 맡기지 않고 `Glossary.apply` 가 원문에 먼저 치환한다.
- **말투**: `Prompts.politeness` 가 존댓말 표지(요·습니다·세요·제가)를 세어 반말/존댓말을 프롬프트에 못 박는다.
  모델에게 "알아서 맞춰"라고 하면 반말을 존댓말로 올려 버린다.
- **API 키는 키체인이 아니라 파일** `~/Library/Application Support/Sokki/keys.json`(0600). 자체 서명 앱은
  빌드마다 키체인 암호 창이 뜨고 "항상 허용"도 안 남았다. 키체인 코드를 다시 넣지 말 것.
- **단축키**: 수정자+키는 Carbon, fn⌃ 처럼 수정자만은 `ModifierHotKey`(이벤트 모니터, 접근성 권한 필요).
- **설정 문구는 '~합니다'체**, 전문 용어 금지(백엔드 → AI 모델). 비개발자가 읽는다.
- 시안: claude.ai/design 프로젝트 `33c3d303-b550-452a-a846-8e568db7e5a0` (Voice Summary App.dc.html).
  팔레트·로고 경로는 `Theme.swift` 에 옮겨 놨다.

## 함정

- `build.sh`/`make-dmg.sh` 는 `set -euo pipefail`. 명령 치환 안의 `grep` 이 빈 결과면 스크립트가 **조용히 종료**되고,
  `grep -q` 는 파이프를 일찍 닫아 pipefail 에 걸린다. `|| true` 또는 변수로 받아 비교한다.
- 하드닝 런타임(Developer ID) 빌드는 `Sokki.entitlements` 의 `audio-input` 이 없으면 마이크가 조용히 안 잡힌다.
- `FoundationModels` 는 `-Xlinker -weak_framework` 로 약하게 링크한다. 타깃은 macOS 13 유지.
- 번들 ID 는 `com.sokki.dictation`. 바꾸면 TCC 권한·UserDefaults 가 초기화된다(Sokgi→Sokki 때 이전 코드 있음).
- 미리보기용 가짜 키는 구글 키 형식(`AIza…` 39자)을 피한다. GitHub 시크릿 스캐너가 잡는다.
- `make-dmg.sh` 는 Finder 를 AppleScript 로 조작해 창 크기·배경·아이콘 위치를 `.DS_Store` 에 심는다. 터미널에 Finder 자동화
  권한이 없으면 거기서 죽는다. 창 크기는 Finder 가 닫을 때 기록하므로 닫았다 다시 연 뒤 닫기 직전에 지정해야 남는다(안 그러면 920×464).
