import CoreHaptics
import Foundation
import Observation
import SwiftUI

/// 授業ごとのメモ。「その日のその授業」に1つ（宿題・持ち物・小テストなど）
@Observable
final class MemoStore {
    static let shared = MemoStore()

    private(set) var memos: [String: String]

    private init() {
        memos = AppGroup.defaults.dictionary(forKey: "memos") as? [String: String] ?? [:]
    }

    /// "yyyy-MM-dd#時限"（時限は0始まり、まとまった授業は最初のコマ）
    static func key(_ date: Date, period: Int) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d#%d", c.year!, c.month!, c.day!, period)
    }

    func memo(_ key: String) -> String { memos[key] ?? "" }

    func set(_ text: String, for key: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = t.isEmpty ? nil : text
        guard memos[key] != value else { return }  // 変わっていなければ保存も描き直しもしない
        memos[key] = value
        AppGroup.defaults.set(memos, forKey: "memos")
    }
}

struct MemoRef: Identifiable {
    let id: String  // MemoStore.key
    let title: String
    let subtitle: String
}

/// 手触り。どれも「じわっと膨らんでから、コトッと着地する」形で、強さと長さだけ変える
enum Haptics {
    private static var engine: CHHapticEngine?
    private static let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// 箱が広がってメモになる
    static func open() { play(swell: 0.22, peak: 0.75, land: 1.0, sharpness: 0.55) }
    /// メモが箱へ戻る
    static func close() { play(swell: 0.12, peak: 0.4, land: 0.55, sharpness: 0.5) }
    /// 横に払って日をめくる。短く柔らかい「スッ」から軽い「トン」
    static func swipe() { play(swell: 0.09, peak: 0.45, land: 0.7, sharpness: 0.75) }
    /// 日付を押して選ぶ
    static func tick() { play(swell: 0, peak: 0, land: 0.55, sharpness: 0.8) }

    private static func play(swell: TimeInterval, peak: Float, land: Float, sharpness: Float) {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        if swell > 0 {
            events.append(hum(at: 0, duration: swell, intensity: peak, sharpness: 0.15))
            curves.append(CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [.init(relativeTime: 0, value: 0.1), .init(relativeTime: swell * 0.8, value: 1),
                                .init(relativeTime: swell, value: 0.3)],
                relativeTime: 0))
        }
        events.append(tap(at: swell, intensity: land, sharpness: sharpness))
        run(events, curves)
    }

    /// 「コツ」1回
    static func tap(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)],
                      relativeTime: time)
    }

    /// 続く振動（「じわっ」）
    static func hum(at time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)],
                      relativeTime: time, duration: duration)
    }

    static func run(_ events: [CHHapticEvent], _ curves: [CHHapticParameterCurve] = []) {
        guard supported else { return }
        do {
            if engine == nil {
                let e = try CHHapticEngine()
                e.isAutoShutdownEnabled = true
                e.resetHandler = { try? engine?.start() }
                engine = e
            }
            try engine?.start()
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            try engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Haptics failed:", error)
        }
    }
}

struct MemoSheet: View {
    let ref: MemoRef
    let source: Namespace.ID
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var closing = false
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    private var store = MemoStore.shared

    init(ref: MemoRef, source: Namespace.ID) {
        self.ref = ref
        self.source = source
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("宿題・持ち物・小テストなど")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 21)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(ref.title).font(.headline)
                            Text(ref.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !text.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("消去", systemImage: "trash", role: .destructive) { text = "" }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了", systemImage: "checkmark") { closing = true; Haptics.close(); dismiss() }
                    }
                }
        }
        // 下から出すのではなく、押した授業のカードからそのまま広がって開く
        .navigationTransition(.zoom(sourceID: ref.id, in: source))
        .onAppear {
            text = store.memo(ref.id)
            // 広がりきってからキーボードを出す（同時だと動きがもたつく）
            if text.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            }
        }
        .onDisappear {
            if !closing { Haptics.close() }  // 下に払って閉じたとき
            saveTask?.cancel()
            store.set(text, for: ref.id)
        }
        // 1文字ごとに保存すると裏の時間割まで毎回描き直すので、打つ手が止まってから保存する
        .onChange(of: text) { _, t in
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                store.set(t, for: ref.id)
            }
        }
    }
}
