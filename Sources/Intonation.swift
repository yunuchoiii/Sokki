import AVFoundation

/// 말 끝 억양. "밥 먹었어"와 "밥 먹었어?"는 글자로 같고 억양으로만 갈린다. 받아쓰기는 문장부호를 멋대로 찍어서
/// 글자만 보는 모델은 같은 입력에 한 번은 물음표, 한 번은 마침표를 찍었다(2026-09-25).
/// 애플 음성 인식의 voiceAnalytics 는 단어 구간이 마지막 음절 전에 잘려(0.6초) 올린 억양이 평평하게 나왔다.
/// 그래서 녹음 소리의 끝부분에서 음높이를 직접 잰다. 녹음 전체의 마지막 문장만 볼 수 있다.
struct Intonation {
    enum Direction: String { case rising = "올라감", falling = "내려감", flat = "평평함" }
    let direction: Direction
    /// 마지막 0.35초 동안 오른 반음 (최소제곱 기울기)
    let semitones: Double
    let voicedFrames: Int
}

/// 녹음 마지막 몇 초를 모아 두고 끝 억양을 잰다. append 는 오디오 스레드, analyze 는 녹음이 멈춘 뒤 부른다.
final class IntonationTracker {

    private var samples: [Float] = []
    private var sampleRate: Double = 48_000
    private let keepSeconds = 2.5
    private let lock = NSLock()

    func reset() {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        lock.lock()
        sampleRate = buffer.format.sampleRate
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        let limit = Int(keepSeconds * sampleRate)
        if samples.count > limit * 2 { samples.removeFirst(samples.count - limit) }   // 가끔만 잘라 복사를 줄인다
        lock.unlock()
    }

    func analyze() -> Intonation? {
        lock.lock()
        let rate = sampleRate
        let all = samples.suffix(Int(keepSeconds * rate))
        lock.unlock()

        // 16kHz 로 솎아 계산량을 줄인다. 음높이(70~400Hz)에는 충분하다.
        let step = max(1, Int(rate / 16_000))
        let sr = rate / Double(step)
        let x = stride(from: all.startIndex, to: all.endIndex, by: step).map { all[$0] }
        guard x.count > Int(sr * 0.5) else { return nil }

        // 말이 끝난 곳: 단축키를 누르기 전 침묵을 건너뛴다. 20ms 에너지가 최대의 10% 를 넘는 마지막 지점.
        let hop = Int(sr * 0.01), win = Int(sr * 0.04)
        func rms(_ a: Int, _ b: Int) -> Float {
            var s: Float = 0; for i in a..<b { s += x[i] * x[i] }; return sqrt(s / Float(b - a))
        }
        let energyFrame = Int(sr * 0.02)
        let energies = stride(from: 0, to: x.count - energyFrame, by: energyFrame).map { rms($0, $0 + energyFrame) }
        guard let peak = energies.max(), peak > 0.003,
              let lastLoud = energies.lastIndex(where: { $0 > max(peak * 0.1, 0.003) }) else { return nil }
        let speechEnd = (lastLoud + 1) * energyFrame
        let start = max(0, speechEnd - Int(sr * 0.8))

        // 프레임마다 정규화 자기상관으로 기본 주파수를 찾는다. 탐색 범위 끝에 걸린 값은 잡음이다
        // (전부 400Hz 로 찍힌 녹음이 있었다).
        let minLag = Int(sr / 400), maxLag = Int(sr / 70)
        var track: [(t: Double, hz: Double)] = []
        var i = start
        while i + win + maxLag < min(x.count, speechEnd + win) {
            var best = 0.0, bestLag = 0
            for lag in minLag...maxLag {
                var xy: Float = 0, xx: Float = 0, yy: Float = 0
                for k in 0..<win {
                    let a = x[i + k], b = x[i + k + lag]
                    xy += a * b; xx += a * a; yy += b * b
                }
                let r = xx > 0 && yy > 0 ? Double(xy / sqrt(xx * yy)) : 0
                if r > best { best = r; bestLag = lag }
            }
            if best > 0.5, bestLag > minLag, bestLag < maxLag { track.append((Double(i) / sr, sr / Double(bestLag))) }
            i += hop
        }
        guard track.count >= 8 else { return nil }

        // 반음으로 바꾸고, 앞뒤 다섯 프레임 중앙값에서 3반음 넘게 튄 프레임은 버린다. 말 끝에서 소리가 흐려지며
        // 음높이를 반으로 잡는 옥타브 오류가 "-7 -7 -7"로 나와 올린 억양을 "내려감"으로 뒤집었다.
        func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
        let center = median(track.map(\.hz))
        let raw = track.map { (t: $0.t, st: 12 * log2($0.hz / center)) }
        let st = raw.indices.compactMap { k -> (t: Double, st: Double)? in
            let near = raw[max(0, k - 2)...min(raw.count - 1, k + 2)].map(\.st)
            return abs(raw[k].st - median(near)) <= 3 ? raw[k] : nil
        }
        // 말이 끝나며 소리가 흐려지는 마지막 세 프레임은 버린다. "+2 +2 +1 +1 +1 -6"처럼 끝 한 프레임이
        // 튀어 올린 억양을 평평하게 만들었다(사람 목소리, 2026-09-25). 몰려서 튀면 이웃 중앙값 필터로도 안 걸린다.
        let steady = Array(st.dropLast(3))
        guard steady.count >= 6, let lastT = steady.last?.t else { return nil }

        // 마지막 0.35초의 기울기(최소제곱). 끝 몇 프레임만 비교하면 한두 프레임에 휘둘렸다.
        let window = steady.filter { $0.t >= lastT - 0.35 }
        guard window.count >= 5 else { return nil }
        let mt = window.map(\.t).reduce(0, +) / Double(window.count)
        let ms = window.map(\.st).reduce(0, +) / Double(window.count)
        let num = window.reduce(0) { $0 + ($1.t - mt) * ($1.st - ms) }
        let den = window.reduce(0) { $0 + ($1.t - mt) * ($1.t - mt) }
        guard den > 0 else { return nil }
        let rise = num / den * 0.35   // 0.35초 동안 오른 반음
        // 사람 목소리는 TTS(±5~11반음)보다 차이가 작다(±2~5). 2.5반음 넘을 때만 방향을 정하고 나머진 평평함으로 둔다.
        let direction: Intonation.Direction = rise >= 2.5 ? .rising : (rise <= -2.5 ? .falling : .flat)
        let shape = steady.suffix(30).map { String(format: "%+.0f", $0.st) }.joined(separator: " ")
        Log.write(String(format: "억양(직접 측정): 끝 %+.1f반음 → %@ (유성 %d프레임, 기준 %.0fHz)\n  반음 흐름: %@",
                         rise, direction.rawValue, steady.count, center, shape))
        return Intonation(direction: direction, semitones: rise, voicedFrames: st.count)
    }
}
