import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tts_engine.dart';
import '../playback/playback_controller.dart';
import '../state/reader_state.dart';

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
              icon: const Icon(Icons.library_books),
              tooltip: 'Library',
              onPressed: () => Navigator.pushNamed(context, '/library'),
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
            Expanded(child: _ContentArea(state: state)),
            _TtsControls(state: state),
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
  final ScrollController _scroll = ScrollController();
  // One key per chunk so we can measure item positions.
  final List<GlobalKey> _keys = [];
  int _lastScrolledIndex = -1;

  @override
  void didUpdateWidget(_ContentArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    _maybeScrollToCurrent();
  }

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  void _syncKeys() {
    final needed = widget.state.chunks.length;
    while (_keys.length < needed) {
      _keys.add(GlobalKey());
    }
    if (_keys.length > needed) _keys.removeRange(needed, _keys.length);
  }

  void _maybeScrollToCurrent() {
    final idx = widget.state.currentChunkIndex;
    if (idx == _lastScrolledIndex) return;
    if (_keys.isEmpty || idx >= _keys.length) return;
    _lastScrolledIndex = idx;
    // Schedule after the frame so the item is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _keys[idx];
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.3, // place item ~30% from top
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    if (state.loadState == LoadState.loading) {
      return const Center(child: CircularProgressIndicator());
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Open a TXT, PDF, or EPUB file to begin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    _syncKeys();
    _maybeScrollToCurrent();

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: state.chunks.length,
      itemBuilder: (context, index) {
        final isCurrent = index == state.currentChunkIndex;
        return GestureDetector(
          key: _keys[index],
          onTap: () => state.seekAndPlay(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCurrent
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              state.chunks[index],
              style: TextStyle(
                fontSize: 17,
                height: 1.6,
                color: isCurrent
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TtsControls extends StatelessWidget {
  final ReaderState state;
  const _TtsControls({required this.state});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(
        'TTS: ${state.selectedEngine.displayName}',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              // Speed slider
              Row(
                children: [
                  const Text('Speed'),
                  Expanded(
                    child: Slider(
                      min: 0.5,
                      max: 2.0,
                      divisions: 6,
                      value: state.playbackSpeed,
                      label: '${state.playbackSpeed.toStringAsFixed(1)}×',
                      onChanged: state.setSpeed,
                    ),
                  ),
                  Text('${state.playbackSpeed.toStringAsFixed(1)}×'),
                ],
              ),
            ],
          ),
        ),
      ],
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
              : ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text('Download ${state.selectedVoice}'),
                  onPressed: state.downloadPiperModel,
                )
        else
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 16),
              const SizedBox(width: 4),
              Text(
                'Model ready',
                style: Theme.of(context).textTheme.labelSmall,
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
    final isPlaying = state.playbackStatus == PlaybackStatus.playing;
    final isPaused = state.playbackStatus == PlaybackStatus.paused;
    final isLoading = state.playbackStatus == PlaybackStatus.loading;
    final canPlay = state.chunks.isNotEmpty && !isLoading;

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
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    iconSize: 40,
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: canPlay
                        ? () {
                            if (isPlaying) {
                              state.pause();
                            } else if (isPaused) {
                              state.resume();
                            } else {
                              state.play();
                            }
                          }
                        : null,
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
