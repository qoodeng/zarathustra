import Foundation

enum RemediationRegressionTests {
    static func run() {
        testHistoryRetention()
        testDiscardedAudioIsRemoved()
        testSpeechSetupBufferIsBounded()
        testVisibleTextTruncationHonorsLimit()
    }

    private static func testHistoryRetention() {
        let store = PipelineHistoryStore(inMemory: true)
        let now = Date()
        let old = makeHistoryItem(
            timestamp: now.addingTimeInterval(-10 * 24 * 60 * 60),
            audioFileName: "old.wav"
        )
        let recent = makeHistoryItem(timestamp: now, audioFileName: "recent.wav")
        do {
            _ = try store.append(old, maxCount: 20)
            _ = try store.append(recent, maxCount: 20)
            let removed = try store.trim(
                to: 20,
                olderThan: now.addingTimeInterval(-7 * 24 * 60 * 60)
            )
            expectEqual(Set(removed), Set(["old.wav"]))
            expectEqual(store.loadAllHistory().map(\.audioFileName), ["recent.wav"])
        } catch {
            fatalError("History retention test failed: \(error)")
        }
    }

    private static func testDiscardedAudioIsRemoved() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zarathustra-audio-test-\(UUID().uuidString).wav")
        do {
            try Data([0, 1, 2, 3]).write(to: url)
        } catch {
            fatalError("Could not create audio lifecycle fixture: \(error)")
        }
        expectEqual(FileManager.default.fileExists(atPath: url.path), true)
        expectEqual(AudioRecorder.finalizeTemporaryRecording(at: url, shouldKeep: false), nil)
        expectEqual(FileManager.default.fileExists(atPath: url.path), false)
    }

    private static func testSpeechSetupBufferIsBounded() {
        let limit = SpeechAnalyzerStreamingSession.maxPendingPCMBytes
        expectEqual(
            SpeechAnalyzerStreamingSession.canBufferPendingPCM(
                currentBytes: limit - 1,
                incomingBytes: 1
            ),
            true
        )
        expectEqual(
            SpeechAnalyzerStreamingSession.canBufferPendingPCM(
                currentBytes: limit,
                incomingBytes: 1
            ),
            false
        )
        expectEqual(
            SpeechAnalyzerStreamingSession.canBufferPendingPCM(
                currentBytes: 0,
                incomingBytes: limit + 1
            ),
            false
        )
    }

    private static func testVisibleTextTruncationHonorsLimit() {
        let text = String(repeating: "a", count: 100) + String(repeating: "z", count: 100)
        let truncated = ScreenTextService.truncatedMiddle(text, to: 80)
        expectEqual(truncated.count, 80)
        expectEqual(truncated.hasPrefix("a"), true)
        expectEqual(truncated.hasSuffix("z"), true)
        expectEqual(truncated.contains("[…]"), true)
    }

    private static func makeHistoryItem(timestamp: Date, audioFileName: String) -> PipelineHistoryItem {
        PipelineHistoryItem(
            timestamp: timestamp,
            rawTranscript: "raw",
            postProcessedTranscript: "final",
            postProcessingPrompt: nil,
            contextSummary: "",
            contextScreenshotDataURL: nil,
            contextScreenshotStatus: "not captured",
            postProcessingStatus: "done",
            debugStatus: "",
            customVocabulary: "",
            audioFileName: audioFileName
        )
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard actual != expected else { return }
        fatalError("\(file):\(line): expected \(expected), got \(actual)")
    }
}
