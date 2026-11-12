import Foundation
import UserNotifications

/// iOSの通知予約は最大64件なので、今日から先の授業を64件まで予約し直す（アプリを開くたびに更新）
enum Notifier {
    static func requestAndSchedule() {
        let center = UNUserNotificationCenter.current()
        guard TimetableStore.shared.hasTimetable else {
            LiveActivities.refresh()
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { LiveActivities.refresh() }
        }
    }

    static func schedule(skipping covered: Set<Date> = []) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let settings = Settings.current
        let end = Timetable.termEnd
        var count = 0
        var day = cal.startOfDay(for: now)

        while count < 64 && day <= end {
            let lessons = Timetable.lessons(for: day, settings: settings)
            for (i, lesson) in lessons.enumerated() {
                guard let lesson, count < 64 else { continue }
                // 同じ授業・同じ教室の連続コマは最初だけ通知
                if i > 0, let prev = lessons[i - 1], prev.name == lesson.name, prev.room == lesson.room { continue }
                let p = Timetable.periods[i]
                guard let start = cal.date(bySettingHour: p.start.0, minute: p.start.1, second: 0, of: day),
                      let fire = cal.date(byAdding: .minute, value: -10, to: start),
                      fire > now, !covered.contains(fire) else { continue }

                let content = UNMutableNotificationContent()
                // 続くコマもまとめて「6・7限」と書く
                var last = i
                while last + 1 < lessons.count, let next = lessons[last + 1], next.name == lesson.name, next.room == lesson.room,
                      !Timetable.isLongBreak(before: last + 1) { last += 1 }
                content.title = "\((i...last).map { "\($0 + 1)" }.joined(separator: "・"))限 \(lesson.name)（10分後）"
                content.body = [lesson.room.isEmpty ? "" : "教室: \(lesson.room)", lesson.teacher].filter { !$0.isEmpty }.joined(separator: " / ")
                content.sound = .default
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: "\(fire.timeIntervalSince1970)", content: content, trigger: trigger))
                count += 1
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
    }
}
