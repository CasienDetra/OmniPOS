class FileRecord {
  const FileRecord({
    required this.filename,
    required this.originalname,
    required this.mimetype,
    required this.size,
    required this.encoding,
    required this.path,
    required this.createdAt,
  });

  final String filename;
  final String originalname;
  final String mimetype;
  final int size;
  final String encoding;
  final String path;
  final DateTime createdAt;

  Map<String, Object?> toDocument() => {
    'filename': filename,
    'originalname': originalname,
    'mimetype': mimetype,
    'size': size,
    'encoding': encoding,
    'path': path,
    'created_at': createdAt.toUtc(),
  };

  static FileRecord? fromDocument(Map<String, dynamic>? doc) {
    if (doc == null) return null;
    final created = doc['created_at'];
    return FileRecord(
      filename: doc['filename'] as String,
      originalname: doc['originalname'] as String? ?? 'unknown',
      mimetype: doc['mimetype'] as String? ?? 'application/octet-stream',
      size: (doc['size'] as num?)?.toInt() ?? 0,
      encoding: doc['encoding'] as String? ?? '7bit',
      path: doc['path'] as String? ?? '',
      createdAt: created is DateTime ? created : DateTime.now(),
    );
  }

  Map<String, Object?> uploadData() => {
    'uri': 'api/file/$filename',
    'filename': filename,
    'originalname': originalname,
    'mimetype': mimetype,
    'size': size,
    'encoding': encoding,
  };
}
