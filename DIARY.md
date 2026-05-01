# Diary

## 2026-04-28
- Built Android app foundation for Hui Shi TTS Reader.
- Implemented PDF and EPUB import plus chapter-aware chunking.
- Added local Android TTS fallback and cloud TTS path with diagnostics.
- Added progressive build behavior: early playback while remaining chunks generate.
- Improved follow-along timing and status/progress visibility.
- Hardened cloud handling with graceful fallback to local voice.

## 2026-04-30
- Added persistent library tracking in Room for imported books, source metadata, and resume position.
- Added Library UI list with source availability status and open-from-library action.
- Added page browsing mode toggle: Browse only vs Auto-play page.
- Fixed page navigation snap-back issues by decoupling page selection from immediate seek, pausing on manual page selection, and stabilizing page-to-chunk mapping.
- Improved page playback safety so selecting an unsynthesized page reports status instead of jumping to an incorrect chunk.
- Verified repeated debug builds and installs on device after each fix.
- Tested and briefly enabled home Wi-Fi server routing, then reverted to prior localhost USB-reverse settings for next-day troubleshooting.
