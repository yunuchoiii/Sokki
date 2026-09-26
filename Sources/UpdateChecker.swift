import AppKit

/// GitHub 릴리스와 현재 버전을 비교해 새 버전을 알려 준다. 앱을 교체하진 않는다 — 다운로드 링크를 열어 주고
/// 실제 업데이트는 Sparkle(`Updater`)이 한다. 여기 남은 건 `--check-update` 진단 플래그가 쓰는
/// GitHub 릴리스 API 조회뿐이다 — appcast 와 무관하게 "지금 최신이 뭔지"를 확인할 때 쓴다.
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

}
