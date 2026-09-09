# Sokki

단축키를 누르고 말하면, 받아 적고, AI 가 군말을 정리해서, 커서가 있는 자리에 붙여 넣어 주는 macOS 메뉴바 앱입니다.

**[⬇ 최신 버전 다운로드 (DMG)](https://github.com/yunuchoiii/Sokki/releases/latest/download/Sokki.dmg)** · macOS 13 이상 · 무료 · [바뀐 점 보기](https://github.com/yunuchoiii/Sokki/releases)

```
단축키 → 말하기 → 단축키 → AI 정리 → 클립보드 복사 (또는 커서 위치에 자동 붙여넣기)
```

받아쓰기는 macOS 에 내장된 애플 음성 인식을 씁니다. 돈이 들거나 키가 필요한 건 "AI 정리" 단계뿐이고,
그것도 **무료 Gemini 키**나 **macOS 26 의 Apple Intelligence** 로 무료로 쓸 수 있습니다. Claude 는 선택 사항입니다.

## 설치

1. 위 링크에서 `Sokki-x.y.z.dmg` 를 받아 엽니다.
2. Sokki 를 **Applications** 폴더로 끌어 넣고 실행합니다. 애플 공증을 받은 앱이라 경고 없이 열립니다.
3. 처음 녹음할 때 **마이크**와 **음성 인식** 권한 창이 뜹니다. 둘 다 허용합니다.
4. **시스템 설정 > 키보드 > 받아쓰기**를 켜고 언어에 한국어를 추가합니다.
   이 스위치가 꺼져 있으면 인식이 아예 되지 않습니다. 설정 > 고급 · 진단 > "받아쓰기 설정 열기"로 바로 갈 수 있습니다.
5. 첫 실행 때 설정 창이 열리면 주로 쓰는 분야를 고릅니다. 용어를 알아듣는 데 씁니다.

메뉴바에 파형 아이콘이 생기면 준비 끝입니다. Dock 에도 Sokki 가 뜨는데, 원하지 않으면 설정 > 일반에서 끌 수 있습니다.

## 사용법

- **⌃⌥Space** 를 누르고 말합니다. 다시 누르면 녹음이 끝나고 정리가 시작됩니다.
  단축키는 설정 > 일반에서 바꿀 수 있고, `fn⌃` 처럼 수정자 키만 눌렀다 떼는 것도 됩니다.
- 정리가 끝나면 결과가 **클립보드에 복사**됩니다. 어디든 ⌘V 로 붙여 넣으세요.
- 커서 위치에 **자동으로 붙여 넣게** 하려면 설정 > 일반 > "커서 위치에 자동 붙여넣기"를 켭니다.
  시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 Sokki 를 허용해야 합니다.
- 메뉴바 아이콘이나 Dock 아이콘을 누르면 창이 열립니다. 최근 요약, 원문 보기, 다시 요약, 전체 기록이 여기 있습니다.
- 말을 멈추면 알아서 끝내게 하려면 설정 > 일반 > "말을 멈추면 자동 요약"을 켭니다 (기본은 꺼져 있고 5초).
- AI 정리가 실패해도 말한 내용은 사라지지 않습니다. 원문이 그대로 복사되고 "다시 요약" 버튼이 나옵니다.

## AI 모델 고르기

설정 > 음성인식 · AI > **AI 모델**. 받아쓰기 자체는 어느 쪽을 골라도 무료입니다.

| 선택 | 필요한 것 | 비용 | 속도 |
|---|---|---|---|
| **AUTO** (기본) | Gemini 무료 키. macOS 26 이고 Apple Intelligence 가 켜져 있으면 둘을 같이 돌려 나은 쪽을 씀 | 무료 | 1~5초 |
| Apple AI (이 맥) | macOS 26 + Apple Intelligence | 무료, 인터넷 불필요 | 1~2초 |
| Gemini | [Google AI Studio](https://aistudio.google.com/apikey) 무료 키 (카드 등록 불필요) | 무료 | 1~5초, 혼잡할 땐 가끔 실패 |
| Claude API | Anthropic 키 + 크레딧 충전 | 한 번에 4원 안팎 | 1초 안팎 |
| Claude Code | Claude 구독 + 터미널에서 `claude` 로그인 | 구독 사용량 | 10~60초 |
| AI 로 정리하기 끄기 | 없음 | 무료 | 받아쓰기 원문 그대로 |

**가장 쉬운 길**은 Gemini 무료 키입니다. 설정 > 음성인식 · AI > API 키 옆의 **?** 버튼에 발급 순서가 있고,
"발급 페이지 열기"를 누르면 바로 갑니다. 키는 이 맥의 본인 계정만 읽을 수 있는 파일에 저장됩니다
(`~/Library/Application Support/Sokki/keys.json`).

macOS 26 을 쓰고 있다면 키 없이도 Apple AI 만으로 됩니다. 인터넷도 필요 없습니다.

## 설정 창 한눈에

메뉴바 아이콘 우클릭 또는 창의 **설정…** 으로 엽니다.

| 탭 | 있는 것 |
|---|---|
| 일반 | 단축키, 자동 요약, 인식 언어(한국어·English·日本語), 클립보드·자동 붙여넣기, 로그인 시 실행, Dock 표시 |
| 개인화 | 주로 쓰는 분야, 내 소개, 추가 용어("잘못 들린 말 → 올바른 표기"), 화면 모드 |
| 음성인식 · AI | 애플 서버 인식 여부, AI 모델, 정리 스타일(기본·격식·구어체·원문 최소 손질), API 키 |
| 단축키 | 직접 녹음 또는 프리셋 |
| 고급 · 진단 | 상태 진단, AI 연결 테스트, 붙여넣기 테스트, 로그 열기, 시스템 설정 바로 가기 |

## 안 될 때

설정 > 고급 · 진단의 **현재 상태 진단**이 권한·언어·키 상태를 한 화면에 보여 줍니다.

| 증상 | 확인할 것 |
|---|---|
| 말했는데 아무것도 안 나옴 | 시스템 설정 > 키보드 > 받아쓰기가 켜져 있는지. 마이크 권한. 로그의 `오디오 버퍼 N개` 가 0 이면 마이크가 안 잡힌 것 |
| 원문은 나오는데 정리가 안 됨 | AI 모델 연결 테스트. Gemini 는 저녁 시간에 503 이 잦으니 AUTO 나 Apple AI 로 |
| 클립보드에만 복사되고 붙여넣기가 안 됨 | 손쉬운 사용 권한. 앱을 새로 설치했다면 목록에서 Sokki 를 뺐다가 다시 추가 |
| 에어팟으로 녹음하면 소리가 줄어듦 | 녹음 중에는 macOS 가 에어팟을 통화 모드로 바꿉니다. 녹음이 끝나면 돌아옵니다 |

로그는 `~/Library/Logs/Sokki.log` 에 남습니다. 설정 > 고급 · 진단 > "로그 열기".

## 개인정보

- 음성은 애플 음성 인식으로 처리합니다. 기본은 이 맥 안에서만 인식하고, "애플 서버에서 처리"를 켜면 애플 서버로 갑니다.
- 받아 적은 텍스트는 고른 AI 모델에만 전송됩니다. Apple AI 를 고르면 아무 데도 보내지 않습니다.
- 요약 기록은 이 맥에만 저장됩니다.

---

# 개발자용

Xcode 프로젝트 없이 `swiftc` 로 빌드합니다. 명령줄 도구만 있으면 됩니다.

```bash
xcode-select --install      # 이미 있으면 건너뜀
./build.sh                  # build/Sokki.app  (서명: Developer ID > 로컬 'Sokgi Dev' > 애드혹 순으로 자동)
./build.sh --install        # /Applications 에 설치하고 실행 (실행 중인 Sokki 는 종료)
open build/Sokki.app        # 터미널에서 Contents/MacOS/Sokki 를 직접 실행하면 권한 주체가 터미널이 되어 붙여넣기가 안 됨
```

작업 규칙과 구조에서 안 보이는 결정은 [CLAUDE.md](CLAUDE.md) 에 있습니다.

## 검증

```bash
build/Sokki.app/Contents/MacOS/Sokki --render-previews /tmp/sokki-previews   # 팝오버·설정 창 각 상태를 PNG 로
build/Sokki.app/Contents/MacOS/Sokki --polish "어 그 테스트 입니다"            # 녹음 없이 정리만 (GEMINI_API_KEY 환경변수 가능)
tail -f ~/Library/Logs/Sokki.log                                             # "자동 모드: ○○ 채택 (n초)" 로 어느 모델이 이겼는지
```

## 배포

```bash
./make-dmg.sh               # 빌드 → DMG → Developer ID 서명 → 공증 → 스테이플
```

Developer ID Application 인증서와 `notarytool` 프로필 `sokki`(`xcrun notarytool store-credentials sokki …`)가
있는 맥에서만 공증됩니다. 순서: Info.plist 버전 올림 → `make-dmg.sh` → dev→main PR → 머지 **후** 태그 →
`gh release create vX.Y.Z build/Sokki-X.Y.Z.dmg build/Sokki.dmg` → `gh workflow run pages.yml -R yunuchoiii/Sokki-Pages`(랜딩 페이지 재빌드).
고정 이름 `Sokki.dmg` 를 같이 올려야 README 의
바로 받기 링크(`releases/latest/download/Sokki.dmg`)가 새 버전을 가리킵니다. GitHub Actions 워크플로는 인증서가 없어 공증이 안 되므로 수동 실행 전용입니다.

## 구조

```
Sources/
  main.swift            앱 진입, 상태 머신, 팝오버·Dock·메뉴, 침묵 감지, 진단
  PopoverView.swift     팝오버 화면 (대기 / 녹음 중 / 정리 중 / 완료 / 기록 / 오류)
  AppModel.swift        팝오버가 관찰하는 상태와 동작
  SettingsWindow.swift  설정 창 (일반 / 개인화 / 음성인식 · AI / 단축키 / 고급 · 진단)
  SpeechRecorder.swift  AVAudioEngine 마이크 탭 + SFSpeechRecognizer 실시간 인식 (녹음마다 엔진 생성·해제)
  ClaudeClient.swift    정리 프롬프트·스타일·말투 감지, AI 모델 분기(Polisher), Anthropic API
  GeminiClient.swift    Google AI Studio (모델 겹쳐 쏘기, 폴백)
  AppleClient.swift     macOS 26 FoundationModels 온디바이스 (약한 링크)
  CLIClient.swift       claude -p 서브프로세스
  HotKey.swift          Carbon 전역 핫키 + 수정자 전용 핫키(fn⌃ 등, 접근성 권한 필요)
  Paster.swift          클립보드 백업 → 주입 → ⌘V 합성 → 복원
  History.swift         요약 기록 (UserDefaults)
  Prefs.swift           설정(UserDefaults), API 키 파일(keys.json, 0600)
  Theme.swift           팔레트, 로고 벡터
  PreviewRenderer.swift --render-previews
  Log.swift             ~/Library/Logs/Sokki.log
Info.plist              LSUIElement, 권한 문구, 버전
Sokki.entitlements      하드닝 런타임용 (audio-input 없으면 마이크가 조용히 안 잡힘)
build.sh · make-dmg.sh
```

동작 흐름:

```
전역 핫키 → AVAudioEngine 마이크 탭 → SFSpeechRecognizer (부분 결과 스트리밍)
  → 핫키 다시 → 최종 원문 → Glossary.apply(용어 치환) → Polisher (AUTO: Apple 온디바이스 ∥ Gemini)
  → 클립보드 복사 / NSPasteboard 주입 → ⌘V 합성 → 클립보드 복원
```

## 알아 둘 점

- 애플 서버 인식은 한 번에 약 1분 제한이 있습니다. 온디바이스 인식은 제한이 없습니다.
- 애드혹 서명 빌드는 재빌드마다 접근성 권한이 풀릴 수 있습니다. `./build.sh --install --reset-perms`.
- 번들 ID `com.sokki.dictation` 을 바꾸면 권한과 설정이 초기화됩니다.

## 다음에 붙일 만한 것

- 푸시투토크 (누르고 있는 동안만 녹음)
- 앱별 정리 스타일 자동 전환 (Slack 이면 구어체, Mail 이면 격식체)
- whisper.cpp 인식 엔진 (`SpeechRecorder` 인터페이스만 맞추면 교체 가능)
