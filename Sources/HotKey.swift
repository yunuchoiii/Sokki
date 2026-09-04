import Foundation
import Carbon.HIToolbox
import AppKit

/// Carbon 전역 핫키. 접근성 권한 없이도 등록되며 어느 앱이 앞에 있든 동작한다.
enum HotKey {

    private static var handlerRef: EventHandlerRef?
    private static var hotKeyRef: EventHotKeyRef?
    private static var action: (() -> Void)?

    /// 예: register(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    @discardableResult
    static func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        unregister()
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async { HotKey.action?() }
                return noErr
            },
            1, &spec, nil, &handlerRef
        )
        guard installStatus == noErr else { return false }

        // 'SOKG' 시그니처
        let id = EventHotKeyID(signature: OSType(0x534F4B47), id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, id,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        return registerStatus == noErr
    }

    static func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        action = nil
    }
}

/// 키 코드 + Carbon 수정자 조합. 프리셋이든 직접 녹음한 것이든 이 하나로 다룬다.
struct HotKeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// keyCode 가 이 값이면 "수정자 키만 눌렀다 떼는" 단축키 (예: fn⌃). Carbon 이 아니라 이벤트 모니터로 잡는다.
    static let modifierOnlyKeyCode: UInt32 = 0xFFFF
    /// Carbon 에는 fn 이 없어서 앱에서만 쓰는 비트.
    static let fnFlag: UInt32 = 1 << 20

    var isModifierOnly: Bool { keyCode == Self.modifierOnlyKeyCode }

    /// "⌃⌥Space", "fn⌃" 처럼 표시
    var title: String { isModifierOnly ? modifierSymbols : modifierSymbols + Self.keyName(keyCode) }

    var modifierSymbols: String {
        var t = ""
        if modifiers & Self.fnFlag != 0            { t += "fn" }
        if modifiers & UInt32(controlKey) != 0 { t += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { t += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { t += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { t += "⌘" }
        return t
    }

    /// NSEvent 의 수정자 플래그를 Carbon 값으로. fn 은 뺀다 (화살표·F키 이벤트에도 .function 이 붙는다).
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    /// 수정자 전용 단축키용: fn 까지 포함.
    static func modifierBits(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m = carbonModifiers(from: flags)
        if flags.contains(.function) { m |= fnFlag }
        return m
    }

    static func keyName(_ code: UInt32) -> String {
        if let n = keyNames[Int(code)] { return n }
        return "키\(code)"
    }

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`"
    ]
}

/// 수정자 키만 눌렀다 떼면 발동하는 단축키. 다른 키가 끼면 취소된다 (⌃C 같은 입력에 안 걸린다).
/// 전역 이벤트 모니터라 손쉬운 사용 권한이 있어야 다른 앱 위에서 동작한다.
enum ModifierHotKey {
    private static var monitors: [Any] = []
    private static var target: UInt32 = 0
    private static var armed = false

    static var isAvailable: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func register(_ combo: HotKeyCombo, action: @escaping () -> Void) -> Bool {
        unregister()
        guard combo.isModifierOnly, combo.modifiers != 0, isAvailable else { return false }
        target = combo.modifiers

        let handle: (NSEvent) -> Void = { event in
            guard event.type == .flagsChanged else { armed = false; return }
            let now = HotKeyCombo.modifierBits(from: event.modifierFlags)
            if now == target {
                armed = true
            } else if armed, now & target != target {
                armed = false
                DispatchQueue.main.async(execute: action)
            } else {
                armed = false
            }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handle) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { handle($0); return $0 }) {
            monitors.append(l)
        }
        return !monitors.isEmpty
    }

    static func unregister() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        armed = false
    }
}

/// 단축키 프리셋. 메뉴에서 고를 수 있게 해 둔다.
struct HotKeyPreset {
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotKeyPreset] = [
        HotKeyPreset(title: "⌃⌥Space", keyCode: UInt32(kVK_Space),
                     modifiers: UInt32(controlKey | optionKey)),
        HotKeyPreset(title: "⌥Space", keyCode: UInt32(kVK_Space),
                     modifiers: UInt32(optionKey)),
        HotKeyPreset(title: "⌃⌥D", keyCode: UInt32(kVK_ANSI_D),
                     modifiers: UInt32(controlKey | optionKey)),
        HotKeyPreset(title: "⌘⇧Space", keyCode: UInt32(kVK_Space),
                     modifiers: UInt32(cmdKey | shiftKey))
    ]

    static func preset(at index: Int) -> HotKeyPreset {
        all.indices.contains(index) ? all[index] : all[0]
    }

    var combo: HotKeyCombo { HotKeyCombo(keyCode: keyCode, modifiers: modifiers) }
}
