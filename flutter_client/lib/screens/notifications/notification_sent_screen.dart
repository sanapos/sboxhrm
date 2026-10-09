import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/notifications/notification_category_meta.dart';

/// Các đợt thông báo đã gửi cho nhân viên: ai đã đọc, ai chưa, nhắc lại người chưa đọc.
class NotificationSentScreen extends StatefulWidget {
  const NotificationSentScreen({super.key});

  @override
  State<NotificationSentScreen> createState() => _NotificationSentScreenState();
}

class _NotificationSentScreenState extends State<NotificationSentScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _scheduled = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _cancelScheduled(String id) async {
    final r = await _api.cancelScheduledNotification(id);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _load();
    } else {
      NotificationOverlayManager()
          .showError(title: 'Không hủy được', message: r['message']?.toString() ?? '');
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final sc = await _api.getScheduledNotifications();
    if (sc['isSuccess'] == true && sc['data'] is List) {
      _scheduled = [
        for (final x in sc['data'] as List)
          if (x is Map) Map<String, dynamic>.from(x),
      ];
    }
    final r = await _api.getSentNotifications();
    if (!mounted) return;
    if (r['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = r['message']?.toString() ?? 'Không tải được danh sách';
      });
      return;
    }
    final d = r['data'] as Map?;
    setState(() {
      _loading = false;
      _items = [
        for (final x in (d?['items'] as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];
    });
  }

  String _when(dynamic v) {
    final d = parseApiUtcDateTime(v?.toString())?.toLocal();
    return d == null ? '' : DateFormat('HH:mm dd/MM/yyyy').format(d);
  }

  Widget _scheduledSection() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.schedule_send_rounded, size: 18, color: SboxColors.brand500),
            const SizedBox(width: 8),
            Text(tr('Hẹn giờ gửi'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          for (final x in _scheduled)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr('${x['title']}'), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(tr(switch ((x['status'] as num?)?.toInt() ?? 0) {
                0 => '${_when(x['sendAt'])} · ${x['recipientCount']} người',
                1 => 'Đang gửi…',
                2 => 'Đã gửi lúc ${_when(x['sentAt'])}',
                3 => 'Lỗi: ${x['error'] ?? ''}',
                _ => 'Đã hủy',
              })),
              trailing: ((x['status'] as num?)?.toInt() ?? 0) == 0
                  ? TextButton(onPressed: () => _cancelScheduled(x['id'].toString()), child: Text(tr('Hủy')))
                  : null,
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(
        title: Text(tr('Thông báo đã gửi')),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)))
              : _items.isEmpty && _scheduled.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(tr('Chưa gửi thông báo nào cho nhân viên.'),
                            style: const TextStyle(color: SboxColors.slate500)),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length + (_scheduled.isEmpty ? 0 : 1),
                        itemBuilder: (_, idx) {
                          if (_scheduled.isNotEmpty && idx == 0) return _scheduledSection();
                          final i = _scheduled.isEmpty ? idx : idx - 1;
                          final b = _items[i];
                          final total = (b['total'] as num?)?.toInt() ?? 0;
                          final read = (b['read'] as num?)?.toInt() ?? 0;
                          final meta = NotificationCategoryMeta.of(b['categoryCode']?.toString());
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14), side: const BorderSide(color: SboxColors.slate200)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => _SentDetailScreen(batchId: b['batchId'].toString())));
                                if (mounted) _load();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(meta.icon, size: 18, color: meta.color),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(tr('${b['title']}'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w800)),
                                    ),
                                    Text(_when(b['sentAt']),
                                        style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(tr('${b['body']}'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, color: SboxColors.slate600)),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      minHeight: 6,
                                      value: total == 0 ? 0 : read / total,
                                      backgroundColor: SboxColors.slate200,
                                      color: read == total ? SboxColors.success : SboxColors.brand500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(tr('$read/$total người đã đọc'),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _SentDetailScreen extends StatefulWidget {
  const _SentDetailScreen({required this.batchId});
  final String batchId;

  @override
  State<_SentDetailScreen> createState() => _SentDetailScreenState();
}

class _SentDetailScreenState extends State<_SentDetailScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _d;
  bool _onlyUnread = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.getSentNotificationDetail(widget.batchId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true) {
        _d = Map<String, dynamic>.from(r['data'] as Map);
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Không tải được';
      }
    });
  }

  Future<void> _remind() async {
    setState(() => _busy = true);
    final r = await _api.remindUnreadNotification(widget.batchId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã nhắc', message: tr('Đã gửi nhắc cho ${(r['data'] as Map?)?['reminded'] ?? 0} người chưa đọc'));
      _load();
    } else {
      NotificationOverlayManager().showError(title: 'Chưa nhắc được', message: r['message']?.toString() ?? '');
    }
  }

  Future<void> _recall() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thu hồi thông báo?')),
        content: Text(tr(
            'Thông báo sẽ biến mất khỏi trung tâm thông báo của những người CHƯA đọc. Người đã đọc giữ nguyên; thông báo đã hiện trên màn hình điện thoại không gỡ được.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Thu hồi'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final r = await _api.recallSentNotification(widget.batchId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã thu hồi', message: tr('Đã gỡ khỏi ${(r['data'] as Map?)?['recalled'] ?? 0} người chưa đọc'));
      _load();
    } else {
      NotificationOverlayManager().showError(title: 'Không thu hồi được', message: r['message']?.toString() ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final recipients = [
      for (final x in (d?['recipients'] as List? ?? const []))
        if (x is Map) Map<String, dynamic>.from(x),
    ];
    final shown = _onlyUnread ? recipients.where((r) => r['isRead'] != true).toList() : recipients;
    final total = (d?['total'] as num?)?.toInt() ?? 0;
    final read = (d?['read'] as num?)?.toInt() ?? 0;
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(
        title: Text(tr('Chi tiết thông báo')),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: SboxColors.slate200),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('${d!['title']}'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(tr('${d['body']}'), style: const TextStyle(color: SboxColors.slate700, height: 1.35)),
                      const SizedBox(height: 10),
                      Text(tr('$read/$total người đã đọc'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    FilterChip(
                      label: Text(tr('Chỉ người chưa đọc (${total - read})')),
                      selected: _onlyUnread,
                      onSelected: (v) => setState(() => _onlyUnread = v),
                    ),
                    const Spacer(),
                    if (total - read > 0)
                      TextButton.icon(
                        onPressed: _busy ? null : _recall,
                        icon: const Icon(Icons.undo_rounded, size: 18, color: SboxColors.danger),
                        label: Text(tr('Thu hồi'), style: const TextStyle(color: SboxColors.danger)),
                      ),
                    if (d['canRemind'] == true)
                      FilledButton.icon(
                        onPressed: _busy ? null : _remind,
                        icon: const Icon(Icons.notifications_active_rounded, size: 18),
                        label: Text(tr('Nhắc người chưa đọc')),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  if (d['canRemind'] != true && total - read > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(tr('Đã nhắc gần đây — có thể nhắc lại sau 2 giờ.'),
                          style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                    ),
                  for (final r in shown)
                    ListTile(
                      dense: true,
                      tileColor: Colors.white,
                      leading: Icon(r['isRead'] == true ? Icons.done_all_rounded : Icons.schedule_rounded,
                          color: r['isRead'] == true ? SboxColors.success : SboxColors.warning),
                      title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        if ((r['code']?.toString() ?? '').isNotEmpty) '${r['code']}',
                        if ((r['department']?.toString() ?? '').isNotEmpty) '${r['department']}',
                      ].join(' · ')),
                      trailing: Text(
                        r['isRead'] == true
                            ? DateFormat('HH:mm dd/MM')
                                .format((parseApiUtcDateTime(r['readAt']?.toString()) ?? DateTime.now()).toLocal())
                            : tr('Chưa đọc'),
                        style: TextStyle(
                            fontSize: 12, color: r['isRead'] == true ? SboxColors.slate500 : SboxColors.warningText),
                      ),
                    ),
                ]),
    );
  }
}
