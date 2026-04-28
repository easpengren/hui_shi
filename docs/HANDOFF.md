# Handoff - Hui Shi TTS Reader

## Snapshot
- Platform: Android (Kotlin + Compose + Room + Media3).
- App name/icon: Hui Shi branding integrated.
- Ingestion: plain text, PDF (positioned extraction + header/footer suppression), EPUB (chapter-aware parsing).
- Playback: chunked audio with follow-along highlighting and progress sync.

## What Works
- Local Android TTS path is stable for large docs and problematic PDF/Markdown content.
- Cloud TTS path is integrated with request/response handling, queue polling, and diagnostics.
- Automatic fallback from cloud to local is in place to avoid crashes.
- Build Audio supports progressive generation with early playback and background chunk generation.
- UI safe-area fix applied for top controls.

## Current TTS Behavior
- If cloud succeeds, synthesis runs in cloud mode.
- If cloud fails for any chunk, fallback uses local TTS for continuity.
- UI shows status/progress and a cloud fallback message only when fallback is used.

## Configuration
- Key/value loaded from `gradle.properties` or environment variables:
  - `TTS_API_KEY`
  - `TTS_API_BASE_URL` (also supports `TTS_API_URL` alias)
- URL is normalized with trailing slash at build time.

## Known Notes
- Cloud provider contract can vary by endpoint model/voice behavior; fallback ensures user flow remains functional.
- Large PDFs will still take time due to chunk count and synthesis duration.

## Recommended Next Steps
1. Add explicit voice picker UI for cloud voice IDs (and optional local engine voice options).
2. Add persistent resume of unfinished chunk builds after app restart.
3. Add a "fast mode" for very large docs (smaller first batch + immediate play).
4. Add integration tests that mock cloud queued responses and fallback transitions.

## Operational Commands
- Build/install debug:
  - `./gradlew :app:installDebug`
- Launch on connected device:
  - `/home/ericaspen/Android/Sdk/platform-tools/adb shell am start -n com.example.ttsreader/.MainActivity`
