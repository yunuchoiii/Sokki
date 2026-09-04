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

    /// (쓸 수 있는지, 사람이 읽을 상태 설명)
    static func availability() -> (ok: Bool, note: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return (true, "사용 가능 — 네트워크 없이 이 맥에서 처리")
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return (false, "Apple Intelligence 가 꺼져 있음 — 시스템 설정 > Apple Intelligence & Siri 에서 켜기")
                case .deviceNotEligible:
                    return (false, "이 맥은 Apple Intelligence 를 지원하지 않음")
                case .modelNotReady:
                    return (false, "모델 다운로드 중 — 잠시 뒤 다시 시도")
                @unknown default:
                    return (false, "사용 불가 (\(reason))")
                }
            }
        }
        #endif
        return (false, "macOS 26 이상에서만 지원")
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
