import Foundation

/// Siriに「次の授業は？」と聞かれたときの答え
enum NextClass {
    struct Found {
        let period: Int  // 1始まり
        let lesson: Lesson
        let start: Date
        let dayOffset: Int  // 0=今日, 1=明日…
    }

    private static let cal = Calendar(identifier: .gregorian)

    /// now より後に始まる最初の授業。同じ授業・同じ教室が続くコマは1つの授業として扱う（2コマ続きの2コマ目は「次」にしない）
    static func find(after now: Date, settings: Settings = .current) -> Found? {
        let today = cal.startOfDay(for: now)
        let termEnd = Timetable.termEnd
        for offset in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today), day <= termEnd else { return nil }
            let lessons = Timetable.lessons(for: day, settings: settings)
            for (i, lesson) in lessons.enumerated() {
                guard let lesson else { continue }
                if i > 0, let prev = lessons[i - 1], prev.name == lesson.name, prev.room == lesson.room,
                   !Timetable.isLongBreak(before: i) { continue }
                let p = Timetable.periods[i]
                guard let start = cal.date(bySettingHour: p.start.0, minute: p.start.1, second: 0, of: day),
                      start > now else { continue }
                return Found(period: i + 1, lesson: lesson, start: start, dayOffset: offset)
            }
        }
        return nil
    }

    static func answer(at now: Date, english: Bool) -> String {
        guard TimetableStore.shared.hasTimetable else {
            return english ? "Open the app to add your timetable first." : "アプリを開いて時間割を登録してください。"
        }
        let found = find(after: now)
        return english ? englishAnswer(found, now) : japaneseAnswer(found, now)
    }

    // MARK: 今日・明日の授業

    /// その日の授業を順に読み上げる（2コマ続きは「3・4限」とまとめる）
    static func dayAnswer(_ date: Date, tomorrow: Bool, english: Bool) -> String {
        guard TimetableStore.shared.hasTimetable else {
            return english ? "Open the app to add your timetable first." : "アプリを開いて時間割を登録してください。"
        }
        let day = cal.startOfDay(for: date)
        let lessons = Timetable.lessons(for: day)
        var blocks: [(first: Int, last: Int, lesson: Lesson)] = []
        for (i, l) in lessons.enumerated() {
            guard let l else { continue }
            if let b = blocks.last, b.last == i - 1, b.lesson.name == l.name, b.lesson.room == l.room,
               !Timetable.isLongBreak(before: i) {
                blocks[blocks.count - 1].last = i
            } else {
                blocks.append((i, i, l))
            }
        }
        let count = lessons.compactMap { $0 }.count
        let names = Timetable.data.english ?? [:]

        guard let last = blocks.last else {
            if english { return tomorrow ? "You have no classes tomorrow." : "You have no classes today." }
            return tomorrow ? "明日は授業はありません。" : "今日は授業はありません。"
        }
        let e = Timetable.periods[last.last].end
        let end = cal.date(bySettingHour: e.0, minute: e.1, second: 0, of: day)!

        if english {
            let list = blocks.map { b in
                let p = b.first == b.last ? "period \(b.first + 1)" : "periods \(b.first + 1) and \(b.last + 1)"
                return "\(p), \(Spoken.english(b.lesson.name, names))"
            }
            let classes = count == 1 ? "1 class" : "\(count) classes"
            return "You have \(classes) \(tomorrow ? "tomorrow" : "today"): \(list.joined(separator: "; ")). "
                + "You finish at \(format(end, e.1 == 0 ? "h a" : "h:mm a", "en_US"))."
        }
        let list = blocks.map { b in
            (b.first == b.last ? "\(b.first + 1)限" : "\(b.first + 1)・\(b.last + 1)限") + " \(b.lesson.name)"
        }
        return "\(tomorrow ? "明日" : "今日")は\(count)コマです。\(list.joined(separator: "、"))。"
            + "\(format(end, e.1 == 0 ? "H時" : "H時m分", "ja_JP"))までです。"
    }

    // MARK: 日本語

    private static func japaneseAnswer(_ f: Found?, _ now: Date) -> String {
        guard let f else { return "しばらく授業はありません。" }
        let day: String
        switch f.dayOffset {
        case 0: day = ""
        case 1: day = "明日、"
        case 2..<7: day = format(f.start, "EEEE", "ja_JP") + "、"
        default: day = format(f.start, "M月d日（E）", "ja_JP") + "、"
        }
        let m = cal.component(.minute, from: f.start)
        let time = format(f.start, m == 0 ? "H時" : "H時m分", "ja_JP")
        var s = "次は\(day)\(f.period)限の\(f.lesson.name)。\(time)から"
        s += f.lesson.room.isEmpty ? "です。" : "\(f.lesson.room)です。"
        if f.dayOffset == 0 {
            let (h, min) = untilStart(f, now)
            s += "あと" + (h == 0 ? "\(min)分" : min == 0 ? "\(h)時間" : "\(h)時間\(min)分") + "です。"
        }
        return s
    }

    // MARK: 英語（Siriが英語のとき。英語の声で読めるように教科名や教室も英語にする）

    private static func englishAnswer(_ f: Found?, _ now: Date) -> String {
        guard let f else { return "You have no classes coming up." }
        let names = Timetable.data.english ?? [:]
        let day: String
        switch f.dayOffset {
        case 0: day = ""
        case 1: day = "tomorrow: "
        case 2..<7: day = "on " + format(f.start, "EEEE", "en_US") + ": "
        default: day = "on " + format(f.start, "EEEE, MMMM d", "en_US") + ": "
        }
        let m = cal.component(.minute, from: f.start)
        let time = format(f.start, m == 0 ? "h a" : "h:mm a", "en_US")
        var s = "Your next class is \(day)\(Spoken.english(f.lesson.name, names)), period \(f.period), at \(time)"
        if !f.lesson.room.isEmpty { s += " in " + Spoken.englishRoom(f.lesson.room, names) }
        s += "."
        if f.dayOffset == 0 {
            let (h, min) = untilStart(f, now)
            let hours = h == 1 ? "1 hour" : "\(h) hours", mins = min == 1 ? "1 minute" : "\(min) minutes"
            s += " It starts in " + (h == 0 ? mins : min == 0 ? hours : "\(hours) and \(mins)") + "."
        }
        return s
    }

    private static func untilStart(_ f: Found, _ now: Date) -> (hours: Int, minutes: Int) {
        let total = max(1, Int(ceil(f.start.timeIntervalSince(now) / 60)))
        return (total / 60, total % 60)
    }

    private static func format(_ d: Date, _ f: String, _ locale: String) -> String {
        let df = DateFormatter()
        df.calendar = cal
        df.locale = Locale(identifier: locale)
        df.dateFormat = f
        return df.string(from: d)
    }
}

/// 時間割の日本語（教科名・教室）を英語のSiriが読める形にする。
/// 読み込んだ時間割は Claude が付けた英語名（TimetableData.english）を使い、なければ辞書で組み立て、辞書にない漢字はローマ字読みにする
enum Spoken {
    static func english(_ text: String, _ names: [String: String]) -> String {
        if let en = names[text.trimmingCharacters(in: .whitespaces)], !en.isEmpty { return en }
        // 全角の英数字（ＰＣ室、３０１）を半角に。かなやⅡはそのまま
        let t = String(String.UnicodeScalarView(text.trimmingCharacters(in: .whitespaces).unicodeScalars.map {
            (0xFF01...0xFF5E).contains($0.value) ? Unicode.Scalar($0.value - 0xFEE0)! : $0
        }))
        if let en = exact[t] { return en }
        if t.allSatisfy(\.isASCII) { return t }

        var words: [String] = []
        var ascii = "", unknown = ""
        func flush() {
            if !ascii.isEmpty { words.append(ascii); ascii = "" }
            if !unknown.isEmpty { words.append(romaji(unknown)); unknown = "" }
        }
        var rest = Substring(t)
        while let c = rest.first {
            if let key = dictionaryKeys.first(where: { rest.hasPrefix($0) }) {
                flush()
                if let en = dictionary[key], !en.isEmpty { words.append(en) }
                rest = rest.dropFirst(key.count)
                continue
            }
            rest = rest.dropFirst()
            if let n = romanNumerals[c] {
                flush(); words.append(n)
            } else if let g = greek[c] {
                flush(); words.append(g)
            } else if "・／/（）()「」 　,、".contains(c) {
                flush()
            } else if c.isASCII {
                if !unknown.isEmpty { flush() }
                ascii.append(c)
            } else {
                if !ascii.isEmpty { flush() }
                unknown.append(c)
            }
        }
        flush()
        return words.joined(separator: " ")
    }

    /// 「in ○○」に続く形。番号だけの教室は "room 310"、それ以外は "the Physics Room"
    static func englishRoom(_ room: String, _ names: [String: String]) -> String {
        let en = english(room, names)
        if en.hasPrefix("your ") || en.lowercased().hasPrefix("room ") { return en }
        if en.allSatisfy({ $0.isNumber || $0 == "-" || ($0.isASCII && $0.isUppercase) }) { return "room \(en)" }
        return "the \(en)"
    }

    /// 漢字・かなを日本語の読みでローマ字にする（「宮川」→ "Miyakawa"）
    private static func romaji(_ s: String) -> String {
        let cf = s as CFString
        let tokenizer = CFStringTokenizerCreate(nil, cf, CFRange(location: 0, length: CFStringGetLength(cf)),
                                                kCFStringTokenizerUnitWord, Locale(identifier: "ja_JP") as CFLocale)
        var out: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                out.append(latin.prefix(1).uppercased() + latin.dropFirst())
            }
        }
        return out.isEmpty ? s : out.joined(separator: " ")
    }

    private static let romanNumerals: [Character: String] = [
        "Ⅰ": "1", "Ⅱ": "2", "Ⅲ": "3", "Ⅳ": "4", "Ⅴ": "5", "Ⅵ": "6", "Ⅶ": "7", "Ⅷ": "8", "Ⅸ": "9", "Ⅹ": "10",
        "ⅰ": "1", "ⅱ": "2", "ⅲ": "3", "ⅳ": "4", "ⅴ": "5",
    ]
    private static let greek: [Character: String] = ["α": "alpha", "β": "beta", "γ": "gamma", "δ": "delta"]

    /// 名前全体がこれのときだけ（"HR" が "CHR" の途中に当たらないように）
    private static let exact: [String: String] = [
        "LH": "Homeroom", "LHR": "Homeroom", "HR": "Homeroom", "SHR": "Homeroom",
    ]

    /// 長い語から先に当てる（「物理室」を「物理」+「室」にしない）
    private static let dictionaryKeys = dictionary.keys.sorted { $0.count > $1.count }

    private static let dictionary: [String: String] = [
        // 国語
        "現代の国語": "Modern Japanese", "現代文": "Modern Japanese", "言語文化": "Language and Culture",
        "論理国語": "Logical Japanese", "文学国語": "Literary Japanese", "国語表現": "Japanese Expression",
        "古典探究": "Classics", "古典": "Classics", "古文": "Classical Japanese", "漢文": "Classical Chinese", "国語": "Japanese",
        // 英語
        "英語コミュニケーション": "English Communication", "英コミ": "English Communication", "コミュ英": "English Communication",
        "論理・表現": "Logic and Expression", "論理表現": "Logic and Expression", "論表": "Logic and Expression",
        "英語表現": "English Expression", "英表": "English Expression", "英会話": "English Conversation", "英語": "English",
        // 数学・理科
        "数学": "Math", "算数": "Math",
        "物理基礎": "Basic Physics", "化学基礎": "Basic Chemistry", "生物基礎": "Basic Biology", "地学基礎": "Basic Earth Science",
        "物理": "Physics", "化学": "Chemistry", "生物": "Biology", "地学": "Earth Science", "理科": "Science",
        // 地歴・公民
        "公共": "Civics", "政治・経済": "Politics and Economics", "政経": "Politics and Economics", "倫理": "Ethics",
        "現代社会": "Contemporary Society", "歴史総合": "History", "日本史探究": "Japanese History", "日本史": "Japanese History",
        "世界史探究": "World History", "世界史": "World History", "地理総合": "Geography", "地理探究": "Geography",
        "地理": "Geography", "社会": "Social Studies",
        // 実技など
        "保健体育": "Health and P.E.", "体育": "P.E.", "保健": "Health", "美術": "Art", "音楽": "Music", "書道": "Calligraphy",
        "工芸": "Crafts", "芸術": "Arts", "情報": "Information Technology", "技術・家庭": "Technology and Home Economics",
        "家庭基礎": "Home Economics", "家庭総合": "Home Economics", "家庭科": "Home Economics", "家庭": "Home Economics",
        "技術": "Technology",
        // 探究・学活
        "総合的な探究の時間": "Integrated Studies", "総合的な学習の時間": "Integrated Studies", "総合探究": "Integrated Studies",
        "総探": "Integrated Studies", "総合": "Integrated Studies", "探究ラボ": "Inquiry Lab", "探究": "Inquiry",
        "卒業研究": "Graduation Research", "卒探": "Graduation Research", "課題研究": "Research Project",
        "ロングホームルーム": "Homeroom", "ホームルーム": "Homeroom", "学活": "Class Activities", "学級活動": "Class Activities",
        "道徳": "Moral Education", "基礎": "Basics", "演習": "Practice", "発展": "Advanced", "選択": "Elective",
        // 教室
        "HR教室": "your homeroom", "ホームルーム教室": "your homeroom", "教室": "Classroom",
        "物理実験室": "Physics Lab", "化学実験室": "Chemistry Lab", "生物実験室": "Biology Lab",
        "物理室": "Physics Room", "化学室": "Chemistry Room", "生物室": "Biology Room", "地学室": "Earth Science Room",
        "理科室": "Science Room", "実験室": "Lab", "美術室": "Art Room", "音楽室": "Music Room", "書道室": "Calligraphy Room",
        "技術室": "Technology Room", "家庭科室": "Home Economics Room", "調理室": "Cooking Room", "被服室": "Sewing Room",
        "講義室": "Lecture Room", "多目的室": "Multipurpose Room", "多目的ホール": "Multipurpose Hall", "視聴覚室": "AV Room",
        "図書室": "Library", "図書館": "Library", "体育館": "Gym", "武道場": "Martial Arts Hall", "グラウンド": "Field",
        "校庭": "Field", "プール": "Pool", "講堂": "Auditorium", "ホール": "Hall", "ラウンジ": "Lounge", "ラボ": "Lab",
        "会議室": "Meeting Room", "PC室": "Computer Room", "パソコン室": "Computer Room", "コンピュータ室": "Computer Room",
        "情報室": "Computer Room", "演習室": "Seminar Room", "ゼミ室": "Seminar Room", "号館": "Building", "棟": "Building",
        "階": "Floor", "室": "Room", "第": "", "号室": "",
    ]
}
