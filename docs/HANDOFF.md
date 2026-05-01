# Handoff - Hui Shi TTS Reader

## Snapshot
- Platform: Android (Kotlin + Compose + Room + Media3).
- App name/icon: Hui Shi branding integrated.
- Ingestion: plain text, PDF (positioned extraction + header/footer suppression), EPUB (chapter-aware parsing).
- Playback: chunked audio with follow-along highlighting and progress sync.

## What Works
- Local Android TTS path is stable for large docs and problematic PDF/Markdown content.
- Kokoro cloud path is integrated for chunked synthesis from the device.
- Native Android fallback is integrated when cloud synthesis fails.
- Build Audio supports progressive generation with early playback and background chunk generation.
- UI safe-area fix applied for top controls.

## Current TTS Behavior
- If cloud succeeds, synthesis runs in Kokoro cloud mode.
- If cloud fails for any chunk, fallback uses native Android TTS for continuity.
- If `KOKORO_TTS_ENGINE` is configured and unavailable, native fallback uses the system default engine.

## Configuration
- Key/value loaded from `gradle.properties` or environment variables:
-  - `KOKORO_API_BASE_URL` (also supports `KOKORO_API_URL`, `TTS_API_BASE_URL`, and `TTS_API_URL` aliases)
-  - `KOKORO_API_KEY` (also supports `TTS_API_KEY` alias)
  - `KOKORO_TTS_ENGINE` (optional Android engine package)

## Known Notes
- On-device voice quality and language support depend on installed Android TTS engines/voices.
- Cloud provider contract may vary by endpoint behavior; fallback preserves playback continuity.
- Large PDFs will still take time due to chunk count and synthesis duration.

## Recommended Next Steps
1. Add explicit voice picker UI for cloud voice IDs plus installed local fallback voices.
2. Add persistent resume of unfinished chunk builds after app restart.
3. Add a "fast mode" for very large docs (smaller first batch + immediate play).
4. Add integration tests for cloud queue responses and fallback transitions.

## Operational Commands
- Build/install debug:
  - `./gradlew :app:installDebug`
- Launch on connected device:
  - `/home/ericaspen/Android/Sdk/platform-tools/adb shell am start -n com.example.ttsreader/.MainActivity`
