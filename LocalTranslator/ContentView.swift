import SwiftUI
import UIKit

/// 誰が話しているか
enum Speaker {
    case me
    case partner
}

/// 音声認識（SenseVoice）の準備の状態
enum RecognizerState {
    case loading
    case ready(SpeechRecognizer)
    case failed(String)
}

/// 翻訳（PLaMo）の準備の状態
enum TranslatorState {
    case loading
    case ready(Translator)
    case failed(String)
}

/// いまマイクまわりで何をしているか
enum MicActivity: Equatable {
    /// 録音中（もう一度押すと止まる）
    case recording(Speaker)
    /// 録った声を文字にしている最中
    case processing(Speaker)
    /// 文字にした文を翻訳している最中
    case translating(Speaker)
}

/// マイクボタンの下に出すお知らせ
enum MicNotice {
    case notHeard
    case translationFailed
    case error(String)
}

/// 対面翻訳の画面。上半分は相手用（逆さま）、下半分は自分用。
struct ContentView: View {
    @State private var partnerLanguage: PartnerLanguage = .korean
    /// 最後に聞き取った自分の発言と、相手の発言（話した言葉のまま）
    @State private var lastMine: String?
    @State private var lastPartner: String?
    /// その訳（自分の発言 → 相手の言語、相手の発言 → 日本語）
    @State private var lastMineTranslated: String?
    @State private var lastPartnerTranslated: String?
    @State private var recognizerState: RecognizerState = .loading
    @State private var translatorState: TranslatorState = .loading
    @State private var activity: MicActivity?
    @State private var notices: [Speaker: MicNotice] = [:]
    @State private var showMicPermissionAlert = false
    /// 録音を始めたときの言語（途中で帯の言語を変えても、録った言語で文字にする）
    @State private var recordingLanguageCode = ""
    /// 録音を始めたときの「訳す先の言語」（PLaMo のコード）
    @State private var recordingTargetCode = ""
    @State private var recorder = AudioRecorder()
    /// 確認用：最後に録音した人と、その長さ（秒）。「▶︎聞く」で聞き返せる。
    @State private var lastRecordingSpeaker: Speaker?
    @State private var lastRecordingSeconds: Double = 0
    /// 文字サイズ。アプリを閉じても覚えておく。
    @AppStorage("textSize") private var textSizeRaw = TextSize.small.rawValue
    @Environment(\.openURL) private var openURL

    private var textSize: Binding<TextSize> {
        Binding(
            get: { TextSize(rawValue: textSizeRaw) ?? .small },
            set: { textSizeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 相手用パネル。向かいに座った人が読めるように 180 度回転させる。
            // 黒い文字＝自分の発言の訳、グレーの文字＝相手が言ったこと。
            SpeakerPanel(
                title: "\(partnerLanguage.partnerLabel) · \(partnerLanguage.nativeName)",
                hint: partnerLanguage.tapToSpeakHint,
                status: status(for: .partner),
                heard: lastMineTranslated,
                pendingLabel: activity == .translating(.me) ? partnerLanguage.translatingLabel : nil,
                said: lastPartner,
                tint: .purple,
                textSize: textSize.wrappedValue,
                isRecording: activity == .recording(.partner),
                isProcessing: isBusy(.partner),
                isDisabled: !canPress(.partner),
                micLabel: "相手のマイク",
                playbackLabel: playbackLabel(for: .partner),
                onPlayback: { recorder.playLast() }
            ) {
                micTapped(.partner)
            }
            .rotationEffect(.degrees(180))

            MiddleBar(partnerLanguage: $partnerLanguage, textSize: textSize)

            // 自分用パネル。黒い文字＝相手の発言の訳、グレーの文字＝自分が言ったこと。
            SpeakerPanel(
                title: "自分 · 日本語",
                hint: "マイクを押して話してね",
                status: status(for: .me),
                heard: lastPartnerTranslated,
                pendingLabel: activity == .translating(.partner) ? "翻訳中…" : nil,
                said: lastMine,
                tint: .teal,
                textSize: textSize.wrappedValue,
                isRecording: activity == .recording(.me),
                isProcessing: isBusy(.me),
                isDisabled: !canPress(.me),
                micLabel: "自分のマイク",
                playbackLabel: playbackLabel(for: .me),
                onPlayback: { recorder.playLast() }
            ) {
                micTapped(.me)
            }
        }
        .task {
            // 話し始めが切れないように、マイクを先に動かしておく（許可がまだなら、最初に押したときに聞く）
            if AudioRecorder.hasPermission {
                try? recorder.warmUp()
            }
            // メモリを一度にたくさん使わないように、1 つずつ順番に読み込む
            await loadRecognizer()
            await loadTranslator()
        }
        .alert("マイクが使えないよ", isPresented: $showMicPermissionAlert) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("設定アプリの「LocalTranslator」で、マイクをオンにしてね。")
        }
    }

    // MARK: - 状態に合わせた表示

    /// マイクボタンの下に出す文字
    private func status(for speaker: Speaker) -> String {
        let isMe = speaker == .me
        let preparing = isMe ? "準備中…" : partnerLanguage.preparingLabel
        switch recognizerState {
        case .loading:
            return preparing
        case .failed(let message):
            return isMe ? "音声認識が使えません（\(message)）" : partnerLanguage.failedLabel
        case .ready:
            break
        }
        if case .loading = translatorState {
            return preparing
        }

        switch activity {
        case .recording(speaker):
            return isMe ? "聞き取り中… もう一度押すと終わるよ" : partnerLanguage.listeningLabel
        case .processing(speaker):
            return isMe ? "文字にしています…" : partnerLanguage.processingLabel
        case .translating(speaker):
            return isMe ? "翻訳しています…" : partnerLanguage.translatingLabel
        default:
            break
        }

        switch notices[speaker] {
        case .notHeard:
            return isMe ? "うまく聞き取れなかったよ。もう一度話してね" : partnerLanguage.notHeardLabel
        case .translationFailed:
            return isMe ? "翻訳できなかったので、話した言葉のまま出しています" : partnerLanguage.translationFailedLabel
        case .error(let message):
            return message
        case nil:
            break
        }

        // 翻訳のモデルが読み込めなかったときは、ずっと知らせておく
        if case .failed(let message) = translatorState {
            return isMe ? "翻訳が使えません（\(message)）" : partnerLanguage.translatorUnavailableLabel
        }
        return " "
    }

    /// 確認用の「録音 ○秒 ▶︎聞く」。最後に録音した人のパネルにだけ、何もしていないときに出す。
    private func playbackLabel(for speaker: Speaker) -> String? {
        guard activity == nil, lastRecordingSpeaker == speaker else { return nil }
        return String(format: "録音 %.1f秒 ▶︎聞く", lastRecordingSeconds)
    }

    /// 文字にしている最中・翻訳している最中か（マイクのところに「…」を出す）
    private func isBusy(_ speaker: Speaker) -> Bool {
        activity == .processing(speaker) || activity == .translating(speaker)
    }

    /// このマイクボタンを押せるか。
    /// 録音中の人は「止める」ために押せる。それ以外の人や、文字にしている・翻訳している最中は押せない。
    private func canPress(_ speaker: Speaker) -> Bool {
        guard case .ready = recognizerState else { return false }
        if case .loading = translatorState { return false }
        switch activity {
        case nil: return true
        case .recording(let current): return current == speaker
        case .processing, .translating: return false
        }
    }

    // MARK: - 動き

    /// アプリを開いたときに、SenseVoice のモデルを裏で読み込む（数秒かかる）。
    private func loadRecognizer() async {
        guard case .loading = recognizerState else { return }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try SpeechRecognizer() }
        }.value
        switch result {
        case .success(let recognizer):
            recognizerState = .ready(recognizer)
        case .failure(let error):
            recognizerState = .failed(error.localizedDescription)
        }
    }

    /// アプリを開いたときに、PLaMo のモデルを裏で読み込む（数秒かかる）。
    private func loadTranslator() async {
        guard case .loading = translatorState else { return }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try Translator() }
        }.value
        switch result {
        case .success(let translator):
            translatorState = .ready(translator)
        case .failure(let error):
            translatorState = .failed(error.localizedDescription)
        }
    }

    /// マイクボタンを押したとき：止まっていれば録音開始、録音中なら終了。
    private func micTapped(_ speaker: Speaker) {
        switch activity {
        case nil:
            startRecording(speaker)
        case .recording(speaker):
            finishRecording(speaker)
        default:
            break
        }
    }

    private func startRecording(_ speaker: Speaker) {
        guard case .ready = recognizerState else { return }
        notices[speaker] = nil

        Task { @MainActor in
            guard await AudioRecorder.requestPermission() else {
                showMicPermissionAlert = true
                return
            }
            // 許可を待っている間に、もう片方が話し始めていたら何もしない
            guard activity == nil else { return }
            do {
                try recorder.start()
                // 自分のマイク：日本語で聞いて、相手の言語に訳す
                // 相手のマイク：帯で選んだ言語で聞いて、日本語に訳す
                recordingLanguageCode = speaker == .me ? "ja" : partnerLanguage.senseVoiceCode
                recordingTargetCode = speaker == .me ? partnerLanguage.plamoCode : "ja"
                activity = .recording(speaker)
            } catch {
                notices[speaker] = .error("録音を始められませんでした")
            }
        }
    }

    private func finishRecording(_ speaker: Speaker) {
        guard case .ready(let recognizer) = recognizerState else { return }
        let language = recordingLanguageCode
        let target = recordingTargetCode
        activity = .processing(speaker)

        Task { @MainActor in
            // 語尾が切れないように、少しだけ録り続けてから止まる
            let recording = await recorder.stop()
            lastRecordingSpeaker = speaker
            lastRecordingSeconds = Double(recording.samples.count) / AudioRecorder.sampleRate
            // 押していた時間が 0.3 秒より短いときは、押し間違いとみなす
            let isTooShort = recording.pressedSeconds < 0.3 || recording.samples.isEmpty
            let raw = isTooShort
                ? SpeechRecognizer.Heard(text: "", languageTag: "")
                : await recognizer.transcribe(recording.samples, language: language)
            // 英語は全部大文字で出てくるので、ふつうの書き方に直す（PLaMo にも直した文を渡す）
            let spoken = SpokenLanguage.detect(
                text: raw.text, senseVoiceTag: raw.languageTag, requested: language)
            let heard = spoken == "en"
                ? SpeechRecognizer.Heard(text: EnglishCase.normalize(raw.text), languageTag: raw.languageTag)
                : raw

            guard !heard.text.isEmpty else {
                notices[speaker] = .notHeard
                activity = nil
                return
            }

            // まず話した言葉を出して、訳ができるまで相手側に「翻訳中…」を出す
            switch speaker {
            case .me:
                lastMine = heard.text
                lastMineTranslated = nil
            case .partner:
                lastPartner = heard.text
                lastPartnerTranslated = nil
            }
            activity = .translating(speaker)

            let translated = await translation(of: heard, requested: language, target: target)
            if translated == nil {
                notices[speaker] = .translationFailed
            }
            let shown = translated ?? heard.text
            switch speaker {
            case .me: lastMineTranslated = shown
            case .partner: lastPartnerTranslated = shown
            }
            activity = nil
        }
    }

    /// 聞き取った文を訳す。訳せなかったときは nil。
    /// 話された言語が訳す先と同じなら（例：相手が日本語で話した）、訳さずにそのまま返す。
    private func translation(
        of heard: SpeechRecognizer.Heard, requested: String, target: String
    ) async -> String? {
        let source = SpokenLanguage.detect(
            text: heard.text, senseVoiceTag: heard.languageTag, requested: requested)
        if source == SpokenLanguage.family(ofPlamoCode: target) {
            return heard.text
        }
        guard case .ready(let translator) = translatorState else { return nil }
        do {
            let text = try await translator.translate(
                heard.text, from: SpokenLanguage.plamoSourceCode(for: source), to: target)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}

/// 片方の人のパネル。黒い文字＝相手の言葉の訳、グレーの文字＝自分が言ったこと（同じ大きさ）。
/// 文が短いときは真ん中に表示し、枠に入りきらないときは枠の中でスクロールできる。
struct SpeakerPanel: View {
    let title: String
    let hint: String
    /// マイクボタンの下に出す文字（準備中・聞き取り中など）
    let status: String
    let heard: String?
    /// 訳ができるまでの間、訳文の場所に出す文字（「翻訳中…」）。nil なら出さない。
    let pendingLabel: String?
    let said: String?
    let tint: Color
    let textSize: TextSize
    let isRecording: Bool
    let isProcessing: Bool
    let isDisabled: Bool
    let micLabel: String
    /// 確認用の「録音 ○秒 ▶︎聞く」。nil なら出さない。
    let playbackLabel: String?
    let onPlayback: () -> Void
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 入りきるなら 1 つ目（真ん中寄せ）、入りきらないなら 2 つ目（スクロール）が選ばれる
            ViewThatFits(in: .vertical) {
                message
                    .frame(maxHeight: .infinity)
                ScrollView {
                    message
                        .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
            }
            .frame(maxHeight: .infinity)
            // 新しい文が来たら、スクロール位置をいちばん上に戻す
            .id("\(heard ?? "")|\(said ?? "")")

            Button(action: action) {
                Image(systemName: micIcon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: isRecording)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(isRecording ? Color.red : tint))
                    .opacity(isDisabled && !isProcessing ? 0.4 : 1)
            }
            .disabled(isDisabled)
            .accessibilityLabel(micLabel)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // エラーの説明が長いときも読めるように、4 行まで出す
                .lineLimit(4)

            if let playbackLabel {
                Button(playbackLabel, action: onPlayback)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.opacity(0.1))
    }

    /// 録音中は波形、文字にしている最中は「…」、それ以外はマイク
    private var micIcon: String {
        if isRecording { return "waveform" }
        if isProcessing { return "ellipsis" }
        return "mic.fill"
    }

    /// 訳文と自分の発言。どちらも文字サイズの設定に合わせて一緒に大きさが変わる。
    private var message: some View {
        VStack(spacing: 12) {
            if let pendingLabel {
                Text(pendingLabel)
                    .font(.system(size: textSize.heardPointSize))
                    .foregroundStyle(.secondary)
            } else if let heard {
                Text(heard)
                    .font(.system(size: textSize.heardPointSize))
                    .foregroundStyle(.primary)
            } else {
                Text(hint)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let said {
                Text(said)
                    .font(.system(size: textSize.saidPointSize))
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }
}

/// 真ん中の帯。左右のボタンで文字サイズ、真ん中のタップで相手の言語を切り替える。
struct MiddleBar: View {
    @Binding var partnerLanguage: PartnerLanguage
    @Binding var textSize: TextSize

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if let smaller = textSize.smaller { textSize = smaller }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 44, height: 40)
            }
            .disabled(textSize.smaller == nil)
            .accessibilityLabel("文字を小さく")

            Menu {
                Picker("相手の言語", selection: $partnerLanguage) {
                    ForEach(PartnerLanguage.allCases) { language in
                        Text("\(language.japaneseName)（\(language.nativeName)）")
                            .tag(language)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("日本語 ⇄ \(partnerLanguage.nativeName)")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }

            Text("文字 \(textSize.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Button {
                if let larger = textSize.larger { textSize = larger }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 44, height: 40)
            }
            .disabled(textSize.larger == nil)
            .accessibilityLabel("文字を大きく")
        }
        .padding(.horizontal, 8)
        .background(.bar)
    }
}

#Preview {
    ContentView()
}
