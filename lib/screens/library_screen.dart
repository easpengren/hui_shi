import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../state/reader_state.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, state, _) => Scaffold(
        appBar: AppBar(title: const Text('Library')),
        body: state.library.isEmpty
            ? const Center(
                child: Text('No books yet. Open a file on the Reader screen.'),
              )
            : ListView.builder(
                itemCount: state.library.length,
                itemBuilder: (context, index) {
                  final entry = state.library[index];
                  return _LibraryTile(
                    entry: entry,
                    onOpen: () async {
                      await state.openFromLibrary(entry);
                      if (context.mounted) Navigator.pop(context);
                    },
                    onDelete: () => state.removeFromLibrary(entry.id),
                  );
                },
              ),
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  final LibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _LibraryTile({
    required this.entry,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final progress = entry.totalChunks > 0
        ? entry.lastChunkIndex / entry.totalChunks
        : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.sourceType.toUpperCase()} • '
              'Chunk ${entry.lastChunkIndex + 1} / ${entry.totalChunks}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 3,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Open & resume',
              onPressed: onOpen,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove from library',
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Remove book?'),
                  content: Text(
                    'Remove "${entry.title}" from your library? The file is not deleted.',
                  ),
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
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
