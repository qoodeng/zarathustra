import Foundation

enum WakePhraseMatcherTests {
    static func run() {
        testHeyZarathustraIsAlwaysRecognized()
        testPlainZarathustraToggle()
        testCommonRecognitionAliases()
        testHiddenRecognitionHints()
        testPhraseBoundariesAndPosition()
        testTrailingDictation()
        testPartialResultSuppression()
        testCooldownAndRearming()
        testExplicitRearm()
    }

    private static func testHeyZarathustraIsAlwaysRecognized() {
        let cases = [
            "hey zarathustra",
            "HEY ZARATHUSTRA",
            "  Hey, Zarathustra!",
            "…hey—zarathustra"
        ]
        for transcript in cases {
            expectEqual(
                WakePhraseMatcher.detect(in: transcript),
                WakePhraseMatch(phrase: .heyZarathustra, trailingText: ""),
                "Did not recognize \(transcript.debugDescription)"
            )
        }
    }

    private static func testPlainZarathustraToggle() {
        expectEqual(WakePhraseMatcher.detect(in: "Zarathustra"), nil)
        expectEqual(
            WakePhraseMatcher.detect(in: "Zarathustra", plainZarathustraEnabled: true),
            WakePhraseMatch(phrase: .zarathustra, trailingText: "")
        )
    }

    private static func testCommonRecognitionAliases() {
        let alwaysOn = [
            "hey zara thustra, write this",
            "hey sarah thustra, write this",
            "hey zara thuster, write this",
            "hey zoroaster, write this",
            "he zarathustra, write this",
            "hay zara thustra, write this",
            "hi sarah thustra, write this"
        ]
        for transcript in alwaysOn {
            expectEqual(
                WakePhraseMatcher.detect(in: transcript),
                WakePhraseMatch(phrase: .heyZarathustra, trailingText: "write this"),
                "Did not normalize \(transcript.debugDescription)"
            )
        }

        for transcript in ["zara thustra, write this", "zara—thustra, write this"] {
            expectEqual(
                WakePhraseMatcher.detect(in: transcript),
                WakePhraseMatch(phrase: .heyZarathustra, trailingText: "write this")
            )
        }

        for transcript in ["Sarah wrote this", "Zara, write this", "zoroaster, write this"] {
            expectEqual(
                WakePhraseMatcher.detect(in: transcript, plainZarathustraEnabled: true),
                nil,
                "Fuzzy alias escaped the Hey-only guard for \(transcript.debugDescription)"
            )
        }
    }

    private static func testHiddenRecognitionHints() {
        expectEqual(WakePhraseMatcher.recognitionHints.contains("Hey Zarathustra"), true, "Canonical wake hint missing")
        expectEqual(WakePhraseMatcher.recognitionHints.contains("Hey Zara Thustra"), true, "Segmented wake hint missing")
        expectEqual(WakePhraseMatcher.recognitionHints.contains("Hey Sarah Thustra"), true, "Acoustic wake hint missing")
        expectEqual(
            WakePhraseMatcher.recognitionHints.allSatisfy { $0.lowercased().hasPrefix("hey") || $0 == "Zarathustra" },
            true,
            "Unsafe plain acoustic alias leaked into recognition hints"
        )
    }

    private static func testPhraseBoundariesAndPosition() {
        let rejected = [
            "zarathustras",
            "hey zarathustras",
            "The zarathustra is loud",
            "They said hey zarathustra"
        ]
        for transcript in rejected {
            expectEqual(
                WakePhraseMatcher.detect(in: transcript, plainZarathustraEnabled: true),
                nil,
                "False positive for \(transcript.debugDescription)"
            )
        }
    }

    private static func testTrailingDictation() {
        expectEqual(
            WakePhraseMatcher.detect(in: "Hey Zarathustra, what's 2 + 3?"),
            WakePhraseMatch(phrase: .heyZarathustra, trailingText: "what's 2 + 3?")
        )
        expectEqual(
            WakePhraseMatcher.detect(in: "Hey Zarathustra, write this down."),
            WakePhraseMatch(phrase: .heyZarathustra, trailingText: "write this down.")
        )
        expectEqual(
            WakePhraseMatcher.detect(in: "Zarathustra — new paragraph", plainZarathustraEnabled: true),
            WakePhraseMatch(phrase: .zarathustra, trailingText: "new paragraph")
        )
    }

    private static func testPartialResultSuppression() {
        let start = Date(timeIntervalSince1970: 100)
        var matcher = WakePhraseMatcher(cooldown: 1)
        expectEqual(matcher.observe("hey zarathustra", at: start)?.phrase, .heyZarathustra)
        expectEqual(matcher.observe("hey zarathustra write", at: start.addingTimeInterval(0.2)), nil)
        expectEqual(matcher.observe("hey zarathustra write this", at: start.addingTimeInterval(2)), nil)
    }

    private static func testCooldownAndRearming() {
        let start = Date(timeIntervalSince1970: 200)
        var matcher = WakePhraseMatcher(cooldown: 1)
        expectEqual(matcher.observe("hey zarathustra", at: start)?.phrase, .heyZarathustra)
        expectEqual(matcher.observe("", at: start.addingTimeInterval(0.5)), nil)
        expectEqual(matcher.observe("hey zarathustra", at: start.addingTimeInterval(0.6)), nil)
        expectEqual(matcher.observe("", at: start.addingTimeInterval(1.1)), nil)
        expectEqual(matcher.observe("hey zarathustra", at: start.addingTimeInterval(1.2))?.phrase, .heyZarathustra)
    }

    private static func testExplicitRearm() {
        let start = Date(timeIntervalSince1970: 300)
        var matcher = WakePhraseMatcher(cooldown: 30)
        _ = matcher.observe("hey zarathustra", at: start)
        matcher.rearm()
        expectEqual(matcher.observe("hey zarathustra", at: start)?.phrase, .heyZarathustra)
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard actual != expected else { return }
        let context = message.isEmpty ? "" : " \(message)"
        fatalError(
            "\(file):\(line): expected \(String(describing: expected)), got \(String(describing: actual)).\(context)"
        )
    }
}
