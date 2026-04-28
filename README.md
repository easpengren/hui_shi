# TTS Reader (Android)

Prototype Android app that reads shared/uploaded text using TTS.ai with:
- text cleaning (header/footer and superscript/footnote stripping)
- PDF extraction with page coordinates and repeated-region header/footer detection
- EPUB parsing with chapter-aware preparation
- smart punctuation normalization for better pauses
- chunked synthesis and file cache
- ExoPlayer playback with adjustable speed
- follow-along word highlighting based on playback progress
- bookmarks and notes stored in Room

## Current Input Paths
- Share text from another app (`ACTION_SEND`, `text/plain`)
- Paste text directly in the app
- Upload plain text, PDF, or EPUB via picker

## Current Parsing Behavior
- PDF: positioned line extraction, merged into reading-order lines, repeated header/footer filtering biased to top/bottom regions
- EPUB: spine-order chapter extraction with HTML-to-text conversion
- Plain text: line batching into synthetic pages

## Configure TTS.ai
Set these build config fields in [app/build.gradle.kts](app/build.gradle.kts):
- `TTS_API_BASE_URL` (default `https://api.tts.ai/`)
- `TTS_API_KEY` (empty for anonymous free tier if allowed)

## Modules
- `core`: text preparation pipeline
- `tts`: network + audio cache
- `data`: Room schema and DAO
- `repo`: orchestration layer
- `playback`: ExoPlayer wrapper
- `ui`: ViewModel and Compose reader screen

## Run
1. Open this folder in Android Studio.
2. Let Gradle sync and install SDK components.
3. Run the `app` configuration on a device/emulator (Android 8+).

## Notes
- Word highlighting uses estimated per-chunk timing from playback progress; it is intentionally approximate.
- Shared text import is direct. Shared binary documents still come through the upload picker path rather than `ACTION_SEND` stream handling.
