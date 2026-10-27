import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../services/api_service.dart';
import '../theme/sbox_tokens.dart';
import '../widgets/notification_overlay.dart';

/// «Nhật ký thao tác AI»: mọi việc Trợ lý ảo đã làm thay người dùng (lập / sửa / xóa / hủy phiếu, duyệt đơn) —
/// ai yêu cầu, câu lệnh gốc, nội dung phiếu, kết quả, mã chứng từ. Chủ cửa hàng / người sửa được thiết lập AI xem được
/// của cả cửa hàng; người khác chỉ xem của mình. Hoàn tác được trong vài phút (chỉ người đã làm).
class AiActionLogScreen extends StatefulWidget {
  const AiActionLogScreen({super.key});

  @override
  State<AiActionLogScreen> createState() => _AiActionLogScreenState();
}

class _AiActionLogScreenState extends State<AiActionLogScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  bool _wholeStore = false;
  bool _canSeeWholeStore = false;

  /// all | high | failed | undone
  String _filter = 'all';
  List<Map<String, dynamic>> _items = const [];
  final Set<String> _undoing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getAiActionLog(
      all: _wholeStore,
      status: switch (_filter) { 'failed' => 'failed', 'undone' => 'undone', _ => null },
      highRisk: _filter == 'high',
    );
    if (!mounted) return;
    final d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : const <String, dynamic>{};
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true) {
        _canSeeWholeStore = d['canSeeWholeStore'] == true;
        _items = ((d['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        _error = r['message']?.toString() ?? 'Không tải được nhật ký';
      }
    });
  }

  Future<void> _undo(Map<String, dynamic> it) async {
    final id = it['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _undoing.add(id));
    final r = await _api.undoAiAction(id);
    if (!mounted) return;
    setState(() => _undoing.remove(id));
    if (r['isSuccess'] == true) {
      final d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : const <String, dynamic>{};
      NotificationOverlayManager().showSuccess(title: 'Đã hoàn tác', message: d['message']?.toString() ?? '');
      _load();
    } else {
      NotificationOverlayManager().showError(
          title: 'Không hoàn tác được', message: r['message']?.toString() ?? tr('Vui lòng thử lại'));
    }
  }

  static (String, Color) _statusLabel(String s) => switch (s) {
        'done' => ('Đã thực hiện', SboxColors.success),
        'failed' => ('Lỗi', SboxColors.danger),
        'undone' => ('Đã hoàn tác', SboxColors.slate500),
        'discarded' => ('Đã bỏ', SboxColors.slate500),
        'running' || 'undoing' => ('Đang xử lý', const Color(0xFFB45309)),
        _ => (s, SboxColors.slate500),
      };

  static String _when(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    // Máy chủ lưu giờ UTC (không kèm múi) → đổi về giờ máy.
    final local = (d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second)).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Nhật ký thao tác AI')),
        actions: [
          IconButton(tooltip: tr('Tải lại'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (_canSeeWholeStore)
              FilterChip(
                selected: _wholeStore,
                label: Text(tr('Cả cửa hàng')),
                avatar: const Icon(Icons.groups_outlined, size: 16),
                onSelected: (v) {
                  setState(() => _wholeStore = v);
                  _load();
                },
              ),
            for (final (code, label) in [
              ('all', 'Tất cả'),
              ('high', 'Xóa / hủy / duyệt hàng loạt'),
              ('failed', 'Lỗi'),
              ('undone', 'Đã hoàn tác'),
            ])
              ChoiceChip(
                selected: _filter == code,
                label: Text(tr(label)),
                onSelected: (_) {
                  setState(() => _filter = code);
                  _load();
                },
              ),
          ]),
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _load, child: Text(tr('Thử lại'))),
        ]),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('Chưa có thao tác nào qua Trợ lý ảo.'),
              textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _row(_items[i]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> it) {
    final status = it['status']?.toString() ?? '';
    final (label, tone) = _statusLabel(status);
    final high = it['risk']?.toString() == 'high';
    final lines = ((it['lines'] as List?) ?? const []).whereType<Map>().toList();
    final id = it['id']?.toString() ?? '';
    final prompt = it['prompt']?.toString() ?? '';
    final result = it['resultMessage']?.toString() ?? '';
    final who = it['userName']?.toString();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: high ? SboxColors.danger.withValues(alpha: 0.4) : SboxColors.slate200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          leading: Icon(high ? Icons.warning_amber_rounded : Icons.auto_awesome_outlined,
              color: high ? SboxColors.danger : SboxColors.violet),
          title: Text(tr(it['title']?.toString() ?? ''),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(_when(it['createdAt']?.toString()), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              if (_wholeStore && who != null && who.isNotEmpty)
                Text(who, style: const TextStyle(fontSize: 12, color: SboxColors.slate700, fontWeight: FontWeight.w600)),
              Text(tr(label), style: TextStyle(fontSize: 12, color: tone, fontWeight: FontWeight.w700)),
              if ((it['docNo']?.toString() ?? '').isNotEmpty)
                Text(it['docNo'].toString(), style: const TextStyle(fontSize: 12, color: SboxColors.slate700)),
            ]),
          ),
          trailing: it['canUndo'] == true
              ? (_undoing.contains(id)
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton.icon(
                      onPressed: () => _undo(it),
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: Text(tr('Hoàn tác')),
                    ))
              : null,
          children: [
            if (prompt.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  // Câu người dùng nói / gõ — giữ nguyên, không dịch.
                  child: Text('«$prompt»',
                      style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: SboxColors.slate700)),
                ),
              ),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 110,
                    child: Text(tr(l['label']?.toString() ?? ''),
                        style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                  ),
                  Expanded(
                    child: Text(l['value']?.toString() ?? '',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SboxColors.slate900)),
                  ),
                ]),
              ),
            if (result.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr(result), style: TextStyle(fontSize: 12, color: tone)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
