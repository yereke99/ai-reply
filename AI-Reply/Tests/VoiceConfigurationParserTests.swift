import XCTest
@testable import AIReply

/// The dictation examples from the brief, in all three languages.
///
/// These are regression tests for a feature that is allowed to be imperfect but
/// is never allowed to be WRONG: a suggestion the user can decline is fine, a
/// schedule silently set to the wrong hours is not.
final class VoiceConfigurationParserTests: XCTestCase {

    func testEnglishWordHours() {
        let result = VoiceConfigurationParser.parse(
            "I sell clothes. We work from ten to six. If stock is unknown, don't tell the customer that it's available.",
            language: .english
        )
        XCTAssertEqual(result.start?.formatted, "10:00")
        XCTAssertEqual(result.end?.formatted, "18:00")
        XCTAssertEqual(result.rules.count, 1)
    }

    func testRussianWordHoursWithMeridiem() {
        let result = VoiceConfigurationParser.parse(
            "Работаем каждый день с десяти утра до шести вечера.",
            language: .russian
        )
        XCTAssertEqual(result.start?.formatted, "10:00")
        XCTAssertEqual(result.end?.formatted, "18:00")
        XCTAssertEqual(result.weekdays, [1, 2, 3, 4, 5, 6, 7])
    }

    /// The Kazakh case-ending form, which is what a speaker actually says.
    func testKazakhDigitHoursWithCaseEndings() {
        let result = VoiceConfigurationParser.parse(
            "Мен киім сатамын. Жұмыс уақыты 10:00-ден 18:00-ге дейін.",
            language: .kazakh
        )
        XCTAssertEqual(result.start?.formatted, "10:00")
        XCTAssertEqual(result.end?.formatted, "18:00")
    }

    func testRussianExplicitDayRange() {
        let result = VoiceConfigurationParser.parse(
            "Работаем с понедельника по субботу с 10:00 до 18:00",
            language: .russian
        )
        XCTAssertEqual(result.weekdays, [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(result.start?.formatted, "10:00")
    }

    func testKazakhRuleIsExtracted() {
        let result = VoiceConfigurationParser.parse(
            "Тауар бар-жоғын нақты білмесең, бар деп айтпа.",
            language: .kazakh
        )
        XCTAssertEqual(result.rules.count, 1)
        XCTAssertTrue(result.rules[0].contains("айтпа"))
    }

    /// A sentence with no schedule in it must not invent one.
    func testNoFalsePositives() {
        let result = VoiceConfigurationParser.parse(
            "I run a design studio and I like short replies",
            language: .english
        )
        XCTAssertNil(result.start)
        XCTAssertNil(result.end)
        XCTAssertNil(result.weekdays)
        XCTAssertTrue(result.isEmpty)
    }

    func testSuggestionBuildsScheduleOnlyForNamedDays() {
        let parsed = VoiceConfigurationParser.parse(
            "Работаем с понедельника по пятницу с 9:00 до 17:00",
            language: .russian
        )
        let hours = parsed.workingHours(basedOn: .default)
        XCTAssertEqual(hours?.isEnabled, true)
        XCTAssertEqual(hours?.schedule(for: 2)?.isEnabled, true)   // Monday
        XCTAssertEqual(hours?.schedule(for: 7)?.isEnabled, false)  // Saturday
        XCTAssertEqual(hours?.schedule(for: 2)?.start.formatted, "09:00")
        XCTAssertEqual(hours?.schedule(for: 2)?.end.formatted, "17:00")
    }

    /// An impossible range is dropped rather than stored inverted.
    func testInvertedRangeIsRejected() {
        let result = VoiceConfigurationParser.parse("с 18:00 до 18:00", language: .russian)
        XCTAssertNil(result.start)
        XCTAssertNil(result.end)
    }
}
