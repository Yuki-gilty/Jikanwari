import Foundation
import Observation
import WidgetKit

struct Lesson: Hashable {
    let name: String
    let teacher: String
    let room: String
}

/// 選択授業の1クラス分（固定の授業は key が "" の1件だけ）
struct Variant: Codable, Hashable {
    var key: String
    var name: String
    var teacher: String
    var room: String

    var lesson: Lesson { Lesson(name: name, teacher: teacher, room: room) }
}

/// 1コマ。英語のクラス分けや理科選択のように人によって授業が変わるコマは group に名前が入り、variants にクラスごとの授業が並ぶ
struct Slot: Codable, Hashable {
    var group: String        // "" = 全員同じ授業
    var variants: [Variant]  // [] = 空き

    static let free = Slot(group: "", variants: [])
}

struct PeriodTime: Codable, Hashable {
    var start: String  // "8:30"
    var end: String
}

/// A/B週・B'週のような週ごとの時間割。先頭が通常週で、それ以外は weekStarts の週だけ使う
struct WeekPattern: Codable, Hashable {
    var name: String
    var weekStarts: [String]  // その週の月曜日 "yyyy-MM-dd"
    var days: [[Slot]]        // [曜日][時限]
}

struct TimetableData: Codable, Hashable {
    var title: String
    var periods: [PeriodTime]
    var dayCount: Int  // 5=月〜金, 6=月〜土
    var patterns: [WeekPattern]
    var termEnd: String  // "yyyy-MM-dd"、不明なら ""
    var hasLessons: Bool {
        !periods.isEmpty && patterns.contains { pattern in
            pattern.days.contains { day in day.contains { slot in
                slot.variants.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            } }
        }
    }

    var english: [String: String]? = nil  // 教科名・教室 → 英語のSiriが読む英語名（読み込み時にClaudeが付ける）
    var calendar: [String: SchoolDay]? = nil  // "yyyy-MM-dd" → 年間予定（休み・午前授業・○曜授業日）
}

/// 年間予定表から読んだ、いつもと違う日
struct SchoolDay: Codable, Hashable {
    var note: String            // "Dalton Fest" "午前授業" など
    var off = false             // 授業がない日
    var weekday: Int? = nil     // ○曜授業日（0=月）
    var lastPeriod: Int? = nil  // 午前授業なら4（ここまでの時限だけ授業）
}

/// Siri用の拡張機能（アプリを開かずに答える）からも読めるように、時間割とクラス設定はApp Groupに置く
enum AppGroup {
    static let id = "group.com.yukiyamamoto.jikanwari"

    static let defaults: UserDefaults = {
        guard let d = UserDefaults(suiteName: id) else { return .standard }
        // App Groupに移す前にアプリ内に保存していたクラス設定を引き継ぐ
        if d.object(forKey: "choices") == nil {
            for key in ["choices", "eng", "ron", "kiso", "sci"] {
                if let v = UserDefaults.standard.object(forKey: key) { d.set(v, forKey: key) }
            }
        }
        return d
    }()

    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) ?? .applicationSupportDirectory
    }
}

struct Settings {
    var choices: [String: String]  // 選択授業のグループ名 → 自分のクラス

    static var current: Settings {
        let d = AppGroup.defaults
        if let c = d.dictionary(forKey: "choices") as? [String: String] { return Settings(choices: c) }
        return Settings(choices: [:])
    }

    func save() { AppGroup.defaults.set(choices, forKey: "choices") }

    func lesson(_ slot: Slot) -> Lesson? {
        guard let first = slot.variants.first else { return nil }
        if slot.group.isEmpty { return first.lesson }
        return (slot.variants.first { $0.key == choices[slot.group] } ?? first).lesson
    }
}

/// 読み込んだ時間割はApp Groupに保存。なければ空の状態から始める
@Observable
final class TimetableStore {
    static let shared = TimetableStore()

    private(set) var data: TimetableData { didSet { periods = Self.parse(data) } }
    var hasTimetable: Bool { data.hasLessons }
    private(set) var isCustom: Bool
    /// 時限の時刻を数字にしたもの。画面を描くたびに文字列を読み直さないよう、時間割が変わったときだけ作る
    @ObservationIgnored private(set) var periods: [(start: (Int, Int), end: (Int, Int))] = []

    private static var url: URL { AppGroup.container.appending(path: "timetable.json") }

    private init() {
        // App Groupに移す前にアプリ内に保存していた時間割を引き継ぐ
        let old = URL.applicationSupportDirectory.appending(path: "timetable.json")
        if old != Self.url, FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: Self.url.path) {
            try? FileManager.default.moveItem(at: old, to: Self.url)
        }
        (data, isCustom) = Self.load()
        periods = Self.parse(data)  // initでは didSet が呼ばれない
    }

    private static func parse(_ t: TimetableData) -> [(start: (Int, Int), end: (Int, Int))] {
        t.periods.map { (Timetable.hm($0.start) ?? (0, 0), Timetable.hm($0.end) ?? (0, 0)) }
    }

    private static func load() -> (TimetableData, Bool) {
        if let raw = try? Data(contentsOf: url), let t = try? JSONDecoder().decode(TimetableData.self, from: raw) {
            return (t, true)
        }
        return (Timetable.empty, false)
    }

    /// Siriの拡張機能はプロセスが残ることがあるので、答える前にアプリで保存した最新の時間割を読み直す
    func reload() { (data, isCustom) = Self.load() }

    func save(_ t: TimetableData) throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(t).write(to: Self.url, options: .atomic)
        data = t
        isCustom = true
        WidgetCenter.shared.reloadAllTimelines()  // ウィジェットも新しい時間割で描き直す
    }

    func resetToEmpty() {
        try? FileManager.default.removeItem(at: Self.url)
        data = Timetable.empty
        isCustom = false
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum Timetable {
    static var data: TimetableData { TimetableStore.shared.data }

    private static let cal = Calendar(identifier: .gregorian)

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var periods: [(start: (Int, Int), end: (Int, Int))] { TimetableStore.shared.periods }

    /// "8:30" → (8, 30)
    static func hm(_ s: String) -> (Int, Int)? {
        let p = s.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
        return (p[0], p[1])
    }

    /// i限の前が30分以上空いていれば長い休み（昼休みなど）
    static func isLongBreak(before i: Int) -> Bool {
        let ps = periods
        guard i > 0, i < ps.count else { return false }
        return (ps[i].start.0 * 60 + ps[i].start.1) - (ps[i - 1].end.0 * 60 + ps[i - 1].end.1) >= 30
    }

    static var termEnd: Date {
        dayFormatter.date(from: data.termEnd) ?? cal.date(byAdding: .day, value: 180, to: Date())!
    }

    /// その日に使う週パターン（index 0 = 通常週）
    static func pattern(for date: Date) -> (index: Int, pattern: WeekPattern) {
        let day = cal.startOfDay(for: date)
        for (i, p) in data.patterns.enumerated() where i > 0 {
            for s in p.weekStarts {
                guard let start = dayFormatter.date(from: s),
                      let end = cal.date(byAdding: .day, value: 7, to: start) else { continue }
                if day >= start && day < end { return (i, p) }
            }
        }
        return (0, data.patterns[0])
    }

    /// 0=月 ... 5=土, nil=授業のない曜日
    static func weekdayIndex(_ date: Date) -> Int? {
        let i = (cal.component(.weekday, from: date) + 5) % 7  // 1=日 → 6
        return i < data.dayCount ? i : nil
    }

    /// 年間予定で、その日がいつもと違うか
    static func schoolDay(_ date: Date) -> SchoolDay? {
        guard let cal = data.calendar, !cal.isEmpty else { return nil }
        return cal[dayFormatter.string(from: date)]
    }

    /// 休みの日は空、午前授業は午前のコマだけ、○曜授業日はその曜日の時間割
    static func lessons(for date: Date, settings: Settings = .current) -> [Lesson?] {
        let n = data.periods.count
        let special = schoolDay(date)
        guard special?.off != true, weekdayIndex(date) != nil,
              let wd = special?.weekday ?? weekdayIndex(date) else { return Array(repeating: nil, count: n) }
        let days = pattern(for: date).pattern.days
        let slots = wd < days.count ? days[wd] : []
        return (0..<n).map { i in
            if let last = special?.lastPeriod, i >= last { return nil }
            return i < slots.count ? settings.lesson(slots[i]) : nil
        }
    }

    /// 選択授業のグループ（クラス設定に並べる）
    static var groups: [(name: String, keys: [String])] {
        var result: [(name: String, keys: [String])] = []
        for p in data.patterns {
            for day in p.days {
                for s in day where !s.group.isEmpty {
                    if let i = result.firstIndex(where: { $0.name == s.group }) {
                        for v in s.variants where !result[i].keys.contains(v.key) { result[i].keys.append(v.key) }
                    } else {
                        result.append((s.group, s.variants.map(\.key)))
                    }
                }
            }
        }
        return result
    }

    /// 初回起動・削除後は、授業も学校情報も持たない。
    static let empty = TimetableData(
        title: "時間割", periods: [], dayCount: 5,
        patterns: [WeekPattern(name: "通常", weekStarts: [], days: Array(repeating: [], count: 5))],
        termEnd: "")
}
