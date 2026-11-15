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
                isListening: listening == .partner,
                isDisabled: listening != nil,
                micLabel: "相手のマイク"
            ) {
                speak(.partner)
            }
            .rotationEffect(.degrees(180))

            LanguageBar(partnerLanguage: $partnerLanguage)

            // 自分用パネル
            SpeakerPanel(
                title: "自分 · 日本語",
                hint: "マイクを押して話してね",
                listeningLabel: "聞き取り中…",
                heard: lastPartner?.japanese,
                said: lastMine?.japanese,
                tint: .teal,
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
struct SpeakerPanel: View {
    let title: String
    let hint: String
    let listeningLabel: String
    let heard: String?
    let said: String?
    let tint: Color
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

            Spacer(minLength: 0)

            Text(heard ?? hint)
                .font(heard == nil ? .body : .title3)
                .foregroundStyle(heard == nil ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)

            if let said {
                Text(said)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

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
}

/// 真ん中の帯。タップすると相手の言語を切り替えられる。
struct LanguageBar: View {
    @Binding var partnerLanguage: PartnerLanguage

    var body: some View {
        Menu {
            Picker("相手の言語", selection: $partnerLanguage) {
                ForEach(PartnerLanguage.allCases) { language in
                    Text("\(language.japaneseName)（\(language.nativeName)）")
                        .tag(language)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text("日本語 ⇄ \(partnerLanguage.nativeName)")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

#Preview {
    ContentView()
}
