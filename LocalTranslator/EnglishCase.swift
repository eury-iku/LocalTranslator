import Foundation

/// SenseVoice は英語を全部大文字で書く（例: "I DON'T UNDERSTAND JAPANESE"）。
/// そのままだと読みにくく、PLaMo も固有名詞だと思ってカタカナにしてしまうので、
/// ふつうの書き方（"I don't understand Japanese"）に直す。
enum EnglishCase {
    /// 大文字のままにする言葉（小文字で書いたもの → 直した形）
    private static let specialWords: [String: String] = {
        var words: [String: String] = ["i": "I", "ok": "OK", "tv": "TV", "usa": "USA", "uk": "UK"]
        let capitalized = [
            // 国・言語・街
            "japan", "japanese", "english", "korea", "korean", "china", "chinese",
            "america", "american", "taiwan", "taiwanese", "hong", "kong",
            "tokyo", "osaka", "kyoto", "seoul", "beijing", "shanghai",
            // 曜日・月（may と march はふつうの言葉と同じなので入れない）
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "january", "february", "april", "june", "july", "august",
            "september", "october", "november", "december",
            "mr", "mrs", "ms", "dr",
        ]
        for word in capitalized {
            words[word] = word.prefix(1).uppercased() + word.dropFirst()
        }
        return words
    }()

    /// 全部大文字の英語を、ふつうの書き方に直す。小文字がまじっていれば、そのまま返す。
    static func normalize(_ text: String) -> String {
        guard text.contains(where: { $0.isLetter && $0.isUppercase }),
              !text.contains(where: { $0.isLetter && $0.isLowercase })
        else { return text }

        var result = ""
        var word = ""
        // 次の言葉が文の始まりか（最初と、. ? ! のあと）
        var sentenceStart = true

        func flushWord() {
            guard !word.isEmpty else { return }
            let lower = word.lowercased()
            // I'M / I'LL のように、' の前で分けて調べる
            let head = String(lower.split(separator: "'", omittingEmptySubsequences: false).first ?? "")
            var fixed = lower
            if let special = specialWords[head] {
                fixed = special + lower.dropFirst(head.count)
            }
            if sentenceStart, let first = fixed.first {
                fixed = first.uppercased() + fixed.dropFirst()
            }
            result += fixed
            word = ""
            sentenceStart = false
        }

        for character in text {
            if character.isLetter || character.isNumber || character == "'" || character == "’" {
                word.append(character)
            } else {
                flushWord()
                result.append(character)
                if ".?!。？！".contains(character) {
                    sentenceStart = true
                }
            }
        }
        flushWord()
        return result
    }
}
