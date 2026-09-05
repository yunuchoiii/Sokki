import Foundation
import AVFoundation
import Speech

enum RecorderError: LocalizedError {
    case recognizerUnavailable(String)
    case notAuthorized
    case micDenied
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable(let locale):
            return "'\(locale)' 음성 인식을 쓸 수 없습니다. 시스템 설정 > 키보드 > 받아쓰기를 켜고 해당 언어를 추가하세요."
        case .notAuthorized:
            return "음성 인식 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 음성 인식에서 Sokki를 켜세요."
        case .micDenied:
            return "마이크 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 Sokki를 켜세요."
        case .noInputDevice:
            return "입력 장치를 찾지 못했습니다. 시스템 설정 > 사운드 > 입력에서 마이크를 확인하세요."
        }
    }
}

/// 마이크 입력을 받아 Apple Speech 프레임워크로 실시간 받아쓰기한다.
final class SpeechRecorder {

    /// 녹음마다 새로 만들고 끝나면 놓아준다. 엔진을 앱 수명 동안 붙들고 있으면 stop() 뒤에도 에어팟이
    /// 통화 모드(출력 볼륨 낮춤·마이크 48kHz)에 남는다 — 객체가 해제될 때만 원래대로 돌아온다. reset() 도 소용없다 (2026-09-05 실측).
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    private var latest = ""
    private var failure: Error?
    private var completion: ((String, Error?) -> Void)?
    private var didFinish = false
    private var earlyFinal = false
    private var safetyTimer: DispatchWorkItem?
    private var bufferCount = 0
    private var configObserver: NSObjectProtocol?
    private var levelHandler: ((Float) -> Void)?

    private(set) var isRunning = false
    private(set) var usingOnDevice = false

    // MARK: - 권한

    static func requestPermissions(_ done: @escaping (Result<Void, Error>) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            Log.write("음성 인식 권한 상태: \(status.rawValue) (3 = 허용)")
            guard status == .authorized else {
                DispatchQueue.main.async { done(.failure(RecorderError.notAuthorized)) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Log.write("마이크 권한: \(granted)")
                DispatchQueue.main.async {
                    done(granted ? .success(()) : .failure(RecorderError.micDenied))
                }
            }
        }
    }

    // MARK: - 시작 / 정지

    /// - onLevel: 입력 레벨(0…1). 파형 표시용. 메인 스레드에서 호출된다.
    func start(localeID: String,
               onPartial: @escaping (String) -> Void,
               onLevel: ((Float) -> Void)? = nil) throws {
        guard !isRunning else { return }

        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else {
            throw RecorderError.recognizerUnavailable(localeID)
        }
        Log.write("recognizer 생성: locale=\(localeID) available=\(rec.isAvailable) onDeviceSupported=\(rec.supportsOnDeviceRecognition)")
        guard rec.isAvailable else {
            throw RecorderError.recognizerUnavailable(localeID)
        }
        recognizer = rec

        latest = ""
        failure = nil
        didFinish = false
        earlyFinal = false
        bufferCount = 0
        completion = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true

        // 온디바이스 모델이 준비 안 된 상태에서 강제하면 인식이 통째로 실패한다.
        // 한 번 실패하면 Prefs.forceServerRecognition이 켜지고 다음부터 서버 인식으로 간다.
        usingOnDevice = rec.supportsOnDeviceRecognition && !Prefs.forceServerRecognition
        req.requiresOnDeviceRecognition = usingOnDevice
        req.addsPunctuation = true
        request = req
        Log.write("인식 방식: \(usingOnDevice ? "온디바이스" : "애플 서버")")

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        Log.write("입력 포맷: \(format.sampleRate)Hz \(format.channelCount)ch")
        guard format.sampleRate > 0, format.channelCount > 0 else {
            self.engine = nil
            throw RecorderError.noInputDevice
        }

        levelHandler = onLevel
        installTap(on: input, format: format, request: req)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.engine = nil
            Log.write("engine.start 실패: \(error)")
            throw error
        }
        isRunning = true
        Log.write("녹음 시작")

        // 녹음 중에 입력 장치가 바뀌면(에어팟 착용/해제 등) 엔진이 멈춘다. 새 장치로 이어서 녹음한다.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.restartAfterDeviceChange()
        }

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.latest = text
                    onPartial(text)
                }
                if result.isFinal {
                    Log.write("최종 인식 결과 수신: \(text.count)자")
                    self.finishOrMarkEarly()
                }
            }

            if let error {
                Log.write("인식 오류: \(error.localizedDescription)")
                DispatchQueue.main.async { self.failure = error }
                self.finishOrMarkEarly()
            }
        }
    }

    /// 녹음을 멈추고 (최종 텍스트, 오류)를 completion으로 넘긴다.
    func stop(completion: @escaping (String, Error?) -> Void) {
        guard isRunning else {
            Log.write("stop 호출됐으나 녹음 중이 아님")
            completion("", nil)
            return
        }
        isRunning = false
        self.completion = completion
        removeConfigObserver()

        releaseEngine()
        request?.endAudio()
        Log.write("녹음 종료 — 오디오 버퍼 \(bufferCount)개 전달됨")

        if bufferCount == 0 {
            Log.write("⚠️ 마이크에서 버퍼가 하나도 안 왔습니다. 입력 장치/권한 문제.")
        }

        if earlyFinal {
            finish()
            return
        }

        let timer = DispatchWorkItem { [weak self] in
            Log.write("최종 결과 대기 시간 초과 — 부분 결과로 진행")
            self?.finish()
        }
        safetyTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: timer)
    }

    func cancel() {
        isRunning = false
        removeConfigObserver()
        completion = nil
        didFinish = true
        safetyTimer?.cancel()
        releaseEngine()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    // MARK: - 내부

    private func installTap(on input: AVAudioInputNode, format: AVAudioFormat, request req: SFSpeechAudioBufferRecognitionRequest) {
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.bufferCount += 1
            req.append(buffer)
            if let onLevel = self.levelHandler {
                let level = Self.level(of: buffer)
                DispatchQueue.main.async { onLevel(level) }
            }
        }
    }

    private func restartAfterDeviceChange() {
        guard isRunning, let req = request, let engine else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        Log.write("입력 장치 변경 감지 — \(format.sampleRate)Hz \(format.channelCount)ch 로 재시작")
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Log.write("새 입력 장치 포맷이 비어 있음 — 녹음을 유지하지 못함")
            return
        }
        engine.stop()
        installTap(on: input, format: format, request: req)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Log.write("장치 변경 후 engine.start 실패: \(error)")
            DispatchQueue.main.async { self.failure = error }
        }
    }

    /// 마이크를 시스템에 완전히 돌려준다. stop() 만으로는 에어팟 통화 모드가 안 풀린다.
    private func releaseEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func removeConfigObserver() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = nil
    }

    /// RMS를 dB로 바꾼 뒤 -50dB…0dB를 0…1로 편다.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = (sum / Float(n)).squareRoot()
        let db = 20 * log10(max(rms, 1e-6))
        return max(0, min(1, (db + 50) / 50))
    }

    /// 인식 콜백은 별도 스레드에서 온다. 상태 변수는 메인 스레드에서만 만진다.
    private func finishOrMarkEarly() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.completion == nil {
                self.earlyFinal = true
            } else {
                self.finish()
            }
        }
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didFinish else { return }
            self.didFinish = true
            self.safetyTimer?.cancel()
            self.safetyTimer = nil

            let text = self.latest
            let err = self.failure
            self.task?.cancel()
            self.task = nil
            self.request = nil

            let done = self.completion
            self.completion = nil
            Log.write("finish — 텍스트 \(text.count)자, 오류: \(err?.localizedDescription ?? "없음")")
            done?(text, err)
        }
    }
}
