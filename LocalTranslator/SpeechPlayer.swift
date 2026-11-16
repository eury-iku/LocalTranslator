import AVFoundation

/// 訳文を声に出して読む（iPhone に最初から入っている声を使うので、ネットは要らない）。
///
/// 音の設定（AVAudioSession）は AudioRecorder が決めたものをそのまま使い、ここではさわらない。
/// さわると、動かしっぱなしにしているマイクが止まってしまうため。
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    /// 読み上げ係。使い捨てにすると途中で声が切れるので、ずっと持っておく。
    private let synthesizer = AVSpeechSynthesizer()
    /// いま読んでいる文の目印（古い文の「終わったよ」を、新しい文のものと取り違えないため）
    private var currentID: ObjectIdentifier?
    /// 読み終わったとき・止めたときに呼ぶ処理
    private var onEnd: (() -> Void)?

    override init() {
        super.init()
        // アプリの音の設定（録音と再生の両方ができるモード）をそのまま使う
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = self
    }

    /// 文を読み上げる。読み上げを始められたら true。
    /// 読める文字がないとき・その言語の声が iPhone にないときは、何もせず false を返す。
    /// - Parameters:
    ///   - languageCode: 声の言語（ja-JP / ko-KR / zh-CN / en-US）
    ///   - onEnd: 読み終わったとき・止めたときに 1 回だけ呼ばれる
    @MainActor
    func speak(_ text: String, languageCode: String, onEnd: @escaping () -> Void) -> Bool {
        // 記号だけ・空っぽの文は読まない
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return false }
        // 声がないまま読ませると、別の言語の声で読んでしまうので、読まない
        guard let voice = AVSpeechSynthesisVoice(language: languageCode) else { return false }

        // 前の読み上げが残っていたら、先に止める
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        currentID = ObjectIdentifier(utterance)
        self.onEnd = onEnd
        synthesizer.speak(utterance)
        return true
    }

    /// 読み上げを止める。読んでいなければ何もしない。
    @MainActor
    func stop() {
        guard currentID != nil else { return }
        synthesizer.stopSpeaking(at: .immediate)
        // 「止まったよ」の知らせを待たずに、すぐ終わりにする（知らせが来なくてもマイクが固まらないように）
        finish()
    }

    @MainActor
    private func finish() {
        currentID = nil
        let handler = onEnd
        onEnd = nil
        handler?()
    }

    /// 知らせが届いた文が、いま読んでいる文なら終わりにする
    private func ended(_ id: ObjectIdentifier) {
        Task { @MainActor in
            guard self.currentID == id else { return }
            self.finish()
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    /// 最後まで読み終わった
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        ended(ObjectIdentifier(utterance))
    }

    /// 途中で止まった
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        ended(ObjectIdentifier(utterance))
    }
}
