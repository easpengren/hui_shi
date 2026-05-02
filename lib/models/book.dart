class Bookmark {
  final int chunkIndex;
  final String label;
  final int createdMs;

  const Bookmark({
    required this.chunkIndex,
    required this.label,
    required this.createdMs,
  });

  Map<String, dynamic> toJson() => {
    'chunkIndex': chunkIndex,
    'label': label,
    'createdMs': createdMs,
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    chunkIndex: (json['chunkIndex'] as num).toInt(),
    label: json['label'] as String? ?? '',
    createdMs: (json['createdMs'] as num).toInt(),
  );
}

class LibraryEntry {
  final String id;
  final String title;
  final String filePath;
  final String sourceType;
  final int lastChunkIndex;
  final int totalChunks;
  final int lastOpenedMs;
  final List<Bookmark> bookmarks;

  const LibraryEntry({
    required this.id,
    required this.title,
    required this.filePath,
    required this.sourceType,
    required this.lastChunkIndex,
    required this.totalChunks,
    required this.lastOpenedMs,
    this.bookmarks = const [],
  });

  LibraryEntry copyWith({
    int? lastChunkIndex,
    int? lastOpenedMs,
    int? totalChunks,
    List<Bookmark>? bookmarks,
  }) => LibraryEntry(
    id: id,
    title: title,
    filePath: filePath,
    sourceType: sourceType,
    lastChunkIndex: lastChunkIndex ?? this.lastChunkIndex,
    totalChunks: totalChunks ?? this.totalChunks,
    lastOpenedMs: lastOpenedMs ?? this.lastOpenedMs,
    bookmarks: bookmarks ?? this.bookmarks,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filePath': filePath,
    'sourceType': sourceType,
    'lastChunkIndex': lastChunkIndex,
    'totalChunks': totalChunks,
    'lastOpenedMs': lastOpenedMs,
    'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
  };

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    filePath: json['filePath'] as String,
    sourceType: json['sourceType'] as String,
    lastChunkIndex: (json['lastChunkIndex'] as num).toInt(),
    totalChunks: (json['totalChunks'] as num).toInt(),
    lastOpenedMs: (json['lastOpenedMs'] as num).toInt(),
    bookmarks: (json['bookmarks'] as List<dynamic>? ?? [])
        .map((b) => Bookmark.fromJson(b as Map<String, dynamic>))
        .toList(),
  );
}
