import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('com.sboxhrm/file_saver');

Future<void> downloadPngBytes(List<int> bytes, String filename) async {
  if (Platform.isAndroid) {
    try {
      await _channel.invokeMethod('saveFile', {
        'bytes': Uint8List.fromList(bytes),
        'filename': filename,
        'mimeType': 'image/png',
      });
      return;
    } on MissingPluginException {
      // Fallback
    }
  }

  final dir = Platform.isAndroid
      ? Directory('/storage/emulated/0/Download')
      : await getApplicationDocumentsDirectory();
  if (!await dir.exists()) await dir.create(recursive: true);
  final filePath = '${dir.path}/$filename';
  final file = File(filePath);
  await file.writeAsBytes(bytes);
}
