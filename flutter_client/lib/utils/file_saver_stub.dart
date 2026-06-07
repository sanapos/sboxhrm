import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/downloaded_documents_service.dart';

/// MethodChannel to interact with native Android MediaStore for saving files
const _channel = MethodChannel('com.sboxhrm/file_saver');

/// Save a file from raw bytes on mobile.
/// Images → saved to Pictures/SBOX HRM (visible in Gallery)
/// Documents (xlsx, csv, pdf) → saved to Downloads/SBOX HRM
/// Returns saved URI/path string (for opening), or null on failure.
Future<String?> saveFileBytes(
  List<int> bytes,
  String filename,
  String mimeType, {
  String? category,
  String? sourceModule,
}) async {
  String? savedUri;
  if (Platform.isAndroid) {
    try {
      savedUri = await _channel.invokeMethod<String>('saveFile', {
        'bytes': Uint8List.fromList(bytes),
        'filename': filename,
        'mimeType': mimeType,
      });
    } on MissingPluginException {
      // Fallback to legacy method if native channel not available
    }
  }

  if (savedUri == null && Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$filename';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(filePath, mimeType: mimeType)],
    );
    savedUri = filePath;
  }

  if (savedUri == null && Platform.isAndroid) {
    final dir = Directory('/storage/emulated/0/Download/SBOX HRM');
    if (!await dir.exists()) await dir.create(recursive: true);
    final filePath = '${dir.path}/$filename';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    savedUri = filePath;
  }

  if (!kIsWeb) {
    await DownloadedDocumentsService.instance.register(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      category: category,
      sourceModule: sourceModule,
      externalUri: savedUri,
    );
  }

  return savedUri;
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
