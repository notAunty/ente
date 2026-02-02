import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/ui/common/linear_progress_dialog.dart';
import 'package:photos/utils/delete_file_util.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/file_util.dart';

final _logger = Logger("OptimizationUtil");

Future<bool> optimizeLocalFiles(
  BuildContext context,
  List<String> localIDs,
) async {
  _logger.info("Trying to optimize local files");
  final List<String> optimizedIDs = [];
  final List<String> localSharedMediaIDs = [];
  final List<String> idsToDelete = [];
  final List<String> nonOptimizableIDs = [];

  final dialogKey = GlobalKey<LinearProgressDialogState>();
  final dialog = LinearProgressDialog(
    AppLocalizations.of(context).genericProgress(
      currentlyProcessing: 0,
      totalCount: localIDs.length,
    ),
    key: dialogKey,
  );

  // ignore: unawaited_futures
  showDialog(
    useRootNavigator: false,
    barrierDismissible: false,
    context: context,
    builder: (context) {
      return dialog;
    },
    barrierColor: Colors.black.withValues(alpha: 0.85),
  );

  int processedCount = 0;

  try {
    for (String id in localIDs) {
      if (dialogKey.currentState != null) {
        dialogKey.currentState!.setProgress(processedCount / localIDs.length);
        dialogKey.currentState!.updateMessage(
          AppLocalizations.of(context).genericProgress(
            currentlyProcessing: processedCount,
            totalCount: localIDs.length,
          ),
        );
      }

      if (id.startsWith(sharedMediaIdentifier)) {
        localSharedMediaIDs.add(id);
        processedCount++;
        continue;
      }

      final AssetEntity? asset = await AssetEntity.fromId(id);
      if (asset == null) {
        _logger.warning("Asset not found for optimization: $id");
        processedCount++;
        continue;
      }

      if (asset.type == AssetType.video) {
        nonOptimizableIDs.add(id);
        processedCount++;
        continue;
      }

      // It's an image. Optimize it.
      File? tempFile;
      try {
        final File? originFile = await asset.originFile;
        if (originFile == null || !originFile.existsSync()) {
          _logger.warning("Origin file not found for asset: $id");
          nonOptimizableIDs.add(id);
          processedCount++;
          continue;
        }

        final tempDir = await getTemporaryDirectory();
        final targetPath =
            "${tempDir.path}/optimized_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}.jpg";

        final result = await FlutterImageCompress.compressAndGetFile(
          originFile.absolute.path,
          targetPath,
          quality: 70, // Reduced quality to target smaller size (~100KB)
          minWidth: 1920,
          minHeight: 1080,
          keepExif: true,
        );

        if (result == null) {
          _logger.warning("Compression failed for $id");
          nonOptimizableIDs.add(id);
          processedCount++;
          continue;
        }
        tempFile = File(result.path);

        // Save to Gallery
        final AssetEntity? newAsset = await PhotoManager.editor.saveImage(
          await result.readAsBytes(),
          title: asset.title,
          filename: asset.title,
        );

        if (newAsset != null) {
          await FilesDB.instance.updateLocalIDForOptimizedFile(id, newAsset.id);
          idsToDelete.add(id);
          optimizedIDs.add(newAsset.id);
        } else {
          _logger.severe("Failed to save optimized asset for $id");
          nonOptimizableIDs.add(id);
        }
      } catch (e, s) {
        _logger.severe("Error optimizing file $id", e, s);
        nonOptimizableIDs.add(id);
      } finally {
        if (tempFile != null && tempFile.existsSync()) {
          try {
            await tempFile.delete();
          } catch (e) {
            _logger.warning("Failed to delete temp file", e);
          }
        }
      }

      processedCount++;
    }
  } catch (e, s) {
    _logger.severe("Global error in optimizeLocalFiles", e, s);
  } finally {
    if (dialogKey.currentContext != null) {
      Navigator.of(dialogKey.currentContext!).pop();
    }
  }

  // Handle deletions: Merge original files (of optimized copies) and non-optimizable files (videos, etc.)
  // This avoids double prompting the user.
  final List<String> allDeletions = [...idsToDelete, ...nonOptimizableIDs];
  if (allDeletions.isNotEmpty) {
    _logger.info("Deleting ${allDeletions.length} files (originals + non-optimizable)");
    try {
        await deleteLocalFilesInBatches(context, allDeletions);
    } catch (e, s) {
        _logger.severe("Failed to delete files after optimization", e, s);
    }
  }

  // Handle shared media deletions separately as they use a different mechanism
  if (localSharedMediaIDs.isNotEmpty) {
    await _tryDeleteSharedMediaFiles(localSharedMediaIDs);
  }

  if (optimizedIDs.isNotEmpty) {
    final updatedFiles = await FilesDB.instance.getLocalFiles(optimizedIDs);
    Bus.instance.fire(
      LocalPhotosUpdatedEvent(updatedFiles, source: "optimizeLocal"),
    );
  }

  if (optimizedIDs.isEmpty && allDeletions.isEmpty && localSharedMediaIDs.isEmpty) {
    return false;
  }

  return true;
}

Future<List<String>> _tryDeleteSharedMediaFiles(List<String> localIDs) {
  final List<String> actuallyDeletedIDs = [];
  try {
    return Future.forEach<String>(localIDs, (id) async {
      final String localPath = getSharedMediaPathFromLocalID(id);
      try {
        if (File(localPath).existsSync()) {
          await File(localPath).delete();
        }
        actuallyDeletedIDs.add(id);
      } catch (e, s) {
        _logger.warning("Could not delete file " + id, e, s);
      }
    }).then((ignore) {
      return actuallyDeletedIDs;
    });
  } catch (e, s) {
    _logger.severe("Unexpected error while deleting share media files", e, s);
    return Future.value(actuallyDeletedIDs);
  }
}
