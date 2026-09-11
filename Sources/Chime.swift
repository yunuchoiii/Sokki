import AppKit

/// 녹음 시작·종료 알림음 "띠딩". 시스템 소리엔 두 음 차임이 없어 사인파 두 음을 합성한다.
/// 시작은 올라가는 음(G5 → C6), 종료는 내려가는 음(C6 → G5). WAV 를 메모리에서 만들어 NSSound 로 재생.
enum Chime {
    enum Kind { case start, stop }

    private static var cache: [Kind: NSSound] = [:]

    static func play(_ kind: Kind, volume: Float = 0.5) {
        let sound: NSSound
        if let cached = cache[kind] {
            sound = cached
        } else {
            guard let s = NSSound(data: wav(for: kind)) else { return }
            cache[kind] = s
            sound = s
        }
        sound.stop()
        sound.volume = volume
        sound.play()
    }

    // MARK: - 합성

    private static let sampleRate = 44_100.0

    private static func wav(for kind: Kind) -> Data {
        let g5 = 783.99, c6 = 1046.50
        let (f1, f2) = kind == .start ? (g5, c6) : (c6, g5)
        var samples: [Float] = []
        samples += tone(f1, seconds: 0.09)
        samples += [Float](repeating: 0, count: Int(sampleRate * 0.02))
        samples += tone(f2, seconds: 0.16)
        return wavData(samples)
    }

    /// 사인파 + 약간의 배음(부드러운 종소리 느낌), 8ms 어택 / 끝으로 갈수록 감쇠.
    private static func tone(_ freq: Double, seconds: Double) -> [Float] {
        let n = Int(sampleRate * seconds)
        let attack = Int(sampleRate * 0.008)
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            let env: Double
            if i < attack { env = Double(i) / Double(attack) }
            else { env = pow(1.0 - Double(i - attack) / Double(n - attack), 1.6) }
            let v = sin(2 * .pi * freq * t) + 0.25 * sin(2 * .pi * freq * 2 * t)
            return Float(v / 1.25 * env * 0.8)
        }
    }

    private static func wavData(_ samples: [Float]) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32767)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)          // PCM, mono
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)     // byte rate, block align, bits
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
