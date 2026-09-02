import Foundation

enum WakePhrase: String, Equatable {
    case heyZarathustra
    case zarathustra

    var displayName: String {
        switch self {
        case .heyZarathustra: return "Hey Zarathustra"
        case .zarathustra: return "Zarathustra"
        }
    }
}

struct WakePhraseMatch: Equatable {
    let phrase: WakePhrase
    let trailingText: String
}

/// Recognizes a wake phrase at the beginning of a live speech transcript.
///
/// Speech recognizers repeatedly publish increasingly complete versions of the
/// same utterance. `observe` therefore emits at most once until a non-matching
/// transcript is observed after the cooldown, or the caller explicitly rearms
/// the matcher for a new recognition session.
struct WakePhraseMatcher {
    var plainZarathustraEnabled: Bool
    var cooldown: TimeInterval

    private var isArmed = true
    private var lastMatchDate: Date?

    init(plainZarathustraEnabled: Bool = false, cooldown: TimeInterval = 1.0) {
        self.plainZarathustraEnabled = plainZarathustraEnabled
        self.cooldown = max(0, cooldown)
    }

    mutating func observe(_ transcript: String, at date: Date = Date()) -> WakePhraseMatch? {
        let detected = Self.detect(in: transcript, plainZarathustraEnabled: plainZarathustraEnabled)

        guard isArmed else {
            if detected == nil, cooldownHasElapsed(at: date) {
                isArmed = true
            }
            return nil
        }

        guard let detected else { return nil }
        isArmed = false
        lastMatchDate = date
        return detected
    }

    mutating func rearm() {
        isArmed = true
        lastMatchDate = nil
    }

    static func detect(
        in transcript: String,
        plainZarathustraEnabled: Bool = false
    ) -> WakePhraseMatch? {
        if let match = match(pattern: heyPattern, phrase: .heyZarathustra, in: transcript) {
            return match
        }
        // SpeechAnalyzer occasionally drops the quiet leading “Hey” while
        // still returning the distinctive segmented product name. Recover
        // only a clearly segmented “Zara Thustra” here; broader acoustic
        // aliases stay Hey-gated.
        if let match = match(pattern: segmentedRecoveryPattern, phrase: .heyZarathustra, in: transcript) {
            return match
        }
        guard plainZarathustraEnabled else { return nil }
        return match(pattern: plainPattern, phrase: .zarathustra, in: transcript)
    }

    static let recognitionHints = [
        "Hey Zarathustra",
        "Zarathustra",
        "Hey Zara Thustra",
        "Hey Sarah Thustra",
        "Hey Zoroaster"
    ]

    private func cooldownHasElapsed(at date: Date) -> Bool {
        guard let lastMatchDate else { return true }
        return date.timeIntervalSince(lastMatchDate) >= cooldown
    }

    private static func match(
        pattern: NSRegularExpression,
        phrase: WakePhrase,
        in transcript: String
    ) -> WakePhraseMatch? {
        let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        guard let result = pattern.firstMatch(in: transcript, range: range),
              let matchedRange = Range(result.range, in: transcript) else {
            return nil
        }

        let trailing = transcript[matchedRange.upperBound...]
            .drop(while: { character in
                character.unicodeScalars.allSatisfy { trailingSeparators.contains($0) }
            })
        return WakePhraseMatch(phrase: phrase, trailingText: String(trailing))
    }

    private static let leadingSeparators = #"^[\s\p{P}\p{S}]*"#
    private static let phraseSeparator = #"[\s\p{P}\p{S}]+"#
    private static let phraseBoundary = #"(?=$|[\s\p{P}\p{S}])"#

    // Keep recognition aliases here rather than in SpeechAnalyzer's custom
    // vocabulary. Vocabulary hints should teach the correct product spelling;
    // these hidden aliases only recover common acoustic substitutions after
    // transcription. Fuzzy forms require the leading “Hey” phrase so enabling
    // the optional plain trigger cannot turn a similar ordinary phrase into a
    // command.
    private static let strictZarathustraVariants = "(?:zarathustra|zara" + phraseSeparator + "thustra)"
    private static let fuzzyZarathustraVariants = "(?:" + [
        strictZarathustraVariants,
        "sarah" + phraseSeparator + "thustra",
        "zara" + phraseSeparator + "thuster",
        "zara" + phraseSeparator + "thustra",
        "zoroaster"
    ].joined(separator: "|") + ")"
    private static let heyVariants = "(?:hey|he|hay|hi)"

    private static let heyPattern = try! NSRegularExpression(
        pattern: leadingSeparators + heyVariants + phraseSeparator + fuzzyZarathustraVariants + phraseBoundary,
        options: [.caseInsensitive]
    )
    private static let plainPattern = try! NSRegularExpression(
        pattern: leadingSeparators + "zarathustra" + phraseBoundary,
        options: [.caseInsensitive]
    )
    private static let segmentedRecoveryPattern = try! NSRegularExpression(
        pattern: leadingSeparators + "zara" + phraseSeparator + "thustra" + phraseBoundary,
        options: [.caseInsensitive]
    )
    private static let trailingSeparators = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)
}
