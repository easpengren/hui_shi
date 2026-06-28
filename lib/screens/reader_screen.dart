import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tts_engine.dart';
import '../playback/playback_controller.dart';
import '../state/reader_state.dart';

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
                onPressed: () => Navigator.maybePop(context),
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

  @override
  void dispose() {
    _scroll.dispose();
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
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.title, style: tt.titleSmall, overflow: TextOverflow.ellipsis),
            if (state.currentChapterTitle.isNotEmpty)
              Text(state.currentChapterTitle,
                  style: tt.titleMedium, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
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
      body: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 120),
        itemCount: chapterChunks.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                state.currentChapterTitle.isEmpty ? state.title : state.currentChapterTitle,
                style: tt.headlineSmall,
              ),
            );
          }
          final idx = i - 1;
          final key = _keys.putIfAbsent(idx, () => GlobalKey());
          final isActive = idx == active;
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
              child: Text(
                chapterChunks[idx],
                style: bodyStyle,
                textAlign: TextAlign.justify,
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: _ReaderBar(state: state),
    );
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
            Text('${(state.progress * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.headphones_outlined),
              tooltip: 'Voice & speed',
              onPressed: () => _showVoiceSheet(context, state),
            ),
          ],
        ),
      ),
    );
  }

  void _showVoiceSheet(BuildContext context, ReaderState state) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          final tt = Theme.of(context).textTheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Read aloud', style: tt.titleMedium),
                const SizedBox(height: 12),
                SegmentedButton<TtsEngine>(
                  segments: TtsEngine.values
                      .map((e) => ButtonSegment(value: e, label: Text(e.displayName)))
                      .toList(),
                  selected: {state.selectedEngine},
                  onSelectionChanged: (s) {
                    state.setEngine(s.first);
                    setSheet(() {});
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Speed'),
                    Expanded(
                      child: Slider(
                        value: state.playbackSpeed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 6,
                        label: '${state.playbackSpeed.toStringAsFixed(1)}×',
                        onChanged: (v) {
                          state.setSpeed(v);
                          setSheet(() {});
                        },
                      ),
                    ),
                    Text('${state.playbackSpeed.toStringAsFixed(1)}×'),
                  ],
                ),
                if (state.selectedEngine == TtsEngine.piper) ...[
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: state.selectedVoice,
                    isExpanded: true,
                    items: kPiperVoices
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        state.setVoice(v);
                        setSheet(() {});
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
                                setSheet(() {});
                              },
                              icon: const Icon(Icons.download),
                              label: Text('Download ${state.selectedVoice}'),
                            ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
