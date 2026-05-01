# TTS Reader (Android)

Prototype Android app that reads shared/uploaded text using Kokoro cloud synthesis on-device, with native Android fallback, plus:
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

## Configure Kokoro Cloud + Native Fallback
Set these build config fields in [app/build.gradle.kts](app/build.gradle.kts):
- `KOKORO_API_BASE_URL` (default `https://api.tts.ai/`, legacy `TTS_API_BASE_URL` alias supported)
- `KOKORO_API_KEY` (legacy `TTS_API_KEY` alias supported)
- `KOKORO_TTS_ENGINE` (optional Android engine package to prefer for fallback; blank uses system default)

## Modules
- `core`: text preparation pipeline
- `tts`: Kokoro cloud synthesis + native fallback + audio cache
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

## Self-Hosting
- Rollout runbook (home server to Hetzner): [docs/SELF_HOST_ROLLOUT.md](docs/SELF_HOST_ROLLOUT.md)
- Docker self-host starter stack: [selfhost/README.md](selfhost/README.md)
