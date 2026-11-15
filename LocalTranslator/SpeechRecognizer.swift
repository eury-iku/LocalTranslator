import Foundation
import SherpaOnnx
import SherpaOnnxC

/// SenseVoice（sherpa-onnx）で、録った音を文字にする。
/// モデルはアプリの中の Models フォルダに入っている（GitHub Actions がビルドのときに入れる）。
final class SpeechRecognizer: @unchecked Sendable {
    enum RecognizerError: LocalizedError {
        case modelNotFound

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "音声認識のモデルがアプリに入っていません"
            }
        }
    }

    private let recognizer: SherpaOnnxOfflineRecognizer
    private let modelPath: String
    private let tokensPath: String
    /// 文字にする作業を 1 つずつ順番に行うための列
    private let queue = DispatchQueue(label: "SpeechRecognizer")

    /// モデルを読み込む。数秒かかるので、画面を止めないように裏で呼ぶ。
    init() throws {
        guard
            let modelsURL = Bundle.main.url(forResource: "Models", withExtension: nil),
            FileManager.default.fileExists(atPath: modelsURL.appendingPathComponent("model.int8.onnx").path),
            FileManager.default.fileExists(atPath: modelsURL.appendingPathComponent("tokens.txt").path)
        else {
            throw RecognizerError.modelNotFound
        }
        modelPath = modelsURL.appendingPathComponent("model.int8.onnx").path
        tokensPath = modelsURL.appendingPathComponent("tokens.txt").path

        var config = Self.makeConfig(model: modelPath, tokens: tokensPath, language: "")
        recognizer = SherpaOnnxOfflineRecognizer(config: &config)
    }

    /// 音を文字にする。language は SenseVoice の言語コード（ja / ko / zh / en）。
    func transcribe(_ samples: [Float], language: String) async -> String {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                // 押されたボタンに合わせて、聞き取る言語を切り替える
                var config = Self.makeConfig(model: modelPath, tokens: tokensPath, language: language)
                recognizer.setConfig(config: &config)

                let result = recognizer.decode(samples: samples, sampleRate: Int(AudioRecorder.sampleRate))
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text)
            }
        }
    }

    private static func makeConfig(model: String, tokens: String, language: String) -> SherpaOnnxOfflineRecognizerConfig {
        let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: model,
            language: language,
            // 数字を「123」のように書いたり、句読点をつけたりする
            useInverseTextNormalization: true
        )
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokens,
            numThreads: 2,
            senseVoice: senseVoice
        )
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        return sherpaOnnxOfflineRecognizerConfig(featConfig: featConfig, modelConfig: modelConfig)
    }
}
