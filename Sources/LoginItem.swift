import ServiceManagement

/// 로그인할 때 Brefly 를 자동으로 띄울지. 설정 창과 설치 마법사가 같이 쓴다.
///
/// macOS 13 의 `SMAppService` 를 쓴다. 등록하면 시스템 설정 > 일반 > 로그인 항목에 앱이 나타나고,
/// 사용자가 거기서 끄면 상태가 `.requiresApproval` 이 된다 — 그때는 우리가 다시 켤 수 없다.
enum LoginItem {

    /// 지금 실제로 켜져 있는지. 시스템이 정답이라 Prefs 에 따로 저장하지 않는다.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// 켜거나 끈다. 실패하면 사람이 읽을 메시지를 돌려주고, 성공하면 nil.
    /// 앱이 /Applications 밖(예: 빌드 폴더)에 있거나 서명이 불안정하면 등록이 거부될 수 있다.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            return "설정 실패: \(error.localizedDescription)"
        }
        // register() 가 성공해도 사용자가 시스템 설정에서 꺼 둔 상태면 .requiresApproval 로 남는다.
        if on && !isEnabled {
            return "시스템 설정 > 일반 > 로그인 항목에서 Brefly 를 켜 주세요."
        }
        return nil
    }
}
