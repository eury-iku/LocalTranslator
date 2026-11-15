import SwiftUI

/// 誰が話しているか
enum Speaker {
    case me
    case partner
}

/// 対面翻訳の画面。上半分は相手用（逆さま）、下半分は自分用。
struct ContentView: View {
    @State private var partnerLanguage: PartnerLanguage = .korean
    @State private var lastMine: SamplePhrase?
    @State private var lastPartner: SamplePhrase?
    @State private var listening: Speaker?
    @State private var mineIndex = 0
    @State private var partnerIndex = 0
    /// 文字サイズ。アプリを閉じても覚えておく。
    @AppStorage("textSize") private var textSizeRaw = TextSize.small.rawValue

    private var textSize: Binding<TextSize> {
        Binding(
            get: { TextSize(rawValue: textSizeRaw) ?? .small },
            set: { textSizeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 相手用パネル。向かいに座った人が読めるように 180 度回転させる。
            SpeakerPanel(
                title: "\(partnerLanguage.partnerLabel) · \(partnerLanguage.nativeName)",
                hint: partnerLanguage.tapToSpeakHint,
                listeningLabel: partnerLanguage.listeningLabel,
                heard: lastMine?.text(in: partnerLanguage),
                said: lastPartner?.text(in: partnerLanguage),
                tint: .purple,
                textSize: textSize.wrappedValue,
                isListening: listening == .partner,
                isDisabled: listening != nil,
                micLabel: "相手のマイク"
            ) {
                speak(.partner)
            }
            .rotationEffect(.degrees(180))

            MiddleBar(partnerLanguage: $partnerLanguage, textSize: textSize)

            // 自分用パネル
            SpeakerPanel(
                title: "自分 · 日本語",
                hint: "マイクを押して話してね",
                listeningLabel: "聞き取り中…",
                heard: lastPartner?.japanese,
                said: lastMine?.japanese,
                tint: .teal,
                textSize: textSize.wrappedValue,
                isListening: listening == .me,
                isDisabled: listening != nil,
                micLabel: "自分のマイク"
            ) {
                speak(.me)
            }
        }
    }

    /// マイクボタンを押したときの仮の動き。
    /// 少し待ってから例文を出す（あとで SenseVoice と PLaMo に置き換える）。
    private func speak(_ speaker: Speaker) {
        guard listening == nil else { return }
        listening = speaker

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            switch speaker {
            case .me:
                lastMine = SampleConversation.mine[mineIndex]
                mineIndex = (mineIndex + 1) % SampleConversation.mine.count
            case .partner:
                lastPartner = SampleConversation.partner[partnerIndex]
                partnerIndex = (partnerIndex + 1) % SampleConversation.partner.count
            }
            listening = nil
        }
    }
}

/// 片方の人のパネル。大きい文字＝相手の言葉の訳、小さい文字＝自分が言ったこと。
/// 文が短いときは真ん中に表示し、枠に入りきらないときは枠の中でスクロールできる。
struct SpeakerPanel: View {
    let title: String
    let hint: String
    let listeningLabel: String
    let heard: String?
    let said: String?
    let tint: Color
    let textSize: TextSize
    let isListening: Bool
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
                Image(systemName: isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(tint))
                    .opacity(isDisabled && !isListening ? 0.4 : 1)
            }
            .disabled(isDisabled)
            .accessibilityLabel(micLabel)

            Text(isListening ? listeningLabel : " ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.opacity(0.1))
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
