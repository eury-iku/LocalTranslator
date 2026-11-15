import Foundation

/// 音声認識と翻訳をつなぐまでの仮データ。
/// マイクボタンを押すと、ここから順番に例文が出てくる。
struct SamplePhrase {
    let japanese: String
    let korean: String
    let chinese: String
    let english: String

    func text(in language: PartnerLanguage) -> String {
        switch language {
        case .korean: return korean
        case .chinese: return chinese
        case .english: return english
        }
    }
}

enum SampleConversation {
    /// 自分（日本語）が話す例文。最後の 1 つは、枠に入りきらない長さを試すための長文。
    static let mine: [SamplePhrase] = [
        SamplePhrase(
            japanese: "この近くにおいしいレストランはありますか？",
            korean: "이 근처에 맛있는 식당이 있어요?",
            chinese: "这附近有好吃的餐厅吗？",
            english: "Is there a good restaurant near here?"
        ),
        SamplePhrase(
            japanese: "駅までどうやって行けばいいですか？",
            korean: "역까지 어떻게 가면 돼요?",
            chinese: "去车站怎么走？",
            english: "How do I get to the station?"
        ),
        SamplePhrase(
            japanese: "写真を撮ってもらえますか？",
            korean: "사진 좀 찍어 주시겠어요?",
            chinese: "可以帮我拍张照片吗？",
            english: "Could you take a photo for me?"
        ),
        SamplePhrase(
            japanese: "すみません、今日の夕方に駅の近くで友達と待ち合わせをしているんですが、道に迷ってしまいました。このあたりに大きな時計台があるカフェがあるかどうか知っていますか？",
            korean: "실례합니다, 오늘 저녁에 역 근처에서 친구와 만나기로 했는데 길을 잃어버렸어요. 이 근처에 큰 시계탑이 있는 카페가 있는지 아세요?",
            chinese: "不好意思，我今天傍晚约了朋友在车站附近见面，但是迷路了。您知道这附近有没有一家有大钟楼的咖啡馆吗？",
            english: "Excuse me, I'm meeting a friend near the station this evening, but I got lost. Do you know if there's a café with a big clock tower around here?"
        ),
    ]

    /// 相手が話す例文。最後の 1 つは長文。
    static let partner: [SamplePhrase] = [
        SamplePhrase(
            japanese: "はい、この道をまっすぐ行くと左にありますよ。",
            korean: "네, 이 길로 쭉 가면 왼쪽에 있어요.",
            chinese: "有的，沿着这条路一直走，就在左边。",
            english: "Yes, go straight down this street and it's on your left."
        ),
        SamplePhrase(
            japanese: "歩いて10分くらいです。",
            korean: "걸어서 10분 정도예요.",
            chinese: "走路大概十分钟。",
            english: "It's about a ten-minute walk."
        ),
        SamplePhrase(
            japanese: "もちろんです。はい、チーズ！",
            korean: "물론이죠. 자, 김치!",
            chinese: "当然可以。来，茄子！",
            english: "Of course. Say cheese!"
        ),
        SamplePhrase(
            japanese: "ああ、そのカフェなら知っていますよ。この先の交差点を右に曲がって、二つ目の信号を過ぎたら銀行の隣にあります。少し分かりにくいので、見つからなかったら近くのコンビニで聞いてみてください。",
            korean: "아, 그 카페라면 알아요. 이 앞 교차로에서 오른쪽으로 돌아서 두 번째 신호등을 지나면 은행 옆에 있어요. 조금 찾기 어려우니까 못 찾으시면 근처 편의점에 물어보세요.",
            chinese: "啊，那家咖啡馆我知道。在前面的路口右转，过了第二个红绿灯，就在银行旁边。有点不好找，如果找不到的话，可以问问附近的便利店。",
            english: "Oh, I know that café. Turn right at the next intersection, and after the second traffic light, it's next to the bank. It's a little hard to find, so if you can't find it, ask at the convenience store nearby."
        ),
    ]
}
