import ExtensionFoundation
import AppIntents

/// Siri・ショートカット専用の拡張機能。アプリ本体を起動せずに、App Groupの時間割を読んで答える
@main
struct JikanwariIntents: AppIntentsExtension {}

/// 動作確認用: Siriから呼ばれた記録をApp Groupの siri.log に残す（Macから devicectl で取り出せる）
func siriLog(_ s: String) {
    let url = AppGroup.container.appending(path: "siri.log")
    let line = Data("\(Date().formatted(.iso8601)) \(s)\n".utf8)
    if let h = try? FileHandle(forWritingTo: url) {
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: line)
        try? h.close()
    } else {
        try? line.write(to: url)
    }
}

/// 英語と日本語の答えを両方渡し、Siriが自分の言語で片方を選ぶ（en.lproj は1つ目、ja.lproj は2つ目を出す）。
/// Siriの言語を直接読む INPreferences.siriLanguageCode() は、この拡張機能に付けられないSiriの権限がないと落ちるので使わない
private func answer(_ intent: String, english: String, japanese: String) -> IntentDialog {
    siriLog("\(intent) → \(japanese) / \(english)")
    return IntentDialog(LocalizedStringResource("answer \(english) \(japanese)"))
}

/// 「Hey Siri、時間割で次の授業」
struct NextClassIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Class"
    static let description = IntentDescription("Tells you your next class, its room and when it starts.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        TimetableStore.shared.reload()
        let now = Date()
        return .result(dialog: answer("next", english: NextClass.answer(at: now, english: true),
                                      japanese: NextClass.answer(at: now, english: false)))
    }
}

/// 「Hey Siri、時間割で今日の授業」
struct TodayClassesIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Classes"
    static let description = IntentDescription("Reads out today's classes.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        TimetableStore.shared.reload()
        let today = Date()
        return .result(dialog: answer("today", english: NextClass.dayAnswer(today, tomorrow: false, english: true),
                                      japanese: NextClass.dayAnswer(today, tomorrow: false, english: false)))
    }
}

/// 「Hey Siri、時間割で明日の授業」
struct TomorrowClassesIntent: AppIntent {
    static let title: LocalizedStringResource = "Tomorrow's Classes"
    static let description = IntentDescription("Reads out tomorrow's classes.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        TimetableStore.shared.reload()
        let tomorrow = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: Date())!
        return .result(dialog: answer("tomorrow", english: NextClass.dayAnswer(tomorrow, tomorrow: true, english: true),
                                      japanese: NextClass.dayAnswer(tomorrow, tomorrow: true, english: false)))
    }
}

/// フレーズは英語。日本語のフレーズは ja.lproj/AppShortcuts.strings（英語1つに日本語1つが対応するので、日本語の言い方を増やすときは英語も増やす）
struct JikanwariShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextClassIntent(), phrases: [
            "Next class in \(.applicationName)",
            "What's my next class in \(.applicationName)",
            "What's my next class on \(.applicationName)",
            "What class do I have next in \(.applicationName)",
            "Ask \(.applicationName) what's next",
            "My next class in \(.applicationName)",
            "Next class on \(.applicationName)",
            "Where is my next class in \(.applicationName)",
            "What's next in \(.applicationName)",
            "Check my next class in \(.applicationName)",
        ], shortTitle: "Next Class", systemImageName: "studentdesk")
        AppShortcut(intent: TodayClassesIntent(), phrases: [
            "Today's classes in \(.applicationName)",
            "What classes do I have today in \(.applicationName)",
            "My classes today in \(.applicationName)",
        ], shortTitle: "Today's Classes", systemImageName: "list.bullet.rectangle")
        AppShortcut(intent: TomorrowClassesIntent(), phrases: [
            "Tomorrow's classes in \(.applicationName)",
            "What classes do I have tomorrow in \(.applicationName)",
            "My classes tomorrow in \(.applicationName)",
        ], shortTitle: "Tomorrow's Classes", systemImageName: "calendar")
    }
}
