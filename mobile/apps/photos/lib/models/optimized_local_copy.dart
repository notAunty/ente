const kOptimizedProxyAlbumName = 'ente Proxies';
const kOptimizedProxyAndroidRelativePath = 'Pictures/$kOptimizedProxyAlbumName';

enum OptimizedLocalCopyStorage {
  appPrivate,
  sharedMediaStore,
}

OptimizedLocalCopyStorage optimizedLocalCopyStorageFromValue(int? value) {
  if (value == null ||
      value < 0 ||
      value >= OptimizedLocalCopyStorage.values.length) {
    return OptimizedLocalCopyStorage.appPrivate;
  }
  return OptimizedLocalCopyStorage.values[value];
}

bool isOptimizedProxyPathName(String pathName) {
  return pathName.trim().toLowerCase() ==
      kOptimizedProxyAlbumName.toLowerCase();
}

bool isOptimizedProxyRelativePath(String? relativePath) {
  if (relativePath == null || relativePath.isEmpty) {
    return false;
  }
  final normalizedPath = relativePath.replaceAll('\\', '/').toLowerCase();
  final expectedPrefix = kOptimizedProxyAndroidRelativePath.toLowerCase();
  return normalizedPath == expectedPrefix ||
      normalizedPath.startsWith('$expectedPrefix/');
}

class OptimizedLocalCopy {
  final int collectionID;
  final int uploadedFileID;
  final String path;
  final String? localID;
  final int size;
  final int? width;
  final int? height;
  final String format;
  final int version;
  final int createdAt;
  final OptimizedLocalCopyStorage storage;

  const OptimizedLocalCopy({
    required this.collectionID,
    required this.uploadedFileID,
    required this.path,
    this.localID,
    required this.size,
    required this.width,
    required this.height,
    required this.format,
    required this.version,
    required this.createdAt,
    this.storage = OptimizedLocalCopyStorage.appPrivate,
  });
}
