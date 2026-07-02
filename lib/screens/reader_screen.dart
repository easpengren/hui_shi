import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tts_engine.dart';
import '../playback/playback_controller.dart';
import '../state/reader_state.dart';
import '../tts/system_tts_client.dart';

/// A chapter-at-a-time reader in the Four Books style: serif-calm typography on
/// paper, a table of contents, font sizing, and read-aloud where the spoken
/// chunk is highlighted in place and any paragraph can be tapped to listen.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, state, _) {
        if (state.loadState == LoadState.loading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (state.chunks.isEmpty) {
          return _EmptyState(state: state);
        }
        return _ReaderView(state: state);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.state});
  final ReaderState state;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Lu Ji')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nothing open', style: tt.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Open a book to read and listen.',
                style: tt.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: state.pickFile,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Open a book'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text('Library'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderView extends StatefulWidget {
  const _ReaderView({required this.state});
  final ReaderState state;

  @override
  State<_ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<_ReaderView> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _lastActive = -1;

  // ── In-chapter search ──────────────────────────────────────────────────────
  bool _searching = false;
  final _searchCtl = TextEditingController();
  String _query = '';
  List<int> _matches = const [];
  int _matchPos = -1;

  void _closeSearch() => setState(() {
        _searching = false;
        _query = '';
        _searchCtl.clear();
        _matches = const [];
        _matchPos = -1;
      });

  void _runSearch(String raw) {
    final q = raw.trim().toLowerCase();
    final chunks = widget.state.currentChapterChunks;
    final matches = <int>[];
    if (q.isNotEmpty) {
      for (var i = 0; i < chunks.length; i++) {
        if (chunks[i].toLowerCase().contains(q)) matches.add(i);
      }
    }
    setState(() {
      _query = q;
      _matches = matches;
      _matchPos = matches.isEmpty ? -1 : 0;
    });
    if (_matchPos >= 0) _scrollToChunk(_matches[_matchPos]);
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _matchPos = (_matchPos + delta) % _matches.length);
    _scrollToChunk(_matches[_matchPos]);
  }

  void _scrollToChunk(int idx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[idx]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.3,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  void _autoScrollToActive(int active) {
    if (active < 0 || active == _lastActive) return;
    _lastActive = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _keys[active];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final chapterChunks = state.currentChapterChunks;
    final active = state.activeChunkInChapter;
    _autoScrollToActive(active);

    final bodyStyle = tt.bodyLarge!.copyWith(
      fontSize: (tt.bodyLarge!.fontSize ?? 18) * state.fontScale,
      height: 1.7,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.local_library_outlined),
          tooltip: 'Library',
          onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
        ),
        title: _searching
            ? TextField(
                controller: _searchCtl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search this chapter…',
                  border: InputBorder.none,
                ),
                onChanged: _runSearch,
                onSubmitted: (_) => _stepMatch(1),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.title,
                      style: tt.titleSmall, overflow: TextOverflow.ellipsis),
                  if (state.currentChapterTitle.isNotEmpty)
                    Text(state.currentChapterTitle,
                        style: tt.titleMedium, overflow: TextOverflow.ellipsis),
                ],
              ),
        actions: _searching
            ? [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _matches.isEmpty
                          ? (_query.isEmpty ? '' : '0/0')
                          : '${_matchPos + 1}/${_matches.length}',
                      style: tt.labelLarge,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: 'Previous match',
                  onPressed: _matches.isEmpty ? null : () => _stepMatch(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Next match',
                  onPressed: _matches.isEmpty ? null : () => _stepMatch(1),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close search',
                  onPressed: _closeSearch,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search',
                  onPressed: () => setState(() => _searching = true),
                ),
                IconButton(
                  icon: const Icon(Icons.text_fields),
                  tooltip: 'Text size',
                  onPressed: () => _showFontSheet(context, state),
                ),
                IconButton(
                  icon: const Icon(Icons.toc),
                  tooltip: 'Contents',
                  onPressed: () => _showContents(context, state),
                ),
              ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(
            value: state.progress,
            minHeight: 2,
            backgroundColor: cs.surface,
          ),
        ),
      ),
      // SelectionArea makes the reading text selectable + copyable; single taps
      // still reach each paragraph's InkWell to play it.
      body: SelectionArea(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 120),
          itemCount: chapterChunks.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  state.currentChapterTitle.isEmpty
                      ? state.title
                      : state.currentChapterTitle,
                  style: tt.headlineSmall,
                ),
              );
            }
            final idx = i - 1;
            final key = _keys.putIfAbsent(idx, () => GlobalKey());
            final isActive = idx == active;
            final isCurrentMatch =
                _matchPos >= 0 && _matches[_matchPos] == idx;
            return Container(
              key: key,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: isActive
                  ? BoxDecoration(
                      color: cs.secondary.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6),
                    )
                  : null,
              padding: isActive
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                  : EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => state.playChapterChunk(idx),
                child: _chunkText(
                    chapterChunks[idx], bodyStyle, cs, isCurrentMatch),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _ReaderBar(state: state),
    );
  }

  /// A paragraph's text, with search-query occurrences highlighted (the current
  /// match a touch stronger). Plain [Text] when there's no active query.
  Widget _chunkText(
      String text, TextStyle style, ColorScheme cs, bool isCurrentMatch) {
    if (_query.isEmpty) {
      return Text(text, style: style, textAlign: TextAlign.justify);
    }
    final lower = text.toLowerCase();
    final hl = style.copyWith(
      backgroundColor:
          (isCurrentMatch ? cs.primary : cs.tertiary).withValues(alpha: 0.35),
      fontWeight: FontWeight.w600,
    );
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final i = lower.indexOf(_query, start);
      if (i < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (i > start) spans.add(TextSpan(text: text.substring(start, i)));
      spans.add(TextSpan(
          text: text.substring(i, i + _query.length), style: hl));
      start = i + _query.length;
    }
    return Text.rich(TextSpan(style: style, children: spans),
        textAlign: TextAlign.justify);
  }

  void _showFontSheet(BuildContext context, ReaderState state) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Text size', style: Theme.of(context).textTheme.titleMedium),
            StatefulBuilder(
              builder: (context, setSheet) => Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Slider(
                      value: state.fontScale,
                      min: 0.8,
                      max: 1.8,
                      divisions: 10,
                      label: '${(state.fontScale * 100).round()}%',
                      onChanged: (v) {
                        state.setFontScale(v);
                        setSheet(() {});
                      },
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 26)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContents(BuildContext context, ReaderState state) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Contents', style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: state.chapters.length,
                itemBuilder: (context, i) {
                  final selected = i == state.currentChapterIndex;
                  return ListTile(
                    title: Text(
                      state.chapters[i].title,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      state.goToChapter(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderBar extends StatelessWidget {
  const _ReaderBar({required this.state});
  final ReaderState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPlaying = state.playbackStatus == PlaybackStatus.playing;
    final isPaused = state.playbackStatus == PlaybackStatus.paused;
    final isLoading = state.playbackStatus == PlaybackStatus.loading;
    final hasPrev = state.currentChapterIndex > 0;
    final hasNext = state.currentChapterIndex < state.chapters.length - 1;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous),
              tooltip: 'Previous chapter',
              onPressed: hasPrev ? state.prevChapter : null,
            ),
            IconButton.filled(
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              tooltip: isPlaying ? 'Pause' : 'Listen',
              onPressed: isLoading
                  ? null
                  : () {
                      if (isPlaying) {
                        state.pause();
                      } else if (isPaused) {
                        state.resume();
                      } else {
                        state.play();
                      }
                    },
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              tooltip: 'Next chapter',
              onPressed: hasNext ? state.nextChapter : null,
            ),
            const Spacer(),
            // Speed lives in the bar — a small menu, applied live (changing it
            // restarts the current sentence), so it never covers the controls.
            PopupMenuButton<double>(
              tooltip: 'Speed',
              initialValue: state.playbackSpeed,
              onSelected: state.setSpeed,
              itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                  .map((s) => PopupMenuItem(value: s, child: Text(_spd(s))))
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(_spd(state.playbackSpeed),
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.record_voice_over_outlined),
              tooltip: 'Voice',
              onPressed: () => _showVoiceDialog(context, state),
            ),
          ],
        ),
      ),
    );
  }

  static String _spd(double s) => '${s % 1 == 0 ? s.toInt() : s}×';

  // A centered dialog (not a bottom sheet) so it never covers the play bar.
  // Speed isn't here — it's inline in the bar now.
  void _showVoiceDialog(BuildContext context, ReaderState state) {
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) {
          final tt = Theme.of(context).textTheme;
          return AlertDialog(
            title: const Text('Read aloud'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<TtsEngine>(
                  segments: TtsEngine.values
                      .map((e) => ButtonSegment(value: e, label: Text(e.displayName)))
                      .toList(),
                  selected: {state.selectedEngine},
                  onSelectionChanged: (s) {
                    state.setEngine(s.first);
                    setDialog(() {});
                  },
                ),
                if (state.selectedEngine == TtsEngine.system) ...[
                  const SizedBox(height: 12),
                  if (state.systemVoices.isEmpty)
                    Text('No installed system voices found. Add voices in '
                        'your device TTS settings.',
                        style: tt.bodySmall)
                  else
                    DropdownButton<String>(
                      value: SystemTtsClient.encodeVoiceId(
                          state.systemVoiceName, state.systemVoiceLocale),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                            value: SystemTtsClient.defaultVoiceId,
                            child: Text('Device default voice')),
                        ...state.systemVoices.map((v) => DropdownMenuItem(
                              value: SystemTtsClient.encodeVoiceMap(v),
                              child: Text(SystemTtsClient.voiceLabel(v),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        final voice = SystemTtsClient.decodeVoiceId(v);
                        if (voice == null) return;
                        state.setSystemVoice(voice.$1, voice.$2);
                        setDialog(() {});
                      },
                    ),
                ],
                if (state.selectedEngine == TtsEngine.piper) ...[
                  const SizedBox(height: 12),
                  DropdownButton<String>(
                    value: state.selectedVoice,
                    isExpanded: true,
                    items: kPiperVoices
                        .map((v) => DropdownMenuItem(
                            value: v, child: Text(piperVoiceLabel(v))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        state.setVoice(v);
                        setDialog(() {});
                      }
                    },
                  ),
                  if (!state.piperModelDownloaded)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: state.isDownloading
                          ? Row(children: [
                              const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(state.downloadStatus, style: tt.bodySmall)),
                            ])
                          : OutlinedButton.icon(
                              onPressed: () async {
                                await state.downloadPiperModel();
                                setDialog(() {});
                              },
                              icon: const Icon(Icons.download),
                              label: Text('Download ${state.selectedVoice}'),
                            ),
                    ),
                ],
                if (state.ttsError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Playback error: ${state.ttsError}',
                    style: tt.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}
