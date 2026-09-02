<p align="center">
  <img src="Resources/AppIcon-Source.png" width="128" height="128" alt="Zarathustra icon">
</p>

<h1 align="center">Zarathustra</h1>

<p align="center">
  Private, system-wide dictation for macOS using Apple SpeechAnalyzer and Apple Foundation Models.
</p>

Zarathustra transcribes speech on device, optionally cleans it up with Apple Intelligence, and inserts the result into the active app. Hold the configured shortcut, speak, and release.

This repository is a security- and privacy-focused fork of [Megaphone](https://github.com/Kuberwastaken/megaphone), imported from upstream commit [`5a9136b`](https://github.com/Kuberwastaken/megaphone/commit/5a9136b3ac8c766e24a5d79ac056df4d427968f1). The original project in turn credits [FreeFlow](https://github.com/zachlatta/freeflow).

## Current status

The fork is under active rework. Build from source for development; there is no trusted Zarathustra binary release yet. Stable downloads will only be published after the fail-closed signing, notarization, and updater checks in this repository have passed on macOS.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode with the macOS 26 SDK
- Apple Intelligence enabled for Smart Cleanup; Basic Cleanup remains available without it

## Build locally

```bash
git clone https://github.com/qoodeng/zarathustra.git
cd zarathustra
make
open "build/Zarathustra Dev.app"
```

Local builds use ad-hoc signing by default. macOS privacy permissions are tied to the app signature, so rebuilding may require granting Microphone, Speech Recognition, and Accessibility permissions again.

Run the deterministic test target on a compatible Mac with:

```bash
make test
```

## How it works

- `SpeechAnalyzer` streams on-device speech recognition while recording.
- Apple Foundation Models can rewrite and clean the transcript on device.
- A deterministic cleanup pass is used when Apple Intelligence is unavailable or times out.
- Accessibility inserts the result and can provide selected or nearby text for optional command context.
- “Hey Zarathustra” activates inline commands; the shorter “Zarathustra” trigger is optional.

## Privacy and network behavior

Audio, transcripts, writing context, and cleanup requests are processed on the Mac. Zarathustra has no transcription server and requires no account or API key.

When automatic update checks are enabled, the app contacts GitHub’s releases API and sends ordinary network request metadata. Opening repository or release links also contacts GitHub. No audio, transcript, prompt, selected text, or visible-window context is included in those requests.

History retention and optional audio retention are being hardened on the remediation branch. Review [`REVIEW_STEP_1.md`](REVIEW_STEP_1.md) for the audit scope and current findings.

## License and attribution

Zarathustra retains Megaphone’s MIT license and copyright notice. See [`LICENSE`](LICENSE). Fork-specific changes are also released under the MIT license.
