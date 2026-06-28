import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_update_ui.dart';
import '../models/book.dart';
import '../state/reader_state.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    // Quiet update check on launch (the library is the home screen).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkAndOfferUpdate(context);
    });
  }

  Future<void> _openBook(ReaderState state, Future<void> Function() load) async {
    try {
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open this book: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    if (state.loadState == LoadState.error || state.chunks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.errorMessage ??
              'Could not open this book — the file may have moved or been deleted.'),
        ),
      );
      return;
    }
    Navigator.pushNamed(context, '/reader');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, state, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          actions: [
            IconButton(
              icon: const Icon(Icons.system_update_outlined),
              tooltip: 'Check for updates',
              onPressed: () => checkAndOfferUpdate(context, manual: true),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openBook(state, state.pickFile),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Open a book'),
        ),
        body: state.library.isEmpty
            ? _EmptyLibrary(onOpen: () => _openBook(state, state.pickFile))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: state.library.length,
                itemBuilder: (context, index) {
                  final entry = state.library[index];
                  return _LibraryCard(
                    entry: entry,
                    onOpen: () =>
                        _openBook(state, () => state.openFromLibrary(entry)),
                    onDelete: () => state.removeFromLibrary(entry.id),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('Your shelf is empty', style: tt.headlineSmall),
            const SizedBox(height: 8),
            Text('Open a TXT, EPUB, or PDF to read and listen.',
                style: tt.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Open a book'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.entry,
    required this.onOpen,
    required this.onDelete,
  });

  final LibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final progress = entry.totalChunks > 0
        ? (entry.lastChunkIndex / entry.totalChunks).clamp(0.0, 1.0)
        : 0.0;
    final pct = (progress * 100).round();
    final started = entry.lastChunkIndex > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title,
                        style: tt.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.sourceType.toUpperCase()}'
                      '${started ? '  ·  $pct% read' : '  ·  not started'}'
                      '  ·  ${_lastOpened(entry.lastOpenedMs)}',
                      style: tt.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: cs.surface,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    icon: Icon(started
                        ? Icons.play_circle_outline
                        : Icons.menu_book_outlined),
                    tooltip: started ? 'Resume' : 'Read',
                    onPressed: onOpen,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove',
                    onPressed: () => _confirmDelete(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove book?'),
        content: Text(
            'Remove "${entry.title}" from your library? The file itself is not deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  String _lastOpened(int ms) {
    if (ms <= 0) return 'never opened';
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
