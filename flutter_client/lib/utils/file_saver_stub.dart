import 'dart:convert';
import 'dart:io';
import 'dart:ui';

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
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/$filename';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    mediaUri = filePath;
    try {
      await Share.shareXFiles(
        [XFile(filePath, mimeType: mimeType, name: filename)],
        sharePositionOrigin: _iosShareOrigin(),
      );
    } catch (e) {
      // iPad/iPhone TestFlight ném PlatformException nếu thiếu neo chia sẻ.
      // File đã ghi — không làm hỏng xuất Excel/PNG.
      debugPrint('iOS share export: $e');
    }
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

/// Điểm neo cho UIActivityViewController. Rect rỗng làm iOS ném
/// PlatformException(error, sharePositionOrigin...).
Rect _iosShareOrigin() {
  final views = PlatformDispatcher.instance.views;
  if (views.isEmpty) return const Rect.fromLTWH(0, 0, 120, 48);
  final size = views.first.physicalSize / views.first.devicePixelRatio;
  final width = size.width > 8 ? size.width : 320.0;
  final height = size.height > 8 ? size.height : 640.0;
  return Rect.fromCenter(
    center: Offset(width / 2, height / 3),
    width: 48,
    height: 48,
  );
}

/// Save a file and immediately open it with the default app.
Future<void> saveAndOpenFileBytes(
    List<int> bytes, String filename, String mimeType) async {
  final savedPath = await saveFileBytes(bytes, filename, mimeType);
  if (savedPath == null) {
    throw Exception('Không lưu được file trên máy');
  }
  if (savedPath.startsWith('content:')) return;
  // iOS đã mở hộp chia sẻ trong saveFileBytes.
  if (Platform.isIOS) return;
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
