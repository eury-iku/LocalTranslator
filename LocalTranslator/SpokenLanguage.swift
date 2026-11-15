import Foundation

/// 聞き取った文が何語だったかを決める。
/// SenseVoice は、マイクで頼んだ言語と違う言葉が聞こえると、聞こえた言葉のまま文字にすることがある。
/// そこで、SenseVoice の判定と、文字の種類（ハングル・かな・漢字・アルファベット）から、
/// 本当に話された言語を決めて、翻訳の「元の言語」に使う。
enum SpokenLanguage {
    /// 話された言語を、ja / ko / zh / en のどれかで返す。
    /// - senseVoiceTag: SenseVoice が判定した言語（例: "ja"、"<|ko|>"）
    /// - requested: マイクで頼んだ言語（ja / ko / zh / en）
    static func detect(text: String, senseVoiceTag: String, requested: String) -> String {
        // SenseVoice が、頼んだのとは違う言語だとはっきり判定したら、それを信じる
        let tag = senseVoiceTag
            .replacingOccurrences(of: "<|", with: "")
            .replacingOccurrences(of: "|>", with: "")
            .lowercased()
        let fromSenseVoice: String? = switch tag {
        case "ja", "ko", "en", "zh": tag
        case "yue": "zh"  // 広東語は中国語として訳す
        default: nil
        }
        if let fromSenseVoice, fromSenseVoice != requested {
            return fromSenseVoice
        }

        // それ以外は、文字の種類で決める
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
        if hangul > 0 { return "ko" }
        if kana > 0 { return "ja" }
        // 漢字だけの文は、日本語のマイクなら日本語、それ以外なら中国語とみなす
        if han > 0 { return requested == "ja" ? "ja" : "zh" }
        if latin > 0 { return "en" }
        return requested
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
