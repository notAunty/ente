import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/optimized_local_copy.dart';
import 'package:photos/utils/file_util.dart';

final _logger = Logger('OptimizedLocalFileUtil');

const kOptimizedCopyTargetBytes = 100 * 1024;
const kOptimizedCopyVersion = 1;

Future<File?> getOptimizedLocalCopyFile(EnteFile file) async {
  final optimizedCopy = await FilesDB.instance.getOptimizedLocalCopy(file);
  if (optimizedCopy == null) {
    return null;
  }

  if (optimizedCopy.storage == OptimizedLocalCopyStorage.sharedMediaStore) {
    final localID = optimizedCopy.localID;
    if (localID == null || localID.isEmpty) {
      await FilesDB.instance.deleteOptimizedLocalCopy(file);
      return null;
    }
    final asset = await AssetEntity.fromId(localID);
    final localFile = await asset?.file;
    if (localFile != null && await localFile.exists()) {
      return localFile;
    }
    await FilesDB.instance.deleteOptimizedLocalCopy(file);
    return null;
  }

  final localFile = File(optimizedCopy.path);
  if (await localFile.exists()) {
    return localFile;
  }
  await FilesDB.instance.deleteOptimizedLocalCopy(file);
  return null;
}

Future<bool> hasOptimizedLocalCopy(EnteFile file) async {
  return await getOptimizedLocalCopyFile(file) != null;
}

Future<OptimizedLocalCopy?> createOptimizedLocalCopy(
  EnteFile file, {
  required bool useSharedStorage,
}) async {
  try {
    if (file.fileType != FileType.image ||
        file.localID == null ||
        file.collectionID == null ||
        file.uploadedFileID == null) {
      return null;
    }

    final sourceFile = await getFile(file, isOrigin: true);
    if (sourceFile == null || !await sourceFile.exists()) {
      return null;
    }

    await deleteOptimizedLocalCopy(file);

    final compressedFile = await _createCompressedCopy(
      file,
      sourceFile,
      outputPath: _getTempOutputPath(file),
    );
    if (compressedFile == null || !await compressedFile.exists()) {
      return null;
    }

    final optimizedCopy = useSharedStorage && Platform.isAndroid
        ? await _createSharedStorageOptimizedCopy(file, compressedFile)
        : await _createAppPrivateOptimizedCopy(file, compressedFile);
    if (optimizedCopy == null) {
      await _safeDeleteFile(compressedFile);
      return null;
    }

    await FilesDB.instance.putOptimizedLocalCopy(optimizedCopy);
    return optimizedCopy;
  } catch (e, s) {
    _logger.warning('Failed to create optimized copy for ${file.tag}', e, s);
    return null;
  }
}

Future<void> deleteOptimizedLocalCopy(EnteFile file) async {
  final optimizedCopy = await FilesDB.instance.getOptimizedLocalCopy(file);
  if (optimizedCopy == null) {
    return;
  }

  if (optimizedCopy.storage == OptimizedLocalCopyStorage.sharedMediaStore) {
    final localID = optimizedCopy.localID;
    if (localID != null && localID.isNotEmpty) {
      try {
        await PhotoManager.editor.deleteWithIds([localID]);
      } catch (e, s) {
        _logger.warning(
          'Failed to delete shared optimized copy ${file.tag}',
          e,
          s,
        );
      }
    }
    await FilesDB.instance.deleteOptimizedLocalCopy(file);
    return;
  }

  final localFile = File(optimizedCopy.path);
  if (await localFile.exists()) {
    await localFile.delete();
  }
  final parentDir = localFile.parent;
  if (await parentDir.exists()) {
    final entries = await parentDir.list().toList();
    if (entries.isEmpty) {
      await parentDir.delete();
    }
  }
  await FilesDB.instance.deleteOptimizedLocalCopy(file);
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
      keepExif: false,
      format: CompressFormat.jpeg,
      autoCorrectionAngle: true,
    );
    if (result == null) {
      continue;
    }
    bestFile = File(result.path);
    if (await bestFile.length() <= kOptimizedCopyTargetBytes) {
      break;
    }
  }

  if (bestFile == null) {
    _logger.warning('Failed to create optimized copy for ${file.tag}');
  }
  return bestFile;
}

Future<OptimizedLocalCopy?> _createAppPrivateOptimizedCopy(
  EnteFile file,
  File compressedFile,
) async {
  final outputPath = _getAppPrivateOutputPath(file);
  final outputDir = Directory(path.dirname(outputPath));
  await outputDir.create(recursive: true);
  final appPrivateFile = await compressedFile.copy(outputPath);
  if (compressedFile.path != appPrivateFile.path) {
    await _safeDeleteFile(compressedFile);
  }
  return _buildOptimizedLocalCopy(
    file,
    path: appPrivateFile.path,
    size: await appPrivateFile.length(),
    storage: OptimizedLocalCopyStorage.appPrivate,
  );
}

Future<OptimizedLocalCopy?> _createSharedStorageOptimizedCopy(
  EnteFile file,
  File compressedFile,
) async {
  try {
    final fileName = _optimizedProxyFileName(file);
    final asset = await PhotoManager.editor.saveImage(
      await compressedFile.readAsBytes(),
      filename: fileName,
      relativePath: kOptimizedProxyAndroidRelativePath,
    );
    return _buildOptimizedLocalCopy(
      file,
      path: asset.relativePath == null
          ? fileName
          : '${asset.relativePath}/$fileName',
      localID: asset.id,
      size: await compressedFile.length(),
      storage: OptimizedLocalCopyStorage.sharedMediaStore,
    );
  } catch (e, s) {
    _logger.warning(
      'Failed to create shared optimized copy for ${file.tag}',
      e,
      s,
    );
    return null;
  } finally {
    await _safeDeleteFile(compressedFile);
  }
}

OptimizedLocalCopy _buildOptimizedLocalCopy(
  EnteFile file, {
  required String path,
  required int size,
  String? localID,
  required OptimizedLocalCopyStorage storage,
}) {
  return OptimizedLocalCopy(
    collectionID: file.collectionID!,
    uploadedFileID: file.uploadedFileID!,
    path: path,
    localID: localID,
    size: size,
    width: _targetWidth(file),
    height: _targetHeight(file),
    format: 'jpeg',
    version: kOptimizedCopyVersion,
    createdAt: DateTime.now().microsecondsSinceEpoch,
    storage: storage,
  );
}

String _getAppPrivateOutputPath(EnteFile file) {
  return path.join(
    Configuration.instance.getOptimizedCopiesDirectory(),
    '${file.collectionID}_${file.uploadedFileID}',
    'optimized.jpg',
  );
}

String _getTempOutputPath(EnteFile file) {
  return path.join(
    Configuration.instance.getTempDirectory(),
    'optimized-copies',
    '${file.collectionID}_${file.uploadedFileID}',
    'optimized.jpg',
  );
}

String _optimizedProxyFileName(EnteFile file) {
  final fileNameBase = file.title == null || file.title!.trim().isEmpty
      ? 'ente_proxy_${file.collectionID}_${file.uploadedFileID}'
      : path.basenameWithoutExtension(file.title!);
  return '${fileNameBase}_ente_proxy.jpg';
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
