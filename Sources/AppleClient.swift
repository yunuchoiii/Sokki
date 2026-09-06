import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleModelError: LocalizedError {
    case unsupportedOS
    case unavailable(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Apple 온디바이스 모델은 macOS 26 이상에서만 쓸 수 있습니다."
        case .unavailable(let reason):
            return "Apple 온디바이스 모델을 쓸 수 없습니다: \(reason)\n시스템 설정 > Apple Intelligence & Siri 에서 켜 주세요."
        case .badResponse:
            return "Apple 온디바이스 모델이 빈 응답을 돌려줬습니다."
        }
    }
}

/// macOS 26 Apple Intelligence 온디바이스 모델. 네트워크를 안 타서 503도 타임아웃도 없다.
/// 시스템 설정에서 Apple Intelligence 를 켜 둬야 한다.
struct AppleClient {

    static let shared = AppleClient()

    /// 온디바이스 모델 상태. 설치 안내는 "켤 수 있는데 꺼짐"과 "아예 안 됨"을 구분해야 한다.
    enum Status: Equatable {
        case available
        case notEnabled      // macOS 26, 지원 기기, Apple Intelligence 스위치만 꺼짐 → 켜면 된다
        case downloading     // 켰지만 모델을 내려받는 중
        case notEligible     // 기기 미지원
        case unsupportedOS   // macOS 26 미만
        case other(String)

        /// 사용자가 스위치를 켜거나 잠시 기다리면 쓸 수 있는 상태
        var canBecomeAvailable: Bool { self == .notEnabled || self == .downloading }
    }

    static func status() -> Status {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .deviceNotEligible:           return .notEligible
                case .modelNotReady:               return .downloading
                @unknown default:                  return .other("\(reason)")
                }
            }
        }
        #endif
        return .unsupportedOS
    }

    /// (쓸 수 있는지, 사람이 읽을 상태 설명)
    static func availability() -> (ok: Bool, note: String) {
        switch status() {
        case .available:     return (true,  "이 맥 안에서 처리합니다. 인터넷 없이 되고 1초 안팎 걸립니다.")
        case .notEnabled:    return (false, "Apple Intelligence 가 꺼져 있습니다. 시스템 설정 > Apple Intelligence & Siri 에서 켤 수 있습니다.")
        case .notEligible:   return (false, "이 맥은 Apple Intelligence 를 지원하지 않습니다.")
        case .downloading:   return (false, "모델을 내려받는 중입니다. 잠시 뒤 다시 시도합니다.")
        case .unsupportedOS: return (false, "macOS 26 이상에서만 지원합니다.")
        case .other(let r):  return (false, "지금은 쓸 수 없습니다 (\(r)).")
        }
    }

    func polish(_ raw: String,
                style: PolishStyle,
                completion: @escaping (Result<String, Error>) -> Void) {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            completion(.failure(AppleModelError.unsupportedOS)); return
        }
        let model = SystemLanguageModel.default
        if case .unavailable(let reason) = model.availability {
            completion(.failure(AppleModelError.unavailable("\(reason)"))); return
        }
        let started = Date()
        Task {
            do {
                let session = LanguageModelSession(model: model, instructions: Prompts.systemCompact(for: style))
                let response = try await session.respond(to: Prompts.userMessage(raw))
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
                Log.write("Apple 온디바이스 응답 \(text.count)자, \(elapsed)초")
                completion(text.isEmpty ? .failure(AppleModelError.badResponse) : .success(text))
            } catch {
                Log.write("Apple 온디바이스 오류: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        #else
        completion(.failure(AppleModelError.unsupportedOS))
        #endif
    }
}
