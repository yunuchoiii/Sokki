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

    // MARK: 백엔드

    /// 정리 단계를 무엇으로 돌릴지.
    enum Backend: String, CaseIterable {
        case gemini // Google AI Studio — 무료 티어, 1초 안쪽
        case cli    // Claude Code CLI — 구독 사용량, 10~27초
        case api    // Anthropic API — 크레딧 충전 필요, 1초 안쪽

        var title: String {
            switch self {
            case .gemini: return "Gemini API (무료, 빠름)"
            case .cli:    return "Claude Code CLI (구독, 느림)"
            case .api:    return "Anthropic API (크레딧 필요, 빠름)"
            }
        }
    }

    static var backend: Backend {
        get { Backend(rawValue: d.string(forKey: "backend") ?? "") ?? .gemini }
        set { d.set(newValue.rawValue, forKey: "backend") }
    }

    // MARK: Gemini

    /// 모델 이름은 자주 바뀐다. 진단 > 'Gemini 모델 목록'에서 실제 목록을 확인할 수 있다.
    /// 2026-09-04 실측: 2.5 계열은 404(퇴역). flash-lite-latest 는 503이 잦고,
    /// 3.1-flash-lite 가 3초 안팎으로 가장 안정적이라 첫 항목(기본값)으로 둔다.
    static let geminiModels = [
        "gemini-3.1-flash-lite",
        "gemini-flash-lite-latest",
        "gemini-flash-latest",
        "gemini-3.5-flash-lite"
    ]

    /// 고른 모델이 503/429를 내면 이 순서로 넘어간다 (고른 모델은 건너뛴다).
    static let geminiFallbacks = [
        "gemini-3.1-flash-lite",
        "gemini-flash-lite-latest",
        "gemini-flash-latest"
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
