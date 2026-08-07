# Handoff — Lu Ji Flutter Reader

> Read this before touching anything. Orientation, not documentation.

## ⚠ Two lineages. Only one of them is the app.

This repo contains **two divergent trees**, and confusing them replaced a working
install once already (2026-08-07):

| branch | what it is | publishes |
|---|---|---|
| **`flutter`** | **the app.** Everything ships from here. | `luji-latest.apk` |
| `main` | an older, different lineage. Retired 2026-08-07. | nothing — workflow removed |

They differ by thousands of lines across ~40 files: `main` has no
`settings_screen`, `about_screen`, `classical_chrome`, `footer_stripper` or batched
PDF loading, and its `reader_state` is 800+ lines smaller. `main` also still
publishes nothing now, so there is exactly one download URL and no ambiguity.

**Do not merge `main` into `flutter`.** Work landed on `main` earlier in 2026-08-07
was *ported* to `flutter`, not merged, precisely because the trees are not
compatible.

## Snapshot
- Path: `/home/ericaspen/projects/lu_ji` · branch **`flutter`** · remote is still
  named `hui_shi` on GitHub (rename pending)
- Flutter + Provider + just_audio + flutter_tts + sherpa_onnx (Piper) + audio_service
- Android primary; Linux for UI smoke tests only
- Ingest: TXT, EPUB, PDF (pdfrx; image-only PDFs show a clear error)
- **184 tests** (2 before 2026-08-07), `flutter analyze` clean

## Current Status (2026-08-07)

A large stretch landed on `flutter`. All of it is verified by tests and a local
release build; **almost none of it has been verified on the device.**

### Reading quality (ported from `main`, adapted)
- `cleanText` collapsed every newline, so nothing downstream could see a line, a
  paragraph or a list item. Fixed — that was the root cause of "George E. P. Box"
  being read as three fragments.
- `splitSentences` replaces the old `[.!?]`+space regex: no breaks on initials,
  dotted acronyms, titles, spaced ellipses or reference abbreviations. Measured
  against pragmatic_segmenter's 52 **Golden Rules**, kept as a test corpus with a
  ratchet (45/52; the 7 unsupported are declared with reasons).
- `list_detector.dart` — a list item is its own chunk. Three guards stop it
  shredding prose: the run must start at index 0, values must be consecutive and of
  one kind, items must have content.
- `speech_normalizer.dart` + `number_speech.dart` — rules chosen by **running
  espeak-ng**, the phonemiser Piper uses, not from docs. It reads `$100.00` as
  "dollar one hundred zero zero", `1,000` as "one zero zero zero", `2026-08-06` as
  "…dash zero eight dash zero six", `Chapter IV` as "chapter **roman** four".
  Strategy is *restructure, don't spell*: emit `100 dollars`, because espeak says
  "one hundred dollars" for that.
- `front_matter.dart` — Gutenberg wrapper by its markers (**19,305 chars** on *The
  Art of War*, ~25 min of spoken licence), publisher boilerplate and the table of
  contents by heuristic, **edges only**. Region-aware: a contents *heading* opens a
  region and entry-shaped lines go until real prose. Per-chunk matching does not
  work here because chunks are sentences, so a copyright block fragments.
  **Policy (owner's choice): skip copyright + TOC, keep title page, byline,
  dedication.**
- `page_map.dart` — navigate by the **printed** page. The folio is read by
  `printedPageNumberFromText` *before* `stripRepeatedHeadersFooters` deletes it.
  Anchors ride in the text as `[Pg N]` markers so they survive cleaning, chunking
  and the re-chunk that happens when another PDF batch loads. EPUB `pagebreak`
  anchors become the same marker. A page number is metadata — **never invented**;
  a book without them shows no page control.

### Playback and lifecycle
- **Background audio** (`audio_service`): playback died when the screen went off
  because nothing kept the process alive. Foreground service + media session +
  lock-screen controls. `MainActivity` was rebased `FlutterActivity` →
  `AudioServiceActivity` (share-intent handling intact).
- Chunks are **one per paragraph**, not packed to `maxLen`. First chunk on a real
  document went 1919 → 77 chars (~25× faster to first audio).
- `rescaleChunkIndex` — a saved position is a bare chunk index, and improving the
  splitter changed one book's count by **22%**. Positions are rescaled by the stored
  `totalChunks`, so chunking can change again safely.
- Progress saves are coalesced (5s) and **flushed** on pause, stop, dispose, app
  background, and before loading another book. A manual seek now saves too — before,
  a book that was *read* rather than listened to never recorded a place.
- Auto-scroll yields for 6s after the reader touches the list.

### Self-update
`AppUpdater` polls `luji-latest.json` and compares `version_code` to the running
build. Quiet check at app start (in `LuJiApp`, behind a `navigatorKey` — **not** on
a screen; it was on `LibraryScreen` and never ran, because `/` is the reader here).
Manual button in the library. Needs `REQUEST_INSTALL_PACKAGES`, the ota_update
FileProvider, `res/xml/filepaths.xml`, and **core library desugaring** in
`build.gradle.kts` (the release build fails at `checkReleaseAarMetadata` without it).

## ⚠ Not verified on the device
Everything above passes tests; the following can only be judged by ear or on the
phone:
1. **Does Piper sound choppy** now that a document makes ~57 chunks where it made 4?
   The lever is a length floor in `chunkText`.
2. **Does folio detection survive a real PDF?** Tested against synthetic page text.
   If the page button does not appear, no numbers were found — `printedPageNumberFromText`
   is the one function to tune.
3. **Does background playback actually survive a locked screen**, with working
   lock-screen controls? That is the entire point of the audio_service change.
4. **Manual scrolling.** The follow-along no longer fights the hand, but the list also
   sits inside a `SelectionArea`, where a drag can be taken as a text selection.
   **If scrolling still fails while nothing is playing, it is the `SelectionArea`** —
   that cause is untouched.

## Open / deferred
- No audible pause *between* paragraphs inside one chunk (`sanitizeForTts` flattens
  the blank line). Would need silence injection or finer chunks.
- Golden Rules still unsupported: 18, 41, 42, 43, 47, 51, 52 — declared with reasons
  in `test/golden_rules_test.dart`.
- Speed parity between Piper and System TTS at the same slider value.
- No export/backup of library data.
- GitHub repo still named `hui_shi`.

## Operational notes
- **Never `adb uninstall`** — wipes library, bookmarks, settings.
- Package `com.example.lu_ji`. CI signs release with the **debug key**, so an APK
  built elsewhere will not upgrade in place.
- CI builds on push to `flutter` and publishes `luji-latest.apk` **and**
  `luji-latest.json` beside it. The names must agree or the updater offers a build it
  cannot download.

```bash
flutter test              # 184 tests
flutter analyze
flutter build apk --release   # verify natives BEFORE pushing; CI failures here are slow
```

Download: https://confucius.monolithstudio.art/downloads/luji-latest.apk
