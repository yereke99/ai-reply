import XCTest
@testable import AIReply

/// Final cleanup before insertion. The rule this file exists to enforce is that
/// normalization is CONSERVATIVE: it fixes whitespace and nothing else, and it
/// must not damage the scripts and content types this app carries.
final class ReplyDraftNormalizerTests: XCTestCase {

    private let normalizer = ReplyDraftNormalizer()

    func testTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(normalizer.normalize("  Hello   there  "), "Hello there")
    }

    func testRemovesSpaceBeforePunctuation() {
        XCTAssertEqual(normalizer.normalize("Hello , world !"), "Hello, world!")
    }

    func testLimitsBlankLines() {
        XCTAssertEqual(normalizer.normalize("One\n\n\n\n\nTwo"), "One\n\nTwo")
    }

    func testPreservesKazakhCharacters() {
        let draft = "Сәлеметсіз бе! Тапсырысыңызды нақтылап, хабарлаймын."
        XCTAssertEqual(normalizer.normalize(draft), draft)
    }

    func testPreservesRussianCharacters() {
        let draft = "Здравствуйте! Уточню статус заказа и напишу вам."
        XCTAssertEqual(normalizer.normalize(draft), draft)
    }

    func testPreservesEmoji() {
        let draft = "Да, вечером свободен 👍🏽 Во сколько?"
        XCTAssertEqual(normalizer.normalize(draft), draft)
    }

    /// A URL's own punctuation must survive: "example.com/a?b=1" contains
    /// exactly the characters the punctuation rule would otherwise chew on.
    func testPreservesURLs() {
        let draft = "Details here: https://example.com/order?id=12 , thanks"
        let result = normalizer.normalize(draft)
        XCTAssertTrue(result.contains("https://example.com/order?id=12"))
    }

    func testPreservesPhoneNumbersAndPrices() {
        XCTAssertEqual(normalizer.normalize("+7 701 234 56 78"), "+7 701 234 56 78")
        XCTAssertEqual(normalizer.normalize("Цена 12 500 ₸"), "Цена 12 500 ₸")
    }

    func testEmptyDraftNormalizesToEmpty() {
        XCTAssertEqual(normalizer.normalize("   \n  "), "")
    }
}
