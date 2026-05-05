import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/tts_engine.dart';
import '../playback/playback_controller.dart';
import '../state/reader_state.dart';
import '../widgets/classical_chrome.dart';

void _showBookmarkSheet(BuildContext context, ReaderState state) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BookmarkSheet(state: state),
  );
}

class _BookmarkSheet extends StatefulWidget {
  final ReaderState state;
  const _BookmarkSheet({required this.state});

  @override
  State<_BookmarkSheet> createState() => _BookmarkSheetState();
}

class _BookmarkSheetState extends State<_BookmarkSheet> {
  final _labelController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.state,
      child: Consumer<ReaderState>(
        builder: (context, state, _) {
          final bookmarks = state.currentBookmarks;
          return SafeArea(
            child: Padding(
              padding: MediaQuery.of(context).viewInsets,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          'Bookmarks',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Text(
                          'Chunk ${state.currentChunkIndex + 1}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.bookmark_add, size: 16),
                          label: const Text('Add'),
                          onPressed: () async {
                            final label = _labelController.text.trim();
                            await state.addBookmark(label);
                            _labelController.clear();
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextField(
                      controller: _labelController,
                      decoration: const InputDecoration(
                        hintText: 'Label (optional)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) async {
                        await state.addBookmark(_labelController.text.trim());
                        _labelController.clear();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (bookmarks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No bookmarks yet.'),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: bookmarks.length,
                        itemBuilder: (context, i) {
                          final bm = bookmarks[i];
                          return ListTile(
                            leading: const Icon(Icons.bookmark_outline),
                            title: Text(bm.label),
                            subtitle: Text('Chunk ${bm.chunkIndex + 1}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  state.removeBookmark(bm.chunkIndex),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              state.jumpToBookmark(bm.chunkIndex);
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, state, _) => Scaffold(
        appBar: AppBar(
          title: Text(
            state.title.isEmpty ? 'Lu Ji' : state.title,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: Icon(
                state.themeMode == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
              tooltip: state.themeMode == ThemeMode.dark
                  ? 'Switch to light mode'
                  : 'Switch to dark mode',
              onPressed: state.toggleThemeMode,
            ),
            if (state.chunks.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.bookmark_add_outlined),
                tooltip: 'Bookmarks',
                onPressed: () => _showBookmarkSheet(context, state),
              ),
            IconButton(
              icon: const Icon(Icons.library_books),
              tooltip: 'Library',
              onPressed: () => Navigator.pushNamed(context, '/library'),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => Navigator.pushNamed(context, '/settings'),
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Open file',
              onPressed: state.loadState == LoadState.loading
                  ? null
                  : state.pickFile,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: DossierHeader(
                title: state.title.isEmpty ? 'The Four Books' : state.title,
                subtitle: state.chunks.isEmpty
                    ? 'Curated reading and listening'
                    : 'Chunk ${state.currentChunkIndex + 1} of ${state.chunks.length}',
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: _ContentArea(state: state),
              ),
            ),
            _PlaybackBar(state: state),
          ],
        ),
      ),
    );
  }
}

class _ContentArea extends StatefulWidget {
  final ReaderState state;
  const _ContentArea({required this.state});

  @override
  State<_ContentArea> createState() => _ContentAreaState();
}

class _ContentAreaState extends State<_ContentArea> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final TextEditingController _searchController = TextEditingController();
  final List<int> _searchMatches = [];
  int _searchMatchPos = -1;
  int _lastScrolledIndex = -1;
  String _lastSearchQuery = '';

  @override
  void didUpdateWidget(_ContentArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchController.text.trim().isNotEmpty) {
      _rebuildSearchMatches(_searchController.text);
    }
    // Only auto-scroll when the playing chunk actually changes.
    if (widget.state.currentChunkIndex != oldWidget.state.currentChunkIndex) {
      _maybeScrollToCurrent();
    }
  }

  @override
  void initState() {
    super.initState();
  }

  void _maybeScrollToCurrent({bool force = false}) {
    final idx = widget.state.currentChunkIndex;
    if (!force && idx == _lastScrolledIndex) return;
    if (widget.state.chunks.isEmpty || idx >= widget.state.chunks.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToIndex(idx, animated: true);
    });
  }

  void _scrollToIndex(int idx, {required bool animated}) {
    if (!_itemScrollController.isAttached) return;
    if (idx < 0 || idx >= widget.state.chunks.length) return;

    _lastScrolledIndex = idx;
    if (animated) {
      _itemScrollController.scrollTo(
        index: idx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
    } else {
      _itemScrollController.jumpTo(index: idx, alignment: 0.3);
    }
  }

  void _rebuildSearchMatches(String query) {
    final normalized = query.trim().toLowerCase();
    final queryChanged = normalized != _lastSearchQuery;
    _lastSearchQuery = normalized;

    _searchMatches.clear();
    if (normalized.isEmpty) {
      if (queryChanged) _searchMatchPos = -1;
      if (mounted) setState(() {});
      return;
    }

    for (var i = 0; i < widget.state.chunks.length; i++) {
      if (widget.state.chunks[i].toLowerCase().contains(normalized)) {
        _searchMatches.add(i);
      }
    }

    if (queryChanged) {
      // User typed a new query — reset position to first match at/after current chunk.
      if (_searchMatches.isNotEmpty) {
        final current = widget.state.currentChunkIndex;
        final firstAtOrAfter = _searchMatches.indexWhere((i) => i >= current);
        _searchMatchPos = firstAtOrAfter >= 0 ? firstAtOrAfter : 0;
      } else {
        _searchMatchPos = -1;
      }
    } else {
      // State changed (chunk advanced) but query is the same — keep position, just clamp.
      _searchMatchPos = _searchMatchPos.clamp(-1, _searchMatches.length - 1);
    }

    if (mounted) setState(() {});
  }

  Future<void> _goToSearchMatch({required bool forward}) async {
    if (_searchMatches.isEmpty) return;
    if (_searchMatchPos < 0) {
      _searchMatchPos = 0;
    } else {
      final delta = forward ? 1 : -1;
      _searchMatchPos =
          (_searchMatchPos + delta + _searchMatches.length) %
          _searchMatches.length;
    }

    final idx = _searchMatches[_searchMatchPos];
    await widget.state.seekToChunk(idx);
    _scrollToIndex(idx, animated: true);
    if (mounted) setState(() {});
  }

  Future<void> _jumpToCurrent() async {
    final idx = widget.state.currentChunkIndex;
    _scrollToIndex(idx, animated: true);
  }

  TextSpan _buildChunkSpan(
    BuildContext context,
    String chunk,
    bool isCurrent,
  ) {
    final query = _searchController.text.trim();
    final baseStyle = TextStyle(
      fontSize: 17,
      height: 1.6,
      color: Theme.of(context).colorScheme.onSurface.withValues(
        alpha: isCurrent ? 1.0 : 0.75,
      ),
    );
    if (query.isEmpty) {
      return TextSpan(text: chunk, style: baseStyle);
    }

    final lowerChunk = chunk.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (true) {
      final found = lowerChunk.indexOf(lowerQuery, start);
      if (found < 0) {
        spans.add(TextSpan(text: chunk.substring(start), style: baseStyle));
        break;
      }
      if (found > start) {
        spans.add(
          TextSpan(text: chunk.substring(start, found), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: chunk.substring(found, found + query.length),
          style: baseStyle.copyWith(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.tertiary.withValues(alpha: 0.35),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = found + query.length;
    }

    return TextSpan(children: spans, style: baseStyle);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    if (state.loadState == LoadState.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              state.loadStatus.isEmpty ? 'Loading...' : state.loadStatus,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    if (state.loadState == LoadState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            state.errorMessage ?? 'Unknown error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state.chunks.isEmpty) {
      return const DossierPanel(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Open a TXT, PDF, or EPUB file to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Search in book',
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              _rebuildSearchMatches('');
                            },
                          ),
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: _rebuildSearchMatches,
                  onSubmitted: (_) => _goToSearchMatch(forward: true),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Previous match',
                onPressed: _searchMatches.isEmpty
                    ? null
                    : () => _goToSearchMatch(forward: false),
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: 'Next match',
                onPressed: _searchMatches.isEmpty
                    ? null
                    : () => _goToSearchMatch(forward: true),
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  _searchMatches.isEmpty
                      ? '0/0'
                      : '${_searchMatchPos + 1}/${_searchMatches.length}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 4),
            child: FilledButton.icon(
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('Current'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onPressed: _jumpToCurrent,
            ),
          ),
        ),
        Expanded(
          child: DossierPanel(
            padding: const EdgeInsets.all(10),
            child: ScrollablePositionedList.builder(
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: state.chunks.length,
              itemBuilder: (context, index) {
                final isCurrent = index == state.currentChunkIndex;
                return GestureDetector(
                  onTap: () => state.seekAndPlay(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Theme.of(
                              context,
                            ).colorScheme.secondary.withValues(alpha: 0.25)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: RichText(
                      text: _buildChunkSpan(
                        context,
                        state.chunks[index],
                        isCurrent,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TtsControls extends StatefulWidget {
  final ReaderState state;
  const _TtsControls({required this.state});

  @override
  State<_TtsControls> createState() => _TtsControlsState();
}

class _TtsControlsState extends State<_TtsControls> {
  double? _draftSpeed;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final sliderSpeed = _draftSpeed ?? state.playbackSpeed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: DossierPanel(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TTS: ${state.selectedEngine.displayName}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            // Engine selector
            SegmentedButton<TtsEngine>(
              segments: TtsEngine.values
                  .map(
                    (e) => ButtonSegment(
                      value: e,
                      label: Text(
                        e.displayName,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              selected: {state.selectedEngine},
              onSelectionChanged: (s) => state.setEngine(s.first),
            ),
            const SizedBox(height: 8),
            // Piper voice picker + download
            if (state.selectedEngine == TtsEngine.piper) ...[
              _PiperVoiceRow(state: state),
              const SizedBox(height: 4),
            ],
            // System voice picker
            if (state.selectedEngine == TtsEngine.system &&
                state.systemVoices.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: state.selectedSystemVoiceName.isNotEmpty
                    ? '${state.selectedSystemVoiceLocale}\u0001${state.selectedSystemVoiceName}'
                    : 'default',
                decoration: const InputDecoration(
                  labelText: 'Android voice',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: state.systemVoiceOptions
                    .map(
                      (option) => DropdownMenuItem(
                        value: option['id'],
                        child: Text(
                          option['label'] ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (selection) {
                  if (selection == null) return;
                  if (selection == 'default') {
                    state.setSystemVoice('', '');
                    return;
                  }

                  final i = selection.indexOf('\u0001');
                  if (i <= 0) return;
                  final locale = selection.substring(0, i);
                  final name = selection.substring(i + 1);
                  state.setSystemVoice(name, locale);
                },
              ),
              const SizedBox(height: 8),
            ],
            // Speed slider
            Row(
              children: [
                const Text('Speed'),
                Expanded(
                  child: Slider(
                    min: 0.1,
                    max: 2.0,
                    divisions: 19,
                    value: sliderSpeed,
                    label: '${sliderSpeed.toStringAsFixed(1)}×',
                    onChanged: (v) {
                      setState(() => _draftSpeed = v);
                    },
                    onChangeEnd: (v) async {
                      await state.setSpeed(v);
                      if (mounted) {
                        setState(() => _draftSpeed = null);
                      }
                    },
                  ),
                ),
                Text('${sliderSpeed.toStringAsFixed(1)}×'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PiperVoiceRow extends StatelessWidget {
  final ReaderState state;
  const _PiperVoiceRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: state.selectedVoice,
          decoration: const InputDecoration(
            labelText: 'Voice',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: kPiperVoices
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: (v) {
            if (v != null) state.setVoice(v);
          },
        ),
        const SizedBox(height: 6),
        if (!state.piperModelDownloaded)
          state.isDownloading
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: state.downloadProgress),
                    const SizedBox(height: 2),
                    Text(
                      state.downloadStatus,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: Text('Download ${state.selectedVoice}'),
                      onPressed: state.downloadPiperModel,
                    ),
                    if (state.downloadStatus.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        state.downloadStatus,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ],
                )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Model ready',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: state.downloadPiperModel,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Re-download'),
                  ),
                ],
              ),
              if (state.downloadStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    state.downloadStatus,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _PlaybackBar extends StatelessWidget {
  final ReaderState state;
  const _PlaybackBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final liveStatus = state.livePlaybackStatus;
    final isPlaying = liveStatus == PlaybackStatus.playing;
    final isLoading = liveStatus == PlaybackStatus.loading;
    final canPlay = state.chunks.isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            // Chunk counter
            Expanded(
              child: state.chunks.isEmpty
                  ? const SizedBox()
                  : Text(
                      'Chunk ${state.currentChunkIndex + 1} / ${state.chunks.length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
            ),
            // Prev
            IconButton(
              icon: const Icon(Icons.skip_previous),
              onPressed: canPlay && state.currentChunkIndex > 0
                  ? () => state.seekToChunk(state.currentChunkIndex - 1)
                  : null,
            ),
            // Play / Pause
            isLoading
                ? IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.stop_circle_outlined),
                    tooltip: 'Stop loading',
                    onPressed: state.stop,
                  )
                : IconButton(
                    iconSize: 40,
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: canPlay ? state.togglePlayPause : null,
                  ),
            // Next
            IconButton(
              icon: const Icon(Icons.skip_next),
              onPressed:
                  canPlay && state.currentChunkIndex < state.chunks.length - 1
                  ? () => state.seekToChunk(state.currentChunkIndex + 1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
