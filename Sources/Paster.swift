import AppKit
import ApplicationServices

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

    static func paste(_ text: String, restoreClipboard: Bool = true) {
        let pb = NSPasteboard.general

        // 기존 클립보드 문자열만 백업한다 (이미지·파일까지 완벽 복원은 MVP 범위 밖).
        let previous = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        // 클립보드 반영이 끝난 뒤 키 이벤트를 쏜다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            sendCommandV()

            guard restoreClipboard, let previous else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // 그 사이 사용자가 다른 걸 복사했으면 건드리지 않는다.
                if pb.string(forType: .string) == text {
                    pb.clearContents()
                    pb.setString(previous, forType: .string)
                }
            }
        }
    }

    private static func sendCommandV() {
        let vKey: CGKeyCode = 0x09 // kVK_ANSI_V
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        src.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
