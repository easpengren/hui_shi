# Handoff - Lu Ji Flutter Reader

## Snapshot
- Primary project path: /home/ericaspen/projects/tts_reader
- Branch: `flutter`
- App stack: Flutter + Provider + just_audio
- Platforms: Android (primary), Linux (UI smoke testing only)
- File ingest: TXT, EPUB, PDF (pdfrx text extraction; image PDFs show clear error)
- TTS engines:
  - System TTS via flutter_tts (Android voices; HQ neural voices prioritized)
  - Piper offline via sherpa_onnx (model downloaded on first use)

## Current Status (2026-05-02)
App is fully functional on Pixel 9a. Debug APK installed. All core features working.

### Screens
- **Reader** (`/`): text panel, playback bar, AppBar with gear/library/bookmark/open icons
- **Library** (`/library`): persistent list of opened books with bookmark chips
- **Settings** (`/settings`): engine selector, voice picker, speed slider, dark mode toggle
- **About** (`/about`): app info, engine descriptions, open-source credits

### Features complete
- PDF / EPUB / TXT ingest with chunking
- System TTS with HQ voice prioritization and human-readable voice names
- Piper offline TTS with model download; human-readable voice labels
- Bookmarks: add/label/jump/delete; shown as chips in library
- Library persistence (SharedPreferences); resume position saved on pause/detach
- Dark mode with persistence
- "Current" jump button above text panel
- Speed slider (local drag state, commits on release)
- Sanitized TTS text (no dot-runs, no punctuation-only chunks spoken)
- Settings and About screens accessible via gear icon

## Critical Operational Notes
- **NEVER use `adb uninstall`** — wipes library, bookmarks, and settings
- Always use: `flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk`
- Force fresh launch after install: `adb shell am force-stop com.example.lu_ji && adb shell am start -n com.example.lu_ji/.MainActivity`
- Device: Pixel 9a, serial `57051JEBF12174`
- Package: `com.example.lu_ji`

## Key Files
| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry, routes (/settings, /about, /library) |
| `lib/state/reader_state.dart` | All state, TTS engine switching, voice loading, humanizer |
| `lib/screens/reader_screen.dart` | Reader UI, content area, playback bar |
| `lib/screens/settings_screen.dart` | Settings: engine, voice, speed, dark mode |
| `lib/screens/about_screen.dart` | About page |
| `lib/screens/library_screen.dart` | Library list with bookmark chips |
| `lib/models/book.dart` | LibraryEntry, Bookmark models |
| `lib/models/tts_engine.dart` | TtsEngine enum, kPiperVoices, kPiperVoiceLabels |
| `lib/tts/piper_tts_client.dart` | Piper/sherpa-onnx TTS client |
| `lib/tts/system_tts_client.dart` | flutter_tts wrapper |
| `lib/playback/playback_controller.dart` | Playback sequencing, speed, error stream |
| `lib/theme/app_theme.dart` | Light/dark themes (prussian/parchment palette) |

## Open / Deferred Work
- Speed parity: Piper and System TTS speeds feel slightly different at the same slider value; may need per-engine calibration
- More Piper voice options could be added to kPiperVoices / kPiperVoiceLabels
- No iOS or Linux audio support (guarded no-ops)
- No export/backup of library data

## Operational Commands
```bash
# Build and install (preserves data)
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk

# Force restart app
adb shell am force-stop com.example.lu_ji && adb shell am start -n com.example.lu_ji/.MainActivity

# Analyze
flutter analyze

# Clean build
flutter clean && flutter build apk --debug
```
