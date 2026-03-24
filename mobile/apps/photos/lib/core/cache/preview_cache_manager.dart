import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class PreviewCacheManager {
  static const key = 'cached-preview-data';

  static CacheManager instance = CacheManager(
    Config(
      key,
      maxNrOfCacheObjects: 200,
      stalePeriod: const Duration(days: 30),
    ),
  );
}
