import Foundation

/// 聞き取った文が何語だったかを決める。
/// 相手が、帯で選んだのとは違う言葉で話すこともあるので、マイクで頼んだ言語をそのまま信じずに、
/// まず文字の種類（ハングル・かな・アルファベット）で決める。
/// 漢字だけの文は文字では決められないので、SenseVoice の判定を使う。
/// 決まった言語は、翻訳の「元の言語」に使う。
enum SpokenLanguage {
    /// 話された言語を、ja / ko / zh / en のどれかで返す。
    /// - senseVoiceTag: SenseVoice が判定した言語（例: "ja"、"<|ko|>"）
    /// - requested: マイクで頼んだ言語（ja / ko / zh / en）
    static func detect(text: String, senseVoiceTag: String, requested: String) -> String {
        var hangul = 0
        var kana = 0
        var han = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: hangul += 1
            case 0x3040...0x30FF, 0x31F0...0x31FF: kana += 1
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF: han += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        // 文字を見れば分かるものは、文字で決める
        if hangul > 0 { return "ko" }
        if kana > 0 { return "ja" }
        if han == 0 {
            return latin > 0 ? "en" : requested
        }

        // 漢字だけの文は、日本語か中国語か文字では分からないので、SenseVoice の判定を使う
        let tag = senseVoiceTag
            .replacingOccurrences(of: "<|", with: "")
            .replacingOccurrences(of: "|>", with: "")
            .lowercased()
        switch tag {
        case "ja": return "ja"
        case "zh", "yue": return "zh"  // 広東語は中国語として訳す
        // 判定がはっきりしないときは、日本語のマイクなら日本語、それ以外なら中国語とみなす
        default: return requested == "ja" ? "ja" : "zh"
        }
    }

    /// PLaMo の言語コードを、ja / ko / zh / en の大まかな分け方に直す（zh-hans → zh）
    static func family(ofPlamoCode code: String) -> String {
        code.hasPrefix("zh") ? "zh" : code
    }

    /// PLaMo に「元の言語」として伝えるコード。
    /// 中国語は簡体字か繁体字か分からないので伝えず、PLaMo に任せる。
    static func plamoSourceCode(for language: String) -> String? {
        language == "zh" ? nil : language
    }
}
