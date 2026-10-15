import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/downloaded_document.dart';
import '../services/downloaded_documents_service.dart';
import 'pos_busy.dart';
import 'share_origin.dart';

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
        sharePositionOrigin: shareOriginRect(),
      );
    } catch (e) {
      // iPad/iPhone TestFlight ném PlatformException nếu thiếu neo chia sẻ.
      // File đã ghi — không làm hỏng xuất Excel/PNG.
      debugPrint('iOS share export: $e');
    }
  }

  // Máy tính (Windows / macOS / Linux): lưu bản công khai vào Downloads/SBOX HRM (không đè tệp cùng tên).
  if (mediaUri == null && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    try {
      final dl = await getDownloadsDirectory();
      if (dl != null) {
        final dir = Directory('${dl.path}${Platform.pathSeparator}SBOX HRM');
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = _uniqueFile(dir, filename);
        await file.writeAsBytes(bytes, flush: true);
        mediaUri = file.path;
      }
    } catch (e) {
      debugPrint('desktop save: $e');
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

/// Tên tệp chưa có trong [dir]: «a.xlsx», «a (1).xlsx», «a (2).xlsx»…
File _uniqueFile(Directory dir, String filename) {
  final sep = Platform.pathSeparator;
  final dot = filename.lastIndexOf('.');
  final stem = dot > 0 ? filename.substring(0, dot) : filename;
  final ext = dot > 0 ? filename.substring(dot) : '';
  var f = File('${dir.path}$sep$filename');
  for (var i = 1; f.existsSync() && i < 1000; i++) {
    f = File('${dir.path}$sep$stem ($i)$ext');
  }
  return f;
}

/// Save a file and immediately open it with the default app.
Future<void> saveAndOpenFileBytes(
    List<int> bytes, String filename, String mimeType) async {
  PosBusy.hideLayer(); // lớp «Đang mở…» không nằm sau hộp này
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
