import AppKit
import ApplicationServices
import Carbon

/// 클립보드를 잠깐 빌려 커서 위치에 텍스트를 붙여 넣는다.
enum Paster {

    /// 접근성 권한 여부. 없으면 Cmd+V 합성이 조용히 실패한다.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        // kAXTrustedCheckOptionPrompt는 SDK 버전에 따라 Unmanaged<CFString>으로
        // 들어오기도 해서 리터럴 키를 직접 쓴다.
        let key = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// 합성 Cmd+V 가 막히는 또 다른 경우. 암호 필드처럼 보안 입력이 켜져 있으면 이벤트가 조용히 버려진다.
    static var secureInputOn: Bool { IsSecureEventInputEnabled() }

    /// 붙여넣기를 시도한다. 키 이벤트를 만들어 쏘았으면 true.
    /// ⚠️ true 는 "이벤트를 보냈다"는 뜻이지 "대상 앱이 받았다"는 보장은 아니다. 초점은 호출하는 쪽이 책임진다.
    @discardableResult
    static func paste(_ text: String, restoreClipboard: Bool = true) -> Bool {
        let pb = NSPasteboard.general

        // 기존 클립보드 문자열만 백업한다 (이미지·파일까지 완벽 복원은 MVP 범위 밖).
        let previous = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        // 클립보드 반영이 끝날 틈을 준 뒤 키 이벤트를 쏜다. 0.08초는 실측으로 정한 값이다.
        Thread.sleep(forTimeInterval: 0.08)
        let sent = sendCommandV()

        if restoreClipboard, let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // 그 사이 사용자가 다른 걸 복사했으면 건드리지 않는다.
                if pb.string(forType: .string) == text {
                    pb.clearContents()
                    pb.setString(previous, forType: .string)
                }
            }
        }
        return sent
    }

    @discardableResult
    private static func sendCommandV() -> Bool {
        let vKey: CGKeyCode = 0x09 // kVK_ANSI_V

        // 지금 시스템이 눌려 있다고 보는 수정자. fn⌃ 같은 수정자 전용 단축키를 쓰면
        // 손을 뗀 뒤에도 여기에 남아 있는 경우가 있다.
        let live = CGEventSource.flagsState(.combinedSessionState)
        if !live.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty {
            Log.write("붙여넣기 직전 수정자 잔류: \(describe(live))")
        }

        // ⚠️ .combinedSessionState 를 쓰면 합성 이벤트의 플래그가 **하드웨어 수정자 상태와 합쳐진다.**
        // fn 이 하나라도 남아 있으면 ⌘V 가 fn⌘V 가 되어 붙여넣기가 아닌 키가 된다.
        // .privateState 는 이 소스만의 수정자 상태를 따로 갖기 때문에 오염되지 않는다.
        guard let src = CGEventSource(stateID: .privateState) else { return false }
        src.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        // ⚠️ Command 키를 **실제로 눌렀다 떼는 이벤트**를 앞뒤로 넣어야 한다.
        // 네이티브 AppKit 은 keyDown 에 박힌 flags 만 봐도 붙여넣지만, Chromium 계열
        // (Chrome · Brave · Electron 앱)은 수정자 상태를 flagsChanged 로 따로 추적한다.
        // Command 가 눌렸다는 이벤트를 못 보면 그냥 "V"를 누른 것으로 처리해 아무 일도 안 일어난다.
        let cmdKey: CGKeyCode = 0x37 // kVK_Command
        guard let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: true),
              let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: false)
        else { return false }

        // 수정자 키 자체는 flagsChanged 로 나가야 한다.
        cmdDown.type = .flagsChanged
        cmdUp.type = .flagsChanged
        cmdDown.flags = .maskCommand
        // 다른 플래그가 섞이지 않게 Command 만 남긴다.
        down.flags = .maskCommand
        up.flags = .maskCommand
        cmdUp.flags = []

        cmdDown.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
        return true
    }

    private static func describe(_ f: CGEventFlags) -> String {
        var names: [String] = []
        if f.contains(.maskCommand) { names.append("⌘") }
        if f.contains(.maskControl) { names.append("⌃") }
        if f.contains(.maskAlternate) { names.append("⌥") }
        if f.contains(.maskShift) { names.append("⇧") }
        if f.contains(.maskSecondaryFn) { names.append("fn") }
        return names.isEmpty ? "없음" : names.joined()
    }
}
