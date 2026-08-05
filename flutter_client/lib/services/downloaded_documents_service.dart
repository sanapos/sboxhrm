import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/downloaded_document.dart';

// dart:io chỉ dùng ngoài web (conditional qua helper nội bộ).
import 'downloaded_documents_io.dart'
    if (dart.library.html) 'downloaded_documents_io_stub.dart'
    if (dart.library.js_interop) 'downloaded_documents_io_stub.dart'
    as dio;

/// Chỉ mục file tải/xuất **nội bộ từng máy** (thư mục app + quét SBOX HRM).
/// Không gọi API, không đồng bộ thiết bị khác, không dùng phân quyền module.
class DownloadedDocumentsService {
  DownloadedDocumentsService._();
  static final DownloadedDocumentsService instance =
      DownloadedDocumentsService._();

  static const _indexFileName = 'index.json';
  List<DownloadedDocument> _items = [];
  bool _loaded = false;

  List<DownloadedDocument> get items => List.unmodifiable(_items);

  /// Web không có thư mục tải xuống cục bộ kiểu app — luôn rỗng, không IO.
  bool get isUnsupportedPlatform => kIsWeb;

  Future<String> _storagePath() async {
    final base = await getApplicationDocumentsDirectory();
    return '${base.path}/sbox_downloads';
  }

  Future<void> _persist() async {
    if (kIsWeb) return;
    try {
      final dirPath = await _storagePath();
      await dio.ensureDir(dirPath);
      await dio.writeString(
        '$dirPath/$_indexFileName',
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('DownloadedDocumentsService._persist: $e');
    }
  }

  Future<void> ensureLoaded({bool rescan = false}) async {
    if (kIsWeb) {
      _items = [];
      _loaded = true;
      return;
    }
    if (_loaded && !rescan) return;
    try {
      final dirPath = await _storagePath();
      await dio.ensureDir(dirPath);
      final indexPath = '$dirPath/$_indexFileName';
      final rawText = await dio.readStringIfExists(indexPath);
      if (rawText != null && rawText.isNotEmpty) {
        try {
          final raw = jsonDecode(rawText);
          if (raw is List) {
            _items = raw
                .whereType<Map>()
                .map((e) => DownloadedDocument.fromJson(
                    Map<String, dynamic>.from(e)))
                .where((d) => dio.fileExists(d.localPath))
                .toList();
          }
        } catch (e) {
          debugPrint('DownloadedDocumentsService load error: $e');
          _items = [];
        }
      } else {
        _items = [];
      }
      if (rescan || _items.isEmpty) {
        await _importFromPublicFolders();
      }
      _items.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      await _persist();
    } catch (e) {
      debugPrint('DownloadedDocumentsService.ensureLoaded: $e');
      _items = [];
    } finally {
      _loaded = true;
    }
  }

  Future<void> _importFromPublicFolders() async {
    if (kIsWeb || !dio.isAndroid) return;
    final dirs = [
      '/storage/emulated/0/Download/SBOX HRM',
      '/storage/emulated/0/Pictures/SBOX HRM',
    ];
    final knownNames = _items.map((e) => e.fileName).toSet();
    for (final dirPath in dirs) {
      if (!await dio.dirExists(dirPath)) continue;
      final files = await dio.listFiles(dirPath);
      for (final entityPath in files) {
        final name = dio.basename(entityPath);
        if (knownNames.contains(name)) continue;
        final ext =
            name.contains('.') ? name.split('.').last.toLowerCase() : '';
        if (!['xlsx', 'xls', 'csv', 'png', 'jpg', 'jpeg', 'pdf'].contains(ext)) {
          continue;
        }
        try {
          final bytes = await dio.readBytes(entityPath);
          final mime = _mimeFromName(name);
          await register(
            bytes: bytes,
            filename: name,
            mimeType: mime,
            category: DownloadDocCategories.inferFromFileName(name),
            downloadedAt: await dio.lastModified(entityPath),
            externalUri: entityPath,
          );
          knownNames.add(name);
        } catch (_) {}
      }
    }
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  String _safeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// Ghi bản sao vào app + thêm chỉ mục (gọi sau khi lưu ra Downloads).
  Future<DownloadedDocument?> register({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    String? category,
    String? sourceModule,
    String? externalUri,
    DateTime? downloadedAt,
  }) async {
    if (kIsWeb) return null;
    try {
      final safeName = _safeFileName(filename);
      final dirPath = await _storagePath();
      await dio.ensureDir(dirPath);
      final id = '${DateTime.now().millisecondsSinceEpoch}_${safeName.hashCode}';
      final storedPath = '$dirPath/${id}_$safeName';
      await dio.writeBytes(storedPath, bytes);
      final cat = category?.isNotEmpty == true
          ? category!
          : DownloadDocCategories.inferFromFileName(
              safeName, hint: sourceModule);

      final doc = DownloadedDocument(
        id: id,
        fileName: safeName,
        displayName: safeName,
        localPath: storedPath,
        mimeType: mimeType,
        category: cat,
        sourceModule: sourceModule,
        sizeBytes: bytes.length,
        downloadedAt: downloadedAt ?? DateTime.now(),
        externalUri: externalUri,
      );
      _items.removeWhere((e) =>
          e.fileName == doc.fileName &&
          e.sizeBytes == doc.sizeBytes &&
          e.downloadedAt.difference(doc.downloadedAt).inMinutes.abs() < 2);
      _items.insert(0, doc);
      await _persist();
      return doc;
    } catch (e) {
      debugPrint('DownloadedDocumentsService.register: $e');
      return null;
    }
  }

  Future<bool> rename(String id, String newDisplayName) async {
    if (kIsWeb) return false;
    await ensureLoaded();
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx < 0) return false;
    final doc = _items[idx];
    var base = newDisplayName.trim();
    if (base.isEmpty) return false;
    final ext = doc.extension;
    if (ext.isNotEmpty && !base.toLowerCase().endsWith(ext)) {
      base = '$base$ext';
    }
    base = _safeFileName(base);
    final dirPath = await _storagePath();
    final newPath = '$dirPath/${doc.id}_$base';
    try {
      await dio.renameFile(doc.localPath, newPath);
      _items[idx] = doc.copyWith(
        fileName: base,
        displayName: base,
        localPath: newPath,
      );
      await _persist();
      return true;
    } catch (e) {
      debugPrint('rename document: $e');
      return false;
    }
  }

  Future<bool> delete(String id) async {
    if (kIsWeb) return false;
    await ensureLoaded();
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx < 0) return false;
    final doc = _items[idx];
    try {
      await dio.deleteFileIfExists(doc.localPath);
    } catch (_) {}
    _items.removeAt(idx);
    await _persist();
    return true;
  }

  List<DownloadedDocument> filter({
    String category = DownloadDocCategories.all,
    String type = 'all',
    DateTime? from,
    DateTime? to,
    String search = '',
  }) {
    var list = List<DownloadedDocument>.from(_items);
    if (category != DownloadDocCategories.all) {
      list = list.where((e) => e.category == category).toList();
    }
    if (type == 'excel') {
      list = list.where((e) => e.isExcel).toList();
    } else if (type == 'image') {
      list = list.where((e) => e.isImage).toList();
    }
    if (from != null) {
      list = list.where((e) => !e.downloadedAt.isBefore(from)).toList();
    }
    if (to != null) {
      final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
      list = list.where((e) => !e.downloadedAt.isAfter(end)).toList();
    }
    if (search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      list = list
          .where((e) =>
              e.displayName.toLowerCase().contains(q) ||
              e.category.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  List<String> categoriesInUse() {
    final set = <String>{};
    for (final d in _items) {
      set.add(d.category);
    }
    final ordered = DownloadDocCategories.presets
        .where((c) => c == DownloadDocCategories.all || set.contains(c))
        .toList();
    for (final c in set) {
      if (!ordered.contains(c)) ordered.add(c);
    }
    return ordered;
  }
}
