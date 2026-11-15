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
        case .korean: return "듣는 중…"
        case .chinese: return "正在听…"
        case .english: return "Listening…"
        }
    }
}
