# Sokki — Typeless 스타일 음성 받아쓰기 (macOS)

단축키를 누르고 말하면, Apple 음성인식이 받아적고 Claude가 정리해서, 커서가 있는 자리에 바로 붙여 넣습니다.

```
⌃⌥Space → 말하기 → (3초 침묵 또는 ⌃⌥Space) → 요약 → 클립보드 복사 / 커서 위치에 붙여넣기
```

메뉴바 🎙 대신 파형 로고가 뜨고, 클릭하면 팝오버가 열립니다. 팝오버는 시안
(claude.ai/design "Voice Summary App")의 세 상태를 그대로 따릅니다.

| 상태 | 화면 |
|---|---|
| 대기 | 녹음 시작 버튼, 단축키 안내, 최근 요약 3건(복사 아이콘·모두 보기) |
| 녹음 중 | 다크 화면, 실시간 파형·부분 인식 텍스트, 타이머, 완료/취소 |
| 완료 | "클립보드에 복사됐어요" 토스트, 제목·언어·길이, 불릿 요약, 원문 보기 · 다시 요약 · ··· |

설정은 팝오버의 **설정…** 또는 상태 아이콘 우클릭 → "설정 창 열기…" 로 여는 별도 창입니다
(일반 / 인식 & 정리 / 단축키 / 고급 & 진단). 단축키는 프리셋 외에 칸을 클릭하고 원하는
조합을 눌러 직접 정할 수 있습니다.

## 빌드

Xcode는 필요 없고 명령줄 도구만 있으면 됩니다.

```bash
xcode-select --install      # 이미 있으면 건너뜀
cd Sokki
chmod +x build.sh
./build.sh
open build/Sokki.app
```

메뉴바에 파형 아이콘이 생깁니다. Dock에는 뜨지 않습니다.

팝오버 각 화면을 PNG로 뽑아 보려면 (시안 대조용):

```bash
./build/Sokki.app/Contents/MacOS/Sokki --render-previews /tmp/sokki-previews
```

## 첫 실행 시 해야 할 것

1. **API 키**: 메뉴바 🎙 → `Claude API 키 설정…` → console.anthropic.com에서 발급한 키 입력 (macOS 키체인에 저장됨)
2. **마이크 / 음성 인식**: 처음 녹음할 때 권한 창이 뜹니다. 허용.
3. **접근성**: 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → Sokki 켜기.
   이게 없으면 자동 붙여넣기가 안 되고 클립보드 복사까지만 됩니다.
4. **macOS 받아쓰기 (필수)**: 시스템 설정 → 키보드 → **받아쓰기를 켜고** 언어에 한국어를 추가하세요.
   이게 꺼져 있으면 `Siri and Dictation are disabled` 오류가 나면서 인식이 아예 안 됩니다.
   온디바이스든 애플 서버든 둘 다 이 스위치에 의존합니다.

## 메뉴 기능

| 항목 | 설명 |
|---|---|
| 인식 언어 | 한국어 / English / 日本語 |
| 정리 스타일 | 기본 · 격식체 · 구어체 유지 · 원문 최소 손질 |
| 단축키 | ⌃⌥Space, ⌥Space, ⌃⌥D, ⌘⇧Space 중 선택 |
| Claude 모델 | Sonnet(기본) / Haiku(빠르고 저렴) / Opus |
| Claude로 정리하기 | 끄면 받아쓰기 원문을 그대로 붙여넣음 |
| 붙여넣기 후 클립보드 복원 | 원래 복사해 둔 내용을 되돌려 줌 |
| 말을 멈추고 3초 뒤 자동 요약 | 끄면 단축키를 다시 누를 때만 요약 |

## 구조

```
Sources/
  main.swift            메뉴바 앱, 상태 머신, 팝오버 연결, 설정 메뉴, 침묵 감지
  PopoverView.swift     SwiftUI 팝오버 화면 (대기 / 녹음 중 / 요약 중 / 완료 / 기록 / 오류)
  AppModel.swift        팝오버가 관찰하는 상태와 동작
  Theme.swift           시안 팔레트, 로고 벡터(메뉴바 템플릿 아이콘·앱 아이콘)
  History.swift         요약 기록 저장(UserDefaults), 제목·날짜·길이 포맷
  SettingsWindow.swift  설정 창 (SwiftUI), 단축키 녹음기, 로그인 시 자동 실행
  PreviewRenderer.swift --render-previews: 각 화면을 PNG로 저장
  SpeechRecorder.swift  AVAudioEngine 마이크 탭 + SFSpeechRecognizer 실시간 인식, 입력 레벨
  ClaudeClient.swift    정리 프롬프트/스타일, 백엔드 분기, Anthropic API 호출
  GeminiClient.swift    Google AI Studio 호출 (기본 백엔드)
  CLIClient.swift       claude -p 서브프로세스 호출 (구독 사용), 경로 탐색·로그인 확인
  Log.swift             stderr + ~/Library/Logs/Sokki.log
  HotKey.swift          Carbon 전역 핫키 (접근성 권한 없이도 동작)
  Paster.swift          클립보드 백업 → 텍스트 주입 → Cmd+V 합성 → 클립보드 복원
  Prefs.swift           키체인 API 키 저장, UserDefaults 설정
Info.plist              LSUIElement, 마이크/음성인식 권한 문구
build.sh                swiftc(+SwiftUI) → .app 번들 → 애드혹 서명
```

동작 흐름:

```
전역 핫키
   ↓
AVAudioEngine 마이크 탭 ──→ SFSpeechRecognitionRequest (부분 결과 스트리밍)
   ↓ (핫키 다시)
endAudio → 최종 transcript
   ↓
Claude Messages API (system: 정리 규칙 + 스타일)
   ↓
NSPasteboard 주입 → CGEvent로 ⌘V → 0.6초 뒤 클립보드 원복
```

## 알아 둘 점

- **애드혹 서명이라 재빌드할 때마다 권한이 초기화될 수 있습니다.** 다시 빌드했는데 붙여넣기가 안 되면 손쉬운 사용 목록에서 Sokki를 뺐다가 다시 추가하세요.
- **Claude 실패 시 원문을 붙여 넣습니다.** 네트워크가 끊기거나 키가 잘못돼도 말한 내용은 사라지지 않습니다.
- **애플 서버 인식은 한 번에 약 1분 제한**이 있습니다. 길게 말할 일이 많으면 온디바이스 인식을 켜거나, 정확도가 아쉬우면 `SpeechRecorder`를 whisper.cpp로 교체하면 됩니다. 인터페이스(`start(localeID:onPartial:)` / `stop(completion:)`)만 맞추면 나머지 코드는 그대로 씁니다.
- **비용**: 받아쓰기는 무료(애플), 정리만 Claude API 과금. Haiku로 두면 한 번에 0.1원 수준입니다.

## 안 될 때

메뉴바 🎙 → **진단** 안에 네 가지가 있습니다.

| 항목 | 확인되는 것 |
|---|---|
| 현재 상태 진단 | 권한 4종, 인식 언어, API 키 유무를 한 화면에 |
| 붙여넣기 테스트 | 3초 뒤 커서 위치에 텍스트 주입 → 접근성 권한 문제 분리 |
| Claude 연결 테스트 | API 키·크레딧·모델명 문제 분리 |
| 로그 열기 | `~/Library/Logs/Sokki.log` — 단계별 실행 기록 |

증상별로:

- **말했는데 아무 것도 안 나옴** → 로그의 `오디오 버퍼 N개` 확인. 0이면 마이크가 안 잡히는 것. 버퍼는 오는데 텍스트가 비면 인식 실패이므로 메뉴에서 `애플 서버 인식 강제`를 켜고 다시 시도.
- **원문은 붙는데 정리가 안 됨** → Claude 호출 실패. `Claude 연결 테스트` 실행.
- **클립보드에만 복사됨** → 접근성 권한 없음. 재빌드했다면 손쉬운 사용 목록에서 Sokki를 뺐다가 다시 추가.

터미널에서 직접 실행하면 로그가 실시간으로 보입니다:

```bash
./build/Sokki.app/Contents/MacOS/Sokki
```

## 요금 — 정리 백엔드 두 가지

받아쓰기(애플 음성인식)는 언제나 무료입니다. 돈이 드는 건 정리 단계뿐이고,
메뉴 > `정리 백엔드`에서 둘 중에 고릅니다.

### 0. Gemini (기본값) — 무료

AI Studio 키로 `gemini-3.1-flash-lite`를 부릅니다. 4초 안에 답이 없거나 503/429가 오면
다음 모델(`gemini-flash-lite-latest` → `gemini-flash-latest`)을 겹쳐 쏘고 먼저 온 답을 씁니다.
Gemini가 전부 막히면 Claude API 키가 있으면 그쪽으로, 없으면 Claude CLI로 넘어갑니다.
정리만 따로 돌려 보려면:

```bash
GEMINI_API_KEY=... ./build/Sokki.app/Contents/MacOS/Sokki --polish "어 그 테스트 입니다"
```

### 1. Claude Code CLI — 구독으로 처리

이미 내고 있는 claude.ai 구독(Pro/Max) 사용량으로 나갑니다. **추가 결제 없음.**
앱이 내부적으로 이렇게 부릅니다:

```bash
claude -p "<받아쓴 원문>" --system-prompt "<정리 규칙>" \
       --model haiku --tools "" --bare --no-session-persistence --max-turns 1
```

`--bare`로 스킬·플러그인·MCP 로딩을 건너뛰어 시작을 앞당기고, `--tools ""`로
코딩 도구를 전부 떼어내 순수 텍스트 편집기로만 씁니다.

준비물: 터미널에서 `claude auth login` 한 번. GUI 앱은 로그인 셸 PATH를 물려받지
못해서 실행 파일을 자동 탐색하는데, 못 찾으면 메뉴 > 진단 > `CLI 경로 직접 지정…`에
`which claude` 결과를 넣어 주세요.

단점은 지연 시간입니다. API 직접 호출이 1초 안쪽이라면 CLI는 프로세스가 뜨는 만큼
2~4초쯤 걸립니다. 그리고 구독 사용량 한도를 같이 씁니다.

### 2. Anthropic API — 크레딧 별도 충전

console.claude.com에서 키를 만들고 크레딧을 충전해야 합니다. 구독료와는 별개 청구예요.
대신 빠릅니다. 실제 단가(2026년 9월 기준):

| 모델 | 입력 | 출력 |
|---|---|---|
| Haiku 4.5 | $1 / 100만 토큰 | $5 / 100만 토큰 |
| Sonnet 5 | $2 / 100만 토큰 | $10 / 100만 토큰 |

한 번 받아쓰기에 입력 700 · 출력 400토큰쯤 잡으면 Haiku 기준 약 $0.0027, **4원 정도**입니다.
하루 50번씩 한 달이면 6천원 안팎이에요.

### 3. 아예 안 쓰기

메뉴에서 `Claude로 정리하기`를 끄면 애플 받아쓰기 원문이 그대로 붙습니다. 완전 무료지만
군말과 오타가 그대로 남습니다.

## 다음에 붙일 만한 것

- 푸시투토크 (누르고 있는 동안만 녹음)
- 녹음 중 파형/부분 텍스트 HUD 오버레이
- 히스토리 창 + 재사용
- 앱별 정리 스타일 자동 전환 (Slack이면 구어체, Mail이면 격식체)
- 커스텀 단어 사전 (고유명사 교정)
