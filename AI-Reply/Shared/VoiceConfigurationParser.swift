import Foundation

/// Turns a dictated sentence into template settings.
///
/// WHAT THIS IS FOR. The brief's example is a user saying "I sell clothes, we
/// work from ten to six, don't tell a customer something is in stock unless we
/// know". Saving that as one blob of text works, but it means the app cannot
/// reason about the schedule, and the model has to re-derive "is it after
/// hours" on every single reply. Extracting the schedule here makes the
/// working-hours context deterministic, which is exactly what the brief asks
/// for.
///
/// WHAT IT DELIBERATELY IS NOT. It is not an understanding of the sentence, and
/// it never silently replaces what the user said. Everything it finds is
/// returned as a SUGGESTION the user confirms on screen, and the raw transcript
/// is always kept as the template's own instructions. When it recognises
/// nothing, the flow is exactly what it was before: free text the model reads.
///
/// It runs locally with no network call, so dictating a profile costs nothing
/// and works offline.
struct VoiceConfigurationParser {

    struct Suggestion: Equatable {
        var start: TimeOfDay?
        var end: TimeOfDay?
        /// `Calendar` weekdays (Sunday == 1), or nil when the sentence did not
        /// mention days at all.
        var weekdays: [Int]?
        /// Sentences that read like a policy the reply must respect.
        var rules: [String]

        var hasWorkingHours: Bool { start != nil && end != nil }
        var isEmpty: Bool { !hasWorkingHours && weekdays == nil && rules.isEmpty }

        /// The schedule these suggestions describe, applied on top of whatever
        /// the user already had so an unmentioned day keeps its own hours.
        func workingHours(basedOn existing: WorkingHours) -> WorkingHours? {
            guard let start, let end, start < end else { return nil }
            let days = weekdays ?? existing.days.filter(\.isEnabled).map(\.weekday)
            let active = Set(days.isEmpty ? [2, 3, 4, 5, 6] : days)

            return WorkingHours(
                isEnabled: true,
                days: (1...7).map { weekday in
                    DaySchedule(
                        weekday: weekday,
                        isEnabled: active.contains(weekday),
                        start: start,
                        end: end
                    )
                }
            )
        }
    }

    // MARK: Entry point

    static func parse(_ transcript: String, language: AppLanguage) -> Suggestion {
        let text = transcript.lowercased()
        let times = timeCandidates(in: text)
        let (start, end) = resolveRange(times)

        return Suggestion(
            start: start,
            end: end,
            weekdays: weekdays(in: text),
            rules: rules(in: transcript, language: language)
        )
    }

    // MARK: Times

    private struct TimeCandidate {
        let position: Int
        let hour: Int
        let minute: Int
        /// "утра" / "pm" / "кешкі" and friends, when the speaker said one.
        let meridiem: Meridiem?
    }

    private enum Meridiem { case morning, afternoon }

    /// Hour words, so "from ten to six" and "с десяти до шести" work as well as
    /// "10:00-18:00". Only 1-12 - nobody dictates "from seventeen hundred".
    private static let hourWords: [String: Int] = [
        // English
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        // Russian, in the forms speech recognition actually returns after "с"/"до"
        "час": 1, "часа": 1, "одного": 1, "двух": 2, "трёх": 3, "трех": 3, "четырёх": 4,
        "четырех": 4, "пяти": 5, "шести": 6, "семи": 7, "восьми": 8, "девяти": 9,
        "десяти": 10, "одиннадцати": 11, "двенадцати": 12,
        // Kazakh
        "бір": 1, "екі": 2, "үш": 3, "төрт": 4, "бес": 5, "алты": 6,
        "жеті": 7, "сегіз": 8, "тоғыз": 9, "он": 10, "он бір": 11, "он екі": 12
    ]

    private static let morningMarkers = ["утра", "am", "a.m.", "morning", "таңғы", "таңертең"]
    private static let afternoonMarkers = ["вечера", "дня", "pm", "p.m.", "evening", "afternoon", "кешкі", "түстен кейін"]

    private static func timeCandidates(in text: String) -> [TimeCandidate] {
        var found: [TimeCandidate] = []

        // Digits first: "18:00", "18.00", "18". The trailing boundary keeps
        // "300" out and stops "10" inside "2010" from matching.
        let pattern = #"(?<![\d:.])([01]?\d|2[0-3])(?:[:.]([0-5]\d))?(?![\d])"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let hourRange = Range(match.range(at: 1), in: text),
                      let hour = Int(text[hourRange]) else { continue }
                var minute = 0
                if match.range(at: 2).location != NSNotFound,
                   let minuteRange = Range(match.range(at: 2), in: text) {
                    minute = Int(text[minuteRange]) ?? 0
                }
                let position = text.distance(from: text.startIndex, to: hourRange.lowerBound)
                found.append(
                    TimeCandidate(
                        position: position,
                        hour: hour,
                        minute: minute,
                        meridiem: meridiem(in: text, near: hourRange.upperBound)
                    )
                )
            }
        }

        // Then hour words, but only when no digits were dictated at all.
        // Mixing the two ("from 10 to six") is rare enough that preferring the
        // unambiguous source is the safer rule.
        if found.isEmpty {
            for (word, hour) in hourWords {
                var searchStart = text.startIndex
                while let wordRange = text.range(
                    of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                    options: .regularExpression,
                    range: searchStart..<text.endIndex
                ) {
                    found.append(
                        TimeCandidate(
                            position: text.distance(from: text.startIndex, to: wordRange.lowerBound),
                            hour: hour,
                            minute: 0,
                            meridiem: meridiem(in: text, near: wordRange.upperBound)
                        )
                    )
                    searchStart = wordRange.upperBound
                }
            }
        }

        return found.sorted { $0.position < $1.position }
    }

    /// Looks a short distance past the number for "утра" / "pm" / "кешкі".
    private static func meridiem(in text: String, near index: String.Index) -> Meridiem? {
        let end = text.index(index, offsetBy: 24, limitedBy: text.endIndex) ?? text.endIndex
        let window = String(text[index..<end])
        if morningMarkers.contains(where: window.contains) { return .morning }
        if afternoonMarkers.contains(where: window.contains) { return .afternoon }
        return nil
    }

    /// The first two candidates are the range. A closing hour that lands before
    /// the opening one is read as the afternoon, which is what "from ten to
    /// six" means to everyone who says it.
    private static func resolveRange(_ candidates: [TimeCandidate]) -> (TimeOfDay?, TimeOfDay?) {
        guard candidates.count >= 2 else { return (nil, nil) }

        var startHour = candidates[0].hour
        var endHour = candidates[1].hour

        if candidates[0].meridiem == .afternoon, startHour < 12 { startHour += 12 }
        if candidates[1].meridiem == .afternoon, endHour < 12 { endHour += 12 }
        if candidates[1].meridiem == nil, endHour <= startHour, endHour + 12 <= 23 { endHour += 12 }

        let start = TimeOfDay(hour: startHour, minute: candidates[0].minute)
        let end = TimeOfDay(hour: endHour, minute: candidates[1].minute)
        guard start < end else { return (nil, nil) }
        return (start, end)
    }

    // MARK: Days

    private static let everydayMarkers = [
        "каждый день", "ежедневно", "без выходных", "все дни",
        "күн сайын", "әр күні", "демалыссыз",
        "every day", "everyday", "daily", "seven days", "all week"
    ]

    private static let weekdayMarkers = [
        "по будням", "будни", "будние", "с понедельника по пятницу",
        "жұмыс күндері", "дүйсенбіден жұмаға",
        "weekdays", "monday to friday", "monday through friday", "mon-fri"
    ]

    private static let saturdayMarkers = [
        "по субботам", "с понедельника по субботу", "включая субботу",
        "сенбіні қоса", "дүйсенбіден сенбіге",
        "monday to saturday", "including saturday", "mon-sat"
    ]

    private static func weekdays(in text: String) -> [Int]? {
        if everydayMarkers.contains(where: text.contains) { return [1, 2, 3, 4, 5, 6, 7] }
        if saturdayMarkers.contains(where: text.contains) { return [2, 3, 4, 5, 6, 7] }
        if weekdayMarkers.contains(where: text.contains) { return [2, 3, 4, 5, 6] }
        return nil
    }

    // MARK: Rules

    /// Markers that make a sentence read like a policy rather than a
    /// description. Conservative on purpose: a missed rule is a line the user
    /// keeps in their own words, while a false one is a line they have to
    /// delete.
    private static func ruleMarkers(_ language: AppLanguage) -> [String] {
        let shared = ["если ", "егер ", " if ", "never", "always"]
        switch language {
        case .russian:
            return shared + [
                "не говори", "не обещай", "не пиши", "нельзя", "не указывай",
                "не подтверждай", "всегда", "никогда", "обязательно", "скажи"
            ]
        case .kazakh:
            return shared + [
                "айтпа", "уәде бер", "жазба", "болмайды", "әрқашан",
                "ешқашан", "міндетті", "деп айт", "растама"
            ]
        case .english:
            return shared + [
                "don't", "do not", "never", "always", "avoid", "make sure",
                "tell them", "must not", "should not"
            ]
        }
    }

    private static func rules(in transcript: String, language: AppLanguage) -> [String] {
        let markers = ruleMarkers(language)
        var result: [String] = []

        for sentence in sentences(in: transcript) {
            let lowered = sentence.lowercased()
            guard markers.contains(where: lowered.contains) else { continue }
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 8 else { continue }
            result.append(String(trimmed.prefix(BusinessContext.maximumRuleCharacters)))
            if result.count == BusinessContext.maximumRules { break }
        }
        return result
    }

    /// Sentence split that tolerates dictation, which often produces no
    /// punctuation at all - in which case the whole transcript is one sentence
    /// and is offered as a single rule.
    private static func sentences(in text: String) -> [String] {
        text.split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
