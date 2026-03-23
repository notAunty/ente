import 'package:photos/models/optimized_local_copy.dart';
import 'package:test/test.dart';

void main() {
  group('optimized proxy path filters', () {
    test('matches the shared proxy album name', () {
      expect(isOptimizedProxyPathName('ente Proxies'), isTrue);
      expect(isOptimizedProxyPathName(' EnTe Proxies '), isTrue);
      expect(isOptimizedProxyPathName('Camera'), isFalse);
    });

    test('matches the shared proxy relative path', () {
      expect(
        isOptimizedProxyRelativePath('Pictures/ente Proxies'),
        isTrue,
      );
      expect(
        isOptimizedProxyRelativePath('Pictures/ente Proxies/subdir'),
        isTrue,
      );
      expect(
        isOptimizedProxyRelativePath(r'Pictures\ente Proxies\subdir'),
        isTrue,
      );
      expect(isOptimizedProxyRelativePath(null), isFalse);
      expect(isOptimizedProxyRelativePath('Pictures/Camera'), isFalse);
    });
  });
}
