import Foundation
import LlamaSwift

/// PLaMo 3 Translate 0.8B（llama.cpp）で、文を別の言語に訳す。
/// モデルはアプリの中の Models フォルダに入っている（GitHub Actions がビルドのときに入れる）。
final class Translator: @unchecked Sendable {
    enum TranslatorError: LocalizedError {
        case modelNotFound
        case loadFailed
        case tooLong
        case failed

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "翻訳のモデルがアプリに入っていません"
            case .loadFailed: return "翻訳のモデルを読み込めませんでした"
            case .tooLong: return "文が長すぎて翻訳できませんでした"
            case .failed: return "翻訳に失敗しました"
            }
        }
    }

    static let modelFileName = "plamo-3-translate-0.8b-Q4_K_M.gguf"

    /// 一度に扱える長さ（元の文＋訳文のトークン数）。会話の 1 文なら十分。
    private static let contextLength: UInt32 = 2048
    /// 訳文の長さの上限（トークン数）
    private static let maxOutputTokens = 512
    /// PLaMo が「訳し終わったよ」と出す印
    private static let stopMarks = ["<|plamo:tag|>", "<|plamo:bos|>"]

    /// llama.cpp の準備は、アプリの中で 1 回だけ行う
    private static let backendReady: Void = llama_backend_init()

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let stopTokens: Set<llama_token>
    /// 翻訳を 1 つずつ順番に行うための列
    private let queue = DispatchQueue(label: "Translator")

    /// モデルを読み込む。数秒かかるので、画面を止めないように裏で呼ぶ。
    init() throws {
        guard
            let modelURL = Bundle.main.url(forResource: "Models", withExtension: nil)?
                .appendingPathComponent(Self.modelFileName),
            FileManager.default.fileExists(atPath: modelURL.path)
        else {
            throw TranslatorError.modelNotFound
        }

        _ = Self.backendReady

        guard let model = llama_model_load_from_file(modelURL.path, llama_model_default_params()) else {
            throw TranslatorError.loadFailed
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = Self.contextLength
        contextParams.n_batch = Self.contextLength
        contextParams.n_threads = 2
        contextParams.n_threads_batch = 2
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw TranslatorError.loadFailed
        }
        guard let vocab = llama_model_get_vocab(model) else {
            llama_free(context)
            llama_model_free(model)
            throw TranslatorError.loadFailed
        }

        self.model = model
        self.context = context
        self.vocab = vocab

        // 「訳し終わったよ」の印が 1 つのトークンなら、その番号を覚えておいて、出た瞬間に止める
        var stops = Set<llama_token>()
        for mark in Self.stopMarks {
            let tokens = Self.tokenize(mark, vocab: vocab, addSpecial: false)
            if tokens.count == 1 { stops.insert(tokens[0]) }
        }
        stopTokens = stops
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    /// 文を訳す。source は元の言語のコード（分からなければ nil）、target は訳す先の言語のコード。
    /// コードは PLaMo の書き方（ja / en / ko / zh-hans など）。
    func translate(_ text: String, from source: String?, to target: String) async throws -> String {
        let prompt = Self.prompt(for: text, from: source, to: target)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try generate(prompt: prompt))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// PLaMo 専用の書き方（PFML3）で、翻訳のお願いを組み立てる。
    /// 例: <|plamo:tag|>dataset<|plamo:msg|>translation<|plamo:tag|>input<|plamo:msg|>こんにちは
    ///     <|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ko<|plamo:msg|>
    /// 文の始まりの印（<|plamo:bos|>）は llama.cpp が自動でつけるので、ここでは書かない。
    static func prompt(for text: String, from source: String?, to target: String) -> String {
        // 聞き取った文に PLaMo の印がまぎれていたら取り除く（お願いの形が崩れないように）
        let cleanText = text.replacingOccurrences(of: "<|plamo:", with: "")
        var prompt = "<|plamo:tag|>dataset<|plamo:msg|>translation<|plamo:tag|>input"
        if let source {
            prompt += "<|plamo:key|>lang<|plamo:val|>\(source)"
        }
        prompt += "<|plamo:msg|>\(cleanText)"
        prompt += "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>\(target)<|plamo:msg|>"
        return prompt
    }

    // MARK: - llama.cpp を動かすところ

    /// お願いの文を読ませて、訳文を 1 トークンずつ作る（毎回いちばん確からしいものを選ぶ）。
    private func generate(prompt: String) throws -> String {
        // 前の翻訳の記憶を消してから始める
        llama_memory_clear(llama_get_memory(context), true)

        var promptTokens = Self.tokenize(prompt, vocab: vocab, addSpecial: true)
        guard !promptTokens.isEmpty else { throw TranslatorError.failed }
        guard promptTokens.count + Self.maxOutputTokens <= Int(Self.contextLength) else {
            throw TranslatorError.tooLong
        }

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        defer { llama_sampler_free(sampler) }

        let readStatus = promptTokens.withUnsafeMutableBufferPointer { buffer in
            llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
        }
        guard readStatus == 0 else { throw TranslatorError.failed }

        // 文字の途中でトークンが切れることがあるので、最後にまとめて文字に戻す
        var bytes: [UInt8] = []
        for _ in 0..<Self.maxOutputTokens {
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) || stopTokens.contains(token) { break }
            bytes += piece(of: token)
            if let text = String(bytes: bytes, encoding: .utf8),
               Self.stopMarks.contains(where: { text.contains($0) }) {
                break
            }

            let status = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            guard status == 0 else { throw TranslatorError.failed }
        }

        var text = String(decoding: bytes, as: UTF8.self)
        for mark in Self.stopMarks {
            if let range = text.range(of: mark) {
                text = String(text[..<range.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 文をトークン（モデルが読める数字の列）に変える。PLaMo の印も 1 つのトークンとして読む。
    private static func tokenize(_ text: String, vocab: OpaquePointer, addSpecial: Bool) -> [llama_token] {
        let byteCount = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: byteCount + 8)
        let count = llama_tokenize(
            vocab, text, Int32(byteCount), &tokens, Int32(tokens.count), addSpecial, true)
        guard count > 0 else { return [] }
        return Array(tokens.prefix(Int(count)))
    }

    /// トークン 1 つを、文字のかけら（バイト列）に戻す
    private func piece(of token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        }
        guard count > 0 else { return [] }
        return buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }
    }
}
