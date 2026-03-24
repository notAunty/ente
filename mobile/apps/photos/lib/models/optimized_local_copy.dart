const kOptimizedProxyAlbumName = 'ente Proxies';
const kOptimizedProxyAndroidRelativePath = 'Pictures/$kOptimizedProxyAlbumName';

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
