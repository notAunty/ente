import 'package:photos/models/preview_export_paths.dart';
import 'package:test/test.dart';

void main() {
  group('preview export path filters', () {
    test('matches the shared preview album name', () {
      expect(isPreviewExportPathName('ente Proxies'), isTrue);
      expect(isPreviewExportPathName(' EnTe Proxies '), isTrue);
      expect(isPreviewExportPathName('Camera'), isFalse);
    });

    test('matches the shared preview relative path', () {
      expect(
        isPreviewExportRelativePath('Pictures/ente Proxies'),
        isTrue,
      );
      expect(
        isPreviewExportRelativePath('Pictures/ente Proxies/subdir'),
        isTrue,
      );
      expect(
        isPreviewExportRelativePath(r'Pictures\ente Proxies\subdir'),
        isTrue,
      );
      expect(isPreviewExportRelativePath(null), isFalse);
      expect(isPreviewExportRelativePath('Pictures/Camera'), isFalse);
    });
  });
}
