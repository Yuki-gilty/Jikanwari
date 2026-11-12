import SwiftUI
import WidgetKit

// MARK: - データ

/// 1日の授業。6・7限のように同じ授業・同じ教室が続くコマは1つにまとめる（アプリの一覧と同じ）
struct ClassBlock: Hashable {
    let first: Int  // 0始まり
    let last: Int
    let lesson: Lesson
    let start: Date
    let end: Date

    var periods: String { (first...last).map { "\($0 + 1)" }.joined(separator: "・") }
}

struct ClassEntry: TimelineEntry {
    let date: Date
    let hasTimetable: Bool
    let day: Date             // 一覧に出す日（放課後なら次に授業がある日）
    let blocks: [ClassBlock]  // その日の授業
    let current: ClassBlock?  // 授業中
    let next: ClassBlock?     // 次の授業（今日でなくてもよい）
    let offNote: String?      // 今日が休みなら、その理由
    let week: [[ClassBlock?]] // 今週（月〜金 × 時限）
}

enum ClassTimeline {
    private static let cal = Calendar.current

    static func blocks(on day: Date) -> [ClassBlock] {
        let lessons = Timetable.lessons(for: day)
        let periods = Timetable.periods
        var result: [ClassBlock] = []
        for (i, lesson) in lessons.enumerated() {
            guard let lesson, i < periods.count,
                  let start = cal.date(bySettingHour: periods[i].start.0, minute: periods[i].start.1, second: 0, of: day),
                  let end = cal.date(bySettingHour: periods[i].end.0, minute: periods[i].end.1, second: 0, of: day) else { continue }
            if let last = result.last, last.last == i - 1, last.lesson == lesson, !Timetable.isLongBreak(before: i) {
                result[result.count - 1] = ClassBlock(first: last.first, last: i, lesson: lesson, start: last.start, end: end)
            } else {
                result.append(ClassBlock(first: i, last: i, lesson: lesson, start: start, end: end))
            }
        }
        return result
    }

    static func entry(at now: Date) -> ClassEntry {
        let has = TimetableStore.shared.hasTimetable
        let today = cal.startOfDay(for: now)
        let todays = blocks(on: today)
        let current = todays.first { $0.start <= now && now < $0.end }
        // 次の授業：今日の残り → なければ2週間先まで探す
        var next = todays.first { $0.start > now }
        var listDay = today
        var list = todays
        if next == nil {
            for offset in 1..<15 {
                guard let d = cal.date(byAdding: .day, value: offset, to: today) else { break }
                let b = blocks(on: d)
                if let first = b.first {
                    next = first
                    // 放課後（今日の授業がもう終わっている）なら、一覧も次の日にする
                    if current == nil { listDay = d; list = b }
                    break
                }
            }
        }
        let off = Timetable.schoolDay(today).flatMap { $0.off ? $0.note : nil }

        // 今週（土日なら来週）の月〜金
        let weekdayOffset = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: weekdayOffset >= 5 ? 7 - weekdayOffset : -weekdayOffset, to: today)!
        let n = Timetable.periods.count
        let week: [[ClassBlock?]] = (0..<Timetable.data.dayCount).map { d in
            let day = cal.date(byAdding: .day, value: d, to: monday)!
            let b = blocks(on: day)
            return (0..<n).map { i in b.first { i >= $0.first && i <= $0.last } }
        }
        return ClassEntry(date: now, hasTimetable: has, day: listDay, blocks: list, current: current,
                          next: next, offNote: off, week: week)
    }

    /// 授業の始まり・終わりのたびに切り替わる1日分
    static func timeline() -> Timeline<ClassEntry> {
        TimetableStore.shared.reload()
        let now = Date()
        var times: Set<Date> = [now]
        for offset in 0...1 {
            guard let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            times.insert(d)
            for b in blocks(on: d) {
                times.insert(b.start)
                times.insert(b.end)
                times.insert(b.start.addingTimeInterval(-60 * 60))  // 1時間前から「あと◯分」を動かす
            }
        }
        let horizon = now.addingTimeInterval(36 * 3600)
        let entries = times.filter { $0 >= now && $0 <= horizon }.sorted().map(entry(at:))
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        return Timeline(entries: entries, policy: .after(min(horizon, cal.date(byAdding: .hour, value: 1, to: tomorrow)!)))
    }
}

struct ClassProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClassEntry { .sample }
    func getSnapshot(in context: Context, completion: @escaping (ClassEntry) -> Void) {
        TimetableStore.shared.reload()
        let e = ClassTimeline.entry(at: Date())
        completion(context.isPreview && (e.next == nil || !e.hasTimetable) ? .sample : e)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClassEntry>) -> Void) {
        completion(ClassTimeline.timeline())
    }
}

extension ClassEntry {
    /// ウィジェットを選ぶ画面の見本
    static var sample: ClassEntry {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: today)! }
        let b = [
            ClassBlock(first: 0, last: 0, lesson: Lesson(name: "英コミⅡ スタンダード", teacher: "", room: "310"), start: at(8, 30), end: at(9, 15)),
            ClassBlock(first: 1, last: 1, lesson: Lesson(name: "D基礎", teacher: "", room: "212"), start: at(9, 25), end: at(10, 10)),
            ClassBlock(first: 2, last: 3, lesson: Lesson(name: "数学B", teacher: "", room: "306"), start: at(10, 20), end: at(12, 0)),
            ClassBlock(first: 4, last: 5, lesson: Lesson(name: "家庭基礎", teacher: "", room: "家庭科室"), start: at(13, 0), end: at(14, 40)),
            ClassBlock(first: 6, last: 7, lesson: Lesson(name: "論理・表現Ⅱ", teacher: "", room: "313"), start: at(14, 50), end: at(16, 30)),
        ]
        let week: [[ClassBlock?]] = (0..<5).map { _ in (0..<8).map { i in b.first { i >= $0.first && i <= $0.last } } }
        return ClassEntry(date: at(10, 5), hasTimetable: true, day: today, blocks: b, current: b[1], next: b[2],
                          offNote: nil, week: week)
    }
}

// MARK: - 次の授業

struct NextClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextClass", provider: ClassProvider()) { e in
            NextClassView(e: e)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("次の授業")
        .description("次の授業・教室・始まるまでの時間")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// 授業中でも、そのあとの授業を出す（見た目は「次の授業」と同じ）
struct AfterThisWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AfterThis", provider: ClassProvider()) { e in
            NextClassView(e: e, alwaysNext: true)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("その次の授業")
        .description("授業中でも、次の授業・教室・始まるまでの時間")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextClassView: View {
    let e: ClassEntry
    var alwaysNext = false
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !e.hasTimetable {
            EmptyTimetable(compact: family.isAccessory)
        } else {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            case .systemLarge: large
            default: small
            }
        }
    }

    /// いま見せる授業：授業中ならその授業、休み時間なら次
    private var focus: ClassBlock? { alwaysNext ? e.next : (e.current ?? e.next) }
    private var inClass: Bool { !alwaysNext && e.current != nil }

    // ロック画面：1行
    private var inline: some View {
        Group {
            if let f = focus {
                Text("\(f.periods)限 \(f.lesson.name)\(f.lesson.room.isEmpty ? "" : " · \(f.lesson.room)")")
            } else {
                Text("授業はありません")
            }
        }
    }

    // ロック画面：丸。始まるまで（授業中は終わるまで）の残りが輪になって減っていく
    @ViewBuilder private var circular: some View {
        if let f = focus {
            let range = inClass ? f.start...f.end : min(e.date, f.start)...f.start
            ProgressView(timerInterval: range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: -2) {
                    Text(f.periods).font(.system(size: f.periods.count > 1 ? 15 : 22, weight: .bold, design: .rounded))
                    Text("限").font(.system(size: 9, weight: .bold))
                }
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "moon.zzz").font(.title3)
            }
        }
    }

    // ロック画面：四角
    @ViewBuilder private var rectangular: some View {
        if let f = focus {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(inClass ? "授業中 \(f.periods)限" : "次 \(f.periods)限")
                    Spacer(minLength: 0)
                    if inClass {
                        Text("〜\(f.end, format: .dateTime.hour().minute())")
                    } else {
                        StartsIn(f: f, now: e.date)
                    }
                }
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
                Text(f.lesson.name).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                if !f.lesson.room.isEmpty {
                    Label(f.lesson.room, systemImage: "mappin.and.ellipse").font(.caption).lineLimit(1)
                }
            }
        } else {
            Text("授業はありません").font(.headline)
        }
    }

    // ホーム：小
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(e: e, inClass: inClass, focus: focus)
            Spacer(minLength: 4)
            if let f = focus {
                BigClass(f: f, nameSize: 22)
                Spacer(minLength: 4)
                Footer(f: f, inClass: inClass, now: e.date)
            } else {
                OffText(note: e.offNote)
            }
        }
    }

    // ホーム：中（左に次の授業、右に今日の残り）
    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.separator).frame(width: 0.5)
            DayList(e: e, limit: 4, skip: focus, compact: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ホーム：大（次の授業を大きく、下に今日の一覧）
    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            Header(e: e, inClass: inClass, focus: focus)
            if let f = focus {
                BigClass(f: f, nameSize: 30)
                Footer(f: f, inClass: inClass, now: e.date)
            } else {
                OffText(note: e.offNote)
            }
            Rectangle().fill(.separator).frame(height: 0.5)
            DayList(e: e, limit: 6, skip: nil, compact: false)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 今日の時間割

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: ClassProvider()) { e in
            Group {
                if e.hasTimetable { TodayView(e: e) } else { EmptyTimetable(compact: false) }
            }
            .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("今日の時間割")
        .description("今日の授業を一覧で。放課後は次の日に切り替わります")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct TodayView: View {
    let e: ClassEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle).font(.headline)
                Text(e.day, format: .dateTime.month().day().weekday())
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let special = Timetable.schoolDay(e.day), !special.off {
                    Text(special.note).font(.caption.weight(.semibold)).lineLimit(1)
                }
            }
            if e.blocks.isEmpty {
                OffText(note: e.offNote)
            } else if family == .systemMedium {
                // 中：2列に並べる
                let half = (e.blocks.count + 1) / 2
                HStack(alignment: .top, spacing: 14) {
                    DayList(e: e, blocks: Array(e.blocks.prefix(half)), compact: true)
                    DayList(e: e, blocks: Array(e.blocks.dropFirst(half)), compact: true)
                }
            } else {
                DayList(e: e, blocks: e.blocks, compact: false)
            }
            Spacer(minLength: 0)
        }
    }

    private var dayTitle: String {
        let cal = Calendar.current
        return cal.isDate(e.day, inSameDayAs: e.date) ? "今日" : cal.isDateInTomorrow(e.day) ? "明日" : "次の授業日"
    }
}

// MARK: - 今週の時間割

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Week", provider: ClassProvider()) { e in
            Group {
                if e.hasTimetable { WeekView(e: e) } else { EmptyTimetable(compact: false) }
            }
            .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("今週の時間割")
        .description("月〜金をマス目で。今日の列と今の授業が分かります")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

struct WeekView: View {
    let e: ClassEntry
    private let days = ["月", "火", "水", "木", "金", "土"]

    var body: some View {
        let cal = Calendar.current
        let todayIndex = (cal.component(.weekday, from: e.date) + 5) % 7
        let periods = e.week.first?.count ?? 0
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Text("").frame(width: 14)
                ForEach(e.week.indices, id: \.self) { d in
                    Text(days[d])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(d == todayIndex ? Color(.systemRed) : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<periods, id: \.self) { i in
                GridRow {
                    Text("\(i + 1)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).frame(width: 14)
                    ForEach(e.week.indices, id: \.self) { d in
                        cell(e.week[d][i], period: i, today: d == todayIndex)
                    }
                }
            }
        }
    }

    private func cell(_ b: ClassBlock?, period i: Int, today: Bool) -> some View {
        let now = today && b != nil && b == e.current
        // 続くコマは最初のマスにだけ名前を書く
        let showName = b.map { $0.first == i } ?? false
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(b == nil ? Color.clear : now ? Color.primary : Color(.secondarySystemBackground))
            .overlay {
                if let b, showName {
                    Text(b.lesson.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(now ? Color(.systemBackground) : .primary)
                        .lineLimit(2).minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .padding(2)
                }
            }
            .overlay {
                if today {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(.systemRed).opacity(0.5), lineWidth: 1)
                }
            }
    }
}

// MARK: - ロック画面：このあとの授業

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Upcoming", provider: ClassProvider()) { e in
            UpcomingView(e: e)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("このあとの授業")
        .description("ロック画面に、このあとの授業を3つ（丸は次の教室）")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct UpcomingView: View {
    let e: ClassEntry
    @Environment(\.widgetFamily) private var family

    /// 授業中の授業と、そのあと
    private var upcoming: [ClassBlock] {
        let rest = e.blocks.filter { $0.end > e.date }
        return rest.isEmpty ? Array(e.blocks.prefix(3)) : Array(rest.prefix(3))
    }

    var body: some View {
        if !e.hasTimetable {
            Image(systemName: "calendar.badge.plus")
        } else if family == .accessoryCircular {
            // 丸：次（授業中ならいま）の教室を大きく
            let f = e.current ?? e.next
            let room = f.map { $0.lesson.room.isEmpty ? String($0.lesson.name.prefix(3)) : $0.lesson.room } ?? "休"
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(f.map { "\($0.periods)限" } ?? "")
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                    Text(room)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 4)
                }
                .widgetAccentable()
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                if upcoming.isEmpty {
                    Text("授業はありません").font(.headline)
                }
                ForEach(upcoming, id: \.self) { b in
                    HStack(spacing: 5) {
                        Text(b.periods)
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .lineLimit(1).fixedSize()
                            .frame(minWidth: 22, alignment: .leading)
                            .widgetAccentable()
                        Text(b.lesson.name).font(.caption.weight(b == e.current ? .heavy : .semibold)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(b.lesson.room).font(.caption2).lineLimit(1)
                    }
                    .opacity(b.end <= e.date ? 0.5 : 1)
                }
            }
        }
    }
}

// MARK: - 部品

private extension WidgetFamily {
    var isAccessory: Bool { [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(self) }
}

/// 「次の授業」「授業中」と、いつの授業か
private struct Header: View {
    let e: ClassEntry
    let inClass: Bool
    let focus: ClassBlock?

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(inClass ? Color(.systemRed) : .secondary)
            Spacer(minLength: 0)
            if let f = focus, !inClass, !Calendar.current.isDate(f.start, inSameDayAs: e.date) {
                Text(f.start, format: .dateTime.month().day().weekday()).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var label: String {
        if inClass { return "授業中" }
        guard let f = focus else { return "今日" }
        let cal = Calendar.current
        if cal.isDate(f.start, inSameDayAs: e.date) { return "次の授業" }
        return cal.isDateInTomorrow(f.start) ? "明日の最初の授業" : "次の授業日"
    }
}

/// 時限と授業名を大きく
private struct BigClass: View {
    let f: ClassBlock
    let nameSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(f.periods)限")
                .font(.system(size: nameSize * 0.62, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(f.lesson.name)
                .font(.system(size: nameSize, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            if !f.lesson.room.isEmpty {
                Label(f.lesson.room, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
    }
}

/// 始まるまで／終わるまで
private struct Footer: View {
    let f: ClassBlock
    let inClass: Bool
    let now: Date

    var body: some View {
        if inClass {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(timerInterval: f.start...f.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(.primary)
                Text("\(f.end, format: .dateTime.hour().minute()) まで").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        } else {
            StartsIn(f: f, now: now).font(.caption.weight(.bold))
        }
    }
}

/// 1時間以内なら「あと12:34」と動かし、それより先は開始時刻
private struct StartsIn: View {
    let f: ClassBlock
    let now: Date

    var body: some View {
        if f.start.timeIntervalSince(now) <= 3600 {
            HStack(spacing: 2) {
                Text("あと")
                Text(timerInterval: min(now, f.start)...f.start, countsDown: true, showsHours: false).monospacedDigit()
            }
            .foregroundStyle(Color(.systemRed))
        } else {
            Text("\(f.start, format: .dateTime.hour().minute())から").foregroundStyle(.secondary)
        }
    }
}

/// その日の授業の一覧。今の授業は反転、終わった授業は薄く
private struct DayList: View {
    let e: ClassEntry
    var blocks: [ClassBlock]
    var compact: Bool

    init(e: ClassEntry, limit: Int, skip: ClassBlock?, compact: Bool) {
        self.e = e
        // まだ終わっていない授業から
        let rest = e.blocks.filter { $0.end > e.date && $0 != skip }
        self.blocks = Array((rest.isEmpty ? e.blocks : rest).prefix(limit))
        self.compact = compact
    }

    init(e: ClassEntry, blocks: [ClassBlock], compact: Bool) {
        self.e = e
        self.blocks = blocks
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            ForEach(blocks, id: \.self) { b in
                row(b)
            }
            if blocks.isEmpty {
                Text("このあとの授業はありません").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ b: ClassBlock) -> some View {
        let now = b == e.current
        let past = b.end <= e.date
        let sub: Color = now ? Color(.systemBackground).opacity(0.75) : .secondary
        return HStack(spacing: 8) {
            // 続くコマは「3・4」と横に1行で（縦に折り返さない）
            Text(b.periods)
                .font(.system(compact ? .caption : .subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: compact ? 22 : 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(b.lesson.name)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)
                if !compact {
                    Text(b.start, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(sub)
                }
            }
            Spacer(minLength: 4)
            Text(b.lesson.room)
                .font(compact ? .caption2 : .caption)
                .lineLimit(1)
                .foregroundStyle(sub)
        }
        .foregroundStyle(now ? Color(.systemBackground) : .primary)
        .padding(.horizontal, now ? 8 : 0)
        .padding(.vertical, now ? 4 : 0)
        .background {
            if now { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary) }
        }
        .opacity(past ? 0.4 : 1)
    }
}

private struct OffText: View {
    let note: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "moon.zzz").font(.title3)
            Text(note == nil ? "授業はありません" : "休み").font(.headline)
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
    }
}

private struct EmptyTimetable: View {
    let compact: Bool
    var body: some View {
        if compact {
            Image(systemName: "calendar.badge.plus")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "calendar.badge.plus").font(.title2)
                Text("アプリで時間割を登録してください").font(.subheadline.weight(.semibold))
            }
        }
    }
}
