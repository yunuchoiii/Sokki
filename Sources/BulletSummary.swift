import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 요약 스타일에서 모델 앞뒤로 도는 코드. 온디바이스 3B 모델은 규칙을 몇 개 넘게 주면 엉뚱하게 적용해서
/// (Prompts.summaryCompact 주석 참고) 기계적으로 할 수 있는 건 여기서 한다.
enum BulletSummary {

    /// 모델에 넘기기 전. 군말을 지우고, 화제를 바꾸는 말은 문장 경계로 바꿔 모델이 거기서 요점을 나누게 한다.
    /// "아 맞다"를 그냥 두면 "처음 한 번만 맞다 다음 주까지…"처럼 두 요점이 한 불릿에 붙었다.
    static func prepare(_ raw: String) -> String {
        var s = raw
        for (from, to) in [("아 맞다", "."), ("아 그리고", ". 그리고")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        let fillers: Set<String> = ["음", "어", "아", "으음", "뭐지"]
        s = s.split(separator: " ").map(String.init).filter { word in
            !fillers.contains(word.trimmingCharacters(in: CharacterSet(charactersIn: ",.…")))
        }.joined(separator: " ")
        s = s.replacingOccurrences(of: " .", with: ".").replacingOccurrences(of: "..", with: ".")
        return dropRepeatedTail(dropRetracted(s))
    }

    /// "결제 하면은 그 다음에 아니다." 처럼 말하다 '아니다'로 거둬들인 문장. 받아쓰기가 '아니다' 뒤에 마침표를 찍어
    /// 고친 말과 다른 문장으로 끊는다. 3B 모델은 이걸 그대로 불릿으로 옮겼다(사용자가 직접 겪음, 2026-09-25).
    /// "그건 사실이 아니다"처럼 '~이/가 아니다'는 평범한 부정이라 건드리지 않는다.
    static func isRetracted(_ sentence: String) -> Bool {
        let words = sentence.trimmingCharacters(in: CharacterSet(charactersIn: " ,.")).split(separator: " ")
        guard words.count >= 2, words.last == "아니다" else { return false }
        let previous = words[words.count - 2]
        return !["이", "가", "은", "는", "도"].contains(where: { previous.hasSuffix($0) })
    }

    /// 문장은 ". " 로만 나눈다. "." 로 나누면 "3.5"가 "3. 5"로 깨졌다.
    static func sentences(_ text: String) -> [String] {
        text.components(separatedBy: ". ").map {
            var s = $0.trimmingCharacters(in: .whitespaces)
            while s.hasSuffix(".") { s.removeLast() }
            return s
        }.filter { !$0.isEmpty }
    }

    static func dropRetracted(_ text: String) -> String {
        let all = sentences(text)
        let kept = all.filter { !isRetracted($0) }
        guard kept.count < all.count, !kept.isEmpty else { return text }   // 지운 게 없으면 원문 그대로
        return kept.joined(separator: ". ") + "."
    }

    /// 끝에 앞말을 되풀이하다 끊긴 조각("… 그리고 아까 말했던 단축키 안내도.")을 뗀다. 모델에 넘기면
    /// "단축키 안내도 있음"처럼 없는 서술어를 붙여 지어냈다(2026-09-25).
    static func dropRepeatedTail(_ text: String) -> String {
        let sentences = sentences(text)
        guard sentences.count >= 2, var tail = sentences.last else { return text }
        for prefix in ["그리고 ", "근데 ", "그래서 "] where tail.hasPrefix(prefix) { tail.removeFirst(prefix.count) }
        let stem = String(tail.dropLast())   // 끝 조사는 달라도 같은 말 ("안내도" / "안내는")
        let before = sentences.dropLast().joined(separator: ". ")
        guard stem.count >= 6, before.contains(stem) else { return text }
        return before + "."
    }

    /// 모델 출력 뒤. 모든 모델 공통: 불릿 모양을 "- "로 맞추고, 끝 마침표·앞 접속사를 떼고,
    /// 되풀이한 조각과 말 고친 흔적을 정리한다.
    static func tidy(_ text: String) -> String {
        var lines: [String] = []
        for line in text.split(separator: "\n") {
            var l = line.trimmingCharacters(in: .whitespaces)
            var stripped = true
            while stripped {   // "- - 그리고 …" 처럼 겹쳐 나오기도 한다
                stripped = false
                for prefix in ["- ", "• ", "* ", "· ", "그리고 ", "그래서 ", "근데 "] where l.hasPrefix(prefix) {
                    l.removeFirst(prefix.count); stripped = true
                }
                l = l.trimmingCharacters(in: .whitespaces)
            }
            while l.hasSuffix(".") { l.removeLast() }
            if !l.isEmpty && !isRetracted(l) { lines.append(l) }
        }
        // 다른 불릿에 통째로 들어 있는 조각은 끊긴 말을 되풀이한 것이다. 끝 조사 하나는 달라도 같게 본다
        // ("단축키 안내도" ⊂ "단축키 안내는 매번 …").
        var kept: [String] = []
        for (i, line) in lines.enumerated() {
            let stem = line.count >= 6 ? String(line.dropLast()) : line
            let covered = lines.enumerated().contains { j, other in
                j != i && other.count > line.count && other.contains(stem)
            }
            if !covered && !kept.contains(line) { kept.append(line) }
        }
        return resolveCorrections(kept).map { "- " + $0 }.joined(separator: "\n")
    }

    /// 클라우드 모델이 말하지 않은 단위·시간대를 붙인 걸 뗀다. 프롬프트에 규칙과 예시를 넣어도 Gemini(3.1-flash-lite,
    /// 3.6-flash 둘 다)가 "예산은 칠백"을 "700만 원"으로, "열 시"를 "오전 10시"로 계속 바꿨다(2026-09-25).
    /// 원문에 그 말이 한 번도 없을 때만 뗀다 — "아침 아홉 시" → "오전 9시" 처럼 말한 걸 바꿔 쓴 건 둔다.
    static func removeUnsaidUnits(_ text: String, raw: String) -> String {
        var out = text
        if !["오전", "오후", "아침", "저녁", "밤", "낮", "새벽"].contains(where: raw.contains) {
            out = out.replacingOccurrences(of: "오전 ", with: "").replacingOccurrences(of: "오후 ", with: "")
        }
        if !raw.contains("만") {
            out = out.replacingOccurrences(of: "만 원", with: "").replacingOccurrences(of: "만원", with: "")
        }
        return out
    }

    /// 불릿의 단어가 원문과 같은 순서로 나오는지. 3B 모델은 원문을 거의 그대로 가져다 쓰므로 순서가 어긋났으면
    /// 뜻이 뒤집혔을 가능성이 크다. "일정을 미루자는 게 아니라 범위를 줄이자는 거예요"를 3번에 2번꼴로
    /// "범위를 줄이는 것이 아니라 일정을 미루는 것이 아니라"로 뒤집었다. 26가지 원문 × 3회에서 이 둘만 걸렸다(오탐 0).
    /// 단어는 앞 두 글자로 비교한다(조사·어미가 바뀌어도 같은 말로 본다). 원문에 없는 단어는 판단에서 뺀다.
    /// 부정어("아니라", "않고", "없어", "못 해")는 자리 하나만 옮겨도 뜻이 뒤집혀서 하나라도 어긋나면 실패로 본다
    /// ("범위를 줄이는 것이 아니라 …" 는 어긋난 단어가 "아니라" 하나뿐이라 비율로는 통과했다).
    static func isFaithful(_ point: String, to raw: String) -> Bool {
        func stems(_ s: String) -> [String] {
            s.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "." }).map(String.init)
                .filter { $0.count >= 2 }.map { String($0.prefix(2)) }
        }
        let negations = ["아니", "않", "없", "못"]
        let source = stems(raw)
        var cursor = 0, inOrder = 0, outOfOrder = 0
        for stem in stems(point) {
            if let i = source[cursor...].firstIndex(of: stem) { inOrder += 1; cursor = i + 1 }
            else if source.contains(stem) {
                if negations.contains(where: { stem.hasPrefix($0) }) { return false }
                outOfOrder += 1
            }
        }
        return outOfOrder < 2 || Double(inOrder) / Double(inOrder + outOfOrder) >= 0.75
    }

    /// "예산은 오백 정도 … 아니다 칠백으로 하죠" → "예산은 칠백으로 하죠".
    /// 3B 모델은 지시해도 말 고친 걸 못 거른다(2026-09-25, 4회 중 0회). 고친 말의 주제어("~은/는")부터를
    /// 새 말로 바꾸고, 그 앞은 살린다 — 앞 불릿을 통째로 버렸더니 같은 불릿의 "캠페인은 릴스 위주"까지 날아갔다.
    static func resolveCorrections(_ lines: [String]) -> [String] {
        /// 마지막 주제어부터 끝까지를 잘라 (앞부분, 주제어)로 돌려준다
        func splitAtLastTopic(_ s: String) -> (head: String, topic: String?) {
            let words = s.split(separator: " ").map(String.init)
            guard let i = words.lastIndex(where: { $0.count >= 2 && ($0.hasSuffix("은") || $0.hasSuffix("는")) })
            else { return ("", nil) }
            return (words[..<i].joined(separator: " "), words[i])
        }
        var out: [String] = []
        for line in lines {
            guard let r = line.range(of: "아니다 ", options: .backwards) else { out.append(line); continue }
            let after = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            let before = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard !after.isEmpty else { out.append(line); continue }
            if before.isEmpty, let previous = out.popLast() {
                // "아니다 …"로 시작하면 앞 불릿의 끝을 고친 것이다
                let (head, topic) = splitAtLastTopic(previous)
                if !head.isEmpty { out.append(head) }
                out.append([topic, after].compactMap { $0 }.joined(separator: " "))
            } else {
                let (head, topic) = splitAtLastTopic(before)
                out.append([head, topic, after].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
            }
        }
        return out
    }
}

#if canImport(FoundationModels)
/// 온디바이스 요약은 구조화 출력으로 받는다. 자유 텍스트로 받으면 요점을 덜 나눴고
/// 한 불릿에 "~고"로 사실 서너 개를 이어 붙였다(2026-09-25 실측).
@available(macOS 26.0, *)
@Generable
struct OnDeviceSummary {
    @Guide(description: "Key points of the memo, in Korean. Each item is one short sentence reusing the speaker's own words.",
           .count(1...7))
    var points: [String]
}
#endif
