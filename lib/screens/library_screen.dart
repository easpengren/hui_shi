import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../state/reader_state.dart';
import '../widgets/classical_chrome.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, state, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
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
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DossierHeader(
                title: 'Library',
                subtitle: 'Canonical works in your local reading corpus',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: state.library.isEmpty
                    ? const Center(
                        child: Text(
                          'No books yet. Open a file from the reader to begin.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: state.library.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
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
            ],
          ),
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
    final hasBookmarks = entry.bookmarks.isNotEmpty;

    return DossierPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${entry.sourceType.toUpperCase()} • Chunk ${entry.lastChunkIndex + 1} / ${entry.totalChunks}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (hasBookmarks) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.bookmark, size: 12,
                            color: Theme.of(context).colorScheme.secondary),
                        const SizedBox(width: 2),
                        Text(
                          '${entry.bookmarks.length}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 3),
                ],
              ),
            ),
            trailing: Wrap(
              spacing: 2,
              children: [
                IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'Open & resume', onPressed: onOpen),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove from library',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Remove book?'),
                      content: Text('Remove "${entry.title}" from your library? The file is not deleted.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
          ),
          if (hasBookmarks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: entry.bookmarks.map((bm) {
                  return ActionChip(
                    avatar: const Icon(Icons.bookmark_outline, size: 14),
                    label: Text(
                      bm.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                    tooltip: 'Chunk ${bm.chunkIndex + 1}',
                    onPressed: () async {
                      final state = context.read<ReaderState>();
                      await state.openFromLibrary(entry);
                      if (context.mounted) {
                        Navigator.pop(context);
                        await state.jumpToBookmark(bm.chunkIndex);
                      }
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
