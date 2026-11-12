import Foundation

/// 学校から配られた後期の時間割（LGごと・A/B週とB'週）。アプリに同梱して、オンボーディングの質問から自分の時間割を組む
struct SchoolCatalog: Decodable {
    struct Entry: Decodable, Hashable {
        let c: String  // 科目コード（例 "512sコⅡ"）
        let r: String  // 教室（先生の名前は持たない）
    }

    struct Course: Decodable {
        let name: String  // 時間割に出す名前（例 "英コミⅡ"）
        let note: String  // 男子/女子 など
    }

    struct Pattern: Decodable {
        let name: String
        let weekStarts: [String]
    }

    struct LG: Decodable, Identifiable {
        let name: String
        let patterns: [[[[Entry]]]]  // [週パターン][曜日][時限] → そのコマに並ぶ授業
        var id: String { name }
    }

    let title: String
    let termEnd: String
    let periods: [[String]]
    let patterns: [Pattern]
    let lgs: [LG]
    let courses: [String: Course]
    let english: [String: String]

    static let current: SchoolCatalog? = {
        guard let url = Bundle.main.url(forResource: "y5-2026-late", withExtension: "json"),
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SchoolCatalog.self, from: raw)
    }()

    func course(_ code: String) -> Course { courses[code] ?? Course(name: code, note: "") }

    /// その授業の教室（よく使う順に2つまで）。同じ名前の授業が並ぶときの見分けに使う
    func rooms(_ code: String, in lg: LG) -> String {
        var count: [String: Int] = [:]
        for e in lg.patterns.joined().joined().joined() where e.c == code && !e.r.isEmpty { count[e.r, default: 0] += 1 }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(2).map(\.key).joined(separator: "・")
    }

    /// 選んだ科目だけを残して、アプリの時間割にする
    func timetable(for lg: LG, taking: Set<String>) -> TimetableData {
        let built = patterns.indices.map { p in
            WeekPattern(name: patterns[p].name, weekStarts: patterns[p].weekStarts, days: lg.patterns[p].map { day in
                day.map { cell in
                    guard let e = cell.first(where: { taking.contains($0.c) }) else { return Slot.free }
                    return Slot(group: "", variants: [Variant(key: "", name: course(e.c).name, teacher: "", room: e.r)])
                }
            })
        }
        return TimetableData(title: "\(title) \(lg.name)",
                             periods: periods.map { PeriodTime(start: $0[0], end: $0[1]) },
                             dayCount: 5, patterns: built, termEnd: termEnd, english: english)
    }
}

/// 「このコマで履修しているのはどれ？」を順に聞いていく。
/// 同じ時間に重なる授業は同時に取れないので、1つ選べばほかは自動で「とっていない」になり、質問はどんどん減る
struct CourseSurvey {
    struct Question: Identifiable, Equatable {
        let id: Int          // cells の番号
        let options: [String]
        let when: String     // "月 3・4限 · 火 5限"
    }

    let lg: SchoolCatalog.LG
    private(set) var answers: [String: Bool] = [:]
    private var history: [[String: Bool]] = []
    private let cells: [[String]]            // 選択肢が多い順
    private let conflicts: [String: Set<String>]
    let allCodes: [String]

    init(lg: SchoolCatalog.LG) {
        self.lg = lg
        var cells: [(codes: [String], p: Int, d: Int, i: Int)] = []
        var conflicts: [String: Set<String>] = [:]
        for (p, pattern) in lg.patterns.enumerated() {
            for (d, day) in pattern.enumerated() {
                for (i, cell) in day.enumerated() where !cell.isEmpty {
                    let codes = cell.map(\.c)
                    cells.append((codes, p, d, i))
                    for c in codes { conflicts[c, default: []].formUnion(codes.filter { $0 != c }) }
                }
            }
        }
        // 選択肢の多いコマから聞くと、少ない質問で全部決まる
        self.cells = cells.sorted { a, b in
            a.codes.count != b.codes.count ? a.codes.count > b.codes.count : (a.p, a.d, a.i) < (b.p, b.d, b.i)
        }.map(\.codes)
        self.conflicts = conflicts
        allCodes = Array(conflicts.keys).sorted()
        // どの授業とも重ならない授業（LH・家庭基礎など）は全員とるので聞かない
        for c in allCodes where conflicts[c]!.isEmpty { answers[c] = true }
    }

    var next: Question? {
        for (n, cell) in cells.enumerated() {
            if cell.contains(where: { answers[$0] == true }) { continue }
            let options = cell.filter { answers[$0] == nil }
            if !options.isEmpty { return Question(id: n, options: options, when: when(options)) }
        }
        return nil
    }

    var progress: Double {
        allCodes.isEmpty ? 1 : Double(answers.count) / Double(allCodes.count)
    }

    var canGoBack: Bool { !history.isEmpty }
    var taking: Set<String> { Set(answers.filter(\.value).keys) }

    /// pick = nil は「どれも履修していない」
    mutating func answer(_ q: Question, pick: String?) {
        history.append(answers)
        for c in q.options { answers[c] = (c == pick) }
        if let pick { for o in conflicts[pick] ?? [] where answers[o] == nil { answers[o] = false } }
    }

    mutating func back() {
        if let last = history.popLast() { answers = last }
    }

    /// 選択肢が並んでいるコマ（A/B週）を「月 3・4限 · 火 5限」のように書く
    private func when(_ codes: [String]) -> String {
        let days = ["月", "火", "水", "木", "金"]
        let set = Set(codes)
        func describe(_ p: Int) -> [String] {
            lg.patterns[p].enumerated().compactMap { d, day in
                let periods = day.indices.filter { set.isSubset(of: day[$0].map(\.c)) }.map { "\($0 + 1)" }
                return periods.isEmpty ? nil : "\(days[d]) \(periods.joined(separator: "・"))限"
            }
        }
        let main = describe(0)
        return (main.isEmpty ? describe(1).map { "B'週 " + $0 } : main).joined(separator: " · ")
    }
}
