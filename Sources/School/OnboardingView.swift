import SwiftUI

/// はじめての時間割づくり。LGを選んで、重なるコマごとに「どれを履修している？」に答えるだけで、
/// A/B週とB'週の時間割が組み上がる。写真・PDFからの読み込みと手入力も選べる
struct OnboardingView: View {
    var startAtLG = false
    var onImport: () -> Void = {}
    var onManual: () -> Void = {}
    var onPrivacy: () -> Void = {}
    var onFinish: () -> Void = {}
    /// 設定から選び直すときだけ。最初の画面で ✕ になる
    var onClose: (() -> Void)?

    private enum Step: Int { case welcome, lg, survey, build }

    @State private var step: Step = .welcome
    @State private var backward = false
    @State private var lg: SchoolCatalog.LG?
    @State private var survey: CourseSurvey?
    private let catalog = SchoolCatalog.current

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Group {
                switch step {
                case .welcome: welcome
                case .lg: lgPicker
                case .survey: surveyStep
                case .build: buildStep
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: backward ? .leading : .trailing).combined(with: .opacity),
                removal: .move(edge: backward ? .trailing : .leading).combined(with: .opacity)))
        }
        .onAppear { if startAtLG, catalog != nil { step = .lg } }
    }

    private func go(_ s: Step) {
        backward = s.rawValue < step.rawValue
        withAnimation(.spring(duration: 0.55, bounce: 0.18)) { step = s }
    }

    // MARK: ようこそ

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeroGrid()
                    .frame(height: 210)
                    .rise(0)
                VStack(alignment: .leading, spacing: 12) {
                    Text("時間割は、\n答えるだけ。")
                        .font(.system(size: 40, weight: .bold))
                        .rise(1)
                    Text("LGと履修している科目を選ぶと、後期の時間割（A/B週・B'週）を自動で組みます。")
                        .foregroundStyle(.secondary)
                        .rise(2)
                }
                .padding(.top, 36)

                VStack(spacing: 12) {
                    if catalog != nil {
                        Button {
                            Haptics.begin()
                            go(.lg)
                        } label: {
                            Text("はじめる").bold().frame(maxWidth: .infinity)
                                .foregroundStyle(Color(.systemBackground))
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.primary)  // アプリの色は白黒（赤は「今日」だけ）
                        .rise(3)
                    }
                    HStack(spacing: 12) {
                        Button(action: onImport) {
                            Label("写真・PDF", systemImage: "doc.viewfinder").frame(maxWidth: .infinity)
                        }
                        Button(action: onManual) {
                            Label("自分で入力", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glass)
                    .rise(4)
                    Text("写真・PDFのAI読み取りは任意です。資料を外部に送信する前に同意を確認します。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .rise(4)
                }
                .controlSize(.large)
                .padding(.top, 36)

                VStack(alignment: .leading, spacing: 8) {
                    Button("プライバシーポリシー", action: onPrivacy)
                        .font(.footnote)
                    Text("個人が制作した非公式アプリです。学校の公式サービスではありません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 28)
                .rise(5)
            }
            .padding(28)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: LG

    private var lgPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(progress: 0.04, icon: onClose == nil ? "chevron.left" : "xmark") {
                Haptics.back()
                if let onClose { onClose() } else { go(.welcome) }
            }
            Text("あなたのLGは？")
                .font(.largeTitle.bold())
                .padding(.top, 28)
                .rise(0)
            Text("高等部2年 · 後期")
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .rise(1)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array((catalog?.lgs ?? []).enumerated()), id: \.element.id) { i, item in
                    Button { pickLG(item) } label: {
                        let on = lg?.id == item.id
                        VStack(spacing: 2) {
                            Text("LG").font(.subheadline.weight(.semibold)).opacity(0.6)
                            Text(item.name.replacingOccurrences(of: "LG", with: ""))
                                .font(.system(size: 60, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(on ? Color(.systemBackground) : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(on ? Color.primary : Color(.secondarySystemBackground)))
                        .scaleEffect(on ? 1.04 : 1)
                    }
                    .buttonStyle(Squish())
                    .disabled(lg != nil)
                    .rise(2 + i)
                }
            }
            .padding(.top, 32)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
        .onAppear { lg = nil }
    }

    private func pickLG(_ item: SchoolCatalog.LG) {
        Haptics.choose()
        withAnimation(.spring(duration: 0.4, bounce: 0.4)) { lg = item }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            survey = CourseSurvey(lg: item)
            go(survey?.next == nil ? .build : .survey)
        }
    }

    // MARK: 履修科目

    @ViewBuilder private var surveyStep: some View {
        if let catalog, let lg, let survey {
            SurveyView(catalog: catalog, lg: lg, survey: Binding(get: { survey }, set: { self.survey = $0 }),
                       onBackOut: { Haptics.back(); go(.lg) },
                       onDone: { go(.build) })
        }
    }

    // MARK: できあがり

    @ViewBuilder private var buildStep: some View {
        if let catalog, let lg, let survey {
            BuildView(catalog: catalog, lg: lg, taking: survey.taking,
                      onBack: { Haptics.back(); go(survey.canGoBack ? .survey : .lg) },
                      onFinish: { data in
                          var data = data
                          data.calendar = Timetable.data.calendar
                          try? TimetableStore.shared.save(data)
                          AppGroup.defaults.set(["lg": lg.name, "taking": Array(survey.taking).sorted()], forKey: "survey")
                          Notifier.requestAndSchedule()
                          LiveActivities.refresh()
                          onFinish()
                      })
        }
    }
}

// MARK: - 質問

private struct SurveyView: View {
    let catalog: SchoolCatalog
    let lg: SchoolCatalog.LG
    @Binding var survey: CourseSurvey
    let onBackOut: () -> Void
    let onDone: () -> Void

    @State private var picked: String?   // 選んだ直後の反転表示
    @State private var pickedNone = false
    @State private var backward = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(progress: 0.08 + 0.84 * survey.progress, canBack: true) {
                guard picked == nil, !pickedNone else { return }
                if survey.canGoBack {
                    Haptics.back()
                    backward = true
                    withAnimation(.spring(duration: 0.5, bounce: 0.15)) { survey.back() }
                } else {
                    onBackOut()
                }
            }
            if let q = survey.next {
                question(q)
                    .id(q.id * 1000 + survey.answers.count)
                    .transition(.asymmetric(
                        insertion: .move(edge: backward ? .leading : .trailing).combined(with: .opacity),
                        removal: .move(edge: backward ? .trailing : .leading).combined(with: .opacity)))
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
    }

    private func question(_ q: CourseSurvey.Question) -> some View {
        let single = q.options.count == 1
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(single ? "この授業を\n履修している？" : "この時間に\n履修しているのは？")
                    .font(.system(size: 30, weight: .bold))
                    .rise(0)
                Label(q.when, systemImage: "clock")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .rise(1)

                VStack(spacing: 10) {
                    ForEach(Array(q.options.enumerated()), id: \.element) { i, code in
                        option(code, in: q)
                            .rise(2 + i)
                    }
                }
                .padding(.top, 26)

                Button { choose(nil, in: q) } label: {
                    Text(single ? "履修していない" : "どれも履修していない")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(pickedNone ? 0.9 : 0.15), lineWidth: pickedNone ? 2 : 1))
                        .scaleEffect(pickedNone ? 0.97 : 1)
                }
                .buttonStyle(Squish())
                .padding(.top, 14)
                .rise(2 + q.options.count)
            }
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .disabled(picked != nil || pickedNone)
    }

    private func option(_ code: String, in q: CourseSurvey.Question) -> some View {
        let course = catalog.course(code)
        let on = picked == code
        return Button { choose(code, in: q) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(course.name).font(.title3.weight(.semibold))
                            .minimumScaleFactor(0.7)  // 「論理・表現Ⅱ アカデミック」も1行に
                        if !course.note.isEmpty {
                            Text(course.note)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().strokeBorder(.secondary.opacity(0.5)))
                        }
                    }
                    Text(catalog.rooms(code, in: lg))
                        .font(.subheadline)
                        .opacity(0.65)
                }
                Spacer(minLength: 8)
                Text(code)
                    .font(.caption.monospaced())
                    .opacity(0.45)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .opacity(on ? 1 : 0.25)
                    .contentTransition(.symbolEffect(.replace))
            }
            .lineLimit(1)
            .foregroundStyle(on ? Color(.systemBackground) : .primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(on ? Color.primary : Color(.secondarySystemBackground)))
            .scaleEffect(on ? 1.02 : 1)
        }
        .buttonStyle(Squish())
    }

    private func choose(_ code: String?, in q: CourseSurvey.Question) {
        if code == nil { Haptics.none() } else { Haptics.choose() }
        withAnimation(.spring(duration: 0.35, bounce: 0.45)) {
            if let code { picked = code } else { pickedNone = true }
        }
        // 選んだのが見えてから次へ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            backward = false
            var s = survey
            s.answer(q, pick: code)
            withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                survey = s
                picked = nil
                pickedNone = false
            }
            if s.next == nil { onDone() }
        }
    }
}

// MARK: - 組み上がり

private struct BuildView: View {
    let catalog: SchoolCatalog
    let lg: SchoolCatalog.LG
    let taking: Set<String>
    let onBack: () -> Void
    let onFinish: (TimetableData) -> Void

    @State private var shown = 0
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var data: TimetableData { catalog.timetable(for: lg, taking: taking) }
    private let days = ["月", "火", "水", "木", "金"]

    var body: some View {
        let data = data
        let week = data.patterns[0].days
        let periods = data.periods.count
        let order = (0..<(5 * periods)).sorted { a, b in (a % 5 + a / 5, a % 5) < (b % 5 + b / 5, b % 5) }  // 左上から斜めに
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let count = week.joined().filter { !$0.variants.isEmpty }.count

        return VStack(alignment: .leading, spacing: 0) {
            StepHeader(progress: done ? 1 : 0.95, canBack: !done, onBack: onBack)
            VStack(alignment: .leading, spacing: 6) {
                Text(done ? "できました" : "組み立てています…")
                    .font(.system(size: 30, weight: .bold))
                    .contentTransition(.opacity)
                Text(done ? "\(lg.name) · 週\(count)コマ · A/B週とB'週" : " ")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 28)

            // 1週間（A/B週）がマスごとに埋まっていく
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    ForEach(days, id: \.self) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                }
                ForEach(0..<periods, id: \.self) { p in
                    GridRow {
                        ForEach(0..<5, id: \.self) { d in
                            let lesson = week[d].indices.contains(p) ? week[d][p].variants.first : nil
                            let visible = (rank[p * 5 + d] ?? 0) < shown
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(lesson == nil ? Color(.secondarySystemBackground) : Color.primary)
                                .overlay {
                                    if let lesson {
                                        Text(lesson.name)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Color(.systemBackground))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                            .padding(.horizontal, 3)
                                    }
                                }
                                .frame(height: 34)
                                .scaleEffect(visible ? 1 : 0.4)
                                .opacity(visible ? 1 : 0)
                        }
                    }
                }
            }
            .padding(.top, 26)

            Spacer()
            Button {
                onFinish(data)
            } label: {
                Text("時間割を見る").bold().frame(maxWidth: .infinity)
                    .foregroundStyle(Color(.systemBackground))
            }
            .buttonStyle(.glassProminent)
            .tint(.primary)
            .controlSize(.large)
            .opacity(done ? 1 : 0)
            .offset(y: done ? 0 : 20)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
        .task {
            let total = 5 * periods
            let step = reduceMotion ? 0.0 : 0.028
            // 授業のマスが現れる瞬間に合わせて「トトトト」
            let hits = order.enumerated().compactMap { i, cell -> TimeInterval? in
                let d = cell % 5, p = cell / 5
                return week[d].indices.contains(p) && !week[d][p].variants.isEmpty ? Double(i) * step + 0.12 : nil
            }
            if !reduceMotion { Haptics.assemble(hits) }
            for i in 1...total {
                withAnimation(.spring(duration: 0.4, bounce: 0.45)) { shown = i }
                if step > 0 { try? await Task.sleep(for: .seconds(step)) }
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 50 : 260))
            Haptics.success()
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { done = true }
        }
    }
}

// MARK: - 部品

/// 戻るボタンと進み具合
private struct StepHeader: View {
    let progress: Double
    var canBack = true
    var icon = "chevron.left"
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .opacity(canBack ? 1 : 0)
            .disabled(!canBack)
            .accessibilityLabel(icon == "xmark" ? "閉じる" : "戻る")

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(Color.primary)
                        .frame(width: max(8, g.size.width * progress))
                }
            }
            .frame(height: 6)
            .animation(.spring(duration: 0.6, bounce: 0.2), value: progress)
        }
        .padding(.top, 8)
    }
}

/// 背景の小さな時間割。マスが波のように明滅して「ここに時間割ができる」感じを出す
private struct HeroGrid: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<6, id: \.self) { p in
                    GridRow {
                        ForEach(0..<5, id: \.self) { d in
                            let wave = max(0, sin(t * 1.6 - Double(d + p) * 0.55))
                            let today = d == 1 && p == 2
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(today ? Color(.systemRed) : Color.primary)
                                .opacity(today ? 0.9 : 0.07 + 0.55 * wave * wave)
                                .scaleEffect(0.92 + 0.08 * wave)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 押している間だけ、ぷにっと沈む
private struct Squish: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 下からふわっと順番に現れる
private struct Rise: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                withAnimation(.spring(duration: 0.7, bounce: 0.25).delay(0.05 + Double(index) * 0.06)) { shown = true }
            }
    }
}

private extension View {
    func rise(_ index: Int) -> some View { modifier(Rise(index: index)) }
}
