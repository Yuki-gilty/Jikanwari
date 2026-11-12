import ActivityKit
import BackgroundTasks
import Foundation

/// 授業が終わった瞬間（と1限の10分前）に「次の授業・教室・開始までの残り時間」のLive Activityを出す。
/// iOS 26 の予約開始APIを使い、アプリを開いたときに今から24時間分を予約し直す。
enum LiveActivities {
    static func refresh() {
        Task {
            for a in Activity<BreakAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            var covered = Set<Date>()  // Live Activityで知らせる時刻（通知と二重にしない）
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                // iOSは同時に持てるLive Activity数に上限がある（予約分含む）ので直近3件だけ
                for s in upcoming(from: Date()).prefix(3) {
                    let content = ActivityContent(state: s, staleDate: s.start, relevanceScore: s.start.timeIntervalSince1970)
                    do {
                        if s.from <= Date() {
                            _ = try Activity.request(attributes: BreakAttributes(), content: content, pushType: nil)
                        } else {
                            let alert = AlertConfiguration(title: "次は\(s.periods)限 \(s.name)",
                                                           body: "教室: \(s.room)（10分後に開始）",
                                                           sound: .default)
                            _ = try Activity.request(attributes: BreakAttributes(), content: content, pushType: nil,
                                                     style: .standard, alertConfiguration: alert, start: s.from)
                            covered.insert(s.from)
                        }
                    } catch {
                        print("LiveActivity request failed:", error)
                        break  // 上限に達したら残りは通常の通知で知らせる
                    }
                }
            }
            Notifier.schedule(skipping: covered)
            scheduleCleanup()
        }
    }

    // MARK: 終わった休み時間を片付ける（積み重ならないように）

    static let cleanupTask = "com.yukiyamamoto.jikanwari.liveactivity-cleanup"

    /// 授業が始まった（休み時間が終わった）Live Activityを消す。バックグラウンドで起こされたときにも呼ぶ
    static func cleanUp() async {
        let now = Date()
        for a in Activity<BreakAttributes>.activities where a.content.state.start <= now {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        scheduleCleanup()
    }

    /// 次の授業が始まるころにアプリを起こしてもらう（起こす時刻はiOSが決めるので、少し遅れることがある）
    private static func scheduleCleanup() {
        let now = Date()
        guard let next = Activity<BreakAttributes>.activities.map(\.content.state.start).filter({ $0 > now }).min() else { return }
        let request = BGAppRefreshTaskRequest(identifier: cleanupTask)
        request.earliestBeginDate = next.addingTimeInterval(30)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: cleanupTask)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// 今から24時間以内の「休み時間 → 次の授業」の一覧
    static func upcoming(from now: Date) -> [BreakAttributes.ContentState] {
        let cal = Calendar(identifier: .gregorian)
        let settings = Settings.current
        var result: [BreakAttributes.ContentState] = []
        for offset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            let lessons = Timetable.lessons(for: day, settings: settings)
            var prevEnd: Date?
            var prev: (i: Int, lesson: Lesson)?
            var block: Int?  // いまの授業のLive Activityが result の何番目か（続く授業をまとめる先）
            for (i, lesson) in lessons.enumerated() {
                let p = Timetable.periods[i]
                guard let start = cal.date(bySettingHour: p.start.0, minute: p.start.1, second: 0, of: day),
                      let end = cal.date(bySettingHour: p.end.0, minute: p.end.1, second: 0, of: day) else { continue }
                defer { prev = lesson.map { (i, $0) } }
                guard let lesson else { continue }
                // 6・7限のように同じ授業が同じ教室で続くなら、間の休み時間は出さずに「6・7限」としてまとめる
                if let prev, prev.i == i - 1, prev.lesson == lesson, !Timetable.isLongBreak(before: i) {
                    if let block { result[block].lastPeriod = i + 1 }
                    prevEnd = end
                    continue
                }
                let from = prevEnd ?? start.addingTimeInterval(-10 * 60)
                block = nil
                if start > now && from < now.addingTimeInterval(24 * 3600) {
                    result.append(.init(period: i + 1, name: lesson.name, room: lesson.room,
                                        teacher: lesson.teacher, from: from, start: start))
                    block = result.count - 1
                }
                prevEnd = end
            }
        }
        return result
    }
}
