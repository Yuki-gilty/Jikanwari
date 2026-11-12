import SwiftUI

/// 年間予定は添付した資料から追加し、適用前に日ごとの授業変更を確認する。
struct CalendarReviewView: View {
    @Binding var data: TimetableData
    let notes: String
    let onSave: () -> Void

    private var dates: [String] { (data.calendar ?? [:]).keys.sorted() }

    var body: some View {
        List {
            Section {
                Text("読み取り結果を確認してください。同じ日付の予定は上書きし、それ以外の登録済み予定は残します。不要な予定は「この予定を削除」で削除できます。")
                if !notes.isEmpty { Label(notes, systemImage: "exclamationmark.bubble") }
            }
            ForEach(dates, id: \.self) { date in
                Section(date) {
                    TextField("予定の名前", text: field(date, \.note, default: ""))
                    Toggle("授業なし", isOn: field(date, \.off, default: false))
                    if data.calendar?[date]?.off != true {
                        Picker("授業の曜日", selection: field(date, \.weekday, default: nil)) {
                            Text("通常どおり").tag(Int?.none)
                            ForEach(0..<data.dayCount, id: \.self) { day in
                                Text(["月", "火", "水", "木", "金", "土"][day] + "曜日").tag(Optional(day))
                            }
                        }
                        Picker("最終時限", selection: field(date, \.lastPeriod, default: nil)) {
                            Text("通常どおり").tag(Int?.none)
                            ForEach(0..<data.periods.count, id: \.self) { index in
                                Text("\(index + 1)限まで").tag(Optional(index + 1))
                            }
                        }
                    }
                    Button("この予定を削除", role: .destructive) { data.calendar?.removeValue(forKey: date) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("確認して予定を保存", action: onSave)
                .bold().frame(maxWidth: .infinity)
                .buttonStyle(.glassProminent).controlSize(.large)
                .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func field<T>(_ date: String, _ key: WritableKeyPath<SchoolDay, T>, default fallback: T) -> Binding<T> {
        Binding(get: { data.calendar?[date]?[keyPath: key] ?? fallback }, set: { value in
            guard var day = data.calendar?[date] else { return }
            day[keyPath: key] = value
            data.calendar?[date] = day
        })
    }
}

struct CalendarEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Timetable.data
    @State private var error: String?

    var body: some View {
        NavigationStack {
            CalendarReviewView(data: $draft, notes: "", onSave: {
                do { try TimetableStore.shared.save(draft); dismiss() }
                catch { self.error = error.localizedDescription }
            })
            .navigationTitle("年間予定を確認・編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
            .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
