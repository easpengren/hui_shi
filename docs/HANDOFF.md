# Handoff - Lu Ji Flutter Reader

## Snapshot
- Primary project path: /home/ericaspen/projects/lu_ji
- App stack: Flutter + Provider state + just_audio playback
- Platforms configured: Android and Linux
- File ingest: TXT, EPUB, PDF (pdfrx text extraction)
- TTS engines:
  - Piper offline via sherpa_onnx
  - System TTS via flutter_tts (works on Android/iOS/macOS/web; guarded as no-op on Linux)

## Current Status
- Flutter app builds and runs:
  - Android debug APK builds successfully
  - Linux desktop run works for UI testing
- Reader behavior updated:
  - Current highlighted chunk now auto-scrolls into view during playback
  - Tapping a chunk now seeks and starts playback from that position
- Library persistence is present via shared_preferences
- Repo state:
  - Remote main currently points to Flutter Lu Ji tree
  - Kotlin history preserved on remote branch kotlin
  - Remote URL still uses repo name hui_shi (rename to lu_ji still pending on GitHub)

## Important Runtime Notes
- Linux desktop is for UI/smoke testing; system TTS plugin support is limited there.
- For real audio validation, use Android phone testing with both engines.
- Piper model download is required before offline voice playback.

## Open Work / Next Focus
1. Phone-side reading quality validation (highest priority):
   - Chunk boundary quality
   - Text cleanup fidelity
   - Highlight/audio synchronization
   - Resume and tap-to-start behavior under real use
2. Collect concrete repro examples from phone runs and tune chunking/cleanup rules.
3. Optional: add iOS platform scaffolding and iOS permission/config wiring.
4. Optional: add regression tests around chunking and playback position transitions.

## Operational Commands
- Get dependencies:
  - bash -c "cd /home/ericaspen/projects/lu_ji && flutter pub get"
- Analyze:
  - bash -c "cd /home/ericaspen/projects/lu_ji && flutter analyze"
- Run on Linux:
  - bash -c "cd /home/ericaspen/projects/lu_ji && flutter run -d linux"
- Build Android debug APK:
  - bash -c "cd /home/ericaspen/projects/lu_ji && flutter build apk --debug"
