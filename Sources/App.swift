import AppIntents
import SwiftUI

@main
struct JikanwariApp: App {
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: phase) { _, p in
            if p == .active { Notifier.requestAndSchedule() }
        }
        // 授業が始まったら、終わった休み時間のLive Activityを消す
        .backgroundTask(.appRefresh(LiveActivities.cleanupTask)) { await LiveActivities.cleanUp() }
    }
}

struct ContentView: View {
    @State private var date = Date()
    /// 次に日を変えるときのスライド方向（先の日なら右から入る）
    @State private var forward = true
    @State private var monthOpen = false        // 1ヶ月のカレンダーを広げている
    @State private var shownMonth = Date()      // 広げているときに見ている月
    @State private var monthForward = true      // 月をめくる向き
    @State private var stripDragging = false    // カレンダーの上で払っている（下の「日を払う」と混ざらないように）
    @State private var monthSliding = false     // 月をめくっている（行は横にすべる）／広げている（行は上下に広がる）
    @State private var memoTarget: MemoRef?
    @State private var swiping = false
    @State private var lastSwipe = Date.distantPast
    @Namespace private var memoSpace
    private var memos = MemoStore.shared
    @State private var showSettings = false
    @State private var showImport = false
    @State private var showCalendarImport = false
    @State private var showCalendarEditor = false
    @State private var calendarEditorAfterSettings = false
    @State private var calendarAfterSettings = false
    @State private var showManual = false
    @State private var manualAfterSettings = false
    @State private var showPrivacy = false
    @State private var showSurvey = false
    @State private var surveyAfterSettings = false
    @State private var importAfterSettings = false
    @State private var confirmReset = false
    @State private var choices = Settings.current.choices
    private var store = TimetableStore.shared

    private let cal = Calendar.current
    /// 色は「今日」の印だけ。あとは白黒の濃淡で見せる
    private let todayRed = Color(.systemRed)
    private let timeColumn: CGFloat = 46
    private let rowInset: CGFloat = 14

    var body: some View {
        let _ = store.data  // 時間割を読み込み直したら描き直す
        Group {
        if !store.hasTimetable {
            onboarding
        } else {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            let now = ctx.date
            let bs = blocks()  // その日の授業は1回だけ組み立てて、タイトルと一覧で使い回す
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    calendarStrip(now)
                        .padding(.top, 14)
                    // 日を変えたら、進む向きに合わせて横にスライドさせる
                    VStack(alignment: .leading, spacing: 0) {
                        dayTitle(now, bs)
                            .padding(.top, 28)
                            .padding(.horizontal, rowInset)
                            .padding(.bottom, 16)
                        if Timetable.weekdayIndex(date) == nil {
                            noClasses
                        } else {
                            dayList(now, bs)
                        }
                    }
                    .id(cal.startOfDay(for: date))
                    .transition(.push(from: forward ? .trailing : .leading))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
                // iPadの広い画面では横に伸ばしすぎず、読みやすい幅で中央に置く
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemBackground).ignoresSafeArea())
            .simultaneousGesture(DragGesture(minimumDistance: 12)
                .onChanged { v in
                    // 横に動き始めたら「払っている」扱いにして、授業の箱の「押した」を止める
                    if !swiping, abs(v.translation.width) > 12, abs(v.translation.width) > abs(v.translation.height) {
                        swiping = true
                    }
                }
                .onEnded { v in
                    defer { swiping = false; lastSwipe = Date() }
                    // 横に払って前後の日へ（縦スクロールとは区別する）
                    guard !stripDragging, abs(v.translation.width) > 40, abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                    stepDay(v.translation.width < 0 ? 1 : -1)
                })
        }
        }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            LiveActivities.refresh()
            if manualAfterSettings {
                manualAfterSettings = false
                showManual = true
            }
            if importAfterSettings {
                importAfterSettings = false
                showImport = true
            }
            if calendarEditorAfterSettings {
                calendarEditorAfterSettings = false
                showCalendarEditor = true
            }
            if calendarAfterSettings {
                calendarAfterSettings = false
                showCalendarImport = true
            }
            if surveyAfterSettings {
                surveyAfterSettings = false
                showSurvey = true
            }
        }) { settingsSheet }
        .sheet(isPresented: $showManual, onDismiss: Notifier.requestAndSchedule) { ManualTimetableView() }
        .sheet(isPresented: $showImport, onDismiss: Notifier.requestAndSchedule) { ImportView() }
        .sheet(isPresented: $showCalendarEditor, onDismiss: Notifier.requestAndSchedule) { CalendarEditorView() }
        .sheet(isPresented: $showCalendarImport, onDismiss: Notifier.requestAndSchedule) { ImportView(calendarOnly: true) }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .fullScreenCover(isPresented: $showSurvey) {
            OnboardingView(startAtLG: true, onFinish: { showSurvey = false }, onClose: { showSurvey = false })
        }
        .fullScreenCover(item: $memoTarget) { MemoSheet(ref: $0, source: memoSpace) }
        .onChange(of: choices) { _, c in Settings(choices: c).save() }

    }

    /// 時間割がまだないとき：LGと履修科目を答えて組む（写真・PDFの読み込みと手入力も選べる）
    private var onboarding: some View {
        OnboardingView(onImport: { showImport = true }, onManual: { showManual = true },
                       onPrivacy: { showPrivacy = true })
    }

    // MARK: 上部

    private var topBar: some View {
        HStack(spacing: 10) {
            Text(format(monthOpen ? shownMonth : date, "yyyy年M月"))
                .font(monthOpen ? .title3.weight(.bold) : .subheadline.weight(.semibold))
                .foregroundStyle(monthOpen ? .primary : .secondary)
                .contentTransition(.numericText(countsDown: !monthForward))
                .animation(.spring(duration: 0.45, bounce: 0.2), value: monthOpen)
            Spacer()
            Button { toggleMonth() } label: {
                Image(systemName: monthOpen ? "chevron.up" : "calendar")
                    .font(.body.weight(.medium))
                    .frame(width: 26, height: 26)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(monthOpen ? "カレンダーを閉じる" : "1ヶ月のカレンダー")
            if !cal.isDateInToday(date) {
                Button { go(to: Date()) } label: {
                    Text("今日")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4)
                        .frame(height: 26)
                }
                .buttonStyle(.glass)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("設定")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, rowInset - 4)
        .padding(.top, 8)
        .animation(.snappy, value: cal.isDateInToday(date))
    }

    /// 週の帯。カレンダーのボタンで、この週の行を残したまま上下に1ヶ月ぶん広がる
    private func calendarStrip(_ now: Date) -> some View {
        let n = Timetable.data.dayCount
        let weeks = monthOpen ? mondays(in: shownMonth) : [monday(of: date)]
        let selectedWeek = monday(of: date)
        let selectedIndex = weeks.firstIndex(of: selectedWeek) ?? 0
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<n, id: \.self) { i in
                    Text(format(cal.date(byAdding: .day, value: i, to: selectedWeek)!, "E"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(monthOpen || !cal.isDate(cal.date(byAdding: .day, value: i, to: selectedWeek)!, inSameDayAs: now)
                                         ? Color.secondary : todayRed)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
            VStack(spacing: monthOpen ? 6 : 0) {
                ForEach(Array(weeks.enumerated()), id: \.element) { k, m in
                    weekRow(m, now)
                        // 広がるときは、今の週から離れた行ほど少し遅れて現れる
                        .transition(.asymmetric(
                            insertion: rowInsertion(k, selectedIndex),
                            removal: rowRemoval(k, selectedIndex)))
                }
            }
            if monthOpen {
                monthNotes
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .gesture(DragGesture(minimumDistance: 30)
            .onChanged { _ in stripDragging = true }
            .onEnded { v in
                DispatchQueue.main.async { stripDragging = false }
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                let dir = v.translation.width < 0 ? 1 : -1
                if monthOpen { flipMonth(dir) } else { shift(7 * dir, swipe: true) }
            })
    }

    private func rowInsertion(_ k: Int, _ selected: Int) -> AnyTransition {
        if monthSliding { return .move(edge: monthForward ? .trailing : .leading).combined(with: .opacity) }
        let d = Double(abs(k - selected))
        return .opacity.combined(with: .scale(scale: 0.94, anchor: k < selected ? .bottom : .top))
            .combined(with: .offset(y: k < selected ? 10 : -10))
            .animation(.spring(duration: 0.5, bounce: 0.25).delay(0.035 * d))
    }

    private func rowRemoval(_ k: Int, _ selected: Int) -> AnyTransition {
        if monthSliding { return .move(edge: monthForward ? .leading : .trailing).combined(with: .opacity) }
        return .opacity.combined(with: .scale(scale: 0.94, anchor: k < selected ? .bottom : .top))
            .animation(.spring(duration: 0.35, bounce: 0.1))
    }

    private func weekRow(_ monday: Date, _ now: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<Timetable.data.dayCount, id: \.self) { i in
                let d = cal.date(byAdding: .day, value: i, to: monday)!
                let selected = cal.isDate(d, inSameDayAs: date)
                let today = cal.isDate(d, inSameDayAs: now)
                let outside = monthOpen && !cal.isDate(d, equalTo: shownMonth, toGranularity: .month)
                let special = Timetable.schoolDay(d)
                Button { pickDay(d) } label: {
                    VStack(spacing: 3) {
                        Text(format(d, "d"))
                            .font(.system(.title3, design: .rounded).weight(selected ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(selected ? Color(.systemBackground) : today ? todayRed
                                             : special?.off == true ? Color(.tertiaryLabel) : .primary)
                            .frame(width: 40, height: 40)
                            .background {
                                // 選んだ日の丸は、日を変えると隣へすべるように移る
                                if selected {
                                    Circle().fill(today ? todayRed : Color.primary)
                                        .matchedGeometryEffect(id: "selectedDay", in: memoSpace)
                                }
                            }
                        Text(mark(special))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(height: 10)
                    }
                    .opacity(outside ? 0.3 : 1)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 日付の下の小さな印
    private func mark(_ day: SchoolDay?) -> String {
        guard let day else { return "" }
        if day.off { return "休" }
        if day.lastPeriod != nil { return "午前" }
        if let w = day.weekday { return ["月", "火", "水", "木", "金", "土"][w] + "曜" }
        return ""
    }

    /// 広げた月の予定（休み・午前授業・○曜授業日）
    @ViewBuilder private var monthNotes: some View {
        let days = (Timetable.data.calendar ?? [:])
            .compactMap { k, v -> (Date, SchoolDay)? in
                guard let d = Timetable.dayFormatter.date(from: k), cal.isDate(d, equalTo: shownMonth, toGranularity: .month),
                      Timetable.weekdayIndex(d) != nil else { return nil }
                return (d, v)
            }
            .sorted { $0.0 < $1.0 }
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(days, id: \.0) { d, v in
                    Button { pickDay(d) } label: {
                        HStack(spacing: 12) {
                            Text(format(d, "d日(E)"))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .frame(width: 64, alignment: .leading)
                            Text(v.note)
                                .font(.subheadline)
                                .foregroundStyle(v.off ? .secondary : .primary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, rowInset)
            .padding(.top, 18)
            .id(cal.component(.month, from: shownMonth))
            .transition(.opacity)
        }
    }

    private func monday(of d: Date) -> Date {
        cal.date(byAdding: .day, value: -((cal.component(.weekday, from: d) + 5) % 7), to: cal.startOfDay(for: d))!
    }

    /// その月の平日を含む週の月曜日
    private func mondays(in month: Date) -> [Date] {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let next = cal.date(byAdding: .month, value: 1, to: first)!
        var m = monday(of: first)
        if cal.date(byAdding: .day, value: Timetable.data.dayCount - 1, to: m)! < first { m = cal.date(byAdding: .day, value: 7, to: m)! }
        var result: [Date] = []
        while m < next {
            result.append(m)
            m = cal.date(byAdding: .day, value: 7, to: m)!
        }
        return result
    }

    private func toggleMonth() {
        monthSliding = false
        if monthOpen { Haptics.fold() } else { Haptics.unfold(rows: mondays(in: date).count) }
        if !monthOpen { shownMonth = date }
        withAnimation(.spring(duration: 0.5, bounce: 0.22)) { monthOpen.toggle() }
    }

    /// 広げたカレンダーで日を選ぶと、その日の週へ畳みながら戻る
    private func pickDay(_ d: Date) {
        guard monthOpen else { go(to: d); return }
        monthSliding = false
        Haptics.fold()
        forward = d > date
        withAnimation(.spring(duration: 0.5, bounce: 0.22)) {
            date = d
            monthOpen = false
        }
    }

    private func flipMonth(_ dir: Int) {
        Haptics.swipe()
        monthForward = dir > 0
        monthSliding = true
        // 向きを先に描き直してから動かす（消える側の行も新しい向きへ抜けるように）
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.45, bounce: 0.15)) {
                shownMonth = cal.date(byAdding: .month, value: dir, to: shownMonth)!
            }
        }
    }

    private func dayTitle(_ now: Date, _ bs: [Block]) -> some View {
        let title = cal.isDate(date, inSameDayAs: now) ? "今日"
            : cal.isDateInTomorrow(date) ? "明日"
            : cal.isDateInYesterday(date) ? "昨日"
            : format(date, "M月d日")
        let relative = title != format(date, "M月d日")
        var detail = [relative ? format(date, "M月d日 EEEE") : format(date, "EEEE")]
        if let last = bs.last {
            let count = bs.reduce(0) { $0 + ($1.lesson == nil ? 0 : $1.last - $1.first + 1) }
            detail.append("\(count)コマ")
            detail.append("\(format(time(last.last, end: true), "H:mm"))まで")
        }
        let week = Timetable.pattern(for: date)

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .contentTransition(.opacity)
            HStack(spacing: 8) {
                Text(detail.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                // 午前授業・○曜授業日など、いつもと違う日
                if let special = Timetable.schoolDay(date), !special.off {
                    Text(special.note)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary))
                        .lineLimit(1)
                }
                if week.index > 0 {
                    Text(week.pattern.name)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().strokeBorder(Color.primary.opacity(0.25)))
                }
            }
        }
    }

    // MARK: 一覧

    private struct Block: Identifiable {
        let first: Int
        var last: Int
        let lesson: Lesson?
        var id: Int { first }
    }

    private func blocks() -> [Block] {
        let lessons = Timetable.lessons(for: date, settings: Settings(choices: choices))
        var result: [Block] = []
        for (i, l) in lessons.enumerated() {
            if let lastBlock = result.last, lastBlock.last == i - 1, !Timetable.isLongBreak(before: i),
               lastBlock.lesson?.name == l?.name, lastBlock.lesson?.room == l?.room {
                result[result.count - 1].last = i
            } else {
                result.append(Block(first: i, last: i, lesson: l))
            }
        }
        while let last = result.last, last.lesson == nil { result.removeLast() }
        return result
    }

    private func time(_ i: Int, end: Bool) -> Date {
        let p = Timetable.periods[i]
        let t = end ? p.end : p.start
        return cal.date(bySettingHour: t.0, minute: t.1, second: 0, of: date)!
    }

    private enum RowState { case normal, current, next, past }

    private func dayList(_ now: Date, _ bs: [Block]) -> some View {
        let isToday = cal.isDate(date, inSameDayAs: now)
        let currentID = isToday ? bs.first { $0.lesson != nil && time($0.first, end: false) <= now && now < time($0.last, end: true) }?.id : nil
        let nextID = isToday ? bs.first { $0.lesson != nil && time($0.first, end: false) > now }?.id : nil

        return VStack(spacing: 8) {
            ForEach(bs) { b in
                let state: RowState = b.id == currentID ? .current : b.id == nextID ? .next
                    : (isToday && time(b.last, end: true) <= now) ? .past : .normal

                if Timetable.isLongBreak(before: b.first) {
                    breakRow(b.first, past: isToday && time(b.first, end: false) <= now)
                }
                if let lesson = b.lesson {
                    // 授業を押すと、その日のその授業のメモを書ける
                    let key = MemoStore.key(date, period: b.first)
                    Button {
                        // 横に払った指が離れたときの「押した」は無視する（日を変えたいだけなので）
                        guard !swiping, Date().timeIntervalSince(lastSwipe) > 0.35 else { return }
                        Haptics.open()
                        memoTarget = MemoRef(id: key, title: lesson.name,
                                             subtitle: format(date, "M月d日(E) ") + periodLabel(b) + "限")
                    } label: {
                        row(b, state, now)
                            .opacity(state == .past ? 0.4 : 1)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(state == .current ? Color.primary : Color(.secondarySystemBackground)))
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(BoxPress())
                    // 箱がそのまま広がってメモになり、閉じると箱へ戻る
                    .matchedTransitionSource(id: key, in: memoSpace) {
                        $0.clipShape(.rect(cornerRadius: 22, style: .continuous))
                    }
                } else {
                    row(b, state, now)
                }
            }
            if bs.isEmpty { noClasses }
        }
    }

    private func periodLabel(_ b: Block) -> String {
        (b.first...b.last).map { "\($0 + 1)" }.joined(separator: "・")
    }

    private func breakRow(_ before: Int, past: Bool) -> some View {
        let end = Timetable.periods[before - 1].end
        let start = Timetable.periods[before].start
        let name = (11...13).contains(end.0) ? "昼休み" : "休み"
        return HStack(spacing: 10) {
            Text(name)
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
            Text(String(format: "%d:%02d – %d:%02d", end.0, end.1, start.0, start.1)).monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.tertiary)
        .padding(.leading, rowInset + timeColumn + 14)
        .padding(.trailing, rowInset)
        .padding(.vertical, 14)
        .opacity(past ? 0.6 : 1)
    }

    private func row(_ b: Block, _ state: RowState, _ now: Date) -> some View {
        let current = state == .current
        let ink: Color = current ? Color(.systemBackground) : .primary
        let sub: Color = current ? Color(.systemBackground).opacity(0.7) : .secondary
        let start = time(b.first, end: false), end = time(b.last, end: true)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {  // 授業名・教室は箱の縦の真ん中に（横は左寄せのまま）
                // 続けて同じ授業なら1つの箱につなげて、時限は「3–4」とまとめずに1コマずつ縦に並べる
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(b.first...b.last, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(i + 1)")
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(b.lesson == nil ? Color(.tertiaryLabel) : ink)
                            Text(format(time(i, end: false), "H:mm"))
                                .font(.caption)
                                .foregroundStyle(sub)
                        }
                    }
                }
                .monospacedDigit()
                .frame(width: timeColumn, alignment: .leading)

                if let lesson = b.lesson {
                    VStack(alignment: .leading, spacing: 3) {
                        // 6・7限のように続く授業は箱が縦に長いので、教科名も大きく
                        Text(lesson.name)
                            .font(b.first == b.last ? .title3.weight(.bold) : .title.weight(.bold))
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(ink)
                        if !lesson.teacher.isEmpty {
                            Text(lesson.teacher)
                                .font(.subheadline)
                                .foregroundStyle(sub)
                        }
                        let memo = memos.memo(MemoStore.key(date, period: b.first))
                        if !memo.isEmpty {
                            Label(memo.replacingOccurrences(of: "\n", with: " "), systemImage: "note.text")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(current ? ink : todayRed)
                                .padding(.top, 3)
                        }
                    }
                    .lineLimit(1)

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(lesson.room)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if state == .next {
                            let mins = max(1, Int(ceil(start.timeIntervalSince(now) / 60)))
                            Text("あと\(mins)分")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(todayRed)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Text("空き")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

            if current {
                let total = end.timeIntervalSince(start)
                let done = min(1, max(0, now.timeIntervalSince(start) / total))
                let left = max(1, Int(ceil(end.timeIntervalSince(now) / 60)))
                HStack(spacing: 12) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ink.opacity(0.2))
                            Capsule().fill(ink).frame(width: max(4, g.size.width * done))
                        }
                    }
                    .frame(height: 4)
                    Text("残り\(left)分")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sub)
                        .monospacedDigit()
                }
                .padding(.leading, timeColumn + 14)
            }
        }
        .padding(.horizontal, rowInset)
        .padding(.vertical, current ? 18 : 15)
        .accessibilityElement(children: .combine)
    }

    private var noClasses: some View {
        // 年間予定で休みの日は、なぜ休みかも出す（Dalton Fest・振替休日など）
        let off = Timetable.schoolDay(date).flatMap { $0.off ? $0.note : nil }
        return VStack(spacing: 10) {
            Image(systemName: off == nil ? "sun.max" : "moon.zzz")
                .font(.system(size: 30, weight: .light))
            Text(off == nil ? "授業はありません" : "休み")
                .font(.subheadline.weight(.medium))
            if let off {
                Text(off)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    // MARK: 設定

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                let groups = Timetable.groups
                if !groups.isEmpty {
                    Section("クラス") {
                        ForEach(groups, id: \.name) { g in
                            Picker(g.name, selection: choice(g)) {
                                ForEach(g.keys, id: \.self) { Text($0.isEmpty ? "—" : $0) }
                            }
                        }
                    }
                }
                Section {
                    ShortcutsLink()
                } header: {
                    Text("Siri")
                } footer: {
                    Text("「Hey Siri、時間割で次の授業」「時間割で今日の授業」「時間割で明日の授業」と話しかけると答えます")
                }
                Section {
                    if SchoolCatalog.current != nil {
                        Button {
                            surveyAfterSettings = true
                            showSettings = false
                        } label: {
                            Label("LGと履修科目を選び直す", systemImage: "checklist")
                        }
                    }
                    Button {
                        importAfterSettings = true
                        showSettings = false
                    } label: {
                        Label("時間割を読み込む", systemImage: "doc.viewfinder")
                    }
                    Button {
                        manualAfterSettings = true
                        showSettings = false
                    } label: {
                        Label("時間割を編集する", systemImage: "square.and.pencil")
                    }
                    Button {
                        calendarAfterSettings = true
                        showSettings = false
                    } label: {
                        Label("年間予定表を読み込む", systemImage: "calendar.badge.plus")
                    }
                    if !(store.data.calendar ?? [:]).isEmpty {
                        Button("年間予定を確認・編集") {
                            calendarEditorAfterSettings = true
                            showSettings = false
                        }
                    }
                    if store.isCustom {
                        Button("時間割を削除する", role: .destructive) { confirmReset = true }
                    }
                } header: {
                    Text(store.data.title)
                } footer: {
                    Text("時間割や年間予定表を写真・PDFから追加できます。年間予定表は任意です。休校日・振替授業・最終時限を確認して保存してください。")
                }
                Section {
                    Button("プライバシーポリシー") { showSettings = false; showPrivacy = true }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完了") { showSettings = false } }
            .confirmationDialog("登録した時間割を削除しますか？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("時間割を削除する", role: .destructive) { store.resetToEmpty(); showSettings = false }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func choice(_ g: (name: String, keys: [String])) -> Binding<String> {
        Binding(get: { choices[g.name].flatMap { g.keys.contains($0) ? $0 : nil } ?? g.keys.first ?? "" },
                set: { choices[g.name] = $0 })
    }

    private func format(_ d: Date, _ f: String) -> String {
        DateFormats.formatter(f).string(from: d)
    }

    private func shift(_ d: Int, swipe: Bool = false) {
        go(to: cal.date(byAdding: .day, value: d, to: date)!, swipe: swipe)
    }

    /// 授業のある曜日だけを前後にたどる（横に払ったとき）
    private func stepDay(_ dir: Int) {
        var d = date
        for _ in 0..<7 {
            d = cal.date(byAdding: .day, value: dir, to: d)!
            if Timetable.weekdayIndex(d) != nil { break }
        }
        go(to: d, swipe: true)
    }
    private func go(to d: Date, swipe: Bool = false) {
        guard !cal.isDate(d, inSameDayAs: date) else { return }
        if swipe { Haptics.swipe() } else { Haptics.tick() }
        forward = d > date
        // 向きを先に描き直してから動かす（消える側の日も新しい向きへ抜けるように）
        DispatchQueue.main.async { withAnimation(.snappy) { date = d } }
    }
}

/// DateFormatterは作るのが重いので、書式ごとに1つだけ作って使い回す（20秒ごとの描き直しで何十回も呼ばれる）
@MainActor
private enum DateFormats {
    private static var cache: [String: DateFormatter] = [:]

    static func formatter(_ format: String) -> DateFormatter {
        if let f = cache[format] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = format
        cache[format] = f
        return f
    }
}

/// 授業の箱を押している間だけ、少し沈む
private struct BoxPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
