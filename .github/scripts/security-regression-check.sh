#!/bin/bash
set -euo pipefail

release_workflow=".github/workflows/release.yml"
updater="Sources/UpdateManager.swift"
history_store="Sources/PipelineHistoryStore.swift"
speech_service="Sources/SpeechAnalyzerService.swift"
audio_recorder="Sources/AudioRecorder.swift"

fail() {
  echo "security regression: $1" >&2
  exit 1
}

if grep -q 'CODESIGN_IDENTITY=-' "$release_workflow"; then
  fail "stable release workflow permits ad-hoc signing"
fi
grep -q 'Require signing and notarization secrets' "$release_workflow" || fail "stable release does not fail closed"
grep -q 'codesign --verify --deep --strict' "$release_workflow" || fail "stable app signature is not verified"
grep -q 'TeamIdentifier=\$APPLE_TEAM_ID' "$release_workflow" || fail "stable signing team is not verified"
grep -q 'notarytool submit' "$release_workflow" || fail "stable DMG is not notarized"
grep -q 'stapler validate' "$release_workflow" || fail "stapled ticket is not validated"

if grep -Eq 'uses: [^ ]+@v[0-9]' .github/workflows/*.yml; then
  fail "GitHub Action dependency uses a mutable major-version tag"
fi

grep -q 'activeTransferTask?.cancel()' "$updater" || fail "byte transfer is not cancelled with the parent update"
grep -q 'Task.checkCancellation()' "$updater" || fail "update phases do not enforce cancellation"
grep -q 'codesign --verify --deep --strict -R=' "$updater" || fail "installer helper does not re-check publisher requirement"
grep -q 'Print :CFBundleIdentifier' "$updater" || fail "installer helper does not re-check bundle identity"

if grep -q 'destroySQLiteStoreFiles' "$history_store"; then
  fail "history load failure can still destroy SQLite files"
fi
grep -q 'NSInMemoryStoreType' "$history_store" || fail "history store lacks non-destructive fallback"
grep -q 'maxPendingPCMBytes' "$speech_service" || fail "speech setup buffer is unbounded"
grep -q 'bufferingOldest' "$speech_service" || fail "speech analyzer AsyncStream is unbounded"
grep -q 'finalizeTemporaryRecording' "$audio_recorder" || fail "discarded recording files are not finalized"
grep -q 'removeItem(at: url)' "$audio_recorder" || fail "discarded recording files are not deleted"

echo "Security regression checks passed."
