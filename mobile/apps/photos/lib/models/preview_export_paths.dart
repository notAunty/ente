const kPreviewExportAlbumName = 'ente Proxies';
const kPreviewExportAndroidRelativePath = 'Pictures/$kPreviewExportAlbumName';

bool isPreviewExportPathName(String pathName) {
  return pathName.trim().toLowerCase() == kPreviewExportAlbumName.toLowerCase();
}

bool isPreviewExportRelativePath(String? relativePath) {
  if (relativePath == null) {
    return false;
  }
  final normalizedPath = relativePath.replaceAll('\\', '/').toLowerCase();
  final expectedPrefix = kPreviewExportAndroidRelativePath.toLowerCase();
  return normalizedPath == expectedPrefix ||
      normalizedPath.startsWith('$expectedPrefix/');
}
