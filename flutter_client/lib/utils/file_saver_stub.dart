import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// MethodChannel to interact with native Android MediaStore for saving files
const _channel = MethodChannel('com.sboxhrm/file_saver');

/// Save a file from raw bytes on mobile.
/// Images → saved to Pictures/SBOX HRM (visible in Gallery)
/// Documents (xlsx, csv, pdf) → saved to Downloads/SBOX HRM
Future<void> saveFileBytes(List<int> bytes, String filename, String mimeType) async {
  if (Platform.isAndroid) {
    try {
      await _channel.invokeMethod('saveFile', {
        'bytes': Uint8List.fromList(bytes),
        'filename': filename,
        'mimeType': mimeType,
      });
      // result is the saved path or uri - success
      return;
    } on MissingPluginException {
      // Fallback to legacy method if native channel not available
    }
  }

  // Fallback: save to downloads directory
  final dir = Platform.isAndroid
      ? Directory('/storage/emulated/0/Download')
      : await getApplicationDocumentsDirectory();
  if (!await dir.exists()) await dir.create(recursive: true);
  final filePath = '${dir.path}/$filename';
  final file = File(filePath);
  await file.writeAsBytes(bytes);
}

/// Save a file from a data-URL on mobile.
Future<void> saveDataUrl(String dataUrl, String filename) async {
  final base64Str = dataUrl.split(',').last;
  final bytes = base64Decode(base64Str);
  String mimeType = 'application/octet-stream';
  if (filename.endsWith('.png')) mimeType = 'image/png';
  if (filename.endsWith('.jpg') || filename.endsWith('.jpeg')) mimeType = 'image/jpeg';
  await saveFileBytes(bytes, filename, mimeType);
}
