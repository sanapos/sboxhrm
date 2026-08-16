import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> saveFileBytes(
  List<int> bytes, [
  String? fileName,
  String? mimeType,
]) async {
  final name = (fileName == null || fileName.trim().isEmpty)
      ? 'sbox_${DateTime.now().millisecondsSinceEpoch}'
      : fileName.trim();
  try {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/SBOX POS');
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (_) {
          dir = await getApplicationDocumentsDirectory();
        }
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (e) {
    debugPrint('saveFileBytes: $e');
    return null;
  }
}

Future<void> saveAndOpenFileBytes(
  List<int> bytes,
  String filename,
  String mimeType,
) async {
  final path = await saveFileBytes(bytes, filename, mimeType);
  if (path != null) {
    await OpenFilex.open(path, type: mimeType);
  }
}

Future<void> openPdfInNewTab(List<int> bytes, [String? filename]) async {
  await saveAndOpenFileBytes(
    bytes,
    filename ?? 'document.pdf',
    'application/pdf',
  );
}
