import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// PDF・写真・スキャンした紙の時間割をClaudeに読み取ってもらい、確認してから保存する
struct ImportView: View {
    var calendarOnly = false
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case pick, reading, review }

    @State private var phase = Phase.pick
    @State private var files: [Attachment] = []
    @State private var hint = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var showScanner = false
    @State private var status = ""
    @State private var target = 0.0  // 読み取りの進み具合（届いた値）
    @State private var shown = 0.0   // 画面の％（target へなめらかに追いつく）
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var draft = Timetable.data
    @State private var notes = ""
    @State private var showAIConsent = false
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick: pickForm
                case .reading: readingView
                case .review:
                    if calendarOnly {
                        CalendarReviewView(data: $draft, notes: notes, onSave: save)
                    } else {
                        ReviewView(data: $draft, notes: notes, onSave: save)
                    }
                }
            }
            .navigationTitle(phase == .review ? "読み取り結果" : (calendarOnly ? "年間予定表を読み込む" : "時間割を読み込む"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { task?.cancel(); dismiss() }
                }
                if phase == .review {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("やり直す") { phase = .pick }
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase != .pick)
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .alert("資料を外部AIに送信しますか？", isPresented: $showAIConsent) {
            Button("キャンセル", role: .cancel) {}
            Button("同意して送信") { start() }
        } message: {
            Text("選んだ写真・PDF・テキスト、ファイル名、補足欄の内容を、時間割・年間予定表の読み取りのためCloudflare経由でAnthropic（Claude API）に送信します。氏名・先生名・クラスなどが資料に含まれる場合、それらも送信されます。不要な個人情報は除いてください。送信先での取り扱いはプライバシーポリシーで確認できます。同意しなければ送信しません。")
        }
    }

    // MARK: 選ぶ

    private var pickForm: some View {
        Form {
            Section {
                if VNDocumentCameraViewController.isSupported {
                    Button { showScanner = true } label: { Label("紙をスキャン", systemImage: "doc.viewfinder") }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                    Label("写真から選ぶ", systemImage: "photo.on.rectangle")
                }
                Button { showFiles = true } label: { Label("ファイルから選ぶ", systemImage: "folder") }
            } footer: {
                Text(calendarOnly ? "任意の追加機能です。年間予定表のPDF・写真・テキストを添付してください。読み取り後に日付や休校日を確認できます。" : "PDF・画像（PNG / JPG / HEIC など）・テキストに対応。A週とB週が別のページでもまとめて選べます。")
            }

            if !files.isEmpty {
                Section("読み込むもの") {
                    ForEach(files) { f in
                        HStack(spacing: 12) {
                            Group {
                                if let p = f.preview {
                                    Image(uiImage: p).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 40, height: 40)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(f.name).lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(f.data.count), countStyle: .file))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { files.remove(atOffsets: $0) }
                }
            }

            Section {
                TextField(calendarOnly ? "例: 2026年度、5年生の予定のみ" : "例: 2年3組。理科は化学を選択", text: $hint, axis: .vertical)
            } header: {
                Text("補足（任意）")
            } footer: {
                Text(calendarOnly ? "年度や対象の学年を書いてください。「午前授業」は最終時限を確認画面で指定できます。" : "学年全体の表なら、自分のクラスを書くと正確になります")
            }

            Section {
                Button("プライバシーポリシー") { showPrivacy = true }
            } footer: {
                Text("読み取りには選んだ資料と補足をCloudflare経由でAnthropicに送信します。送信の前に同意を確認します。")
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section {
                Button { showAIConsent = true } label: {
                    Text("AIで読み取る").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(files.isEmpty)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d),
                       let a = Attachment.image(img, name: "写真 \(files.count + 1)") {
                        files.append(a)
                    }
                }
                photoItems = []
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .plainText, .commaSeparatedText, .text],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    do { files.append(try Attachment.file(at: url)) } catch { self.error = error.localizedDescription }
                }
            case .failure(let e):
                error = e.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner(isPresented: $showScanner) { pages in
                for (i, page) in pages.enumerated() {
                    if let a = Attachment.image(page, name: "スキャン \(files.count + i + 1)") { files.append(a) }
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: 読み取り中

    private var readingView: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: max(0.004, shown))
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int((shown * 100).rounded(.down)))")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: shown))
                    Text("%")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 220)
            VStack(spacing: 8) {
                Text(status).font(.headline)
                    .contentTransition(.opacity)
                Text("1〜2分ほどかかります").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // 届いた進み具合へなめらかに追いつく。返事を待っている間（10〜30%）は時間とともに少しずつ進める
            while !Task.isCancelled {
                if target >= 0.1 && target < 0.3 { target = min(0.29, target + (0.3 - target) * 0.006) }
                let next = shown + (target - shown) * 0.12
                let before = Int(shown * 10), after = Int(next * 10)
                withAnimation(.linear(duration: 0.1)) { shown = next }
                if after > before { Haptics.progress(after) }      // 10%ごとに「コツ」
                if target >= 1, shown > 0.995 {
                    withAnimation(.spring(duration: 0.4)) { shown = 1 }
                    Haptics.success()
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func start() {
        error = nil
        status = "送信しています…"
        target = 0
        shown = 0
        phase = .reading
        let files = files, hint = hint
        task = Task {
            do {
                if calendarOnly {
                    let result = try await TimetableReader.readCalendar(files, hint: hint) { text, p in
                        status = text
                        target = max(target, p)
                    }
                    draft = Timetable.data
                    let incoming = try result.validated(periodCount: draft.periods.count)
                    draft.calendar = (draft.calendar ?? [:]).merging(incoming) { _, new in new }
                    notes = result.notes
                } else {
                    let result = try await TimetableReader.read(files, hint: hint) { text, p in
                        status = text
                        target = max(target, p)
                    }
                    draft = TimetableReader.finish(result.timetable, current: Timetable.data)
                    draft.calendar = Timetable.data.calendar
                    draft.english = result.englishNames
                    notes = result.notes
                }
                target = 1
                try? await Task.sleep(for: .milliseconds(700))  // 100% と「できた」の手触りを見せてから
                phase = .review
            } catch {
                if Task.isCancelled { return }
                self.error = error.localizedDescription
                phase = .pick
            }
        }
    }

    private func save() {
        do {
            try TimetableStore.shared.save(draft)
            dismiss()
        } catch {
            self.error = "保存できませんでした: \(error.localizedDescription)"
            phase = .pick
        }
    }
}

// MARK: - 読み取り結果の確認・修正

private struct SlotRef: Identifiable {
    let pattern: Int, day: Int, period: Int
    var id: String { "\(pattern)-\(day)-\(period)" }
}

private let weekdayNames = ["月", "火", "水", "木", "金", "土"]

struct ReviewView: View {
    @Binding var data: TimetableData
    let notes: String
    let onSave: () -> Void

    @State private var patternIndex = 0
    @State private var editing: SlotRef?

    var body: some View {
        List {
            if !notes.isEmpty {
                Section {
                    Label(notes, systemImage: "exclamationmark.bubble").font(.subheadline)
                }
            }

            if data.patterns.count > 1 {
                Section {
                    Picker("週", selection: $patternIndex) {
                        ForEach(data.patterns.indices, id: \.self) { Text(data.patterns[$0].name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if patternIndex > 0 {
                        TextField("2026-11-09, 2026-12-07", text: weekStartsBinding)
                            .keyboardType(.numbersAndPunctuation)
                    }
                } footer: {
                    if patternIndex > 0 {
                        Text("「\(data.patterns[patternIndex].name)」になる週の月曜日。空ならこの週は使われません")
                    }
                }
            }

            let p = min(patternIndex, data.patterns.count - 1)
            ForEach(0..<data.dayCount, id: \.self) { d in
                Section(weekdayNames[d] + "曜日") {
                    ForEach(data.patterns[p].days[d].indices, id: \.self) { i in
                        Button { editing = SlotRef(pattern: p, day: d, period: i) } label: {
                            row(data.patterns[p].days[d][i], period: i)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onSave) {
                Text("この時間割を保存").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!data.hasLessons)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .sheet(item: $editing) { ref in
            SlotEditor(slot: $data.patterns[ref.pattern].days[ref.day][ref.period],
                       title: "\(weekdayNames[ref.day])曜 \(ref.period + 1)限")
        }
    }

    private func row(_ slot: Slot, period i: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text("\(i + 1)").font(.subheadline.weight(.bold).monospacedDigit())
                if i < data.periods.count {
                    Text(data.periods[i].start).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                if slot.variants.isEmpty {
                    Text("空き").foregroundStyle(.tertiary)
                } else if slot.group.isEmpty, let v = slot.variants.first {
                    Text(v.name).font(.headline)
                    detail(v)
                } else {
                    Text(slot.group).font(.headline)
                    ForEach(slot.variants, id: \.self) { v in
                        HStack(spacing: 6) {
                            Text(v.key).font(.caption.weight(.bold)).foregroundStyle(.blue)
                            detail(v, showName: v.name != slot.group)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func detail(_ v: Variant, showName: Bool = false) -> some View {
        let parts = (showName ? [v.name] : []) + [v.room, v.teacher].filter { !$0.isEmpty }
        return Text(parts.joined(separator: "  ·  ")).font(.subheadline).foregroundStyle(.secondary)
    }

    private var weekStartsBinding: Binding<String> {
        Binding(
            get: { data.patterns[patternIndex].weekStarts.joined(separator: ", ") },
            set: { text in
                data.patterns[patternIndex].weekStarts = text
                    .split(whereSeparator: { ", 、\n".contains($0) })
                    .map(String.init)
            })
    }
}

private struct SlotEditor: View {
    @Binding var slot: Slot
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if !slot.group.isEmpty {
                    Section("選択授業の名前") { TextField("例: 英語クラス", text: $slot.group) }
                }
                ForEach(slot.variants.indices, id: \.self) { i in
                    Section(slot.group.isEmpty ? "授業" : "クラス \(slot.variants[i].key)") {
                        if !slot.group.isEmpty { TextField("クラス", text: $slot.variants[i].key) }
                        TextField("科目", text: $slot.variants[i].name)
                        TextField("教室", text: $slot.variants[i].room)
                        TextField("先生", text: $slot.variants[i].teacher)
                    }
                }
                Section {
                    if slot.variants.isEmpty {
                        Button("授業を入れる") { slot.variants = [Variant(key: "", name: "", teacher: "", room: "")] }
                    } else {
                        Button("空きにする", role: .destructive) { slot = .free }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完了") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 書類スキャナー

private struct DocumentScanner: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onScan: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan((0..<scan.pageCount).map(scan.imageOfPage))
            parent.isPresented = false
        }

        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) {
            parent.isPresented = false
        }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.isPresented = false
        }
    }
}
