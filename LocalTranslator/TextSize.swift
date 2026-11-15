import SwiftUI

/// 文字サイズの 3 段階。訳文と自分の発言の大きさを一緒に切り替える。
/// 「小」は Phase 2 最初の画面と同じ大きさ。
enum TextSize: Int, CaseIterable {
    case small = 0
    case medium = 1
    case large = 2

    /// 大きく表示する訳文の文字サイズ（pt）
    var heardPointSize: CGFloat {
        switch self {
        case .small: return 20  // .title3 と同じ
        case .medium: return 26
        case .large: return 34
        }
    }

    /// 自分の発言の文字サイズ（pt）。訳文と同じ大きさにそろえる（色はグレーで区別）。
    var saidPointSize: CGFloat { heardPointSize }

    /// 画面に出す名前
    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    var larger: TextSize? { TextSize(rawValue: rawValue + 1) }
    var smaller: TextSize? { TextSize(rawValue: rawValue - 1) }
}
