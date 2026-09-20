import AppKit

/// GitHub 릴리스와 현재 버전을 비교해 새 버전을 알려 준다. 앱을 교체하진 않는다 — 다운로드 링크를 열어 주고
/// 사용자가 DMG 를 Applications 에 끌어 넣는다. 스스로 교체하는 자동 업데이트(Sparkle)는 사용자가 늘면 그때.
enum UpdateChecker {

    struct Release {
        let version: String      // "0.4.1"
        let tag: String          // "v0.4.1"
        let notes: String        // 릴리스 본문에서 뽑은 불릿
        let pageURL: String
    }

    enum CheckError: LocalizedError {
        case badResponse(Int)
        case noTag
        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "GitHub 응답 오류 (HTTP \(code))"
            case .noTag: return "릴리스 정보를 읽지 못했습니다"
            }
        }
    }

    static let latestAPI = URL(string: "https://api.github.com/repos/yunuchoiii/brefly/releases/latest")!
    /// README·랜딩 페이지가 쓰는 바로 받기 주소. 고정 이름이라 늘 최신을 가리킨다.
    /// 앱에서는 쓰지 않는다 — 아래 downloadURL(for:) 설명 참고.
    static let freshInstallURL = URL(string: "https://github.com/yunuchoiii/brefly/releases/latest/download/Brefly.dmg")!

    /// 앱 안에서 업데이트를 받을 때 쓰는 주소. 고정 이름이 아니라 **버전 붙은 파일명**을 가리킨다.
    ///
    /// 둘을 갈라 두면 GitHub 이 세어 주는 에셋별 다운로드 수만으로 신규와 기존을 구분할 수 있다.
    ///   Brefly.dmg        → README·랜딩 페이지를 보고 처음 받는 사람
    ///   Brefly-X.Y.Z.dmg  → 이미 쓰고 있다가 업데이트하는 사람 (= 실사용자 하한선)
    /// 추적 코드를 넣지 않고 얻는 지표다. 앱이 보내는 요청은 전과 똑같다.
    ///
    /// ⚠️ 릴리스에 버전 붙은 DMG 를 같이 올리지 않으면 이 링크가 404 가 된다.
    ///    make-dmg.sh 가 두 파일을 다 만들고 배포 절차가 둘 다 올린다(README 참고).
    static func downloadURL(for release: Release) -> URL {
        URL(string: "https://github.com/yunuchoiii/brefly/releases/download/\(release.tag)/Brefly-\(release.version).dmg")
            ?? freshInstallURL
    }
    static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: 조회

    /// 최신 릴리스를 가져온다. 성공 시 현재보다 새 버전이면 Release, 아니면 nil.
    static func check(current: String = currentVersion, completion: @escaping (Result<Release?, Error>) -> Void) {
        var req = URLRequest(url: latestAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Brefly/\(current)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, response, error in
            let result: Result<Release?, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(CheckError.badResponse(http.statusCode))
            } else if let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String {
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let release = Release(version: version, tag: tag,
                                      notes: summarize(json["body"] as? String ?? ""),
                                      pageURL: json["html_url"] as? String ?? "https://github.com/yunuchoiii/brefly/releases")
                result = .success(isNewer(version, than: current) ? release : nil)
            } else {
                result = .failure(CheckError.noTag)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// "0.4.10" > "0.4.9" 처럼 숫자 단위로 비교한다. 문자열 비교면 "0.4.10" < "0.4.9" 가 된다.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 릴리스 본문(마크다운)에서 "바뀐 것" 불릿만 평문으로. 굵게 표시(**)는 벗긴다.
    static func summarize(_ body: String) -> String {
        let sections = body.components(separatedBy: "## ")
        let picked = sections.first { $0.hasPrefix("바뀐 것") } ?? sections.first { $0.contains("\n- ") } ?? ""
        let bullets = picked.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .map { "• " + $0.dropFirst(2).replacingOccurrences(of: "**", with: "") }
        return bullets.joined(separator: "\n")
    }

    // MARK: 자동 확인

    /// 실행할 때 부른다. 하루에 한 번만, "나중에"를 누른 버전은 다시 묻지 않는다.
    static func checkAutomaticallyIfDue() {
        guard Prefs.autoCheckUpdates else { return }
        if let last = Prefs.lastUpdateCheck, Date().timeIntervalSince(last) < autoCheckInterval { return }
        Prefs.lastUpdateCheck = Date()
        check { result in
            switch result {
            case .success(let release?):
                if release.version == Prefs.skippedUpdateVersion {
                    Log.write("새 버전 \(release.version) 있음 — 사용자가 건너뛴 버전이라 조용히 넘어감")
                    return
                }
                Log.write("새 버전 \(release.version) 있음 (현재 \(currentVersion))")
                present(release, manual: false)
            case .success(nil):
                Log.write("업데이트 확인: 최신 버전 (\(currentVersion))")
            case .failure(let error):
                Log.write("업데이트 확인 실패: \(error.localizedDescription)")
            }
        }
    }

    /// 설정의 "업데이트 확인" 버튼. 건너뛴 버전도 다시 보여 주고, 최신이면 그렇다고 말한다.
    static func checkManually() {
        check { result in
            switch result {
            case .success(let release?):
                present(release, manual: true)
            case .success(nil):
                let alert = NSAlert()
                alert.messageText = "최신 버전입니다"
                alert.informativeText = "Brefly \(currentVersion) 이 가장 최근 버전입니다."
                alert.addButton(withTitle: "확인")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "업데이트를 확인하지 못했습니다"
                alert.informativeText = error.localizedDescription + "\n인터넷 연결을 확인하고 다시 시도해 주세요."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "확인")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    private static func present(_ release: Release, manual: Bool) {
        let alert = NSAlert()
        alert.messageText = "Brefly \(release.version) 이 나왔습니다"
        var info = "지금 버전은 \(currentVersion) 입니다."
        if !release.notes.isEmpty { info += "\n\n바뀐 것\n" + release.notes }
        info += "\n\n다운로드를 누르면 DMG 를 받습니다. 열어서 Brefly 를 Applications 에 끌어 넣으면 됩니다."
        alert.informativeText = info
        alert.addButton(withTitle: "다운로드")
        alert.addButton(withTitle: "나중에")
        alert.addButton(withTitle: "바뀐 점 자세히")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(downloadURL(for: release))
            Log.write("업데이트 다운로드 열기: \(release.version)")
        case .alertThirdButtonReturn:
            if let url = URL(string: release.pageURL) { NSWorkspace.shared.open(url) }
        default:
            if !manual { Prefs.skippedUpdateVersion = release.version }
            Log.write("업데이트 \(release.version) 나중에")
        }
    }
}
