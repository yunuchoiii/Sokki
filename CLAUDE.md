# Brefly — 작업 규칙

macOS 메뉴바 음성 받아쓰기·요약 앱. Xcode 프로젝트 없이 `swiftc` 로 빌드한다.
git 규칙(브랜치·커밋·PR)은 전역 `git-workflow` 스킬을 따른다. 여기엔 이 프로젝트에만 있는 것만 적는다.

## 지금 상태 (2026-09-20)

- **앱 이름은 Brefly.** 2026-09-20 에 Sokki 에서 바꿨다. GitHub 에 같은 이름의 macOS 속기 앱(★6)이 있어
  검색에서 밀렸다. 번들 ID 도 `com.brefly.dictation` 으로 바꿨고, 옛 이름의 설정·기록·키는
  `Prefs.migrateFromPreviousNamesIfNeeded()` 가 한 번만 옮겨온다. 코드·문서에 "Sokki" 가 남아 있으면 지운다.
- **저장소는 소문자** `yunuchoiii/brefly`, 랜딩 페이지는 `yunuchoiii/brefly-pages`
  (배포 주소 https://yunuchoiii.github.io/brefly-pages/).
- 최신 릴리스 **v0.5.3**(커서 위치에 붙여넣기가 아무 데도 안 들어가던 버그 수정). dev 에 미릴리스 수정 없음.
- 후원: GitHub Sponsors `yunuchoiii`. `.github/FUNDING.yml`, README, 설정 > 업데이트 탭에 링크.

## 빌드 · 검증 · 배포

```bash
./build.sh                  # build/Brefly.app (서명: Developer ID > 로컬 'Sokgi Dev'(이름 바꾸기 전 인증서, 그대로 쓴다) > 애드혹 순으로 자동)
./build.sh --install        # /Applications 에 설치하고 실행 (실행 중인 Brefly 는 죽인다)
./make-dmg.sh               # 빌드 → DMG → Developer ID 서명 → 공증 → 스테이플 (notarytool 프로필 'brefly' 또는 'sokki' 필요)
```

- **화면 확인**: `build/Brefly.app/Contents/MacOS/Brefly --render-previews <dir>` 가 팝오버·설정 창 각 상태를
  PNG 로 뽑는다(실제 NSHostingView 경로). 화면에 영향 있는 변경은 이걸로 보고 나서 보고한다.
  실제 팝오버는 화면 캡처 권한이 없어 직접 못 본다 — 사용자에게 확인을 부탁한다.
- **요약 확인**: `… --polish "원문"` 이 녹음 없이 정리만 돌린다. AI 모델·프롬프트를 건드렸으면 설치 전에
  반드시 실제로 돌려 본다. 한 번 이걸 안 해서 사용자가 "한 번도 성공한 적 없다"를 겪었다.
- 로그: `~/Library/Logs/Brefly.log`. "자동 모드: ○○ 채택 (n초)" 줄로 어느 모델이 이겼는지 본다.
- 배포: Info.plist 버전 올림 → `./make-dmg.sh` → dev→main PR(사람이 머지) → **머지 후** 태그 →
  `gh release create vX.Y.Z build/Brefly-X.Y.Z.dmg build/Brefly.dmg` →
  **DMG 두 개를 반드시 같이 올린다.** 고정 이름 `Brefly.dmg` 는 README·랜딩 페이지의 바로 받기 링크,
  버전 붙은 `Brefly-X.Y.Z.dmg` 는 앱 안 업데이트 버튼이 가리킨다. 둘을 갈라 둬야 GitHub 다운로드 수로
  신규 설치와 기존 사용자 업데이트를 구분할 수 있다(`UpdateChecker.downloadURL(for:)`). 빠뜨리면 404 다. →
  `gh workflow run pages.yml -R yunuchoiii/brefly-pages`(랜딩 페이지가 릴리스 노트를 빌드 때 가져오므로 다시 빌드). 태그를 머지 전에 찍으면 첫 커밋을 가리킨다(v0.1.0 에서 실수).
  GitHub Actions 워크플로는 인증서가 없어 공증이 안 되므로 수동 실행 전용.

## 구조에서 안 보이는 결정들

- **AI 모델 기본값 AUTO**: Apple 온디바이스(macOS 26 FoundationModels)와 Gemini 를 동시에 부르고, 온디바이스가
  끝난 뒤 2초 안에 Gemini 가 오면 그걸 쓴다. Gemini 무료 티어는 저녁에 503/타임아웃이 잦다(2026-09-04 실측).
- **온디바이스 프롬프트는 예시 없는 압축판**(`Prompts.systemCompact`). 3B급 모델은 예시 문장을 출력에 베껴 넣고,
  가끔 문장을 통째로 빼먹는다. 용어 교정("들린 말 → 표기")은 모델에 맡기지 않고 `Glossary.apply` 가 원문에 먼저 치환한다.
- **말투**: `Prompts.politeness` 가 존댓말 표지(요·습니다·세요·제가)를 세어 반말/존댓말을 프롬프트에 못 박는다.
  모델에게 "알아서 맞춰"라고 하면 반말을 존댓말로 올려 버린다.
- **API 키는 키체인이 아니라 파일** `~/Library/Application Support/Brefly/keys.json`(0600). 자체 서명 앱은
  빌드마다 키체인 암호 창이 뜨고 "항상 허용"도 안 남았다. 키체인 코드를 다시 넣지 말 것.
- **단축키**: 수정자+키는 Carbon, fn⌃ 처럼 수정자만은 `ModifierHotKey`(이벤트 모니터, 접근성 권한 필요).
- **설정 문구는 '~합니다'체**, 전문 용어 금지(백엔드 → AI 모델). 비개발자가 읽는다.
- **음성 인식 기본값은 애플 서버**(`forceServerRecognition` 기본 true, 2026-09-13). 온디바이스는 눈에 띄게 덜
  정확하고 침묵 뒤 구간을 리셋한다 — 같은 버전인데 서버 인식인 맥은 잘 알아듣고 온디바이스인 맥은 못 알아들었다.
- **온디바이스 구간 누적**: 인식기가 침묵 뒤 이전 텍스트를 버린다. `SpeechRecorder.absorb` 가 텍스트로 리셋을
  감지해(앞 4글자 불일치 + 길이 절반 이하) 이전 구간을 이어 붙인다. 부분 결과엔 시간 정보가 없다(전부 0.00).
- **빈 녹음은 오류가 아니다.** 인식기는 침묵을 `kAFAssistantErrorDomain 1110`("No speech detected")로 돌려준다.
  마이크 버퍼가 왔는데 말이 없으면 조용히 끝낸다. 버퍼가 0 이면 그때만 마이크 문제로 안내한다.
- **결과 팝오버는 기본으로 안 뜬다**(`showResultPopover` 기본 false). 정리가 끝나면 닫고, 결과는 메뉴바 아이콘으로 본다.
- **녹음 중 다른 소리 낮추기**(`AudioDucker`): 기본 출력 볼륨을 ×0.3. 블루투스는 1초 뒤 macOS 가 이미 낮췄는지
  보고 안 낮췄을 때만 우리가 낮춘다(에어팟은 통화 모드로 알아서 낮춘다). HDMI 출력은 볼륨 속성이 없어 못 한다.
  ⏯ 미디어 키로 재생을 멈추는 방법은 "지금 재생 중" 앱이 없으면 macOS 가 음악 앱을 열어 버려서 뺐다.
- **업데이트 확인**은 GitHub 릴리스 API. 다운로드는 `releases/latest/download/Brefly.dmg` 고정 이름에 기댄다 —
  릴리스에 그 파일을 꼭 같이 올린다.
- 시안: claude.ai/design 프로젝트 `33c3d303-b550-452a-a846-8e568db7e5a0` (Voice Summary App.dc.html,
  Brefly Onboarding.dc.html). 팔레트·로고 경로는 `Theme.swift` 에 옮겨 놨다.

## 함정

- `build.sh`/`make-dmg.sh` 는 `set -euo pipefail`. 명령 치환 안의 `grep` 이 빈 결과면 스크립트가 **조용히 종료**되고,
  `grep -q` 는 파이프를 일찍 닫아 pipefail 에 걸린다. `|| true` 또는 변수로 받아 비교한다.
- 하드닝 런타임(Developer ID) 빌드는 `Brefly.entitlements` 의 `audio-input` 이 없으면 마이크가 조용히 안 잡힌다.
- `FoundationModels` 는 `-Xlinker -weak_framework` 로 약하게 링크한다. 타깃은 macOS 13 유지.
- 번들 ID 는 `com.brefly.dictation`. 바꾸면 TCC 권한·UserDefaults 가 초기화된다(Sokgi→Sokki→Brefly 때 이전 코드 있음).
- 미리보기용 가짜 키는 구글 키 형식(`AIza…` 39자)을 피한다. GitHub 시크릿 스캐너가 잡는다.
- **공증 프로필 이름을 스크립트에 박지 말 것.** 이름이 안 맞으면 공증이 조용히 생략되고 서명만 된 DMG 가 나온다
  (0.5.0 을 그렇게 한 번 만들었다). `make-dmg.sh` 는 `brefly` → `sokki` 순으로 찾고 `NOTARY_PROFILE` 로 덮어쓸 수 있다.
- **번들 ID 를 바꾸면 첫 실행에서 손쉬운 사용 권한이 잠깐 false 로 보인다**(실측 14초). 바로 오류를 띄우지 말고
  `startTrustWatcher(noticeAfter:)` 로 기다린다.
- `make-dmg.sh` 실행 전에 이전 Brefly 볼륨이 마운트돼 있으면 Finder 배치가 엉뚱한 볼륨을 잡는다. 스크립트가 먼저 내린다.
- `SettingsModel` 의 `hotKeyIndex` didSet 이 `Prefs.customHotKey` 를 지운다. 밖에서 다시 읽을 땐 먼저 읽어 두고 대입한다.
- **릴리스 노트에 `## 바뀐 것` 과 `- ` 불릿을 꼭 넣는다.** 랜딩 페이지(`brefly-pages` 의 `app/page.tsx` `notesOf()`)가
  그 섹션의 불릿만 뽑아 쓴다. 불릿이 없으면 릴리스 카드가 제목·날짜만 남고 본문이 빈 채로 배포된다(v0.5.1 에서 한 번 그랬다).
- `make-dmg.sh` 는 Finder 를 AppleScript 로 조작해 창 크기·배경·아이콘 위치를 `.DS_Store` 에 심는다. 터미널에 Finder 자동화
  권한이 없으면 거기서 죽는다. 창 크기는 Finder 가 닫을 때 기록하므로 닫았다 다시 연 뒤 닫기 직전에 지정해야 남는다(안 그러면 920×464).
