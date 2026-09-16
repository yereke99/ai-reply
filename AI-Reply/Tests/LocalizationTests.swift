import XCTest
@testable import AIReply

/// Localization is a product requirement here, not a nicety: the bug this
/// iteration set out to fix was a Kazakh app showing an English keyboard row.
/// These tests fail if that can happen again.
final class LocalizationTests: XCTestCase {

    // MARK: Keyboard vocabulary

    /// The exact words the brief specifies, per language. If a translation is
    /// dropped or a fallback creeps in, this is where it is caught.
    func testKeyboardVocabularyMatchesTheBrief() {
        let english = AIReplyStrings.forLanguage(.english)
        XCTAssertEqual(english.insert, "Insert")
        XCTAssertEqual(english.regenerate, "Regenerate")
        XCTAssertEqual(english.cancel, "Cancel")
        XCTAssertEqual(english.replaceExisting, "Replace")
        XCTAssertEqual(english.appendToExisting, "Add")
        XCTAssertEqual(english.generating, "Generating…")
        XCTAssertEqual(english.noSourceMessage, "Copy a message first")

        let russian = AIReplyStrings.forLanguage(.russian)
        XCTAssertEqual(russian.insert, "Вставить")
        XCTAssertEqual(russian.regenerate, "Сгенерировать заново")
        XCTAssertEqual(russian.cancel, "Отмена")
        XCTAssertEqual(russian.replaceExisting, "Заменить")
        XCTAssertEqual(russian.appendToExisting, "Добавить")
        XCTAssertEqual(russian.generating, "Создаю ответ…")
        XCTAssertEqual(russian.noSourceMessage, "Сначала скопируйте сообщение")

        let kazakh = AIReplyStrings.forLanguage(.kazakh)
        XCTAssertEqual(kazakh.insert, "Кірістіру")
        XCTAssertEqual(kazakh.regenerate, "Қайта жасау")
        XCTAssertEqual(kazakh.cancel, "Бас тарту")
        XCTAssertEqual(kazakh.replaceExisting, "Ауыстыру")
        XCTAssertEqual(kazakh.appendToExisting, "Қосу")
        XCTAssertEqual(kazakh.generating, "Жауап дайындалуда…")
        XCTAssertEqual(kazakh.noSourceMessage, "Алдымен хабарламаны көшіріңіз")

        // Every language answers the "+" chip in its own words.
        for language in AppLanguage.allCases {
            XCTAssertFalse(AIReplyStrings.forLanguage(language).addTemplateHint.isEmpty)
        }
        XCTAssertNotEqual(russian.addTemplateHint, english.addTemplateHint)
        XCTAssertNotEqual(kazakh.addTemplateHint, english.addTemplateHint)
    }

    func testTemplateNamesMatchTheBrief() {
        XCTAssertEqual(ReplyTemplate.builtIn(.friend, sortIndex: 0).displayName(appLanguage: .kazakh), "Дос")
        XCTAssertEqual(ReplyTemplate.builtIn(.client, sortIndex: 0).displayName(appLanguage: .kazakh), "Клиент")
        XCTAssertEqual(ReplyTemplate.builtIn(.business, sortIndex: 0).displayName(appLanguage: .kazakh), "Бизнес")
        XCTAssertEqual(ReplyTemplate.builtIn(.work, sortIndex: 0).displayName(appLanguage: .kazakh), "Жұмыс")
        XCTAssertEqual(ReplyTemplate.builtInName(.custom, language: .kazakh), "Басқа")

        XCTAssertEqual(ReplyTemplate.builtIn(.friend, sortIndex: 0).displayName(appLanguage: .russian), "Друг")
        XCTAssertEqual(ReplyTemplate.builtIn(.work, sortIndex: 0).displayName(appLanguage: .russian), "Работа")
        XCTAssertEqual(ReplyTemplate.builtInName(.custom, language: .russian), "Свой")

        XCTAssertEqual(ReplyTemplate.builtIn(.friend, sortIndex: 0).displayName(appLanguage: .english), "Friend")
    }

    /// No product string may be identical across all three languages unless it
    /// genuinely is a loan word. This is the test that would have failed when
    /// the keyboard was showing English labels in a Kazakh app.
    func testNoEnglishFallbackLeaksIntoOtherLanguages() {
        let english = AIReplyStrings.forLanguage(.english)
        let russian = AIReplyStrings.forLanguage(.russian)
        let kazakh = AIReplyStrings.forLanguage(.kazakh)

        for (label, en, ru, kk) in [
            ("insert", english.insert, russian.insert, kazakh.insert),
            ("regenerate", english.regenerate, russian.regenerate, kazakh.regenerate),
            ("generating", english.generating, russian.generating, kazakh.generating),
            ("cancel", english.cancel, russian.cancel, kazakh.cancel),
            ("noSourceMessage", english.noSourceMessage, russian.noSourceMessage, kazakh.noSourceMessage)
        ] {
            XCTAssertNotEqual(en, ru, "\(label) is untranslated in Russian")
            XCTAssertNotEqual(en, kk, "\(label) is untranslated in Kazakh")
        }
    }

    // MARK: Language resolution

    func testAppLanguageMapsToTheRightLayoutVocabulary() {
        XCTAssertEqual(AppLanguage.kazakh.keyboardLanguage, .kazakh)
        XCTAssertEqual(AppLanguage.russian.keyboardLanguage, .russian)
        XCTAssertEqual(AppLanguage.english.keyboardLanguage, .english)
    }

    /// A user with a Kazakh app typing on the Russian layout must still see
    /// Kazakh product labels.
    ///
    /// The type system is what enforces this now: `AIReplyStrings` is keyed by
    /// `AppLanguage` and there is no way to reach it from a `KeyboardLanguage`,
    /// so a product label CANNOT be resolved from the layout by accident. This
    /// test pins the intent; `KeyboardStrings`, which owns the layout captions,
    /// lives in the extension target and is verified on device.
    func testProductStringsAreKeyedByAppLanguage() {
        for language in AppLanguage.allCases {
            let strings = AIReplyStrings.forLanguage(language)
            XCTAssertFalse(strings.insert.isEmpty)
        }
        XCTAssertEqual(AIReplyStrings.forLanguage(.kazakh).insert, "Кірістіру")
    }

    // MARK: Catalog completeness

    /// Every key compiled into the app must exist in all three languages.
    /// Reads the built `.lproj` tables rather than the source catalog, so it
    /// checks what actually ships.
    func testEveryStringIsTranslatedInEveryLanguage() throws {
        let tables = try ["en", "ru", "kk"].map { language -> (String, [String: String]) in
            let path = try XCTUnwrap(
                Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "\(language).lproj"),
                "\(language).lproj/Localizable.strings is missing from the app bundle"
            )
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            return (language, table)
        }

        let englishKeys = Set(tables[0].1.keys)
        XCTAssertGreaterThan(englishKeys.count, 150, "the catalog looks truncated")

        for (language, table) in tables.dropFirst() {
            let missing = englishKeys.subtracting(table.keys)
            XCTAssertTrue(missing.isEmpty, "\(language) is missing: \(missing.sorted().prefix(10))")
        }
    }

    /// Catches a key that was added to ru/kk by copying the English value.
    func testUserFacingScreensAreActuallyTranslated() throws {
        let suspects = [
            "setup.title", "setup.paste.body", "setup.fullAccess.why",
            "onboarding.keyboard.title", "onboarding.usage.title",
            "profile.role", "profile.rules", "templates.section.style"
        ]

        func value(_ key: String, _ language: String) throws -> String {
            let path = try XCTUnwrap(
                Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "\(language).lproj")
            )
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            return try XCTUnwrap(table[key], "\(key) missing in \(language)")
        }

        for key in suspects {
            let en = try value(key, "en")
            XCTAssertNotEqual(try value(key, "ru"), en, "\(key) is English in Russian")
            XCTAssertNotEqual(try value(key, "kk"), en, "\(key) is English in Kazakh")
        }
    }
}
