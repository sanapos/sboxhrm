import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/downloaded_document.dart';
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
  String? mediaUri;
  if (Platform.isAndroid) {
    try {
      mediaUri = await _channel.invokeMethod<String>('saveFile', {
        'bytes': Uint8List.fromList(bytes),
        'filename': filename,
        'mimeType': mimeType,
      });
    } catch (e) {
      debugPrint('saveFile MediaStore: $e');
    }
  }

  if (mediaUri == null && Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$filename';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(filePath, mimeType: mimeType)],
    );
    mediaUri = filePath;
  }

  DownloadedDocument? doc;
  if (!kIsWeb) {
    doc = await DownloadedDocumentsService.instance.register(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      category: category,
      sourceModule: sourceModule,
      externalUri: mediaUri,
    );
  }

  // Mở bản trong app. content:// của MediaStore làm OpenFilex báo không thấy file.
  return doc?.localPath ?? mediaUri;
}

/// Save a file and immediately open it with the default app.
Future<void> saveAndOpenFileBytes(
    List<int> bytes, String filename, String mimeType) async {
  final savedPath = await saveFileBytes(bytes, filename, mimeType);
  if (savedPath == null) {
    throw Exception('Không lưu được file trên máy');
  }
  if (savedPath.startsWith('content:')) return;
  try {
    await OpenFilex.open(savedPath, type: mimeType);
  } catch (e) {
    debugPrint('open saved file: $e');
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

/// Mở PDF xem trước (mobile: mở bằng app mặc định).
Future<void> openPdfInNewTab(List<int> bytes, String filename) async {
  await saveAndOpenFileBytes(bytes, filename, 'application/pdf');
}
