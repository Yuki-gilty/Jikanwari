import SwiftUI

/// 外部サービスを使わずに時間割を作成・編集する。
struct ManualTimetableView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Timetable.data
    @State private var periodCount = max(1, Timetable.data.periods.isEmpty ? 6 : Timetable.data.periods.count)
    @State private var reviewing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if reviewing {
                    ReviewView(data: $draft, notes: "各コマをタップして授業を入力してください。空きのコマはそのままで構いません。", onSave: save)
                } else {
                    Form {
                        Section("時間割") {
                            TextField("時間割の名前", text: $draft.title)
                            Picker("曜日", selection: $draft.dayCount) {
                                Text("月〜金").tag(5)
                                Text("月〜土").tag(6)
                            }
                            Stepper("1日あたり \(periodCount) コマ", value: $periodCount, in: 1...12)
                        }
                        Section {
                            ForEach(draft.periods.indices, id: \.self) { i in
                                HStack {
                                    Text("\(i + 1)限").frame(width: 44, alignment: .leading)
                                    TextField("開始", text: $draft.periods[i].start)
                                        .accessibilityLabel("\(i + 1)限の開始時刻")
                                    Text("〜").foregroundStyle(.secondary)
                                    TextField("終了", text: $draft.periods[i].end)
                                        .accessibilityLabel("\(i + 1)限の終了時刻")
                                }
                                .keyboardType(.numbersAndPunctuation)
                                .monospacedDigit()
                            }
                        } header: {
                            Text("授業の時刻")
                        } footer: {
                            Text("8:30 の形式で入力してください。時刻は自分の学校に合わせて変更できます。")
                        }
                        if let error { Section { Text(error).foregroundStyle(.red) } }
                        Section {
                            Button("授業を入力する") {
                                normalizeDays()
                                reviewing = true
                            }
                            .disabled(!validTimes)
                        } footer: {
                            if !validTimes {
                                Text("開始より後の終了時刻を入力し、前の授業と重ならないようにしてください。")
                            }
                        }
                    }
                }
            }
            .navigationTitle(reviewing ? "授業を入力" : "時間割を作る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                if reviewing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("時刻・曜日") { reviewing = false }
                    }
                }
            }
        }
        .onAppear { resizePeriods() }
        .onChange(of: periodCount) { _, _ in resizePeriods() }
        .alert("保存できませんでした", isPresented: Binding(get: { error != nil && reviewing }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var validTimes: Bool {
        guard !draft.periods.isEmpty else { return false }
        var previousEnd = -1
        for p in draft.periods {
            guard let start = Timetable.hm(p.start), let end = Timetable.hm(p.end) else { return false }
            let s = start.0 * 60 + start.1, e = end.0 * 60 + end.1
            guard s < e, s >= previousEnd else { return false }
            previousEnd = e
        }
        return true
    }

    private func resizePeriods() {
        draft.periods = Array(draft.periods.prefix(periodCount))
        while draft.periods.count < periodCount {
            let last = draft.periods.last.flatMap { Timetable.hm($0.end) }
            let start = last.map { $0.0 * 60 + $0.1 + 10 } ?? 510
            let end = start + 50
            draft.periods.append(PeriodTime(start: String(format: "%d:%02d", start / 60, start % 60),
                                           end: String(format: "%d:%02d", end / 60, end % 60)))
        }
    }

    private func normalizeDays() {
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.title = "時間割" }
        for p in draft.patterns.indices {
            var days = Array(draft.patterns[p].days.prefix(draft.dayCount))
            while days.count < draft.dayCount { days.append([]) }
            draft.patterns[p].days = days.map {
                Array($0.prefix(periodCount)) + Array(repeating: .free, count: max(0, periodCount - $0.count))
            }
        }
    }

    private func save() {
        // 日本語入力の未確定文字や空白だけの授業は保存しない。
        for p in draft.patterns.indices {
            for d in draft.patterns[p].days.indices {
                for i in draft.patterns[p].days[d].indices {
                    draft.patterns[p].days[d][i].variants.removeAll {
                        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                }
            }
        }
        guard draft.hasLessons else { error = "少なくとも1つの授業を入力してください。"; return }
        // 手動変更した教科名を古いAI翻訳で読み上げない。
        draft.english = nil
        do { try TimetableStore.shared.save(draft); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
