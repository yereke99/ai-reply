import Foundation

/// Final lightweight cleanup before a draft is inserted into the host field.
/// URL substrings are copied through untouched.
struct ReplyDraftNormalizer {

    private static let urlRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(?:https?://|www\.)\S+"#
    )
    private static let repeatedHorizontalSpaceRegex = try! NSRegularExpression(
        pattern: #"[^\S\r\n]{2,}"#
    )
    private static let spaceBeforePunctuationRegex = try! NSRegularExpression(
        pattern: #"[^\S\r\n]+([,.!?;:])"#
    )
    private static let excessiveBlankLineRegex = try! NSRegularExpression(
        pattern: #"\n[ \t]*\n(?:[ \t]*\n)+"#
    )

    func normalize(_ draft: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var output = ""
        let nsText = trimmed as NSString
        var cursor = 0
        let fullRange = NSRange(location: 0, length: nsText.length)

        for match in Self.urlRegex.matches(in: trimmed, range: fullRange) {
            if match.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                output += Self.normalizePlainSegment(nsText.substring(with: plainRange))
            }

            output += nsText.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }

        if cursor < nsText.length {
            let plainRange = NSRange(location: cursor, length: nsText.length - cursor)
            output += Self.normalizePlainSegment(nsText.substring(with: plainRange))
        }

        return Self.excessiveBlankLineRegex.stringByReplacingMatches(
            in: output,
            range: NSRange(location: 0, length: (output as NSString).length),
            withTemplate: "\n\n"
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizePlainSegment(_ segment: String) -> String {
        var value = repeatedHorizontalSpaceRegex.stringByReplacingMatches(
            in: segment,
            range: NSRange(location: 0, length: (segment as NSString).length),
            withTemplate: " "
        )

        value = spaceBeforePunctuationRegex.stringByReplacingMatches(
            in: value,
            range: NSRange(location: 0, length: (value as NSString).length),
            withTemplate: "$1"
        )

        return value
    }
}
