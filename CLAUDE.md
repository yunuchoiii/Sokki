# Brefly — 작업 규칙

macOS 메뉴바 음성 받아쓰기·요약 앱. Xcode 프로젝트 없이 `swiftc` 로 빌드한다.
git 규칙(브랜치·커밋·PR)은 전역 `git-workflow` 스킬을 따른다. 여기엔 이 프로젝트에만 있는 것만 적는다.

## 지금 상태 (2026-09-25)

- **앱 이름은 Brefly.** 2026-09-20 에 Sokki 에서 바꿨다. GitHub 에 같은 이름의 macOS 속기 앱(★6)이 있어
  검색에서 밀렸다. 번들 ID 도 `com.brefly.dictation` 으로 바꿨고, 옛 이름의 설정·기록·키는
  `Prefs.migrateFromPreviousNamesIfNeeded()` 가 한 번만 옮겨온다. 코드·문서에 "Sokki" 가 남아 있으면 지운다.
- **저장소는 소문자** `yunuchoiii/brefly`, 랜딩 페이지는 `yunuchoiii/brefly-pages`
  (배포 주소 https://yunuchoiii.github.io/brefly-pages/).
- 최신 릴리스 **v0.6.0**(핵심 요약 스타일·억양으로 질문 판별·붙여넣기 수정). dev 에 미릴리스 수정 없음.
  v0.5.3 은 태그만 찍히고 릴리스는 나가지 않았다 — 0.6.0 에 묶어 냈다. 태그는 이력이라 지우지 않았다.
- 후원: GitHub Sponsors `yunuchoiii`. `.github/FUNDING.yml`, README, 설정 > 업데이트 탭에 링크.

## 이어받는 사람에게 (2026-09-25)

다른 컴퓨터·다른 세션이 이어서 작업할 때 먼저 볼 것. **끝나면 지운다** — 오래 두면 거짓말이 된다.

- ⚠️ **릴리스 DMG 는 아무 맥에서나 못 만든다.** Developer ID 인증서와 notarytool 프로필 `brefly` 가
  특정 맥 키체인에 있고, `make-dmg.sh` 는 터미널에 Finder 자동화 권한을 요구한다. 그 맥이 아니면
  코드·PR·문서까지만 하고 DMG 와 릴리스는 넘긴다. `build/` 는 git 에 안 들어간다.
- **아직 확인하지 못한 것 둘.** 0.6.0 으로 나갔지만 실제 동작을 못 봤다.
  ① 로그인 시 자동 실행이 실제로 시스템 설정의 로그인 항목에 등록되는지(화면만 렌더로 봤다)
  ② 붙여넣기가 Chrome·ChatGPT 에서도 되는지(Orca 에서만 확인).
- **다운로드 기준점 38회**(2026-09-20 밤). 벨로그 글 효과를 이 숫자와 비교해 잰다.
  `gh api repos/yunuchoiii/brefly/releases --jq '[.[].assets[].download_count] | add'`
  ⚠️ 검증한다고 DMG 를 curl 로 받지 말 것 — 집계에 섞여 기준점이 오염된다(한 번 그랬다).
  ⚠️ GitHub Traffic(유입 경로)은 **14일만 보관**된다. `velog.io` 가 찍혔는지 그 안에 봐야 한다.
- SEO 는 Search Console 등록·사이트맵·색인 요청까지 끝났다. 남은 건 **백링크뿐이고 사람만 할 수 있다**
  (GeekNews·디스콰이엇 등). 올릴 때 "Brefly(브레플리)" 형태로 한글 이름을 같이 써야 이름이 연결된다.

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
- **요청문 확인**: `… --prompt "원문"` 은 모델을 부르지 않고 모델에 넘어갈 요청문(말투 판정·질문 규칙이 붙은 모습)만 찍는다.
  결과가 이상하면 이것부터 본다 — 존댓말을 반말로 바꾸던 게 모델이 아니라 말투 판정 버그였다(2026-09-25).
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
- **핵심 요약 스타일**(`PolishStyle.summary`)은 다듬기와 프롬프트가 통째로 다르다(`Prompts.summaryBase`/`summaryCompact`).
  다듬기의 "정보를 하나도 버리지 말라"와 정면으로 부딪혀서 덧붙이지 않는다. 온디바이스는 3B 모델이 문장을 새로 쓰면
  뜻을 뒤집어서(“범위를 줄이자” → “범위를 줄이는 게 아니라”) 원문 표현으로 요점만 나누게 하고, 군말·말 고치기·되풀이
  조각은 `BulletSummary` 코드가 처리한다. `isFaithful` 이 불릿의 단어 순서를 원문과 대조해 어긋나면 다시 뽑고, 세 번
  어긋나면 기본 정리로 넘어간다. 프롬프트를 고치면 회의·장보기·메신저·강의·레시피·말 고치기·지시 섞인 말처럼
  유형이 다른 원문 20개 이상을 `--polish` 로 돌려 지어낸 말·숫자·부정어를 직접 본다(2026-09-25 에 26개로 했다).
- **요약은 클라우드가 본체다.** 온디바이스 3B 는 "로그인 먼저… 결제는 그다음에. 아니다. 결제 먼저" 같은 말 고치기를
  못 푼다(그대로 베낀다). 그래서 요약 스타일일 때 AUTO 는 Gemini 를 최대 8초 기다린다. Gemini 는 규칙·예시를 줘도
  "칠백"→"700만 원", "열 시"→"오전 10시"를 붙여서 `BulletSummary.removeUnsaidUnits` 가 원문에 없는 단위·시간대를 뗀다.
  Gemini 무료 키는 동시에 여러 개 보내면 곧바로 429 다 — 테스트는 하나씩 몇 초 간격으로 보낸다.
  ⚠️ **무료 한도가 모델별로 하루 20회다**(gemini-3.6-flash, `GenerateRequestsPerDayPerProjectPerModel-FreeTier`,
  2026-09-25 실측). 헤지가 한 번 요약에 모델 두세 개를 쏘므로 보조 모델은 금방 바닥난다. 테스트로 사용자 키의
  하루 몫을 다 쓰면 사용자가 말해 본 결과가 온디바이스로 떨어진다(실제로 그랬다). 테스트는 스무 개 안쪽으로.
- **말 끝 억양**(`IntonationTracker`): "밥 먹었어"와 "밥 먹었어?"는 글자로 같다. 녹음 마지막 2.5초에서 자기상관으로
  음높이를 직접 재 마지막 0.35초 기울기(반음)를 본다. 애플 `voiceAnalytics` 는 단어 구간이 마지막 음절 전에 잘려서 버렸다.
  ±2.5반음 넘을 때만 쓰고, 명령·제안(올림)이나 의문사·"맞죠"(내림)처럼 글자로 명백하면 코드가 억양을 버린다.
  모델엔 "마지막 말 \"…\"는 끝이 올라갔다"처럼 실제 말을 짚어 준다(추상 지시는 flash-lite 가 무시했다). 다듬기는
  마지막 문장부호를 코드가 한 번 더 맞춘다. 녹음 전체의 마지막 문장만 잴 수 있다.
  시험: `say -v Yuna -o q.aiff "밥 먹었어?"` (파일로 써지는 한국어 음성은 Yuna 뿐), `--polish "…" --intonation up|down`.
  ⚠️ 스피커로 음악·영상이 나오면 마이크에 소리가 꽉 차서(침묵 0) 말 끝도 음높이도 못 잡는다 — 그땐 측정을 포기하고
  글자로만 판단한다(실측: 조용할 때 4개 중 3개 맞고 틀림 0, 소리 날 때 5개 중 4개 측정 불가). 사람 목소리로 확인하려면
  `defaults write com.brefly.dictation saveIntonationAudio -bool true` 로 녹음 끝을 저장해 직접 돌려 본다. 쓰고 나면 끈다.
- **README 캡처(`docs/images/done.png`)는 앱이 실제로 낸 결과여야 한다.** 예전엔 시안의 가짜 요약을 넣어 두었고,
  앱은 요약 기능이 없었다. 사용자가 직접 해 보고 "사기 아니냐"고 했다. `PreviewRenderer` 의 첫 기록을 바꾸면
  그 원문을 `--polish` 로 돌린 출력을 그대로 넣는다.
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
- **손쉬운 사용 권한 창은 하나만 띄운다**(`Paster.sendToSettings`). macOS 권한 요청 창과 시스템 설정을 같이 열면
  사용자에겐 "창 두 개가 항상 같이 뜬다"로 보인다. macOS 27 은 그 목록 이름이 '기기 제어 및 데이터 접근'이다
  (`SystemSettings.accessibilityPath`).
- **애드혹 서명으로 설치하면 목록의 Brefly 스위치가 켜져 있어도 권한이 없다.** 켜진 항목은 예전 서명의 앱 것이다.
  '−'로 지우고 다시 추가해야 한다. 인증서가 없는 맥에선 `./setup-signing.sh` 로 'Brefly Dev' 를 한 번 만들어 둔다.
- **번들 ID 를 바꾸면 첫 실행에서 손쉬운 사용 권한이 잠깐 false 로 보인다**(실측 14초). 바로 오류를 띄우지 말고
  `startTrustWatcher(noticeAfter:)` 로 기다린다.
- `make-dmg.sh` 실행 전에 이전 Brefly 볼륨이 마운트돼 있으면 Finder 배치가 엉뚱한 볼륨을 잡는다. 스크립트가 먼저 내린다.
- `SettingsModel` 의 `hotKeyIndex` didSet 이 `Prefs.customHotKey` 를 지운다. 밖에서 다시 읽을 땐 먼저 읽어 두고 대입한다.
- **릴리스 노트에 `## 바뀐 것` 과 `- ` 불릿을 꼭 넣는다.** 랜딩 페이지(`brefly-pages` 의 `app/page.tsx` `notesOf()`)가
  그 섹션의 불릿만 뽑아 쓴다. 불릿이 없으면 릴리스 카드가 제목·날짜만 남고 본문이 빈 채로 배포된다(v0.5.1 에서 한 번 그랬다).
- `make-dmg.sh` 는 Finder 를 AppleScript 로 조작해 창 크기·배경·아이콘 위치를 `.DS_Store` 에 심는다. 터미널에 Finder 자동화
  권한이 없으면 거기서 죽는다. 창 크기는 Finder 가 닫을 때 기록하므로 닫았다 다시 연 뒤 닫기 직전에 지정해야 남는다(안 그러면 920×464).
