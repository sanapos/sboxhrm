import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// MethodChannel to interact with native Android MediaStore for saving files
const _channel = MethodChannel('com.sboxhrm/file_saver');

/// Save a file from raw bytes on mobile.
/// Images → saved to Pictures/SBOX HRM (visible in Gallery)
/// Documents (xlsx, csv, pdf) → saved to Downloads/SBOX HRM
/// Returns saved URI/path string (for opening), or null on failure.
Future<String?> saveFileBytes(
    List<int> bytes, String filename, String mimeType) async {
  if (Platform.isAndroid) {
    try {
      final result = await _channel.invokeMethod<String>('saveFile', {
        'bytes': Uint8List.fromList(bytes),
        'filename': filename,
        'mimeType': mimeType,
      });
      return result; // content URI or file path
    } on MissingPluginException {
      // Fallback to legacy method if native channel not available
    }
  }

  // iOS: save to temp + show share sheet so user can save/share
  if (Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$filename';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(filePath, mimeType: mimeType)],
    );
    return filePath;
  }

  // Android fallback: save to downloads directory
  final dir = Directory('/storage/emulated/0/Download');
  if (!await dir.exists()) await dir.create(recursive: true);
  final filePath = '${dir.path}/$filename';
  final file = File(filePath);
  await file.writeAsBytes(bytes);
  return filePath;
}

/// Save a file and immediately open it with the default app.
Future<void> saveAndOpenFileBytes(
    List<int> bytes, String filename, String mimeType) async {
  final savedUri = await saveFileBytes(bytes, filename, mimeType);
  if (savedUri != null) {
    await OpenFilex.open(savedUri, type: mimeType);
  }
}

/// Save a file from a data-URL on mobile.
Future<void> saveDataUrl(String dataUrl, String filename) async {
  final base64Str = dataUrl.split(',').last;
  final bytes = base64Decode(base64Str);
  String mimeType = 'application/octet-stream';
  if (filename.endsWith('.png')) mimeType = 'image/png';
  if (filename.endsWith('.jpg') || filename.endsWith('.jpeg')) {
    mimeType = 'image/jpeg';
  }
  await saveFileBytes(bytes, filename, mimeType);
}

/// Save a data-URL file and immediately open it.
Future<void> saveAndOpenDataUrl(String dataUrl, String filename) async {
  final base64Str = dataUrl.split(',').last;
  final bytes = base64Decode(base64Str);
  String mimeType = 'image/png';
  if (filename.endsWith('.jpg') || filename.endsWith('.jpeg')) {
    mimeType = 'image/jpeg';
  }
  await saveAndOpenFileBytes(bytes, filename, mimeType);
}
