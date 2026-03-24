import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/cache/preview_cache_manager.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/preview_export_paths.dart';
import 'package:photos/utils/file_util.dart';

final _logger = Logger('OptimizedLocalFileUtil');

const kPreviewCacheTargetBytes = 256 * 1024;
const kPreviewCacheVersion = 1;

class PreviewCachePolicy {
  final bool enabled;
  final bool useSharedStorage;

  const PreviewCachePolicy({
    required this.enabled,
    required this.useSharedStorage,
  });
}

Future<File?> getPreviewFile(EnteFile file) async {
  if (!_canHavePreview(file)) {
    return null;
  }

  final fileInfo = await PreviewCacheManager.instance.getFileFromCache(
    _previewCacheKey(file),
  );
  return fileInfo?.file;
}

Future<bool> hasPreviewCache(EnteFile file) async {
  return await getPreviewFile(file) != null;
}

Future<void> enqueuePreviewCacheGeneration(
  Iterable<EnteFile> files, {
  required PreviewCachePolicy policy,
}) async {
  if (!policy.enabled) {
    return;
  }

  for (final file in files) {
    if (!_canHavePreview(file)) {
      continue;
    }
    await _cachePreviewForFile(file, policy: policy);
  }
}

Future<void> deletePreviewCache(EnteFile file) async {
  if (!_canHavePreview(file)) {
    return;
  }
  await PreviewCacheManager.instance.removeFile(_previewCacheKey(file));
}

Future<void> _cachePreviewForFile(
  EnteFile file, {
  required PreviewCachePolicy policy,
}) async {
  try {
    final existingPreview = await getPreviewFile(file);
    if (existingPreview != null && await existingPreview.exists()) {
      return;
    }

    final sourceFile = await getFile(file, isOrigin: true);
    if (sourceFile == null || !await sourceFile.exists()) {
      return;
    }

    final compressedFile = await _createCompressedCopy(
      file,
      sourceFile,
      outputPath: _getTempOutputPath(file),
    );
    if (compressedFile == null || !await compressedFile.exists()) {
      return;
    }

    if (policy.useSharedStorage && Platform.isAndroid) {
      await _writeSharedPreviewExport(file, compressedFile);
    }

    await PreviewCacheManager.instance.putFile(
      _previewCacheKey(file),
      await compressedFile.readAsBytes(),
      eTag: _previewCacheKey(file),
      maxAge: const Duration(days: 30),
      fileExtension: 'jpg',
    );
    await _safeDeleteFile(compressedFile);
  } catch (e, s) {
    _logger.warning('Failed to cache preview for ${file.tag}', e, s);
  }
}

Future<File?> _createCompressedCopy(
  EnteFile file,
  File sourceFile, {
  required String outputPath,
}) async {
  final dir = Directory(path.dirname(outputPath));
  await dir.create(recursive: true);
  File? bestFile;
  for (final quality in const [55, 40, 28, 20, 12]) {
    final result = await FlutterImageCompress.compressAndGetFile(
      sourceFile.path,
      outputPath,
      quality: quality,
      minWidth: _targetWidth(file),
      minHeight: _targetHeight(file),
      keepExif: true,
      format: CompressFormat.jpeg,
      autoCorrectionAngle: true,
    );
    if (result == null) {
      continue;
    }
    bestFile = File(result.path);
    if (await bestFile.length() <= kPreviewCacheTargetBytes) {
      break;
    }
  }

  if (bestFile == null) {
    _logger.warning('Failed to create optimized copy for ${file.tag}');
  }
  return bestFile;
}

Future<void> _writeSharedPreviewExport(
  EnteFile file,
  File compressedFile,
) async {
  try {
    await PhotoManager.editor.saveImage(
      await compressedFile.readAsBytes(),
      filename: _previewExportFileName(file),
      relativePath: kPreviewExportAndroidRelativePath,
    );
  } catch (e, s) {
    _logger.warning(
      'Failed to write shared preview export for ${file.tag}',
      e,
      s,
    );
  }
}

String _getTempOutputPath(EnteFile file) {
  return path.join(
    Configuration.instance.getTempDirectory(),
    'optimized-copies',
    '${file.collectionID}_${file.uploadedFileID}',
    'optimized.jpg',
  );
}

String _previewExportFileName(EnteFile file) {
  final fileNameBase = file.title == null || file.title!.trim().isEmpty
      ? 'ente_preview_${file.collectionID}_${file.uploadedFileID}'
      : path.basenameWithoutExtension(file.title!);
  return '${fileNameBase}_ente_preview.jpg';
}

String _previewCacheKey(EnteFile file) {
  return 'preview_${file.uploadedFileID}_v$kPreviewCacheVersion';
}

bool _canHavePreview(EnteFile file) {
  return file.fileType == FileType.image &&
      file.isUploaded &&
      file.collectionID != null &&
      file.uploadedFileID != null;
}

Future<void> _safeDeleteFile(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

int _deviceTargetLongEdge() {
  final view = ui.PlatformDispatcher.instance.views.isNotEmpty
      ? ui.PlatformDispatcher.instance.views.first
      : null;
  if (view == null) {
    return 2048;
  }
  final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
  final logicalHeight = view.physicalSize.height / view.devicePixelRatio;
  return max(logicalWidth, logicalHeight).round();
}

int _targetWidth(EnteFile file) {
  final targetLongEdge = _deviceTargetLongEdge();
  final width = file.width;
  final height = file.height;
  if (width <= 0 || height <= 0) {
    return targetLongEdge;
  }
  if (width >= height) {
    return min(width, targetLongEdge);
  }
  return max(1, (width / height * targetLongEdge).round());
}

int _targetHeight(EnteFile file) {
  final targetLongEdge = _deviceTargetLongEdge();
  final width = file.width;
  final height = file.height;
  if (width <= 0 || height <= 0) {
    return targetLongEdge;
  }
  if (height >= width) {
    return min(height, targetLongEdge);
  }
  return max(1, (height / width * targetLongEdge).round());
}
