import SwiftUI
import AppKit
import ServiceManagement
import Carbon.HIToolbox

// 시안 2a "설정 창 — 일반", 2b "설정 창 — 인식 & 정리". 창 폭 620, 왼쪽 사이드바.
// 단축키 · 고급 & 진단 탭은 시안에 없어서 기존 메뉴 항목을 같은 톤으로 옮겼다.

extension Notification.Name {
    /// 설정 창에서 값이 바뀌면 AppDelegate 가 단축키 재등록·팝오버 갱신을 한다.
    static let sokkiPrefsChanged = Notification.Name("sokkiPrefsChanged")
    static let sokkiHotKeyCaptureBegan = Notification.Name("sokkiHotKeyCaptureBegan")
    static let sokkiHotKeyCaptureEnded = Notification.Name("sokkiHotKeyCaptureEnded")
}

/// Prefs 를 SwiftUI 가 관찰할 수 있게 감싼다. 값을 바꾸면 곧바로 Prefs 에 쓴다.
final class SettingsModel: ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case general, personal, recognition, hotkey, advanced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general:     return "일반"
            case .personal:    return "개인화"
            case .recognition: return "인식 & 정리"
            case .hotkey:      return "단축키"
            case .advanced:    return "고급 & 진단"
            }
        }
        var symbol: String {
            switch self {
            case .general:     return "smallcircle.filled.circle"
            case .personal:    return "person.crop.circle"
            case .recognition: return "waveform.path"
            case .hotkey:      return "keyboard"
            case .advanced:    return "sparkles"
            }
        }
    }

    @Published var tab: Tab = .general

    @Published var hotKeyIndex = Prefs.hotKeyIndex            { didSet { Prefs.hotKeyIndex = hotKeyIndex; Prefs.customHotKey = nil; changed() } }
    @Published var customHotKey = Prefs.customHotKey          { didSet { Prefs.customHotKey = customHotKey; changed() } }
    var currentHotKeyTitle: String { Prefs.currentHotKey.title }
    /// 수정자 전용 단축키인데 권한이 없으면 안내가 필요하다.
    var hotKeyNeedsAccessibility: Bool { Prefs.currentHotKey.isModifierOnly && !accessibilityTrusted }
    @Published var autoStop = Prefs.autoStopOnSilence         { didSet { Prefs.autoStopOnSilence = autoStop; changed() } }
    @Published var silenceSeconds = Prefs.silenceSeconds      { didSet { Prefs.silenceSeconds = silenceSeconds; changed() } }
    @Published var appearance = Prefs.appearance              { didSet { Prefs.appearance = appearance; changed() } }
    @Published var localeID = Prefs.localeID                  { didSet { Prefs.localeID = localeID; changed() } }
    @Published var copyToClipboard = Prefs.copyToClipboard    { didSet { Prefs.copyToClipboard = copyToClipboard; changed() } }
    @Published var autoPaste = Prefs.autoPaste                { didSet { Prefs.autoPaste = autoPaste; changed() } }
    @Published var restoreClipboard = Prefs.restoreClipboard  { didSet { Prefs.restoreClipboard = restoreClipboard; changed() } }
    @Published var showErrorAlerts = Prefs.showErrorAlerts    { didSet { Prefs.showErrorAlerts = showErrorAlerts; changed() } }
    @Published var forceServer = Prefs.forceServerRecognition { didSet { Prefs.forceServerRecognition = forceServer; changed() } }
    @Published var polishEnabled = Prefs.polishEnabled        { didSet { Prefs.polishEnabled = polishEnabled; changed() } }
    @Published var backend = Prefs.backend                    { didSet { Prefs.backend = backend; changed() } }
    @Published var style = Prefs.style                        { didSet { Prefs.style = style; changed() } }
    @Published var geminiModel = Prefs.geminiModel            { didSet { Prefs.geminiModel = geminiModel; changed() } }
    @Published var claudeModel = Prefs.model                  { didSet { Prefs.model = claudeModel; changed() } }
    @Published var cliPath = Prefs.cliPath ?? ""              { didSet { Prefs.cliPath = cliPath.isEmpty ? nil : cliPath; changed() } }
    @Published var cliFallback = Prefs.cliFallback            { didSet { Prefs.cliFallback = cliFallback; changed() } }
    @Published var speakerNote = Prefs.speakerNote            { didSet { Prefs.speakerNote = speakerNote } }
    @Published var glossary = Prefs.glossary                  { didSet { Prefs.glossary = glossary } }
    @Published var usageContexts = Prefs.usageContexts        { didSet { Prefs.usageContexts = usageContexts } }
    /// 처음 실행 안내 배너
    @Published var showOnboarding = !Prefs.onboarded

    func toggleContext(_ c: UsageContext) {
        if usageContexts.contains(c) { usageContexts.remove(c) } else { usageContexts.insert(c) }
    }

    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchAtLoginError = ""
    @Published var accessibilityTrusted = Paster.isTrusted

    /// 진단 동작. AppDelegate 가 채운다.
    struct Actions {
        var testPaste: () -> Void = {}
        var testBackend: () -> Void = {}
        var listGeminiModels: () -> Void = {}
        var checkCLI: () -> Void = {}
        var resetCLIFlags: () -> Void = {}
        var openLog: () -> Void = {}
        var showDiagnostics: () -> Void = {}
        var openDictationSettings: () -> Void = {}
        var openAccessibility: () -> Void = {}
    }
    var actions = Actions()

    private func changed() { NotificationCenter.default.post(name: .sokkiPrefsChanged, object: nil) }

    func refresh() {
        accessibilityTrusted = Paster.isTrusted
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = ""
        } catch {
            launchAtLoginError = "설정 실패: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Sokki \(v) (\(b))"
    }
}

// MARK: - 창

final class SettingsWindowController {
    private var window: NSWindow?
    let model = SettingsModel()

    func show() {
        model.refresh()
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "Sokki 설정"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.titlebarAppearsTransparent = false
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 620, height: 470))
            w.center()
            window = w
        }
        window?.appearance = Prefs.appearance.nsAppearance
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applyAppearance() { window?.appearance = Prefs.appearance.nsAppearance }

    var isVisible: Bool { window?.isVisible ?? false }
}

// MARK: - 뷰

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.line).frame(width: 1)
            ScrollView {
                Group {
                    switch model.tab {
                    case .general:     GeneralPane(model: model)
                    case .personal:    PersonalPane(model: model)
                    case .recognition: RecognitionPane(model: model)
                    case .hotkey:      HotKeyPane(model: model)
                    case .advanced:    AdvancedPane(model: model)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.paperSoft)
        }
        .frame(width: 620, height: 470)
        .onAppear { model.refresh() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsModel.Tab.allCases) { tab in
                let selected = model.tab == tab
                Button(action: { model.tab = tab }) {
                    HStack(spacing: 9) {
                        Image(systemName: tab.symbol).font(.system(size: 12, weight: .medium)).frame(width: 16)
                        Text(tab.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(selected ? .onPrimary : .ink)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(selected ? Color.primaryFill : Color.clear)
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(model.appVersion).font(.system(size: 11)).foregroundColor(.text4).padding(.leading, 6)
        }
        .padding(12)
        .frame(width: 176)
        .background(Color.fill)
    }
}

// MARK: 2a 일반

struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("받아쓰기") {
                SettingsRow(title: "받아쓰기 시작 단축키",
                            subtitle: "칸을 클릭하고 조합을 누르세요. fn⌃ 처럼 수정자 키만 눌렀다 떼도 됩니다.",
                            warning: model.hotKeyNeedsAccessibility ? "수정자 키만 쓰는 단축키는 손쉬운 사용 권한 필요 — 허용하기" : nil,
                            warningAction: model.actions.openAccessibility) {
                    HotKeyRecorderField(model: model)
                }
                SettingsRow(title: "말을 멈추면 자동 요약",
                            subtitle: model.autoStop ? "\(Int(model.silenceSeconds))초간 무음이 이어지면 자동으로 요약"
                                                     : "끄면 단축키를 다시 누를 때만 요약 — 말하다 생각해도 안 끊김") {
                    HStack(spacing: 8) {
                        if model.autoStop {
                            PopupLabel(title: "\(Int(model.silenceSeconds))초",
                                       options: Prefs.silenceOptions.map { "\(Int($0))초" },
                                       selected: Prefs.silenceOptions.firstIndex(of: model.silenceSeconds)) {
                                model.silenceSeconds = Prefs.silenceOptions[$0]
                            }
                        }
                        InkToggle(isOn: $model.autoStop)
                    }
                }
                SettingsRow(title: "인식 언어", subtitle: nil, last: true) {
                    PopupLabel(title: Prefs.locales.first { $0.id == model.localeID }?.title ?? model.localeID,
                               options: Prefs.locales.map(\.title),
                               selected: Prefs.locales.firstIndex { $0.id == model.localeID }) {
                        model.localeID = Prefs.locales[$0].id
                    }
                }
            }

            SettingsSection("결과 처리") {
                SettingsRow(title: "클립보드에 자동 복사", subtitle: nil) {
                    InkToggle(isOn: $model.copyToClipboard)
                }
                SettingsRow(title: "커서 위치에 자동 붙여넣기",
                            subtitle: model.accessibilityTrusted ? "손쉬운 사용(접근성) 권한 확인됨" : nil,
                            warning: model.accessibilityTrusted ? nil : "손쉬운 사용(접근성) 권한 필요 — 허용하기",
                            warningAction: model.actions.openAccessibility) {
                    InkToggle(isOn: $model.autoPaste)
                }
                if model.autoPaste {
                    SettingsRow(title: "붙여넣기 후 클립보드 복원", subtitle: "자동 붙여넣기는 클립보드를 잠깐 빌려 씁니다. 켜면 붙여넣은 뒤 전에 복사해 둔 내용을 되돌려 놓고, 끄면 요약문이 클립보드에 남습니다.") {
                        InkToggle(isOn: $model.restoreClipboard)
                    }
                }
                SettingsRow(title: "실패 시 시스템 알림 표시", subtitle: nil, last: true) {
                    InkToggle(isOn: $model.showErrorAlerts)
                }
            }

            SettingsSection(nil) {
                SettingsRow(title: "로그인 시 Sokki 자동 실행",
                            subtitle: model.launchAtLoginError.isEmpty ? nil : nil,
                            warning: model.launchAtLoginError.isEmpty ? nil : model.launchAtLoginError,
                            last: true) {
                    InkToggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
            }
        }
    }
}

// MARK: 개인화 — 나에 맞춘 것들

struct PersonalPane: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UsageContextSection(model: model)

            SettingsSection("화면") {
                SettingsRow(title: "화면 모드", subtitle: "팝오버와 설정 창에 적용", last: true) {
                    Segmented(options: Prefs.Appearance.allCases.map { ($0, $0.title) }, selection: $model.appearance)
                }
            }
        }
    }
}

// MARK: 2b 인식 & 정리

struct RecognitionPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("음성 인식") {
                SettingsRow(title: "애플 서버 인식 강제", subtitle: "온디바이스 인식을 끄고 서버 인식 사용 (정확도 ↑)", last: true) {
                    InkToggle(isOn: $model.forceServer)
                }
            }

            SettingsSection("정리 (요약)") {
                SettingsRow(title: "AI 로 정리하기", subtitle: "끄면 받아쓰기 원문을 그대로 붙여 넣음") {
                    InkToggle(isOn: $model.polishEnabled)
                }
                SettingsRow(title: "정리 백엔드", subtitle: backendHint) {
                    Segmented(options: Prefs.Backend.allCases.map { ($0, $0.shortTitle) }, selection: $model.backend)
                }
                SettingsRow(title: "정리 스타일", subtitle: "요약 결과의 형식") {
                    PopupLabel(title: model.style.title,
                               options: PolishStyle.allCases.map(\.title),
                               selected: PolishStyle.allCases.firstIndex(of: model.style)) {
                        model.style = PolishStyle.allCases[$0]
                    }
                }
                SettingsRow(title: "모델", subtitle: modelHint, last: model.backend == .apple) {
                    if model.backend == .apple {
                        Text("이 맥의 Apple Intelligence 모델").font(.system(size: 12)).foregroundColor(.text3)
                    } else if model.backend == .gemini || model.backend == .auto {
                        PopupLabel(title: model.geminiModel, options: Prefs.geminiModels,
                                   selected: Prefs.geminiModels.firstIndex(of: model.geminiModel)) {
                            model.geminiModel = Prefs.geminiModels[$0]
                        }
                    } else {
                        PopupLabel(title: model.claudeModel, options: Prefs.models,
                                   selected: Prefs.models.firstIndex(of: model.claudeModel)) {
                            model.claudeModel = Prefs.models[$0]
                        }
                    }
                }
                if model.backend != .apple {
                    SettingsRow(title: "안 되면 Claude CLI 로 재시도",
                                subtitle: "다른 백엔드가 전부 막혔을 때. 10~60초 걸려서 기본은 끔 — 끄면 원문을 바로 복사하고 '다시 요약' 버튼을 줍니다",
                                last: true) {
                        InkToggle(isOn: $model.cliFallback)
                    }
                }
            }

            if model.backend != .apple {
                SettingsSection(model.backend == .cli ? "Claude Code CLI" : "API 키") {
                    if model.backend == .cli {
                        CLIPathRow(model: model)
                    } else {
                        APIKeyRow(slot: (model.backend == .gemini || model.backend == .auto) ? .gemini : .anthropic)
                    }
                }
            }
        }
    }

    private var backendHint: String {
        switch model.backend {
        case .auto:   return AppleClient.availability().ok
                             ? "온디바이스와 Gemini 동시 요청 — 2초 안에 Gemini 가 답하면 그걸, 아니면 온디바이스"
                             : "온디바이스를 못 써서 Gemini 만 사용 — " + AppleClient.availability().note
        case .gemini: return "Google AI Studio 무료 키 · 1~5초, 혼잡하면 503"
        case .apple:  return AppleClient.availability().note
        case .api:    return "Anthropic 크레딧 · 1초 안팎"
        case .cli:    return "claude.ai 구독 사용량 · 10~60초"
        }
    }

    private var modelHint: String {
        switch model.backend {
        case .gemini, .auto: return "Gemini 두 모델을 동시에 쏘고 먼저 온 답을 씁니다"
        case .apple:  return "네트워크를 쓰지 않습니다"
        default:      return "정리는 가벼워서 Haiku 로 충분"
        }
    }
}

private extension Prefs.Backend {
    var shortTitle: String {
        switch self {
        case .auto:   return "자동"
        case .gemini: return "Gemini"
        case .apple:  return "Apple"
        case .api:    return "Claude"
        case .cli:    return "CLI"
        }
    }
}

struct APIKeyRow: View {
    let slot: KeychainStore.Slot
    @State private var editing = false
    @State private var draft = ""
    @State private var saved: String = ""
    @State private var showHelp = false

    private var issueURL: String {
        slot == .gemini ? "https://aistudio.google.com/apikey" : "https://console.anthropic.com/settings/keys"
    }

    /// 비개발자용 발급 안내. ? 버튼을 누르면 말풍선으로 뜬다.
    private var helpSteps: [String] {
        slot == .gemini
        ? ["아래 '발급 페이지 열기'를 누르면 Google AI Studio 가 열립니다. 구글 계정으로 로그인하세요.",
           "파란 'API 키 만들기(Create API key)' 버튼을 누릅니다. 프로젝트를 고르라고 하면 아무거나 골라도 됩니다.",
           "AIza… 로 시작하는 긴 문자열이 나옵니다. 복사 버튼을 누르세요.",
           "여기 '입력' 버튼을 누르고 붙여넣은 뒤 저장하면 끝. 무료이고 카드 등록도 필요 없습니다."]
        : ["아래 '발급 페이지 열기'를 누르면 Anthropic 콘솔이 열립니다. 로그인하세요.",
           "'Create Key' 를 눌러 이름을 정하고 키를 만듭니다. sk-ant-… 로 시작합니다.",
           "키는 그때 한 번만 보여 주니 바로 복사하세요.",
           "Billing 에서 크레딧을 조금 충전해야 동작합니다. 한 번 요약에 5원 안팎입니다."]
    }

    private var masked: String {
        guard !saved.isEmpty else { return "키 없음" }
        let head = saved.prefix(7), tail = saved.suffix(4)
        return "\(head)••••••••••••\(tail)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if editing {
                    SecureField(slot == .gemini ? "AIza..." : "sk-ant-...", text: $draft)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                    SmallButton("저장", filled: true) {
                        KeychainStore.write(draft.trimmingCharacters(in: .whitespacesAndNewlines), to: slot)
                        saved = KeychainStore.read(slot) ?? ""
                        editing = false
                    }
                    SmallButton("취소") { editing = false }
                } else {
                    Text(masked)
                        .font(.system(size: 12, design: .monospaced)).foregroundColor(saved.isEmpty ? .text4 : .text2)
                        .padding(.horizontal, 12).frame(height: 30).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.fill).cornerRadius(7)
                    SmallButton(saved.isEmpty ? "입력" : "변경", filled: true) { draft = ""; editing = true }
                }
                Button(action: { showHelp.toggle() }) {
                    Image(systemName: "questionmark.circle").font(.system(size: 15)).foregroundColor(.text3)
                        .frame(width: 24, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("키 받는 방법")
                .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(slot == .gemini ? "Gemini API 키 받는 법 (무료)" : "Claude API 키 받는 법")
                            .font(.system(size: 13, weight: .bold))
                        ForEach(Array(helpSteps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(i + 1)").font(.system(size: 11, weight: .bold))
                                    .frame(width: 18, height: 18).background(Color.primary.opacity(0.08)).cornerRadius(9)
                                Text(step).font(.system(size: 12)).lineSpacing(2)
                            }
                        }
                        HStack {
                            Spacer()
                            Button("발급 페이지 열기") {
                                if let u = URL(string: issueURL) { NSWorkspace.shared.open(u) }
                            }
                        }
                    }
                    .padding(16).frame(width: 340)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(saved.isEmpty ? Color.coral : Color.green).frame(width: 6, height: 6)
                Text(saved.isEmpty
                     ? (slot == .gemini ? "aistudio.google.com/apikey 에서 무료 발급 · 카드 등록 불필요"
                                        : "console.anthropic.com 에서 발급 · 크레딧 충전 필요")
                     : "키 확인됨 · " + KeychainStore.storageDescription)
                    .font(.system(size: 11)).foregroundColor(.text3)
                Button("발급 페이지 열기") {
                    if let u = URL(string: issueURL) { NSWorkspace.shared.open(u) }
                }.buttonStyle(.link).font(.system(size: 11))
            }
        }
        .padding(14)
        .onAppear { saved = KeychainStore.read(slot) ?? "" }
        .onChange(of: slot) { s in saved = KeychainStore.read(s) ?? ""; editing = false }
    }
}

struct CLIPathRow: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField(CLIClient.resolveExecutable() ?? "/opt/homebrew/bin/claude", text: $model.cliPath)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                SmallButton("확인", filled: true) { model.actions.checkCLI() }
            }
            Text(CLIClient.resolveExecutable().map { "사용 중: \($0)" } ?? "claude 실행 파일을 찾지 못했습니다. `which claude` 결과를 넣어 주세요.")
                .font(.system(size: 11)).foregroundColor(.text3)
        }
        .padding(14)
    }
}

// MARK: 단축키

struct HotKeyPane: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("직접 설정") {
                SettingsRow(title: "받아쓰기 시작 / 종료",
                            subtitle: "칸을 클릭하고 조합을 누르세요. ⌃⌥D 처럼 수정자+키, 또는 fn⌃ 처럼 수정자 키만 눌렀다 떼기.",
                            warning: model.hotKeyNeedsAccessibility ? "수정자 키만 쓰는 단축키는 손쉬운 사용 권한 필요 — 허용하기" : nil,
                            warningAction: model.actions.openAccessibility,
                            last: true) {
                    HotKeyRecorderField(model: model)
                }
            }
            SettingsSection("프리셋") {
                ForEach(Array(HotKeyPreset.all.enumerated()), id: \.offset) { i, p in
                    let on = model.customHotKey == nil && model.hotKeyIndex == i
                    Button(action: { model.hotKeyIndex = i; model.customHotKey = nil }) {
                        HStack {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(on ? .ink : .text4)
                            KeyCapLarge(p.title)
                            Spacer()
                        }
                        .padding(.horizontal, 14).frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < HotKeyPreset.all.count - 1 { HairLine().padding(.leading, 14) }
                }
            }
            Text("단축키는 접근성 권한 없이도 어느 앱에서나 동작합니다. 다른 앱이 같은 조합을 쓰면 등록에 실패할 수 있어요. ⌘ 단독 조합(⌘C 등)은 다른 앱과 겹치기 쉬우니 ⌃⌥ 를 권합니다.")
                .font(.system(size: 11)).foregroundColor(.text3)
        }
    }
}

// MARK: 고급 & 진단

struct AdvancedPane: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("진단") {
                ActionRow("현재 상태 진단", "권한 4종, 인식 언어, 키 유무를 한 화면에", action: model.actions.showDiagnostics)
                ActionRow("정리 백엔드 연결 테스트", "짧은 문장을 실제로 정리해 봅니다", action: model.actions.testBackend)
                ActionRow("붙여넣기 테스트", "3초 뒤 커서 위치에 텍스트를 넣습니다 (자동 붙여넣기 켜져 있어야 함)", action: model.actions.testPaste)
                ActionRow("Gemini 모델 목록", "이 키로 쓸 수 있는 모델을 조회", action: model.actions.listGeminiModels)
                ActionRow("Claude Code CLI 확인", "경로·버전·로그인 상태", action: model.actions.checkCLI)
                ActionRow("CLI 플래그 캐시 초기화", "미지원으로 기억해 둔 플래그를 지움", action: model.actions.resetCLIFlags)
                ActionRow("로그 열기", Log.url.path, action: model.actions.openLog, last: true)
            }
            SettingsSection("시스템") {
                ActionRow("받아쓰기 설정 열기", "시스템 설정 > 키보드 > 받아쓰기가 꺼져 있으면 인식이 안 됩니다", action: model.actions.openDictationSettings)
                ActionRow("손쉬운 사용 권한 열기", "자동 붙여넣기에 필요", action: model.actions.openAccessibility, last: true)
            }
        }
    }
}

// MARK: - 조각

struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content
    init(_ title: String?, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.text3)
            }
            VStack(spacing: 0) { content }
                .background(Color.paper)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.lineStrong, lineWidth: 1))
                .cornerRadius(10)
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    var warning: String? = nil
    var warningAction: (() -> Void)? = nil
    var last: Bool = false
    let accessory: Accessory

    init(title: String, subtitle: String?, warning: String? = nil, warningAction: (() -> Void)? = nil,
         last: Bool = false, @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.subtitle = subtitle; self.warning = warning
        self.warningAction = warningAction; self.last = last; self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.ink)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 11)).foregroundColor(.text3)
                    }
                    if let warning {
                        Button(action: { warningAction?() }) {
                            Text(warning).font(.system(size: 11)).foregroundColor(.coralDeep)
                        }.buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 8)
                accessory
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if !last { HairLine().padding(.leading, 14) }
        }
    }
}

struct ActionRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void
    var last = false
    init(_ title: String, _ subtitle: String, action: @escaping () -> Void, last: Bool = false) {
        self.title = title; self.subtitle = subtitle; self.action = action; self.last = last
    }
    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, last: last) {
            SmallButton("실행", action: action)
        }
    }
}

struct InkToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() } }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Color.primaryFill : Color.lineStrong).frame(width: 38, height: 22)
                Circle().fill(isOn ? Color.onPrimary : Color.white).frame(width: 18, height: 18).padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 드롭다운. SwiftUI Menu 는 macOS 에서 라벨 꾸밈을 무시해 NSMenu 를 직접 띄운다.
struct PopupLabel: View {
    let title: String
    let options: [String]
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        Button(action: popUp) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(.ink).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundColor(.text3)
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.fill)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.lineStrong, lineWidth: 1))
            .cornerRadius(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func popUp() {
        let menu = NSMenu()
        for (i, label) in options.enumerated() {
            let item = NSMenuItem(title: label, action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            item.tag = i
            item.state = (i == selected) ? .on : .off
            item.target = MenuTarget.shared
            item.representedObject = MenuChoice(onSelect)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class MenuChoice { let run: (Int) -> Void; init(_ run: @escaping (Int) -> Void) { self.run = run } }
private final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    @objc func pick(_ sender: NSMenuItem) { (sender.representedObject as? MenuChoice)?.run(sender.tag) }
}

struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let on = opt.0 == selection
                Button(action: { selection = opt.0 }) {
                    Text(opt.1).font(.system(size: 12, weight: .semibold))
                        .foregroundColor(on ? .onPrimary : .text2)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(on ? Color.primaryFill : Color.clear)
                        .cornerRadius(6)
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.fill).cornerRadius(8)
        .fixedSize()
    }
}

struct KeyCapLarge: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(.ink)
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.fill)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.lineStrong, lineWidth: 1))
            .cornerRadius(7)
    }
}

struct SmallButton: View {
    let title: String
    var filled = false
    let action: () -> Void
    init(_ title: String, filled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.filled = filled; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundColor(filled ? .onPrimary : .ink)
                .padding(.horizontal, 12).frame(height: 28)
                .background(filled ? Color.primaryFill : Color.paper)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(filled ? Color.clear : Color.lineStrong, lineWidth: 1))
                .cornerRadius(7)
        }.buttonStyle(.plain)
    }
}


// MARK: - 단축키 녹음기

/// 클릭하면 녹음 상태가 되고, 앱에 들어오는 다음 keyDown 을 단축키로 저장한다. Esc 로 취소.
/// 첫 응답자 방식은 SwiftUI 호스팅 창에서 키를 못 받아서, 로컬 이벤트 모니터로 가로챈다.
struct HotKeyRecorderField: View {
    @ObservedObject var model: SettingsModel
    @State private var recording = false
    @State private var heldModifiers = ""
    @State private var monitors: [Any] = []
    @State private var maxHeld: UInt32 = 0

    private var label: String {
        if recording { return heldModifiers.isEmpty ? "키 조합을 누르세요…" : heldModifiers + "…" }
        return model.currentHotKeyTitle
    }

    var body: some View {
        Button(action: { if !recording { start() } }) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(recording ? .coralDeep : .ink)
                if !recording, model.customHotKey != nil {
                    Text("직접 설정").font(.system(size: 10)).foregroundColor(.text3)
                }
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(recording ? Color.coral.opacity(0.08) : Color.fill)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(recording ? Color.coral : Color.lineStrong, lineWidth: 1))
            .cornerRadius(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(recording ? "Esc 로 취소 · 수정자 키만 눌렀다 떼도 저장됩니다" : "클릭해서 바꾸기")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        heldModifiers = ""
        maxHeld = 0
        NotificationCenter.default.post(name: .sokkiHotKeyCaptureBegan, object: nil)

        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let mods = HotKeyCombo.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else {
                NSSound.beep()
                return nil
            }
            model.customHotKey = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            stop()
            return nil
        }
        let flagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let now = HotKeyCombo.modifierBits(from: event.modifierFlags)
            heldModifiers = HotKeyCombo(keyCode: 0, modifiers: now).modifierSymbols
            if now & maxHeld == maxHeld, now != maxHeld {
                maxHeld = now              // 더 누르는 중
            } else if now == 0, maxHeld != 0 {
                // 전부 뗐고 그 사이 다른 키가 없었다 → 수정자 전용 단축키
                model.customHotKey = HotKeyCombo(keyCode: HotKeyCombo.modifierOnlyKeyCode, modifiers: maxHeld)
                stop()
                return nil
            } else if now == 0 {
                maxHeld = 0
            }
            return nil
        }
        monitors = [keyMonitor, flagMonitor].compactMap { $0 }
    }

    private func stop() {
        guard recording else { return }
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        recording = false
        heldModifiers = ""
        NotificationCenter.default.post(name: .sokkiHotKeyCaptureEnded, object: nil)
    }
}


// MARK: - 사용 분야·상황

/// 체크한 분야의 설명과 용어가 정리 프롬프트에 들어간다. 프롬프트에 특정 직군 용어를 박아 두지 않기 위한 장치.
struct UsageContextSection: View {
    @ObservedObject var model: SettingsModel
    @State private var showExtras = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        SettingsSection("주로 어디에 쓰나요?") {
            VStack(alignment: .leading, spacing: 12) {
                if model.showOnboarding {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles").foregroundColor(.coral)
                        Text("처음이시군요. 주로 쓰는 분야와 상황을 골라 주세요. 골라 둔 분야의 용어(예: 개발이면 README·레포·React)를 받아쓰기가 잘못 들어도 바로잡습니다. 여러 개 골라도 됩니다.")
                            .font(.system(size: 12)).foregroundColor(.ink).lineSpacing(2)
                    }
                    .padding(12)
                    .background(Color.coral.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.coral.opacity(0.35), lineWidth: 1))
                    .cornerRadius(8)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(UsageContext.allCases) { c in
                        let on = model.usageContexts.contains(c)
                        Button(action: { model.toggleContext(c) }) {
                            HStack(spacing: 8) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13)).foregroundColor(on ? .ink : .text4)
                                Image(systemName: c.symbol).font(.system(size: 11)).foregroundColor(.text2).frame(width: 14)
                                Text(c.title).font(.system(size: 12, weight: on ? .semibold : .regular)).foregroundColor(.ink)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).frame(height: 34)
                            .background(on ? Color.fill : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.lineStrong : Color.line, lineWidth: 1))
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if model.showOnboarding {
                    HStack {
                        Spacer()
                        SmallButton("이대로 시작", filled: true) {
                            Prefs.onboarded = true
                            model.showOnboarding = false
                        }
                    }
                }

                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showExtras.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: showExtras ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold))
                        Text("직접 추가 — 내 소개, 자주 쓰는 용어")
                    }
                    .font(.system(size: 12)).foregroundColor(.text2)
                }
                .buttonStyle(.plain)

                if showExtras {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("내 소개 (선택)").font(.system(size: 12, weight: .semibold)).foregroundColor(.ink)
                        Text("예) 시큐어로그에서 SCSM 이라는 사내 솔루션을 만든다.")
                            .font(.system(size: 11)).foregroundColor(.text3)
                        TextEditor(text: $model.speakerNote)
                            .font(.system(size: 12)).frame(height: 48)
                            .padding(6).background(Color.fill).cornerRadius(7)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.lineStrong, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("추가 용어 (선택)").font(.system(size: 12, weight: .semibold)).foregroundColor(.ink)
                        Text("한 줄에 하나. \"잘못 들린 말 → 올바른 표기\" 또는 단어만. 예) 에스씨에스엠 → SCSM")
                            .font(.system(size: 11)).foregroundColor(.text3)
                        TextEditor(text: $model.glossary)
                            .font(.system(size: 12, design: .monospaced)).frame(height: 90)
                            .padding(6).background(Color.fill).cornerRadius(7)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.lineStrong, lineWidth: 1))
                    }
                }
            }
            .padding(14)
        }
    }
}
