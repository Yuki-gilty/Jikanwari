import ActivityKit
import Foundation

/// 休み時間のLive Activity：次の授業・教室・開始までのカウントダウン
struct BreakAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var period: Int      // 次の授業の時限(1始まり)
        var lastPeriod: Int? = nil  // 6・7限のように続くときの最後の時限

        /// "6" や "6・7"
        var periods: String { lastPeriod.map { "\(period)・\($0)" } ?? "\(period)" }
        var name: String
        var room: String
        var teacher: String
        var from: Date       // 休み時間の開始(=前の授業の終わり)
        var start: Date      // 次の授業の開始
    }
}
