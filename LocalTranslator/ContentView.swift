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
    /// 訳文を読み上げている最中（Speaker は、訳を聞く側の人）
    case speaking(Speaker)
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
    /// その訳を読み上げる声の言語（ja-JP など）。読み上げない文のときは nil。
    /// 訳せずに話した言葉のまま出したときや、訳す必要がなかったときは読み上げない。
    @State private var mineTranslatedVoiceCode: String?
    @State private var partnerTranslatedVoiceCode: String?
    @State private var recognizerState: RecognizerState = .loading
    @State private var translatorState: TranslatorState = .loading
    @State private var activity: MicActivity?
    @State private var notices: [Speaker: MicNotice] = [:]
    @State private var showMicPermissionAlert = false
    /// 録音を始めたときの言語（途中で帯の言語を変えても、録った言語で文字にする）
    @State private var recordingLanguageCode = ""
    /// 録音を始めたときの「訳す先の言語」（PLaMo のコード）
    @State private var recordingTargetCode = ""
    /// 録音を始めたときの「訳文を読み上げる声の言語」
    @State private var recordingVoiceCode = ""
    @State private var recorder = AudioRecorder()
    @State private var speechPlayer = SpeechPlayer()
    /// 文字サイズ。アプリを閉じても覚えておく。
    @AppStorage("textSize") private var textSizeRaw = TextSize.small.rawValue
    /// 訳文を自動で読み上げるか。アプリを閉じても覚えておく。
    /// オフでも、パネルの 🔊 を押せば読み上げる。
    @AppStorage("speechEnabled") private var speechEnabled = true
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

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
                isSpeaking: isSpeaking,
                isDisabled: !canPress(.partner),
                micLabel: "相手のマイク",
                canReplay: mineTranslatedVoiceCode != nil,
                isReplayDisabled: activity != nil,
                onReplay: { replay(for: .partner) }
            ) {
                micTapped(.partner)
            }
            .rotationEffect(.degrees(180))

            MiddleBar(partnerLanguage: $partnerLanguage, textSize: textSize, speechEnabled: $speechEnabled)

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
                isSpeaking: isSpeaking,
                isDisabled: !canPress(.me),
                micLabel: "自分のマイク",
                canReplay: partnerTranslatedVoiceCode != nil,
                isReplayDisabled: activity != nil,
                onReplay: { replay(for: .me) }
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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // アプリが裏に回ったら、読み上げとマイクを止める。録音中だった音は捨てる。
                speechPlayer.stop()
                if case .recording = activity {
                    activity = nil
                }
                recorder.shutDown()
            case .active:
                // 戻ってきたら、話し始めが切れないように、マイクをまた動かしておく
                if AudioRecorder.hasPermission {
                    try? recorder.warmUp()
                }
            default:
                // 通知やコントロールセンターを見ているだけのときは、何もしない
                break
            }
        }
        .onChange(of: speechEnabled) { _, isOn in
            // 読み上げ中にオフにしたら、その場で止める
            if !isOn {
                speechPlayer.stop()
            }
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
        case .speaking:
            // 読み上げ中は、どちらのマイクを押しても止められる
            return isMe ? "読み上げ中… マイクを押すと止まるよ" : partnerLanguage.speakingLabel
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

    /// 文字にしている最中・翻訳している最中か（マイクのところに「…」を出す）
    private func isBusy(_ speaker: Speaker) -> Bool {
        activity == .processing(speaker) || activity == .translating(speaker)
    }

    /// 訳文を読み上げている最中か（マイクのところに「■」を出す）
    private var isSpeaking: Bool {
        if case .speaking = activity { return true }
        return false
    }

    /// このマイクボタンを押せるか。
    /// 録音中の人は「止める」ために押せる。それ以外の人や、文字にしている・翻訳している最中は押せない。
    /// 読み上げ中は、どちらの人も「読み上げを止める」ために押せる。
    private func canPress(_ speaker: Speaker) -> Bool {
        guard case .ready = recognizerState else { return false }
        if case .loading = translatorState { return false }
        switch activity {
        case nil: return true
        case .recording(let current): return current == speaker
        case .processing, .translating: return false
        case .speaking: return true
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
    /// 読み上げ中なら、読み上げを止めるだけ（録音は始めない）。
    private func micTapped(_ speaker: Speaker) {
        switch activity {
        case nil:
            startRecording(speaker)
        case .recording(speaker):
            finishRecording(speaker)
        case .speaking:
            speechPlayer.stop()
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
                recordingVoiceCode = speaker == .me ? partnerLanguage.voiceCode : "ja-JP"
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
        let voiceCode = recordingVoiceCode
        activity = .processing(speaker)

        Task { @MainActor in
            // 語尾が切れないように、少しだけ録り続けてから止まる
            let recording = await recorder.stop()
            // 押していた時間が 0.3 秒より短いときは、押し間違いとみなす
            let isTooShort = recording.pressedSeconds < 0.3 || recording.samples.isEmpty
            let raw = isTooShort
                ? SpeechRecognizer.Heard(text: "", languageTag: "")
                : await recognizer.transcribe(recording.samples, language: language)
            // 英語が全部大文字で出てきたら、ふつうの書き方に直す（PLaMo にも直した文を渡す）
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
                mineTranslatedVoiceCode = nil
            case .partner:
                lastPartner = heard.text
                lastPartnerTranslated = nil
                partnerTranslatedVoiceCode = nil
            }
            activity = .translating(speaker)

            let translated = await translation(of: heard, requested: language, target: target)
            if translated == nil {
                notices[speaker] = .translationFailed
            }
            let shown = translated?.text ?? heard.text
            // 読み上げるのは、ちゃんと訳せた文だけ
            let voice = translated?.isTranslated == true ? voiceCode : nil
            switch speaker {
            case .me:
                lastMineTranslated = shown
                mineTranslatedVoiceCode = voice
            case .partner:
                lastPartnerTranslated = shown
                partnerTranslatedVoiceCode = voice
            }
            activity = nil
            // 帯の 🔊 がオフのとき・アプリが裏に回っているときは、自動では読まない
            if let voice, speechEnabled, scenePhase == .active {
                // 訳を聞くのは、話した人の向かいの人
                speak(shown, voiceCode: voice, to: speaker == .me ? .partner : .me)
            }
        }
    }

    /// 🔊 を押したとき：そのパネルに出ている訳文を、もう一度読み上げる。
    private func replay(for listener: Speaker) {
        let text = listener == .me ? lastPartnerTranslated : lastMineTranslated
        let voice = listener == .me ? partnerTranslatedVoiceCode : mineTranslatedVoiceCode
        guard let text, let voice else { return }
        speak(text, voiceCode: voice, to: listener)
    }

    /// 訳文を読み上げる。読み終わるか、マイクを押して止めるまで、録音は始められない。
    /// 声が iPhone にないとき・読める文字がないときは、何もしない（文字だけ出ている状態のまま）。
    private func speak(_ text: String, voiceCode: String, to listener: Speaker) {
        guard activity == nil else { return }
        // 電話などで音が止まっていたら、動かし直しておく
        if AudioRecorder.hasPermission {
            try? recorder.warmUp()
        }
        let started = speechPlayer.speak(text, languageCode: voiceCode) {
            // マイクが拾った読み上げの声を捨てて、次の録音に混ざらないようにする
            recorder.discardPreRoll()
            if case .speaking = activity {
                activity = nil
            }
        }
        if started {
            activity = .speaking(listener)
        }
    }

    /// 聞き取った文を訳す。訳せなかったときは nil。
    /// 話された言語が訳す先と同じなら（例：相手が日本語で話した）、訳さずにそのまま返す（isTranslated は false）。
    private func translation(
        of heard: SpeechRecognizer.Heard, requested: String, target: String
    ) async -> (text: String, isTranslated: Bool)? {
        let source = SpokenLanguage.detect(
            text: heard.text, senseVoiceTag: heard.languageTag, requested: requested)
        if source == SpokenLanguage.family(ofPlamoCode: target) {
            return (heard.text, false)
        }
        guard case .ready(let translator) = translatorState else { return nil }
        do {
            let text = try await translator.translate(
                heard.text, from: SpokenLanguage.plamoSourceCode(for: source), to: target)
            return text.isEmpty ? nil : (text, true)
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
    /// 訳文を読み上げている最中か（マイクが「止める」ボタンになる）
    let isSpeaking: Bool
    let isDisabled: Bool
    let micLabel: String
    /// 🔊（もう一度読み上げる）を出すか。読み上げられる訳文があるときだけ出す。
    let canReplay: Bool
    /// 🔊 を押せなくするか（録音中・処理中・読み上げ中）
    let isReplayDisabled: Bool
    let onReplay: () -> Void
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // 見出しと、🔊（もう一度読み上げる）ボタン
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if canReplay {
                    Button(action: onReplay) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.body)
                            .foregroundStyle(tint)
                            .frame(width: 44, height: 32)
                            .opacity(isReplayDisabled ? 0.4 : 1)
                    }
                    .disabled(isReplayDisabled)
                    .accessibilityLabel("もう一度読み上げる")
                }
            }
            // 🔊 が出たり消えたりしても、下の文が動かないように高さを決めておく
            .frame(height: 32)

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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.opacity(0.1))
    }

    /// 録音中は波形、文字にしている最中は「…」、読み上げ中は「■」、それ以外はマイク
    private var micIcon: String {
        if isRecording { return "waveform" }
        if isSpeaking { return "stop.fill" }
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

/// 真ん中の帯。左右のボタンで文字サイズ、国旗のタップで相手の言語、🔊 で自動の読み上げを切り替える。
struct MiddleBar: View {
    @Binding var partnerLanguage: PartnerLanguage
    @Binding var textSize: TextSize
    /// 訳文を自動で読み上げるか
    @Binding var speechEnabled: Bool

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
                        Text("\(language.flag) \(language.japaneseName)（\(language.nativeName)）")
                            .tag(language)
                    }
                }
            } label: {
                // 言語は国旗で見せる（日本語 ⇄ 相手の言語）
                HStack(spacing: 6) {
                    Text("🇯🇵 ⇄ \(partnerLanguage.flag)")
                        .font(.title3)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .accessibilityLabel("相手の言語：\(partnerLanguage.japaneseName)")

            Button {
                speechEnabled.toggle()
            } label: {
                Image(systemName: speechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(speechEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 40)
            }
            .accessibilityLabel(speechEnabled ? "自動の読み上げをオフにする" : "自動の読み上げをオンにする")

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
