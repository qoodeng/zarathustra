# Megaphone Step 1 Review

Date: 2026-09-02  
Reviewed upstream commit: `5a9136b3ac8c766e24a5d79ac056df4d427968f1`  
Scope: architecture, security, privacy, reliability, concurrency, persistence, permissions, updater/release path, and test coverage.

Model transcription and rewrite quality were deliberately treated as acceptable and were not benchmarked or compared.

## Executive verdict

Megaphone is a credible Apple-native foundation: its transcription and rewrite pipeline is genuinely local, it has no cloud transcription configuration, it has sensible deterministic fallbacks, and the updater verifies a downloaded app against the installed app's designated code-signing requirement before launching its replacement helper.

I would fork it, but I would not ship the fork unchanged. The first hardening pass should fix three high-impact paths before adding features:

1. Stable releases can fall back to ad-hoc signing and still be published.
2. Cancelling an update does not cancel the detached download and can allow installation to continue.
3. A Core Data load error causes automatic deletion of the entire run-history database.

The main privacy concern is not cloud transmission; it is undisclosed local retention. Every run can retain raw and rewritten text, selected text, window metadata, prompts, custom vocabulary, and WAV audio. Wake-command prompts can also retain up to 2,400 characters of visible window text.

## Architecture and data flow

1. A macOS 13-compatible launcher checks the OS and `execv`s the macOS 26 core executable.
2. `AppState` coordinates shortcuts, recording, context capture, transcription, cleanup, pasteboard injection, run history, and most UI state.
3. `AudioRecorder` writes a temporary 16 kHz mono WAV while also emitting 24 kHz mono PCM16 chunks.
4. `SpeechAnalyzerStreamingSession` feeds those chunks to Apple's `SpeechAnalyzer`; the WAV is used as a file-based fallback.
5. `AppContextService` reads the active app, window title, selection, and nearby text with Accessibility. Wake commands may additionally read the visible accessibility tree or OCR a focused-window screenshot.
6. `AppleFoundationModelsPostProcessor` performs cleanup or command execution on-device, with deterministic output validation and fallback behavior.
7. The result is placed on the pasteboard and injected with synthetic keyboard events.
8. Run metadata is stored in Core Data and WAV files are copied into Application Support.

Outbound networking is limited to update metadata/assets and GitHub repository/profile metadata used by setup/settings UI. No transcript or audio upload path was found.

The app is not sandboxed. It requests microphone, Accessibility, and optionally Screen Recording access. Given the global event tap and cross-application UI automation, the lack of sandboxing may be operationally necessary, but it increases the importance of minimizing retained data and hardening the update/release chain.

## Findings

### High — Stable releases fail open to ad-hoc signing

Evidence:

- `.github/workflows/release.yml:79-81` deliberately sets `CODESIGN_IDENTITY=-` when signing secrets are absent.
- `.github/workflows/release.yml:130-136` also falls back to ad-hoc signing when no usable identity can be extracted.
- `.github/workflows/release.yml:176-186` publishes the resulting DMG as the latest stable release.
- The README's one-line installer clears quarantine and replaces the current installation.

Impact: a missing, expired, or incorrectly imported certificate can produce a stable release without the publisher identity users and the in-app updater rely on. The updater should reject such an update, but manual installation instructions weaken Gatekeeper protection and may replace a valid installation.

Recommendation: stable releases must fail closed unless all signing and notarization inputs are present, the final app and DMG verify against the expected Developer ID Team ID, notarization succeeds, and stapler validation passes. Keep ad-hoc fallback only for explicitly marked development artifacts. Pin every release-workflow action to a commit SHA; `actions/checkout`, Pages actions, and artifact actions currently use mutable major tags.

### High — Update cancellation does not cancel the actual download

Evidence:

- `Sources/UpdateManager.swift:759-763` cancels `activeDownloadTask` and immediately resets the UI.
- `Sources/UpdateManager.swift:825-859` performs byte iteration and file output in a separate `Task.detached`.
- Only the detached task checks `Task.isCancelled`; cancelling its parent does not cancel it.
- `Sources/UpdateManager.swift:861-933` awaits the detached task and then proceeds into mount, validation, helper launch, and app replacement without another parent-cancellation check.

Impact: the UI can say an update was cancelled while the download continues, after which Megaphone may still mount and install it. This is both a reliability defect and a violation of explicit user intent.

Recommendation: keep the download in structured concurrency or retain and cancel the actual URLSession/download task. Check cancellation before every phase transition, especially before mounting, staging, and launching the replacement helper. Add an integration test that cancels mid-stream and proves no mount or install operation occurs.

### High — A store-load error silently destroys all run history

Evidence:

- `Sources/PipelineHistoryStore.swift:29-35` treats any initial persistent-store load error as grounds to delete the SQLite database, WAL, and SHM files.
- `Sources/PipelineHistoryStore.swift:48-59` retries with a fresh database and silently falls back to memory if that also fails.
- `Sources/PipelineHistoryStore.swift:260-265` performs the deletion without backup, quarantine, error classification, or user confirmation.

Impact: a transient I/O error, incompatible schema, partial migration, disk issue, or recoverable corruption can erase every stored transcript and its database references. Associated WAV files are then orphaned because startup cleanup only knows filenames still present in the database.

Recommendation: never delete the store automatically. Move failing files to a timestamped recovery directory, report the precise error, attempt supported migration/recovery, and require an explicit reset for destructive recovery. Reconcile the audio directory against live history records at startup.

### Medium — Sensitive local history is broader than users are told

Evidence:

- `Sources/AppState.swift:2944-2946` copies every completed recording into Application Support before transcription completes.
- `Sources/AppState.swift:3214-3234` records raw/final transcripts, the full post-processing prompt, system prompt, selected text, captured selection, custom vocabulary, app identity, bundle ID, window title, and audio filename.
- `Sources/ScreenTextService.swift:16-37` collects up to 2,400 characters from the visible window.
- `Sources/AppleFoundationModelsPostProcessor.swift:563-569` embeds visible window text in the command prompt.
- `Sources/AppState.swift:3078-3087` stores that prompt in run history.
- `Sources/PipelineHistoryStore.swift:301-322` persists these fields as ordinary Core Data string attributes. WAV files are also ordinary files. There is no history-disable setting or time-based retention.
- Setup describes Accessibility primarily as needed for pasting and says there is no server, but does not clearly state that speech, selections, visible window content, prompts, and audio are retained locally.

Impact: sensitive content from emails, chats, documents, terminal windows, or selected text can live indefinitely on disk and in backups. “On-device” prevents server disclosure but is not the same as “not retained.” The prompt field makes the screen-context toggle a persistence control as well as an inference control.

Recommendation: make history retention explicit and configurable; default audio retention off; store only the minimum fields needed for normal operation; never persist visible-window text inside model prompts unless the user enables a clearly labeled debug capture; add time-based retention; and document exactly what is stored. Use restrictive directory/file permissions and consider encryption if the threat model includes other same-user processes or unencrypted backups. Secure-field filtering should be shared by both `AppContextService` and `ScreenTextService`.

### Medium — Cancelled and failed recordings are not deleted

Evidence:

- `Sources/AudioRecorder.swift:296-320` returns `nil` whenever `discard` is true and clears `tempFileURL` before callers can recover it.
- `Sources/AudioRecorder.swift:241-254` and `Sources/AudioRecorder.swift:695-704` then attempt to delete the returned URL, but it is necessarily `nil` on the discard path.
- `cleanup()` cannot repair this because the stored URL has already been cleared.

Impact: cancelled recordings and recordings that fail after creating the WAV can remain in the system temporary directory, contrary to the expected discard behavior. This creates both sensitive-data residue and storage leakage.

Recommendation: return or capture the finalized URL independently of whether it should be kept, delete it on every discard/error path, and test cancellation and write-failure cleanup with a temporary directory fixture.

### Medium — Speech setup uses unbounded buffering

Evidence:

- `Sources/SpeechAnalyzerService.swift:284` stores pre-setup audio in an unbounded `[Data]`.
- `Sources/SpeechAnalyzerService.swift:312-363` can spend an open-ended period resolving locale and downloading/reserving model assets before flushing it.
- `Sources/SpeechAnalyzerService.swift:333` creates an `AsyncStream` with its default unbounded buffering policy.
- `Sources/SpeechAnalyzerService.swift:367-375` appends every incoming chunk until setup completes.

Impact: while a language model is downloading, unavailable, or slow to initialize, recording can grow memory without a hard limit. At 24 kHz mono PCM16, raw input alone is about 48 KB/s, before collection and converted-buffer overhead.

Recommendation: cap buffered duration/bytes, use a bounded `AsyncStream` policy, surface dropped/backpressured input, and fall back to the already-written WAV when streaming setup misses its budget.

### Medium — Mutable global app state bypasses Swift concurrency checks

Evidence:

- `Sources/AppState.swift:215` declares a roughly 3,700-line observable coordinator as `@unchecked Sendable` rather than isolating it to `@MainActor`.
- It owns dozens of mutable `@Published` and private fields, UI timers, unstructured tasks, Dispatch callbacks, transcription state, and persistence state.
- `Sources/AppState.swift:2965-3042` runs a transcription task that reads mutable settings while the settings UI can change them; only some writes are explicitly returned to `MainActor`.

Impact: the compiler is told to trust thread safety it cannot verify. Current code often dispatches UI writes to the main queue, but settings and session inputs can be read concurrently or inconsistently, and future edits can easily introduce a real race.

Recommendation: isolate UI/coordinator state to `@MainActor`, snapshot immutable per-recording configuration at start/stop, and move audio, speech, history, and update work behind actors or narrow Sendable service interfaces. Split `AppState` by responsibility before significant feature work.

### Medium — Publisher verification has a replacement-time race

Evidence:

- `Sources/UpdateManager.swift:987-1017` validates bundle ID, version, strict code signature, and equality with the installed app's designated requirement before launching the helper.
- `Sources/UpdateManager.swift:1078-1082` later copies the staged app and checks only generic signature validity and version. The helper does not re-check bundle ID or the expected designated requirement after the copy.

Impact: a malicious same-user process could replace the staged app between validation and copy with a different validly signed app using the expected version. This requires an already-compromised user session, so it is defense-in-depth rather than a remote update exploit.

Recommendation: pass the expected designated requirement and bundle ID to the helper, validate immediately before copying, then validate the installed destination again before relaunch. Prefer an immutable/open-file or privileged standard updater design if distribution grows.

### Medium — High-risk platform paths have no automated coverage

Evidence:

- The test target includes deterministic parsing, dictionary, context classification, shortcut models, and model-output validation.
- It excludes `AudioRecorder`, `SpeechAnalyzerService`, `ScreenTextService`, `PipelineHistoryStore`, `UpdateManager`, `RecordingOverlayManager`, and the end-to-end `AppState` pipeline.
- The stable release workflow runs only this deterministic target before signing and publishing.

Impact: cancellation, data deletion, cleanup, update replacement, and permission/context regressions can ship while all tests pass.

Recommendation: introduce protocol boundaries for filesystem, URL loading, process execution, pasteboard, Accessibility, and screen capture; add deterministic unit tests for failure/cancellation paths; and add a macOS integration/smoke job that builds the complete app and exercises store migration, updater validation, temp-file cleanup, and overlay lifecycle.

### Low — Privacy language omits non-content network traffic

Evidence:

- The README correctly says audio/transcripts are not uploaded, but its headline says the app runs “entirely on your Mac.”
- `UpdateManager` automatically checks `megaphone.kuber.studio` and GitHub.
- `GitHubMetadataCache` and remote avatar views contact GitHub when setup/settings surfaces appear.

Impact: no speech content was found in these requests, but users who interpret “entirely on your Mac” as “no network activity” will see unexpected outbound connections.

Recommendation: keep the stronger and accurate claim—transcription and cleanup are on-device—and separately disclose update and decorative GitHub requests. Avoid fetching stars, contributors, and avatars unless that UI is visible, and consider omitting decorative network requests in a privacy-focused fork.

## Controls worth preserving

- Speech and Foundation Models processing are local, with no cloud API key or transcript upload path.
- Smart cleanup has deterministic fallback behavior and validates suspicious empty, truncated, expanded, profanity-filtered, and markdown-wrapped outputs.
- The updater validates bundle ID/version, strict code signature, and publisher designated requirement before launching the helper, and keeps a rollback copy.
- Screen OCR is only attempted when Screen Recording was already granted, avoiding an unexpected permission prompt during dictation.
- Nearby caret context explicitly excludes native secure text fields.
- Clipboard preservation tries not to overwrite a clipboard value the user changed after dictation.
- The recording pipeline retains a WAV fallback when live streaming cannot produce a transcript.

## Recommended remediation order

1. Make stable release signing/notarization fail closed and pin release dependencies.
2. Fix update cancellation and revalidate publisher identity in the helper.
3. Replace destructive history recovery with backup/quarantine and audio reconciliation.
4. Fix discarded-temp-audio deletion.
5. Add retention controls and stop persisting visible-window text in prompts/history by default.
6. Bound streaming buffers.
7. Main-actor isolate and decompose `AppState`.
8. Add tests around every item above before feature expansion.

## Verification performed and limitations

- Reviewed all primary runtime, persistence, context capture, updater, launcher, entitlement, build, and release-workflow paths at the pinned commit.
- Searched for network, process execution, filesystem persistence, unsafe concurrency declarations, force operations, and sensitive logging.
- `git diff --check` passes for the local overlay-animation change made after the audit.
- Tests could not run in this workspace: it is Linux and has neither Swift nor Xcode/macOS 26 SDK (`make test` fails at the missing `xcrun`/`swiftc` tools). The full app and animation therefore require verification on macOS 26.
- `qoodeng/zarathustra` was initialized from the exact Git tree at upstream commit `5a9136b3ac8c766e24a5d79ac056df4d427968f1`; the review and overlay change live on `codex/step-1-review`. Because the destination began as an empty standalone repository rather than a GitHub-native fork, earlier upstream commit history is not present before the import commit.
