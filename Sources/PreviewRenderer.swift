import AppKit
import SwiftUI

/// `Sokki --render-previews <dir>` 로 실행하면 팝오버 각 상태와 아이콘을 PNG로 저장하고 끝난다.
/// 실제 NSHostingView로 그리므로 팝오버에 뜨는 화면과 같은 코드 경로다. 화면 확인·시안 대조용.
enum PreviewRenderer {

    static func run(outputDir: String) {
        KeychainStore.stub = [.gemini: "preview-gemini-key-not-real-0000", .anthropic: ""]   // 구글 키 형식(AIza…)을 피한다 — GitHub 시크릿 스캐너가 가짜 값을 잡았다
        let dir = URL(fileURLWithPath: outputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let now = Date()
        let samples = [
            SummaryRecord(title: "마케팅 회의 정리 — 3가지 액션 아이템",
                          summary: "- 온보딩 첫 화면은 설명 대신 **마이크 버튼을 바로 누르게** 유도\n- 단축키(⌥Space) 안내를 첫 실행 시 한 번만 노출\n- 다음 주까지 시안 2개 준비 — 금요일 리뷰",
                          raw: "그래서 온보딩 첫 화면은 지금처럼 설명을 길게 쓰지 말고, 사용자가 바로 마이크 버튼을 누르게 유도하는 게 좋을 것 같고요, 아 그리고 아까 말했던 단축키 안내도 매번 보여줄 필요는 없고 처음 한 번만… 아 맞다, 다음 주까지 시안 두 개 준비해서 금요일에 리뷰하죠.",
                          date: now.addingTimeInterval(-14 * 60), duration: 160, localeID: "ko-KR", polished: true),
            SummaryRecord(title: "아이디어 메모 — 신규 온보딩 개선안",
                          summary: "신규 온보딩 개선안입니다.", raw: "신규 온보딩 개선안 어쩌구",
                          date: Calendar.current.date(bySettingHour: 11, minute: 2, second: 0, of: now)!,
                          duration: 72, localeID: "ko-KR", polished: true),
            SummaryRecord(title: "Weekly sync recap — follow-ups",
                          summary: "Follow-ups from weekly sync.", raw: "so the weekly sync follow ups are",
                          date: now.addingTimeInterval(-26 * 3600), duration: 245, localeID: "en-US", polished: true)
        ]

        let model = AppModel()
        model.history = samples
        model.micReady = true
        model.hotKeyTitle = "⌥ Space"
        model.backendTitle = Prefs.Backend.gemini.title

        func snap(_ name: String) {
            let image = render(PopoverRoot(model: model))
            write(image, to: dir.appendingPathComponent("\(name).png"))
        }

        model.phase = .idle
        snap("1a-idle")

        model.phase = .recording
        model.elapsed = 47
        model.levels = [0.95, 0.8, 0.62, 0.5, 0.4, 0.33, 0.28, 0.22, 0.16, 0.12, 0.08]
        model.partialText = samples[0].raw.prefix(150) + " 그리고 아까 말했던 단축키 안내도"
        snap("1b-recording")

        model.phase = .done(samples[0], .copied)
        model.rawExpanded = false
        snap("1c-done")
        model.rawExpanded = true
        snap("1c-done-expanded")

        model.phase = .done(samples[0], .viewing)
        model.rawExpanded = false
        snap("1c-viewing")

        model.phase = .polishing
        model.pendingRaw = samples[0].raw
        model.polishNote = "gemini-3.1-flash-lite 응답이 늦어 gemini-3.6-flash 에도 요청 중…"
        snap("polishing")

        model.retryRecord = samples[0]
        model.phase = .error("정리에 실패해서 원문을 그대로 복사했어요\n\n"
            + APIErrorText.describe(service: "Gemini", code: 503,
                                    body: #"{"error":{"code":503,"message":"This model is currently experiencing high demand. Spikes in demand are usually temporary. Please try again later.","status":"UNAVAILABLE"}}"#))
        snap("error")
        model.retryRecord = nil

        model.phase = .idle
        model.screen = .history
        snap("history")

        model.screen = .main
        model.history = []
        snap("1a-idle-empty")

        let settings = SettingsModel()
        settings.usageContexts = [.devFrontend, .devMobile]
        settings.showOnboarding = true
        for tab in SettingsModel.Tab.allCases {
            settings.tab = tab
            write(render(SettingsView(model: settings)), to: dir.appendingPathComponent("2-settings-\(tab.rawValue).png"))
        }

        // 다크 모드
        model.screen = .main
        model.history = samples
        model.phase = .idle
        write(render(PopoverRoot(model: model), dark: true), to: dir.appendingPathComponent("dark-1a-idle.png"))
        model.phase = .done(samples[0], .copied)
        write(render(PopoverRoot(model: model), dark: true), to: dir.appendingPathComponent("dark-1c-done.png"))
        settings.tab = .general
        write(render(SettingsView(model: settings), dark: true), to: dir.appendingPathComponent("dark-2-settings-general.png"))

        settings.showOnboarding = false
        write(render(PersonalPane(model: settings).padding(20).frame(width: 620).background(Color.paperSoft)),
              to: dir.appendingPathComponent("2-settings-personal-full.png"))
        write(render(GeneralPane(model: settings).padding(20).frame(width: 620).background(Color.paperSoft)),
              to: dir.appendingPathComponent("2-settings-general-full.png"))

        // 설치 안내 (시안 Sokki Onboarding.dc.html 의 아트보드 이름을 그대로 쓴다)
        func wizard(_ name: String, dark: Bool = false, apple: Bool = true, _ setup: (OnboardingModel) -> Void) {
            let m = OnboardingModel(previewMode: true, appleAvailable: apple)
            setup(m)
            write(render(OnboardingView(model: m), dark: dark), to: dir.appendingPathComponent("3-onboarding-\(name).png"))
        }
        wizard("W0-welcome") { _ in }
        wizard("W1-mic-idle") { $0.step = .mic }
        wizard("W1-mic-requesting") { $0.step = .mic; $0.mic = .requesting }
        wizard("W1-mic-granted") { $0.step = .mic; $0.mic = .granted }
        wizard("W1-mic-denied") { $0.step = .mic; $0.mic = .denied }
        wizard("W2-speech-idle") { $0.step = .speech }
        wizard("W2-speech-granted-dictation-off") { $0.step = .speech; $0.speech = .granted }
        wizard("W2-speech-granted-dictation-unknown") { $0.step = .speech; $0.speech = .granted; $0.dictationEnabled = nil }
        wizard("W2-speech-done") { $0.step = .speech; $0.speech = .granted; $0.dictationEnabled = true }
        wizard("W3-model-A") { $0.step = .model }
        wizard("W3-model-B-empty", apple: false) { $0.step = .model }
        wizard("W3-model-B-verified", apple: false) { $0.step = .model; $0.keyVerified = true }
        wizard("W4-hotkey-default") { $0.step = .hotkey }
        wizard("W4-hotkey-recording") { $0.step = .hotkey; $0.recording = true }
        wizard("W4-hotkey-modifier-only") { $0.step = .hotkey; $0.presetIndex = nil; $0.hotKeyTitle = "fn⌃"; $0.hotKeyIsModifierOnly = true }
        wizard("W5-paste-default") { $0.step = .paste }
        wizard("W5-paste-waiting") { $0.step = .paste; $0.autoPaste = true }
        wizard("W5-paste-granted") { $0.step = .paste; $0.autoPaste = true; $0.accessibilityTrusted = true }
        wizard("W6-fields") { $0.step = .fields; $0.usageContexts = [.meeting, .devFrontend] }
        wizard("W7-done") { $0.step = .done }
        wizard("W0-welcome-dark", dark: true) { _ in }
        wizard("W1-mic-idle-dark", dark: true) { $0.step = .mic }

        let strip = HStack(spacing: 24) {
            ForEach([10.0, 30.0, 44.0, 60.0, 70.0, 85.0], id: \.self) { f in
                VStack(spacing: 6) {
                    SokkiLoader(size: 56, fixedFrame: f)
                    Text("\(Int(f))f").font(.system(size: 10)).foregroundColor(.text3)
                }
            }
        }.padding(20).background(Color.paper)
        write(render(strip), to: dir.appendingPathComponent("loader-frames.png"))

        write(Logo.appIcon(size: 256), to: dir.appendingPathComponent("app-icon.png"))
        write(Logo.mark(size: 72, wave: Theme.ink, dot: Theme.coral), to: dir.appendingPathComponent("logo-mark.png"))
        let menubar = Logo.menuBarIcon()
        menubar.isTemplate = false
        write(menubar, to: dir.appendingPathComponent("menubar-icon.png"))

        print("미리보기 저장: \(dir.path)")
    }

    private static func render<V: View>(_ view: V, scale: CGFloat = 2, dark: Bool = false) -> NSImage {
        let host = NSHostingView(rootView: view)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.appearance = appearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("저장 실패: \(url.lastPathComponent)"); return
        }
        try? png.write(to: url)
        print("  \(url.lastPathComponent)  \(Int(image.size.width))×\(Int(image.size.height))")
    }
}
