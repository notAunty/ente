class OptimizedLocalCopy {
  final int collectionID;
  final int uploadedFileID;
  final String path;
  final int size;
  final int? width;
  final int? height;
  final String format;
  final int version;
  final int createdAt;

  const OptimizedLocalCopy({
    required this.collectionID,
    required this.uploadedFileID,
    required this.path,
    required this.size,
    required this.width,
    required this.height,
    required this.format,
    required this.version,
    required this.createdAt,
  });
}
