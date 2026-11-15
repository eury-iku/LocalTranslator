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

/// いまマイクまわりで何をしているか
enum MicActivity: Equatable {
    /// 録音中（もう一度押すと止まる）
    case recording(Speaker)
    /// 録った声を文字にしている最中
    case processing(Speaker)
}

/// マイクボタンの下に出すお知らせ
enum MicNotice {
    case notHeard
    case error(String)
}

/// 対面翻訳の画面。上半分は相手用（逆さま）、下半分は自分用。
struct ContentView: View {
    @State private var partnerLanguage: PartnerLanguage = .korean
    /// 最後に聞き取った自分の発言と、相手の発言
    @State private var lastMine: String?
    @State private var lastPartner: String?
    @State private var recognizerState: RecognizerState = .loading
    @State private var activity: MicActivity?
    @State private var notices: [Speaker: MicNotice] = [:]
    @State private var showMicPermissionAlert = false
    /// 録音を始めたときの言語（途中で帯の言語を変えても、録った言語で文字にする）
    @State private var recordingLanguageCode = ""
    @State private var recorder = AudioRecorder()
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
            // 翻訳（PLaMo）をつなぐまでは、聞き取った文をそのまま出す。
            SpeakerPanel(
                title: "\(partnerLanguage.partnerLabel) · \(partnerLanguage.nativeName)",
                hint: partnerLanguage.tapToSpeakHint,
                status: status(for: .partner),
                heard: lastMine,
                said: lastPartner,
                tint: .purple,
                textSize: textSize.wrappedValue,
                isRecording: activity == .recording(.partner),
                isProcessing: activity == .processing(.partner),
                isDisabled: !canPress(.partner),
                micLabel: "相手のマイク"
            ) {
                micTapped(.partner)
            }
            .rotationEffect(.degrees(180))

            MiddleBar(partnerLanguage: $partnerLanguage, textSize: textSize)

            // 自分用パネル
            SpeakerPanel(
                title: "自分 · 日本語",
                hint: "マイクを押して話してね",
                status: status(for: .me),
                heard: lastPartner,
                said: lastMine,
                tint: .teal,
                textSize: textSize.wrappedValue,
                isRecording: activity == .recording(.me),
                isProcessing: activity == .processing(.me),
                isDisabled: !canPress(.me),
                micLabel: "自分のマイク"
            ) {
                micTapped(.me)
            }
        }
        .task {
            await loadRecognizer()
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
        switch recognizerState {
        case .loading:
            return isMe ? "準備中…" : partnerLanguage.preparingLabel
        case .failed(let message):
            return isMe ? "音声認識が使えません（\(message)）" : partnerLanguage.failedLabel
        case .ready:
            break
        }

        switch activity {
        case .recording(speaker):
            return isMe ? "聞き取り中… もう一度押すと終わるよ" : partnerLanguage.listeningLabel
        case .processing(speaker):
            return isMe ? "文字にしています…" : partnerLanguage.processingLabel
        default:
            break
        }

        switch notices[speaker] {
        case .notHeard:
            return isMe ? "うまく聞き取れなかったよ。もう一度話してね" : partnerLanguage.notHeardLabel
        case .error(let message):
            return message
        case nil:
            return " "
        }
    }

    /// このマイクボタンを押せるか。
    /// 録音中の人は「止める」ために押せる。それ以外の人や、文字にしている最中は押せない。
    private func canPress(_ speaker: Speaker) -> Bool {
        guard case .ready = recognizerState else { return false }
        switch activity {
        case nil: return true
        case .recording(let current): return current == speaker
        case .processing: return false
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
                recordingLanguageCode = speaker == .me ? "ja" : partnerLanguage.senseVoiceCode
                activity = .recording(speaker)
            } catch {
                notices[speaker] = .error("録音を始められませんでした")
            }
        }
    }

    private func finishRecording(_ speaker: Speaker) {
        guard case .ready(let recognizer) = recognizerState else { return }
        let samples = recorder.stop()
        let language = recordingLanguageCode
        activity = .processing(speaker)

        Task { @MainActor in
            // 0.3 秒より短い音は、押し間違いとみなす
            let isTooShort = samples.count < Int(AudioRecorder.sampleRate * 0.3)
            let text = isTooShort ? "" : await recognizer.transcribe(samples, language: language)

            if text.isEmpty {
                notices[speaker] = .notHeard
            } else {
                switch speaker {
                case .me: lastMine = text
                case .partner: lastPartner = text
                }
            }
            activity = nil
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
    let said: String?
    let tint: Color
    let textSize: TextSize
    let isRecording: Bool
    let isProcessing: Bool
    let isDisabled: Bool
    let micLabel: String
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
                .lineLimit(2)
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
            if let heard {
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
