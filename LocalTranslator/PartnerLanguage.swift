import Foundation

/// 相手の言語。PLaMo の target_lang に渡すコードも持たせておく。
enum PartnerLanguage: String, CaseIterable, Identifiable {
    case korean
    case chinese
    case english

    var id: String { rawValue }

    /// 画面に出す言語名（その言語で書く）
    var nativeName: String {
        switch self {
        case .korean: return "한국어"
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    /// 日本語での言語名
    var japaneseName: String {
        switch self {
        case .korean: return "韓国語"
        case .chinese: return "中国語"
        case .english: return "英語"
        }
    }

    /// PLaMo 3 Translate の target_lang に渡すコード
    var plamoCode: String {
        switch self {
        case .korean: return "ko"
        case .chinese: return "zh-hans"
        case .english: return "en"
        }
    }

    /// SenseVoice に「この言語で聞いて」と伝えるコード
    var senseVoiceCode: String {
        switch self {
        case .korean: return "ko"
        case .chinese: return "zh"
        case .english: return "en"
        }
    }

    /// 読み上げの声の言語（iPhone に入っている声を選ぶためのコード）
    var voiceCode: String {
        switch self {
        case .korean: return "ko-KR"
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        }
    }

    /// 読み上げている最中の表示
    var speakingLabel: String {
        switch self {
        case .korean: return "읽는 중… 마이크를 누르면 멈춰요"
        case .chinese: return "正在朗读… 按麦克风可停止"
        case .english: return "Speaking… tap the mic to stop"
        }
    }

    /// 相手側パネルの見出し（「相手」をその言語で）
    var partnerLabel: String {
        switch self {
        case .korean: return "상대방"
        case .chinese: return "对方"
        case .english: return "Partner"
        }
    }

    /// 相手側パネルの案内文
    var tapToSpeakHint: String {
        switch self {
        case .korean: return "마이크를 누르고 말씀하세요"
        case .chinese: return "请按麦克风说话"
        case .english: return "Press the mic and speak"
        }
    }

    /// 聞き取り中の表示
    var listeningLabel: String {
        switch self {
        case .korean: return "듣는 중… 다시 누르면 끝나요"
        case .chinese: return "正在听… 再按一次结束"
        case .english: return "Listening… tap again to finish"
        }
    }

    /// 声を文字にしている最中の表示
    var processingLabel: String {
        switch self {
        case .korean: return "글자로 바꾸는 중…"
        case .chinese: return "正在转换成文字…"
        case .english: return "Converting to text…"
        }
    }

    /// 翻訳している最中の表示
    var translatingLabel: String {
        switch self {
        case .korean: return "번역 중…"
        case .chinese: return "正在翻译…"
        case .english: return "Translating…"
        }
    }

    /// 翻訳できなかったときの表示
    var translationFailedLabel: String {
        switch self {
        case .korean: return "번역하지 못했어요"
        case .chinese: return "翻译失败"
        case .english: return "Couldn't translate"
        }
    }

    /// 翻訳が使えないときの表示
    var translatorUnavailableLabel: String {
        switch self {
        case .korean: return "번역을 사용할 수 없어요"
        case .chinese: return "无法使用翻译"
        case .english: return "Translation is unavailable"
        }
    }

    /// アプリの準備中（モデルの読み込み中）の表示
    var preparingLabel: String {
        switch self {
        case .korean: return "준비 중…"
        case .chinese: return "准备中…"
        case .english: return "Getting ready…"
        }
    }

    /// 何も聞き取れなかったときの表示
    var notHeardLabel: String {
        switch self {
        case .korean: return "잘 안 들렸어요. 다시 말씀해 주세요"
        case .chinese: return "没听清楚，请再说一次"
        case .english: return "Couldn't hear you. Please try again"
        }
    }

    /// 準備に失敗したときの表示
    var failedLabel: String {
        switch self {
        case .korean: return "음성 인식을 사용할 수 없어요"
        case .chinese: return "无法使用语音识别"
        case .english: return "Speech recognition is unavailable"
        }
    }
}
