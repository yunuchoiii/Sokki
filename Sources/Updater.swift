import AppKit
import Sparkle

/// 앱이 스스로 업데이트를 받아 교체한다.
///
/// 예전에는 새 버전이 있으면 알림창을 띄우고 브라우저로 DMG 주소를 열어 줬다. 그러면 사용자가
/// 앱을 끄고, DMG 를 열고, Applications 로 끌어넣고, 교체 확인까지 눌러야 했다. 네 단계다.
/// Sparkle 은 내려받기·교체·재시작을 다 한다 — 사용자는 "설치"만 누른다.
///
/// 설정은 Info.plist 에 있다.
///   SUFeedURL               appcast.xml 주소 (brefly-pages 에 올린다)
///   SUPublicEDKey           업데이트 서명 검증용 공개키
///   SUEnableAutomaticChecks 자동 확인 켬
///   SUScheduledCheckInterval 86400초(하루)
///
/// ⚠️ 서명 개인키를 잃으면 기존 사용자에게 업데이트를 영영 보낼 수 없다.
///    로그인 키체인의 "Private key for signing Sparkle updates" 항목이다.
enum Updater {

    /// Sparkle 이 앱이 사는 동안 살아 있어야 해서 전역으로 붙잡아 둔다.
    private static var controller: SPUStandardUpdaterController?

    /// 앱 시작 때 한 번. 이후 확인 주기는 Sparkle 이 알아서 관리한다.
    static func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        Log.write("Sparkle 시작 — 자동 확인 \(Prefs.autoCheckUpdates ? "켬" : "끔")")
        controller?.updater.automaticallyChecksForUpdates = Prefs.autoCheckUpdates
    }

    /// 설정 > 업데이트 의 "확인" 버튼. 최신이어도 결과 창을 띄운다.
    static func checkManually() {
        guard let controller else {
            Log.write("Sparkle 이 아직 시작되지 않아 수동 확인을 건너뜀")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// 설정에서 자동 확인을 켜고 끌 때 Sparkle 에도 알려 준다.
    static func setAutomaticChecks(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
    }

    /// 마지막으로 확인한 시각. 설정 화면에 보여 줄 수 있다.
    static var lastCheckDate: Date? { controller?.updater.lastUpdateCheckDate }
}
