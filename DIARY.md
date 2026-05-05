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

## 2026-05-02
- Fixed "Current" button overlapping text by replacing Stack+Positioned with Column layout (button row above text panel).
- Added Settings screen (/settings): engine selector (ToggleButtons), voice picker, speed slider, dark mode toggle.
- Added About screen (/about): app description, engine explanations, open-source credits.
- Moved TTS controls out of reader screen into Settings; reader AppBar now has gear icon.
- Added _humanizeVoiceName() in ReaderState: converts opaque Android voice IDs (en-us-x-iob-network) to readable labels (IOB (en-US) · Online). Verified via logcat.
- Added kPiperVoiceLabels map; Piper voices now show human names (Lessac (en-US) · Medium, etc.).
- Fixed DropdownButtonFormField using initialValue (one-shot) → value (reactive); voice picker now reflects live state.
- Fixed SegmentedButton illegible white-on-tan in light mode by replacing with ToggleButtons with explicit colors.
- Added explicit text color and dropdownColor to all voice pickers so they read correctly in light mode.
- Added dark mode SwitchListTile to Settings; dark mode toggle remains in AppBar too.
- NOTE: adb uninstall wiped library during this session. Always use adb install -r going forward.

## 2026-05-04
- Reworked reader navigation to index-based scrolling using scrollable_positioned_list; Current button and search next/prev now jump reliably to target chunks.
- Fixed chunk text readability in light theme by forcing explicit onSurface-based text color in RichText spans.
- Persisted and restored selected TTS engine and Piper voice across app restarts.
- Hardened playback controls: toggle now uses live controller status, play anchors from the current chunk when idle, and early-init access no longer crashes UI.
- Stabilized widget smoke test harness (provider path + viewport setup); flutter test now passes.
- Known-good debug build validated on device after install: current/search/play-pause/voice persistence behaviors verified.
