class LibraryEntry {
  final String id;
  final String title;
  final String filePath;
  final String sourceType; // txt, pdf, epub
  final int lastChunkIndex;
  final int totalChunks;
  final int lastOpenedMs;

  const LibraryEntry({
    required this.id,
    required this.title,
    required this.filePath,
    required this.sourceType,
    required this.lastChunkIndex,
    required this.totalChunks,
    required this.lastOpenedMs,
  });

  LibraryEntry copyWith({int? lastChunkIndex, int? lastOpenedMs}) =>
      LibraryEntry(
        id: id,
        title: title,
        filePath: filePath,
        sourceType: sourceType,
        lastChunkIndex: lastChunkIndex ?? this.lastChunkIndex,
        totalChunks: totalChunks,
        lastOpenedMs: lastOpenedMs ?? this.lastOpenedMs,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filePath': filePath,
    'sourceType': sourceType,
    'lastChunkIndex': lastChunkIndex,
    'totalChunks': totalChunks,
    'lastOpenedMs': lastOpenedMs,
  };

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    filePath: json['filePath'] as String,
    sourceType: json['sourceType'] as String,
    lastChunkIndex: (json['lastChunkIndex'] as num).toInt(),
    totalChunks: (json['totalChunks'] as num).toInt(),
    lastOpenedMs: (json['lastOpenedMs'] as num).toInt(),
  );
}
