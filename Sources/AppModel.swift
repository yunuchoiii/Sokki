import AppKit
import Combine

/// 팝오버가 그리는 상태. AppDelegate가 갱신하고 SwiftUI가 관찰한다.
final class AppModel: ObservableObject {

    enum Delivery {
        case copied     // 클립보드 복사
        case pasted     // 커서 위치에 붙여넣음
        case viewing    // 기록에서 열어 본 것 — 토스트 없음
    }

    enum Phase {
        case idle
        case recording
        case polishing
        case done(SummaryRecord, Delivery)
        case error(String)
    }

    enum Screen {
        case main
        case history
    }

    @Published var phase: Phase = .idle
    @Published var screen: Screen = .main

    // 녹음 중
    @Published var elapsed: TimeInterval = 0
    /// 최근 파형 레벨. [0]이 가장 새 값. 0…1.
    @Published var levels: [Float] = Array(repeating: 0, count: 11)
    @Published var partialText = ""

    // 완료 화면
    @Published var rawExpanded = false

    // 오류 화면: 정리에 실패한 기록이 있으면 "다시 요약" 버튼을 보여준다
    @Published var retryRecord: SummaryRecord?

    // 환경
    @Published var history: [SummaryRecord] = HistoryStore.load()
    @Published var micReady = false
    @Published var hotKeyTitle = Prefs.currentHotKey.title
    @Published var localeID = Prefs.localeID
    @Published var autoStop = Prefs.autoStopOnSilence
    @Published var backendTitle = Prefs.backend.title
    /// 요약 중 화면의 진행 상황 한 줄
    @Published var polishNote = ""
    /// 지금 요약 중인 원문. 취소·원문 복사 버튼용.
    @Published var pendingRaw = ""

    /// 뷰가 호출하는 동작. AppDelegate가 채운다.
    struct Actions {
        var startRecording: () -> Void = {}
        var finishRecording: () -> Void = {}
        var cancelRecording: () -> Void = {}
        var openSettings: () -> Void = {}
        var quit: () -> Void = {}
        var copy: (SummaryRecord) -> Void = { _ in }
        var copyRaw: (SummaryRecord) -> Void = { _ in }
        var resummarize: (SummaryRecord) -> Void = { _ in }
        var delete: (SummaryRecord) -> Void = { _ in }
        var openLog: () -> Void = {}
        var dismissError: () -> Void = {}
        var cancelPolish: () -> Void = {}
        var copyPendingRaw: () -> Void = {}
    }
    var actions = Actions()

    func pushLevel(_ level: Float) {
        levels.removeLast()
        levels.insert(level, at: 0)
    }

    func resetRecording() {
        elapsed = 0
        partialText = ""
        levels = Array(repeating: 0, count: 11)
    }

    func refreshPrefs() {
        hotKeyTitle = Prefs.currentHotKey.title
        localeID = Prefs.localeID
        autoStop = Prefs.autoStopOnSilence
        backendTitle = Prefs.backend.title
    }

    func upsert(_ record: SummaryRecord) {
        if let i = history.firstIndex(where: { $0.id == record.id }) {
            history[i] = record
        } else {
            history.insert(record, at: 0)
        }
        HistoryStore.save(history)
    }

    func remove(_ record: SummaryRecord) {
        history.removeAll { $0.id == record.id }
        HistoryStore.save(history)
    }
}
