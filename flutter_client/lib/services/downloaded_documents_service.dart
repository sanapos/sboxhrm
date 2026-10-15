import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/downloaded_document.dart';
import '../utils/public_file_ops.dart' as pub;

// dart:io chỉ dùng ngoài web (conditional qua helper nội bộ).
import 'downloaded_documents_io.dart'
    if (dart.library.html) 'downloaded_documents_io_stub.dart'
    if (dart.library.js_interop) 'downloaded_documents_io_stub.dart'
    as dio;

/// Chỉ mục file tải/xuất **nội bộ từng máy**, RIÊNG theo tài khoản + cửa hàng đang đăng nhập
/// (thư mục `sbox_downloads/<cửa hàng>_<tài khoản>/`). Không gọi API, không đồng bộ thiết bị khác.
///
/// • Mỗi tệp được giữ một bản quản lý trong app (mở / đổi tên / chia sẻ); bản ở thư mục Tải xuống (nếu có) là bản riêng
///   và chỉ bị xóa khi người dùng chọn.
/// • Bản trong app tự dọn sau [retentionDays] ngày hoặc khi tổng vượt [maxStoredBytes] (xóa cũ nhất trước).
/// • Tệp ở thư mục công khai chỉ được nhập khi người dùng bấm «Nhập từ thư mục SBOX HRM»; tệp đã xóa khỏi danh sách
///   không bị nhập lại.
class DownloadedDocumentsService {
  DownloadedDocumentsService._();
  static final DownloadedDocumentsService instance = DownloadedDocumentsService._();

  static const retentionDays = 30;
  static const maxStoredBytes = 300 * 1024 * 1024;
  static const _indexFileName = 'index.json';
  static const _importExts = ['xlsx', 'xls', 'csv', 'png', 'jpg', 'jpeg', 'pdf', 'docx'];

  // ── Chỉ để kiểm thử ──
  @visibleForTesting
  String? rootOverride;
  @visibleForTesting
  List<String>? publicDirsOverride;
  @visibleForTesting
  bool? androidOverride;
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  String? _owner;
  List<DownloadedDocument> _items = [];
  // Khóa «p:<đường dẫn>» / «n:<tên gốc>|<dung lượng>» của bản công khai người dùng đã gỡ khỏi danh sách.
  final Set<String> _ignored = {};
  bool _loaded = false;
  bool _legacyCleaned = false;
  Future<void> _lock = Future<void>.value();

  List<DownloadedDocument> get items => List.unmodifiable(_owner == null ? const <DownloadedDocument>[] : _items);

  int get totalBytes => items.fold(0, (s, d) => s + d.sizeBytes);

  /// Web không có thư mục tải xuống cục bộ kiểu app — luôn rỗng, không IO.
  bool get isUnsupportedPlatform => kIsWeb;

  bool get _android => androidOverride ?? dio.isAndroid;

  /// Chỉ Android có thư mục công khai để nhập thủ công.
  bool get isImportSupported => !kIsWeb && _android;

  /// Đặt chủ sở hữu hiện tại (null = chưa đăng nhập: không đọc / ghi gì). Đổi chủ → danh sách trong bộ nhớ được làm mới.
  void setOwner(String? key) {
    if (key == _owner) return;
    _owner = key;
    _items = [];
    _ignored.clear();
    _loaded = false;
  }

  Future<T> _run<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _lock = _lock.catchError((Object _) {}).then((_) async {
      try {
        completer.complete(await fn());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  // ───────────────────────── Đường dẫn ─────────────────────────

  Future<String> _rootPath() async {
    if (rootOverride != null) return rootOverride!;
    final base = await getApplicationDocumentsDirectory();
    return '${base.path}/sbox_downloads';
  }

  static String _safeSegment(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<String> _ownerDir() async => '${await _rootPath()}/${_safeSegment(_owner!)}';

  Future<String> _docDir(String id) async => '${await _ownerDir()}/files/${_safeSegment(id)}';

  static String _safeFileName(String name) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    s = s.replaceAll(RegExp(r'^\.+'), '');
    if (s.isEmpty) return 'tai_lieu';
    if (s.length > 150) {
      final dot = s.lastIndexOf('.');
      final ext = dot > 0 && s.length - dot <= 8 ? s.substring(dot) : '';
      s = '${s.substring(0, 150 - ext.length)}$ext';
    }
    return s;
  }

  // ───────────────────────── Chỉ mục ─────────────────────────

  Future<void> _persist() async {
    if (kIsWeb || _owner == null) return;
    try {
      final dirPath = await _ownerDir();
      await dio.ensureDir(dirPath);
      await dio.writeString(
        '$dirPath/$_indexFileName',
        jsonEncode({
          'version': 2,
          'items': _items.map((e) => e.toJson()).toList(),
          'ignored': _ignored.toList(),
        }),
      );
    } catch (e) {
      debugPrint('DownloadedDocumentsService._persist: $e');
    }
  }

  /// Bản cũ (trước khi tách theo tài khoản) để tệp của mọi người dùng chung một thư mục → xóa bản sao đó một lần.
  /// Bản gốc ở thư mục Tải xuống không bị đụng tới.
  Future<void> _cleanLegacyLocked() async {
    if (_legacyCleaned || kIsWeb) return;
    _legacyCleaned = true;
    try {
      final root = await _rootPath();
      final raw = await dio.readStringIfExists('$root/$_indexFileName');
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded.whereType<Map>()) {
          final p = e['localPath']?.toString();
          if (p != null && p.isNotEmpty) await dio.deleteFileIfExists(p);
        }
      }
      await dio.deleteFileIfExists('$root/$_indexFileName');
    } catch (e) {
      debugPrint('DownloadedDocumentsService legacy cleanup: $e');
    }
  }

  Future<void> _loadLocked({bool force = false}) async {
    if (kIsWeb || _owner == null) {
      _items = [];
      _loaded = true;
      return;
    }
    if (_loaded && !force) return;
    try {
      await _cleanLegacyLocked();
      final dirPath = await _ownerDir();
      await dio.ensureDir(dirPath);
      final rawText = await dio.readStringIfExists('$dirPath/$_indexFileName');
      _items = [];
      _ignored.clear();
      if (rawText != null && rawText.isNotEmpty) {
        try {
          final raw = jsonDecode(rawText);
          final list = raw is Map ? raw['items'] : raw;
          if (list is List) {
            _items = list
                .whereType<Map>()
                .map((e) => DownloadedDocument.fromJson(Map<String, dynamic>.from(e)))
                .where((d) => dio.fileExists(d.localPath))
                .toList();
          }
          if (raw is Map && raw['ignored'] is List) {
            _ignored.addAll((raw['ignored'] as List).map((e) => '$e'));
          }
        } catch (e) {
          debugPrint('DownloadedDocumentsService load error: $e');
          _items = [];
        }
      }
      await _cleanupLocked();
      _items.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      await _persist();
    } catch (e) {
      debugPrint('DownloadedDocumentsService.ensureLoaded: $e');
      _items = [];
    } finally {
      _loaded = true;
    }
  }

  Future<void> ensureLoaded({bool force = false}) => _run(() => _loadLocked(force: force));

  // ───────────────────────── Tự dọn ─────────────────────────

  Future<void> _removePrivateLocked(DownloadedDocument d, {required bool tombstone}) async {
    try {
      await dio.deleteDirIfExists(await _docDir(d.id));
    } catch (_) {}
    if (tombstone) _tombstone(d);
  }

  void _tombstone(DownloadedDocument d) {
    final ext = d.externalUri;
    if (ext == null) return;
    _ignored.add('n:${d.originalName}|${d.sizeBytes}');
    if (!ext.startsWith('content:')) _ignored.add('p:$ext');
  }

  Future<void> _cleanupLocked() async {
    final cutoff = clock().subtract(const Duration(days: retentionDays));
    final expired = _items.where((d) => d.downloadedAt.isBefore(cutoff)).toList();
    for (final d in expired) {
      await _removePrivateLocked(d, tombstone: true);
      _items.remove(d);
    }
    var total = _items.fold<int>(0, (s, d) => s + d.sizeBytes);
    if (total > maxStoredBytes) {
      final oldestFirst = [..._items]..sort((a, b) => a.downloadedAt.compareTo(b.downloadedAt));
      for (final d in oldestFirst) {
        if (total <= maxStoredBytes) break;
        await _removePrivateLocked(d, tombstone: true);
        _items.remove(d);
        total -= d.sizeBytes;
      }
    }
  }

  // ───────────────────────── Thêm / nhập ─────────────────────────

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  Future<DownloadedDocument?> _registerLocked({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    String? category,
    String? sourceModule,
    String? externalUri,
    DateTime? downloadedAt,
  }) async {
    if (_owner == null) return null;
    try {
      if (!_loaded) await _loadLocked();
      final safeName = _safeFileName(filename);
      final id = '${clock().millisecondsSinceEpoch}_${safeName.hashCode.abs()}';
      final dir = await _docDir(id);
      await dio.ensureDir(dir);
      final storedPath = '$dir/$safeName';
      await dio.writeBytes(storedPath, bytes);
      final cat = category?.isNotEmpty == true
          ? category!
          : DownloadDocCategories.inferFromFileName(safeName, hint: sourceModule);

      final doc = DownloadedDocument(
        id: id,
        fileName: safeName,
        displayName: safeName,
        localPath: storedPath,
        mimeType: mimeType,
        category: cat,
        sourceModule: sourceModule,
        sizeBytes: bytes.length,
        downloadedAt: downloadedAt ?? clock(),
        externalUri: externalUri,
      );
      // Cùng một tệp xuất lại trong 2 phút: thay bản cũ (và xóa luôn bản sao cũ — trước đây bị bỏ lại mồ côi).
      final dups = _items
          .where((e) =>
              e.originalName == doc.originalName &&
              e.sizeBytes == doc.sizeBytes &&
              e.downloadedAt.difference(doc.downloadedAt).inMinutes.abs() < 2)
          .toList();
      for (final d in dups) {
        await _removePrivateLocked(d, tombstone: false);
        _items.remove(d);
      }
      _items.insert(0, doc);
      await _cleanupLocked();
      await _persist();
      return doc;
    } catch (e) {
      debugPrint('DownloadedDocumentsService.register: $e');
      return null;
    }
  }

  /// Ghi bản quản lý vào app + thêm chỉ mục (gọi sau khi lưu ra Downloads).
  Future<DownloadedDocument?> register({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    String? category,
    String? sourceModule,
    String? externalUri,
    DateTime? downloadedAt,
  }) {
    if (kIsWeb) return Future.value(null);
    return _run(() => _registerLocked(
          bytes: bytes,
          filename: filename,
          mimeType: mimeType,
          category: category,
          sourceModule: sourceModule,
          externalUri: externalUri,
          downloadedAt: downloadedAt,
        ));
  }

  /// Nhập tệp xuất trước đây còn ở thư mục SBOX HRM (Tải xuống / Ảnh) — chỉ Android, chỉ khi người dùng yêu cầu.
  /// Bỏ qua tệp đã có, tệp đã gỡ khỏi danh sách và tệp cũ hơn thời hạn tự dọn. Trả về số tệp nhập thêm.
  Future<int> importFromPublicFolders() => _run(() async {
        if (kIsWeb || !_android || _owner == null) return 0;
        if (!_loaded) await _loadLocked();
        final dirs = publicDirsOverride ??
            const ['/storage/emulated/0/Download/SBOX HRM', '/storage/emulated/0/Pictures/SBOX HRM'];
        final cutoff = clock().subtract(const Duration(days: retentionDays));
        var added = 0;
        for (final dirPath in dirs) {
          if (!await dio.dirExists(dirPath)) continue;
          for (final entityPath in await dio.listFiles(dirPath)) {
            final name = dio.basename(entityPath);
            final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
            if (!_importExts.contains(ext)) continue;
            try {
              final size = await dio.fileLength(entityPath);
              final modified = await dio.lastModified(entityPath);
              if (modified.isBefore(cutoff)) continue;
              final known = _items.any((e) => e.originalName == name && e.sizeBytes == size) ||
                  _ignored.contains('p:$entityPath') ||
                  _ignored.contains('n:$name|$size');
              if (known) continue;
              final doc = await _registerLocked(
                bytes: await dio.readBytes(entityPath),
                filename: name,
                mimeType: _mimeFromName(name),
                category: DownloadDocCategories.inferFromFileName(name),
                downloadedAt: modified,
                externalUri: entityPath,
              );
              if (doc != null) added++;
            } catch (_) {}
          }
        }
        _items.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
        await _persist();
        return added;
      });

  // ───────────────────────── Sửa / xóa ─────────────────────────

  Future<bool> rename(String id, String newDisplayName) => _run(() async {
        if (kIsWeb || _owner == null) return false;
        if (!_loaded) await _loadLocked();
        final idx = _items.indexWhere((e) => e.id == id);
        if (idx < 0) return false;
        final doc = _items[idx];
        var base = newDisplayName.trim();
        if (base.isEmpty) return false;
        final ext = doc.extension;
        if (ext.isNotEmpty && !base.toLowerCase().endsWith(ext)) base = '$base$ext';
        base = _safeFileName(base);
        final newPath = '${await _docDir(doc.id)}/$base';
        try {
          if (newPath != doc.localPath) await dio.moveFile(doc.localPath, newPath);
          _items[idx] = doc.copyWith(fileName: base, displayName: base, localPath: newPath);
          await _persist();
          return true;
        } catch (e) {
          debugPrint('rename document: $e');
          return false;
        }
      });

  /// Xóa khỏi danh sách (và bản trong app). [deletePublicCopy]: xóa luôn bản ở thư mục Tải xuống / Ảnh.
  /// Không xóa bản công khai thì nó không bị nhập lại về danh sách.
  Future<bool> delete(String id, {bool deletePublicCopy = false}) async =>
      (await deleteMany([id], deletePublicCopy: deletePublicCopy)) > 0;

  Future<int> deleteMany(Iterable<String> ids, {bool deletePublicCopy = false}) => _run(() async {
        if (kIsWeb || _owner == null) return 0;
        if (!_loaded) await _loadLocked();
        final idSet = ids.toSet();
        final targets = _items.where((e) => idSet.contains(e.id)).toList();
        for (final doc in targets) {
          var publicGone = false;
          final ext = doc.externalUri;
          if (deletePublicCopy && ext != null) publicGone = await pub.deletePublicCopy(ext);
          await _removePrivateLocked(doc, tombstone: !publicGone);
          _items.remove(doc);
        }
        if (targets.isNotEmpty) await _persist();
        return targets.length;
      });

  // ───────────────────────── Lọc / sắp xếp ─────────────────────────

  List<DownloadedDocument> filter({
    String category = DownloadDocCategories.all,
    String type = DownloadFileKinds.all,
    DateTime? from,
    DateTime? to,
    String search = '',
    DownloadSort sort = DownloadSort.newest,
  }) {
    var list = List<DownloadedDocument>.from(items);
    if (category != DownloadDocCategories.all) {
      list = list.where((e) => e.category == category).toList();
    }
    if (type != DownloadFileKinds.all) {
      list = list.where((e) => e.kind == type).toList();
    }
    if (from != null) {
      final start = DateTime(from.year, from.month, from.day);
      list = list.where((e) => !e.downloadedAt.isBefore(start)).toList();
    }
    if (to != null) {
      final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
      list = list.where((e) => !e.downloadedAt.isAfter(end)).toList();
    }
    if (search.trim().isNotEmpty) {
      final q = DownloadDocCategories.normalize(search);
      final raw = search.trim().toLowerCase();
      list = list
          .where((e) =>
              e.displayName.toLowerCase().contains(raw) ||
              e.category.toLowerCase().contains(raw) ||
              (q.isNotEmpty && DownloadDocCategories.normalize(e.displayName).contains(q)))
          .toList();
    }
    switch (sort) {
      case DownloadSort.newest:
        list.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      case DownloadSort.oldest:
        list.sort((a, b) => a.downloadedAt.compareTo(b.downloadedAt));
      case DownloadSort.name:
        list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      case DownloadSort.size:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    }
    return list;
  }

  List<String> categoriesInUse() {
    final set = items.map((d) => d.category).toSet();
    final ordered = DownloadDocCategories.presets
        .where((c) => c == DownloadDocCategories.all || set.contains(c))
        .toList();
    for (final c in set) {
      if (!ordered.contains(c)) ordered.add(c);
    }
    return ordered;
  }
}
