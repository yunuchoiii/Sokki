import Foundation
import AppKit

/// API 키는 ~/Library/Application Support/Sokki/keys.json (0600) 에, 나머지 설정은 UserDefaults 에.
///
/// 원래는 키체인이었다. 자체 서명 앱은 빌드마다(심지어 고정 인증서로 바꾼 뒤에도) 키체인 항목을 읽을 때
/// 암호 창이 떴고 "항상 허용"도 안 남았다 (2026-09-04). 개인 도구라 본인만 읽는 파일로 충분하다.
enum KeychainStore {

    enum Slot: String, CaseIterable {
        case anthropic = "anthropic-api-key"
        case gemini    = "gemini-api-key"

        var envVar: String {
            switch self {
            case .anthropic: return "ANTHROPIC_API_KEY"
            case .gemini:    return "GEMINI_API_KEY"
            }
        }
    }

    /// 미리보기 렌더처럼 실제 키가 필요 없을 때 넣어 두는 가짜 값.
    static var stub: [Slot: String]?

    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sokki", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("keys.json")
    }()

    static var storageDescription: String { "~/Library/Application Support/Sokki/keys.json (본인만 읽기)" }

    private static let lock = NSLock()
    private static var loaded: [String: String]?

    private static func load() -> [String: String] {
        if let loaded { return loaded }
        var dict: [String: String] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            dict = json
        }
        loaded = dict
        return dict
    }

    private static func save(_ dict: [String: String]) {
        loaded = dict
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func read(_ slot: Slot) -> String? {
        if let stub { return stub[slot] }
        // 환경변수가 있으면 우선 사용 (터미널에서 테스트할 때 편함)
        if let env = ProcessInfo.processInfo.environment[slot.envVar], !env.isEmpty {
            return env
        }
        lock.lock(); defer { lock.unlock() }
        if let v = load()[slot.rawValue], !v.isEmpty { return v }
        return nil
    }

    @discardableResult
    static func write(_ key: String, to slot: Slot) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var dict = load()
        if key.isEmpty { dict.removeValue(forKey: slot.rawValue) } else { dict[slot.rawValue] = key }
        save(dict)
        return true
    }

    // 기존 호출부 호환
    static func readAPIKey() -> String? { read(.anthropic) }
    @discardableResult
    static func writeAPIKey(_ key: String) -> Bool { write(key, to: .anthropic) }
}

enum Prefs {

    private static let d = UserDefaults.standard

    /// 앱 이름을 Sokgi → Sokki 로 바꾸면서 번들 ID 가 바뀌었다 (2026-09-04).
    /// 예전 도메인의 설정·기록과 키 파일을 한 번만 옮겨온다.
    static func migrateFromSokgiIfNeeded() {
        let flag = "migratedFromSokgi"
        guard !d.bool(forKey: flag) else { return }
        d.set(true, forKey: flag)

        if let old = UserDefaults(suiteName: "com.sokgi.dictation") {
            var count = 0
            for (key, value) in old.dictionaryRepresentation() where d.object(forKey: key) == nil {
                // 시스템이 넣는 키(AppleLanguages 등)는 건너뛴다
                if key.hasPrefix("Apple") || key.hasPrefix("NS") || key.hasPrefix("com.apple") { continue }
                d.set(value, forKey: key)
                count += 1
            }
            if count > 0 { Log.write("Sokgi 설정 \(count)개 이전") }
        }

        let fm = FileManager.default
        let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let oldKeys = support.appendingPathComponent("Sokgi/keys.json")
        let newKeys = support.appendingPathComponent("Sokki/keys.json")
        if fm.fileExists(atPath: oldKeys.path), !fm.fileExists(atPath: newKeys.path) {
            try? fm.createDirectory(at: newKeys.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            if (try? fm.copyItem(at: oldKeys, to: newKeys)) != nil {
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: newKeys.path)
                Log.write("Sokgi 키 파일 이전")
            }
        }
    }

    // MARK: 인식 언어

    static let locales: [(title: String, id: String)] = [
        ("한국어", "ko-KR"),
        ("English (US)", "en-US"),
        ("日本語", "ja-JP")
    ]

    static var localeID: String {
        get { d.string(forKey: "localeID") ?? "ko-KR" }
        set { d.set(newValue, forKey: "localeID") }
    }

    // MARK: 정리 스타일

    static var style: PolishStyle {
        get { PolishStyle(rawValue: d.string(forKey: "style") ?? "") ?? .standard }
        set { d.set(newValue.rawValue, forKey: "style") }
    }

    // MARK: 화자 정보 · 용어 사전 (정리 프롬프트에 들어간다)

    /// 화자가 누구인지. 모델이 문맥을 잡는 데 쓴다. 예) "프론트엔드 개발자. React·React Native·Swift 를 쓴다."
    static var speakerNote: String {
        get { d.string(forKey: "speakerNote") ?? "" }
        set { d.set(newValue, forKey: "speakerNote") }
    }

    /// 사용자가 직접 추가한 용어. 한 줄에 하나. "잘못 들린 말 → 올바른 표기" 또는 그냥 단어.
    static var glossary: String {
        get { d.string(forKey: "glossary") ?? "" }
        set { d.set(newValue, forKey: "glossary") }
    }

    /// 주로 어떤 분야·상황에서 쓰는지. 체크한 것의 설명과 용어가 프롬프트에 들어간다.
    static var usageContexts: Set<UsageContext> {
        get { Set((d.stringArray(forKey: "usageContexts") ?? []).compactMap(UsageContext.init(rawValue:))) }
        set { d.set(newValue.map(\.rawValue).sorted(), forKey: "usageContexts") }
    }

    /// 처음 실행 때 분야 선택을 안내했는지
    static var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }

    // MARK: 백엔드

    /// 정리 단계를 무엇으로 돌릴지.
    enum Backend: String, CaseIterable {
        case auto   // Apple 온디바이스 + Gemini 동시 — 빠르고 나은 쪽
        case gemini // Google AI Studio — 무료 티어, 1~5초 (혼잡하면 503)
        case apple  // macOS 26 Apple Intelligence 온디바이스 — 무료, 오프라인
        case api    // Anthropic API — 크레딧 충전 필요, 1초 안쪽
        case cli    // Claude Code CLI — 구독 사용량, 10~60초

        var title: String {
            switch self {
            case .auto:   return "AUTO (Apple 온디바이스 + Gemini)"
            case .gemini: return "Gemini API (무료)"
            case .apple:  return "Apple 온디바이스 (무료, 오프라인)"
            case .api:    return "Anthropic API (크레딧 필요, 빠름)"
            case .cli:    return "Claude Code CLI (구독, 느림)"
            }
        }
    }

    /// 자동 모드에서 온디바이스가 끝난 뒤 Gemini 답을 얼마나 더 기다릴지.
    static let autoGraceSeconds: TimeInterval = 2.0

    /// Gemini/Apple 이 전부 실패했을 때 Claude CLI 까지 시도할지. 10~60초 걸려서 기본은 끔.
    static var cliFallback: Bool {
        get { d.object(forKey: "cliFallback") as? Bool ?? false }
        set { d.set(newValue, forKey: "cliFallback") }
    }

    static var backend: Backend {
        get { Backend(rawValue: d.string(forKey: "backend") ?? "") ?? .auto }
        set { d.set(newValue.rawValue, forKey: "backend") }
    }

    // MARK: Gemini

    /// 모델 이름은 자주 바뀐다. 진단 > 'Gemini 모델 목록'에서 실제 목록을 확인할 수 있다.
    /// 2026-09-04 실측: 2.5 계열은 404(퇴역). flash-lite-latest 는 503이 잦고,
    /// 3.1-flash-lite 가 3초 안팎으로 가장 안정적이라 첫 항목(기본값)으로 둔다.
    /// 22:19 재측정: -latest 별칭 둘은 응답 자체가 없고(타임아웃), 3.6-flash 2.3초 · 3.1-flash-lite 5.3초 · 3.5-flash 9.2초.
    static let geminiModels = [
        "gemini-3.1-flash-lite",
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-flash-lite-latest",
        "gemini-flash-latest"
    ]

    /// 고른 모델이 늦거나 503/429를 내면 이 순서로 겹쳐 쏜다 (고른 모델은 건너뛴다).
    static let geminiFallbacks = [
        "gemini-3.1-flash-lite",
        "gemini-3.6-flash",
        "gemini-3.5-flash"
    ]

    static var geminiModel: String {
        get { d.string(forKey: "geminiModel") ?? geminiModels[0] }
        set { d.set(newValue, forKey: "geminiModel") }
    }

    /// claude 실행 파일 경로를 직접 지정할 때. 비워두면 자동 탐색.
    static var cliPath: String? {
        get { d.string(forKey: "cliPath") }
        set { d.set(newValue, forKey: "cliPath") }
    }

    /// 설치된 claude 버전이 모르는 플래그. 한 번 걸리면 기억해서 다음부터 뺀다.
    static var unsupportedCLIFlags: Set<String> {
        get { Set(d.stringArray(forKey: "unsupportedCLIFlags") ?? []) }
        set { d.set(Array(newValue), forKey: "unsupportedCLIFlags") }
    }

    // MARK: 모델

    /// 받아쓰기 정리는 가벼운 작업이라 Haiku로 충분하다. 첫 항목이 기본값.
    static let models = ["claude-haiku-4-5-20251001", "claude-sonnet-5", "claude-opus-5"]

    static var model: String {
        get { d.string(forKey: "model") ?? models[0] }
        set { d.set(newValue, forKey: "model") }
    }

    // MARK: 단축키

    static var hotKeyIndex: Int {
        get { d.integer(forKey: "hotKeyIndex") }
        set { d.set(newValue, forKey: "hotKeyIndex") }
    }

    /// 설정 창에서 직접 녹음한 단축키. 있으면 프리셋보다 우선한다.
    static var customHotKey: HotKeyCombo? {
        get {
            guard d.object(forKey: "customHotKeyCode") != nil else { return nil }
            return HotKeyCombo(keyCode: UInt32(d.integer(forKey: "customHotKeyCode")),
                               modifiers: UInt32(d.integer(forKey: "customHotKeyMods")))
        }
        set {
            if let c = newValue {
                d.set(Int(c.keyCode), forKey: "customHotKeyCode")
                d.set(Int(c.modifiers), forKey: "customHotKeyMods")
            } else {
                d.removeObject(forKey: "customHotKeyCode")
                d.removeObject(forKey: "customHotKeyMods")
            }
        }
    }

    /// 실제로 등록할 단축키.
    static var currentHotKey: HotKeyCombo {
        customHotKey ?? HotKeyPreset.preset(at: hotKeyIndex).combo
    }

    // MARK: 기타

    /// Claude 정리를 끄면 받아쓰기 원문을 그대로 붙여 넣는다.
    static var polishEnabled: Bool {
        get { d.object(forKey: "polishEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "polishEnabled") }
    }

    /// 커서 위치에 자동으로 붙여넣을지. 끄면 클립보드에만 넣는다(권한 불필요).
    /// 애드혹 서명 앱은 재빌드마다 접근성 권한이 풀리므로 기본값은 끔.
    static var autoPaste: Bool {
        get { d.object(forKey: "autoPaste") as? Bool ?? false }
        set { d.set(newValue, forKey: "autoPaste") }
    }

    /// 결과를 클립보드에 넣을지. 끄면 기록에만 남는다(자동 붙여넣기가 켜져 있으면 그쪽이 우선).
    static var copyToClipboard: Bool {
        get { d.object(forKey: "copyToClipboard") as? Bool ?? true }
        set { d.set(newValue, forKey: "copyToClipboard") }
    }

    static var restoreClipboard: Bool {
        get { d.object(forKey: "restoreClipboard") as? Bool ?? true }
        set { d.set(newValue, forKey: "restoreClipboard") }
    }

    /// 실패했을 때 시스템 알림창까지 띄운다. 팝오버가 오류를 보여주므로 기본은 끔.
    static var showErrorAlerts: Bool {
        get { d.object(forKey: "showErrorAlerts") as? Bool ?? false }
        set { d.set(newValue, forKey: "showErrorAlerts") }
    }

    /// 말을 멈추고 N초가 지나면 자동으로 녹음을 끝내고 요약한다. 생각하다 끊기는 게 싫다는 피드백으로 기본은 끔.
    static var autoStopOnSilence: Bool {
        get { d.object(forKey: "autoStopOnSilence") as? Bool ?? false }
        set { d.set(newValue, forKey: "autoStopOnSilence") }
    }

    static let silenceOptions: [TimeInterval] = [2, 3, 5, 8, 12]

    static var silenceSeconds: TimeInterval {
        get { let v = d.double(forKey: "silenceSeconds"); return v > 0 ? v : 5 }
        set { d.set(newValue, forKey: "silenceSeconds") }
    }

    /// 화면 모드: 시스템 / 라이트 / 다크
    enum Appearance: String, CaseIterable {
        case system, light, dark
        var title: String {
            switch self {
            case .system: return "시스템"
            case .light:  return "라이트"
            case .dark:   return "다크"
            }
        }
        /// nil 이면 시스템을 따른다.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light:  return NSAppearance(named: .aqua)
            case .dark:   return NSAppearance(named: .darkAqua)
            }
        }
        var isDark: Bool {
            switch self {
            case .dark: return true
            case .light: return false
            case .system:
                return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            }
        }
    }

    static var appearance: Appearance {
        get { Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system }
        set { d.set(newValue.rawValue, forKey: "appearance") }
    }

    /// 온디바이스 인식이 한 번 실패하면 켜진다. 이후 애플 서버 인식으로 넘어간다.
    static var forceServerRecognition: Bool {
        get { d.bool(forKey: "forceServerRecognition") }
        set { d.set(newValue, forKey: "forceServerRecognition") }
    }
}


/// 앱을 쓰는 분야·상황. 체크한 항목의 `context` 는 프롬프트의 화자 설명에, `glossary` 는 용어 사전에 합쳐진다.
enum UsageContext: String, CaseIterable, Identifiable {
    case devFrontend, devBackend, devMobile, design, product, marketing, meeting, messenger, email, study, personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .devFrontend: return "프론트엔드 개발"
        case .devBackend:  return "백엔드·인프라 개발"
        case .devMobile:   return "iOS·Android 앱 개발"
        case .design:      return "디자인·UX"
        case .product:     return "기획·PM"
        case .marketing:   return "마케팅·영업"
        case .meeting:     return "회의·업무 메모"
        case .messenger:   return "메신저 (Slack·카톡)"
        case .email:       return "이메일·보고"
        case .study:       return "공부·강의 노트"
        case .personal:    return "일상·개인 메모"
        }
    }

    var symbol: String {
        switch self {
        case .devFrontend: return "chevron.left.forwardslash.chevron.right"
        case .devBackend:  return "server.rack"
        case .devMobile:   return "iphone"
        case .design:      return "paintbrush"
        case .product:     return "list.clipboard"
        case .marketing:   return "megaphone"
        case .meeting:     return "person.2"
        case .messenger:   return "bubble.left.and.bubble.right"
        case .email:       return "envelope"
        case .study:       return "book"
        case .personal:    return "note.text"
        }
    }

    /// 화자 설명에 붙는 한 문장
    var context: String {
        switch self {
        case .devFrontend: return "프론트엔드 개발자다. React·TypeScript·웹 용어를 자주 쓴다."
        case .devBackend:  return "백엔드·인프라 일을 한다. 서버·DB·배포 용어를 자주 쓴다."
        case .devMobile:   return "iOS·Android 앱을 만든다. Swift·Kotlin·React Native 용어를 자주 쓴다."
        case .design:      return "디자인·UX 일을 한다. Figma·컴포넌트·시안 이야기를 자주 한다."
        case .product:     return "기획·PM 일을 한다. 요구사항·일정·우선순위 이야기를 자주 한다."
        case .marketing:   return "마케팅·영업 일을 한다. 캠페인·전환·고객 이야기를 자주 한다."
        case .meeting:     return "회의 내용과 업무 메모를 남기는 데 쓴다. 결정 사항·담당자·마감이 중요하다."
        case .messenger:   return "메신저에 보낼 말을 정리하는 데 쓴다. 말투를 딱딱하게 바꾸지 않는다."
        case .email:       return "이메일이나 보고에 쓸 글을 정리하는 데 쓴다."
        case .study:       return "공부·강의 내용을 노트로 남기는 데 쓴다. 개념과 용어를 정확히 적는다."
        case .personal:    return "일상 메모·일기·할 일을 적는 데 쓴다."
        }
    }

    /// "들린 말 → 표기" 용어. 한 줄에 하나.
    var glossary: String {
        switch self {
        case .devFrontend: return """
            리듬이, 리드 미 → README
            레포, 랩 포, 래포 → 레포(repo)
            리 액트 → React
            타입스크립트 → TypeScript
            넥스트 → Next.js
            프론트 앤드, 프론트느 → 프론트엔드
            깃 헙, 깃 허브 → GitHub
            풀 리퀘스트, 피알 → PR
            커밋, 브랜치, 머지, 클론, 푸시, 빌드, 배포, 리팩터링, 컴포넌트, 훅, 상태 관리
            """
        case .devBackend: return """
            리듬이, 리드 미 → README
            레포, 랩 포 → 레포(repo)
            100 and, 백 앤드 → 백엔드
            에이피아이 → API
            디비 → DB
            도커 → Docker
            쿠버네티스 → Kubernetes
            깃 헙 → GitHub
            배포, 서버, 인프라, 마이그레이션, 캐시, 큐, 스케줄러
            """
        case .devMobile: return """
            스위프트 → Swift
            스위프트 유아이 → SwiftUI
            코틀린 → Kotlin
            리 액트 네이티브 → React Native
            엑스코드 → Xcode
            앱스토어 → App Store
            테스트 플라이트 → TestFlight
            시뮬레이터, 빌드, 배포, 권한, 푸시 알림
            """
        case .design: return """
            피그마 → Figma
            시안, 와이어프레임, 프로토타입, 컴포넌트, 디자인 시스템, 토큰, 여백, 정렬
            유엑스 → UX
            유아이 → UI
            """
        case .product: return """
            피엠 → PM
            스프린트, 백로그, 요구사항, 우선순위, 로드맵, 마일스톤, 일정, 리스크
            케이피아이 → KPI
            오케이알 → OKR
            """
        case .marketing: return """
            캠페인, 전환율, 리드, 퍼널, 랜딩 페이지, 광고비, 고객, 제안서, 견적
            씨티에이 → CTA
            로아스 → ROAS
            """
        case .meeting: return """
            액션 아이템, 담당자, 마감, 결정 사항, 안건, 후속 조치, 다음 회의
            """
        case .messenger: return ""
        case .email: return """
            수신, 참조, 첨부, 회신, 요청 드립니다, 확인 부탁드립니다
            """
        case .study: return """
            개념, 정의, 예시, 정리, 복습, 챕터, 과제
            """
        case .personal: return ""
        }
    }
}


/// 용어 사전의 "들린 말 → 표기" 줄을 원문에 그대로 적용한다.
/// 모델(특히 온디바이스)이 사전을 절반만 따르길래, 확실한 것은 코드가 먼저 바꿔 둔다.
enum Glossary {

    struct Rule { let variants: [String]; let replacement: String }

    static func rules() -> [Rule] {
        var lines: [String] = []
        for c in UsageContext.allCases where Prefs.usageContexts.contains(c) {
            lines += c.glossary.split(separator: "\n").map(String.init)
        }
        lines += Prefs.glossary.split(separator: "\n").map(String.init)

        var result: [Rule] = []
        for line in lines {
            let parts = line.components(separatedBy: "→")
            guard parts.count == 2 else { continue }
            let variants = parts[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var right = parts[1].trimmingCharacters(in: .whitespaces)
            // "레포(repo)" → "레포": 괄호 안은 모델용 설명이라 치환 결과에는 넣지 않는다
            if let paren = right.range(of: "(") { right = String(right[..<paren.lowerBound]).trimmingCharacters(in: .whitespaces) }
            guard !variants.isEmpty, !right.isEmpty else { continue }
            result.append(Rule(variants: variants, replacement: right))
        }
        return result
    }

    /// 긴 변형부터 바꿔서 "리 액트 네이티브"가 "React 네이티브"로 반쯤 바뀌는 일을 막는다.
    static func apply(to text: String) -> String {
        var out = text
        let pairs = rules().flatMap { r in r.variants.map { ($0, r.replacement) } }
            .sorted { $0.0.count > $1.0.count }
        for (from, to) in pairs where from != to {
            out = out.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        return out
    }
}
