import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
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

Future<OptimizedLocalCopy?> createOptimizedLocalCopy(EnteFile file) async {
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

  final outputFile = await _createCompressedCopy(file, sourceFile);
  if (outputFile == null || !await outputFile.exists()) {
    return null;
  }

  final optimizedCopy = OptimizedLocalCopy(
    collectionID: file.collectionID!,
    uploadedFileID: file.uploadedFileID!,
    path: outputFile.path,
    size: await outputFile.length(),
    width: _targetWidth(file),
    height: _targetHeight(file),
    format: 'jpeg',
    version: kOptimizedCopyVersion,
    createdAt: DateTime.now().microsecondsSinceEpoch,
  );
  await FilesDB.instance.putOptimizedLocalCopy(optimizedCopy);
  return optimizedCopy;
}

Future<void> deleteOptimizedLocalCopy(EnteFile file) async {
  final optimizedCopy = await FilesDB.instance.getOptimizedLocalCopy(file);
  if (optimizedCopy == null) {
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

Future<File?> _createCompressedCopy(EnteFile file, File sourceFile) async {
  final dirPath = path.join(
    Configuration.instance.getOptimizedCopiesDirectory(),
    '${file.collectionID}_${file.uploadedFileID}',
  );
  final dir = Directory(dirPath);
  await dir.create(recursive: true);
  final outputPath = path.join(dir.path, 'optimized.jpg');

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
