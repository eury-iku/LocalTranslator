import Foundation

/// 音声認識と翻訳をつなぐまでの仮データ。
/// マイクボタンを押すと、ここから順番に例文が出てくる。
struct SamplePhrase {
    let japanese: String
    let korean: String
    let chinese: String

    func text(in language: PartnerLanguage) -> String {
        switch language {
        case .korean: return korean
        case .chinese: return chinese
        }
    }
}

enum SampleConversation {
    /// 自分（日本語）が話す例文
    static let mine: [SamplePhrase] = [
        SamplePhrase(
            japanese: "この近くにおいしいレストランはありますか？",
            korean: "이 근처에 맛있는 식당이 있어요?",
            chinese: "这附近有好吃的餐厅吗？"
        ),
        SamplePhrase(
            japanese: "駅までどうやって行けばいいですか？",
            korean: "역까지 어떻게 가면 돼요?",
            chinese: "去车站怎么走？"
        ),
        SamplePhrase(
            japanese: "写真を撮ってもらえますか？",
            korean: "사진 좀 찍어 주시겠어요?",
            chinese: "可以帮我拍张照片吗？"
        ),
    ]

    /// 相手が話す例文
    static let partner: [SamplePhrase] = [
        SamplePhrase(
            japanese: "はい、この道をまっすぐ行くと左にありますよ。",
            korean: "네, 이 길로 쭉 가면 왼쪽에 있어요.",
            chinese: "有的，沿着这条路一直走，就在左边。"
        ),
        SamplePhrase(
            japanese: "歩いて10分くらいです。",
            korean: "걸어서 10분 정도예요.",
            chinese: "走路大概十分钟。"
        ),
        SamplePhrase(
            japanese: "もちろんです。はい、チーズ！",
            korean: "물론이죠. 자, 김치!",
            chinese: "当然可以。来，茄子！"
        ),
    ]
}
