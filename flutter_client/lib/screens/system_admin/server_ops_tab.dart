import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';

class ServerOpsTab extends StatefulWidget {
  const ServerOpsTab({super.key});

  @override
  State<ServerOpsTab> createState() => ServerOpsTabState();
}

class ServerOpsTabState extends State<ServerOpsTab> {
  final _api = ApiService();
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _storage;
  List<Map<String, dynamic>> _files = [];
  String _kind = 'pos';
  final _version = TextEditingController();
  final _notes = TextEditingController();
  bool _activate = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    _version.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getServerStorage(),
        _api.getServerReleases(),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0]['isSuccess'] == true && results[0]['data'] is Map) {
          _storage = Map<String, dynamic>.from(results[0]['data'] as Map);
        }
        if (results[1]['isSuccess'] == true && results[1]['data'] is Map) {
          _files = AdminHelpers.extractList(
              (results[1]['data'] as Map)['files'] ?? (results[1]['data'] as Map)['Files']);
        }
      });
    } catch (e) {
      debugPrint('ServerOpsTab: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _cleanup(String scope, {required bool apply}) async {
    if (apply) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Xác nhận dọn rác')),
          content: Text(tr(scope == 'host'
              ? 'Xóa image Docker không chạy, cache build, journal, rác /root /opt /tmp. Không đụng DB, upload, container đang chạy.'
              : 'Xóa file Flutter lẫn trong wwwroot API (canvaskit, index.html…).')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Dọn'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    final res = await _api.cleanupServer(scope: scope, apply: apply);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] == true && res['data'] is Map && !apply) {
      await _showCleanupPreview(Map<String, dynamic>.from(res['data'] as Map));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(_msg(res, apply ? 'Đã gửi yêu cầu dọn' : 'Thất bại')))),
      );
    }
    await loadData();
  }

  Future<void> _showCleanupPreview(Map<String, dynamic> data) async {
    final app = data['app'] is Map ? Map<String, dynamic>.from(data['app'] as Map) : null;
    final host = data['host'] is Map ? Map<String, dynamic>.from(data['host'] as Map) : null;
    final items = AdminHelpers.extractList(app?['items']);
    final lines = <String>[
      if (host?['message'] != null) '${host!['message']}',
      if (app != null) 'Rác app ~ ${_bytes(_asNum(app['freedBytes']))}',
      ...items.map((e) => '• ${e['path']} (${_bytes(_asNum(e['bytes']))})'),
    ];
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xem trước dọn rác')),
        content: SizedBox(
          width: 420,
          child: Text(
            tr(lines.isEmpty ? 'Không thấy rác app.' : lines.join('\n')),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
        ],
      ),
    );
  }

  String _msg(Map res, String fallback) {
    final top = res['message']?.toString() ?? '';
    if (top.isNotEmpty) return top;
    final data = res['data'];
    if (data is Map) {
      final nested = data['message']?.toString() ??
          (data['host'] is Map ? (data['host']['message']?.toString() ?? '') : '');
      if (nested.isNotEmpty) return nested;
    }
    return fallback;
  }

  Future<void> _pickUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['apk', 'exe', 'msi', 'zip', 'json', 'bin'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Không đọc được file (thử lại trên web/desktop)'))),
      );
      return;
    }
    setState(() => _busy = true);
    final res = await _api.uploadServerRelease(
      bytes: bytes,
      fileName: f.name,
      kind: _kind,
      versionName: _version.text.trim(),
      releaseNotes: _notes.text.trim(),
      activate: _activate,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(_msg(res, res['isSuccess'] == true ? 'Đã tải lên' : 'Upload thất bại'))),
    ));
    await loadData();
  }

  Future<void> _delete(String name, bool protectedFile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa $name?')),
        content: Text(tr(protectedFile
            ? 'Đây là file OTA đang dùng. Xóa sẽ làm mất link cập nhật.'
            : 'Xóa file khỏi server.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xóa'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final res = await _api.deleteServerRelease(name, force: protectedFile);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(_msg(res, res['isSuccess'] == true ? 'Đã xóa' : 'Không xóa được'))),
    ));
    await loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _diskCard(),
          const SizedBox(height: 16),
          _cleanupCard(),
          const SizedBox(height: 16),
          _uploadCard(),
          const SizedBox(height: 16),
          _filesCard(),
        ],
      ),
    );
  }

  Widget _diskCard() {
    final used = _asNum(_storage?['diskUsedMb']);
    final total = _asNum(_storage?['diskTotalMb']);
    final free = _asNum(_storage?['diskFreeMb']);
    final pct = _asNum(_storage?['diskPercent']);
    final host = _storage?['hostGc'];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(borderColor: AdminHelpers.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Ổ đĩa server'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Text(
            tr(total > 0
                ? '${_gb(used)} / ${_gb(total)} · còn ${_gb(free)} (${pct.toStringAsFixed(0)}%)'
                : 'Chưa đo được'),
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total > 0 ? (pct / 100).clamp(0, 1) : 0,
            minHeight: 10,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 8),
          Text(
            tr('wwwroot ${_gb(_asNum(_storage?['wwwrootMb']))} · downloads ${_gb(_asNum(_storage?['downloadsMb']))} · rác app ~ ${_bytes(_asNum(_storage?['junkBytes']))}'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (_storage?['hostGcReady'] != true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('Chưa gắn /opt/zkteco/gc — dọn host từ Super Admin sẽ không chạy.'),
                style: TextStyle(fontSize: 12, color: Colors.orange[800]),
              ),
            ),
          if (host is Map && host['ranAt'] != null) ...[
            const SizedBox(height: 6),
            Text(
              tr('Lần dọn host: ${host['ranAt']} · giải phóng ${_kb(host['freedKb'])}'),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cleanupCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Dọn rác'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            tr('An toàn: không xóa Postgres, Redis, upload cửa hàng, image đang chạy.'),
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _cleanup('app', apply: false),
              icon: const Icon(Icons.preview, size: 18),
              label: Text(tr('Xem rác app')),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _cleanup('app', apply: true),
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: Text(tr('Dọn wwwroot')),
            ),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _cleanup('host', apply: true),
              icon: const Icon(Icons.cleaning_services, size: 18),
              label: Text(tr('Dọn host (Docker + rác deploy)')),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _uploadCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Tải phần mềm / APK lên server'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            tr('Chỉ nhận .apk .exe .msi .zip .json .bin · tối đa 280 MB · kiểm tra chữ ký file.'),
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final k in const ['pos', 'hrm', 'agent', 'software'])
              ChoiceChip(
                label: Text(tr(k == 'pos'
                    ? 'POS APK'
                    : k == 'hrm'
                        ? 'HRM APK'
                        : k == 'agent'
                            ? 'Print Agent'
                            : 'Khác')),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _version,
            decoration: InputDecoration(
              labelText: tr('Phiên bản (vd. 1.0.183)'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            decoration: InputDecoration(
              labelText: tr('Ghi chú phát hành'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Đặt làm bản phát hành hiện tại (OTA)')),
            value: _activate,
            onChanged: (v) => setState(() => _activate = v),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _pickUpload,
            icon: const Icon(Icons.upload_file),
            label: Text(tr(_busy ? 'Đang tải…' : 'Chọn file và tải lên')),
          ),
        ],
      ),
    );
  }

  Widget _filesCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('File trên server (/downloads)'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (_files.isEmpty)
            Text(tr('Chưa có file'), style: TextStyle(color: Colors.grey[600])),
          for (final f in _files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_iconFor('${f['kind']}')),
              title: Text('${f['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${_bytes(_asNum(f['bytes']))} · ${f['kind'] ?? ''} · ${f['updatedAt'] ?? ''}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: IconButton(
                tooltip: tr('Xóa'),
                onPressed: _busy ? null : () => _delete('${f['name']}', f['protectedFile'] == true),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(String kind) => switch (kind) {
        'pos' || 'hrm' => Icons.android,
        'agent' => Icons.print,
        'gateway' => Icons.memory,
        'meta' => Icons.description,
        _ => Icons.inventory_2,
      };

  double _asNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  String _gb(num mb) {
    if (mb <= 0) return '0';
    final gb = mb / 1024;
    if (gb >= 10) return '${gb.toStringAsFixed(0)} GB';
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  String _kb(dynamic raw) {
    final kb = _asNum(raw);
    return _gb(kb / 1024);
  }

  String _bytes(num n) {
    if (n >= 1024 * 1024 * 1024) return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (n >= 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(0)} MB';
    if (n >= 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${n.toStringAsFixed(0)} B';
  }
}
