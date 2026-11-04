import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_basics.dart';
import '../../widgets/sbox/sbox_charts.dart';

/// Số việc chờ duyệt — tab «Cần duyệt» và khối «Cần xử lý» trên Tổng quan cùng đọc.
final bossInboxCount = ValueNotifier<int>(0);

/// Loại việc chờ duyệt (khớp `kind` của GET api/boss/inbox).
class BossInboxKind {
  const BossInboxKind(this.label, this.icon, this.tone);
  final String label;
  final IconData icon;
  final SboxTone tone;

  static const all = <String, BossInboxKind>{
    'posApproval': BossInboxKind('Máy bán hàng xin duyệt', Icons.point_of_sale_rounded, SboxTone.danger),
    'leave': BossInboxKind('Nghỉ phép', Icons.beach_access_rounded, SboxTone.brand),
    'overtime': BossInboxKind('Tăng ca', Icons.more_time_rounded, SboxTone.violet),
    'correction': BossInboxKind('Sửa công', Icons.edit_calendar_rounded, SboxTone.warning),
    'mobileAttendance': BossInboxKind('Chấm công điện thoại', Icons.phone_android_rounded, SboxTone.brand),
    'shiftSwap': BossInboxKind('Đổi ca', Icons.swap_horiz_rounded, SboxTone.violet),
    'shift': BossInboxKind('Ca theo giờ', Icons.schedule_rounded, SboxTone.neutral),
    'advance': BossInboxKind('Ứng lương', Icons.payments_rounded, SboxTone.success),
    'tripAdvance': BossInboxKind('Tạm ứng công tác', Icons.flight_takeoff_rounded, SboxTone.success),
    'tripSettlement': BossInboxKind('Quyết toán công tác', Icons.receipt_rounded, SboxTone.success),
    'penalty': BossInboxKind('Phiếu phạt', Icons.gavel_rounded, SboxTone.danger),
    'cash': BossInboxKind('Phiếu thu chi', Icons.account_balance_wallet_rounded, SboxTone.warning),
  };

  static BossInboxKind of(String kind) =>
      all[kind] ?? const BossInboxKind('Khác', Icons.inbox_rounded, SboxTone.neutral);
}

/// Duyệt / từ chối một việc bằng đúng endpoint sẵn có của loại đó. Trả về câu lỗi, null nếu được.
Future<String?> bossDecide(String kind, String id, {required bool approve, String? reason}) async {
  final api = ApiService();
  final Map<String, dynamic> r;
  switch (kind) {
    case 'posApproval':
      r = await api.decidePosRemoteApproval(id, approve: approve, reason: reason);
    case 'leave':
      r = approve ? await api.approveLeave(id) : await api.rejectLeave(id, reason);
    case 'overtime':
      r = approve ? await api.approveOvertime(id) : await api.rejectOvertime(id, reason: reason);
    case 'correction':
      r = await api.approveAttendanceCorrection(requestId: id, isApproved: approve, approverNote: reason);
    case 'mobileAttendance':
      r = await api.approveMobileAttendance(recordId: id, approved: approve, rejectionReason: reason);
    case 'shiftSwap':
      r = await api.approveShiftSwap(id, approve: approve, rejectionReason: reason);
    case 'shift':
      r = approve ? await api.approveShift(id) : await api.rejectShift(id, reason: reason);
    case 'advance':
      r = await api.approveAdvanceRequest(requestId: id, isApproved: approve, rejectionReason: reason);
    case 'tripAdvance':
      r = await api.approveBusinessTripAdvance(id, approve, rejectionReason: reason);
    case 'tripSettlement':
      r = await api.approveBusinessTripSettlement(id, approve, rejectionReason: reason);
    case 'penalty':
      r = approve ? await api.approvePenaltyTicket(id) : await api.cancelPenaltyTicket(id, reason: reason);
    case 'cash':
      r = await api.updateCashTransactionStatus(
          id, approve ? {'status': 'Completed', 'isPaid': true} : {'status': 'Cancelled'});
    default:
      return 'Loại việc này chưa duyệt được trên SBOX BOSS';
  }
  if (r['isSuccess'] == true) return null;
  return r['message']?.toString() ?? 'Không xử lý được';
}

/// SBOX BOSS — «Cần duyệt»: mọi việc chờ chủ / quản lý, lọc theo loại, duyệt / từ chối từng việc
/// hoặc chọn nhiều để duyệt cùng lúc. Từ chối bắt buộc ghi lý do.
class BossInboxScreen extends StatefulWidget {
  const BossInboxScreen({super.key});

  @override
  State<BossInboxScreen> createState() => _BossInboxScreenState();
}

class _BossInboxScreenState extends State<BossInboxScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _items = const [];
  Map<String, int> _counts = const {};
  String? _error;
  bool _loading = false;
  bool _loaded = false;
  String _kind = 'all';
  final Set<String> _selected = {};
  final Set<String> _busy = {};
  Timer? _timer;
  String? _branch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _branch = BranchSession.instance.currentId;
    BranchSession.instance.addListener(_onBranchChanged);
    _load();
    // Yêu cầu «duyệt từ xa» của máy POS chỉ sống 3 phút → hỏi lại thường xuyên khi chưa có push.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BranchSession.instance.removeListener(_onBranchChanged);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  void _onBranchChanged() {
    if (BranchSession.instance.currentId == _branch) return;
    _branch = BranchSession.instance.currentId;
    _load();
  }

  static String _key(Map<String, dynamic> it) => '${it['kind']}:${it['id']}';

  Future<void> _load({bool silent = false}) async {
    if (_loading) return;
    _loading = true;
    final r = await ApiService().getBossInbox();
    _loading = false;
    if (!mounted) return;
    setState(() {
      if (r['isSuccess'] == true && r['data'] is Map) {
        final d = r['data'] as Map;
        _items = [for (final it in (d['items'] as List? ?? const [])) if (it is Map) Map<String, dynamic>.from(it)];
        _counts = {
          for (final e in ((d['counts'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt(),
        };
        _selected.removeWhere((k) => !_items.any((it) => _key(it) == k));
        _error = null;
        _loaded = true;
        bossInboxCount.value = _items.length;
      } else if (!silent || !_loaded) {
        _error = r['message']?.toString() ?? 'Không tải được việc chờ duyệt';
      }
    });
  }

  Future<String?> _askReason(String title) async {
    final ctrl = TextEditingController();
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            SboxSpace.lg, 0, SboxSpace.lg, MediaQuery.viewInsetsOf(ctx).bottom + SboxSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr(title), style: SboxType.titleSmStyle()),
          const SizedBox(height: SboxSpace.md),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(labelText: tr('Lý do từ chối'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: SboxSpace.md),
          SboxButton(
            label: 'Từ chối',
            expand: true,
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) return;
              Navigator.pop(ctx, t);
            },
          ),
        ]),
      ),
    );
    ctrl.dispose();
    return res;
  }

  Future<void> _decide(List<Map<String, dynamic>> targets, {required bool approve}) async {
    String? reason;
    if (!approve) {
      reason = await _askReason(targets.length == 1 ? 'Từ chối việc này?' : 'Từ chối ${targets.length} việc?');
      if (reason == null) return;
    }
    setState(() => _busy.addAll(targets.map(_key)));
    var ok = 0;
    final errors = <String>[];
    for (final it in targets) {
      final err = await bossDecide('${it['kind']}', '${it['id']}', approve: approve, reason: reason);
      if (err == null) {
        ok++;
      } else {
        errors.add('${it['person'] ?? ''}: $err');
      }
    }
    if (!mounted) return;
    setState(() {
      _busy.removeAll(targets.map(_key));
      _selected.clear();
    });
    final verb = approve ? 'duyệt' : 'từ chối';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      duration: Duration(seconds: errors.isEmpty ? 2 : 6),
      content: Text(errors.isEmpty
          ? tr('Đã $verb $ok việc')
          : tr('Đã $verb $ok việc, lỗi ${errors.length}: ${errors.first}')),
    ));
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      if (_error != null) {
        return SboxEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Không tải được việc chờ duyệt',
          message: _error,
          action: SboxButton(label: 'Thử lại', onPressed: _load),
        );
      }
      return const SboxLoading(message: 'Đang tải việc chờ duyệt…');
    }
    final shown = _kind == 'all' ? _items : _items.where((it) => it['kind'] == _kind).toList();
    final selectedItems = _items.where((it) => _selected.contains(_key(it))).toList();
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: SboxSpace.md, vertical: SboxSpace.sm),
          children: [
            _chip('all', '${tr('Tất cả')} (${_items.length})'),
            for (final e in BossInboxKind.all.entries)
              if ((_counts[e.key] ?? 0) > 0) _chip(e.key, '${tr(e.value.label)} (${_counts[e.key]})'),
          ],
        ),
      ),
      if (selectedItems.isNotEmpty)
        Material(
          color: SboxColors.brand50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SboxSpace.md, vertical: SboxSpace.xs),
            child: Row(children: [
              Expanded(child: Text(tr('Đã chọn ${selectedItems.length}'), style: SboxType.bodyStrong(SboxColors.brand800))),
              TextButton(onPressed: () => setState(_selected.clear), child: Text(tr('Bỏ chọn'))),
              TextButton(
                onPressed: () => _decide(selectedItems, approve: false),
                child: Text(tr('Từ chối'), style: const TextStyle(color: SboxColors.dangerText)),
              ),
              FilledButton(onPressed: () => _decide(selectedItems, approve: true), child: Text(tr('Duyệt'))),
            ]),
          ),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: shown.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  SboxEmptyState(icon: Icons.task_alt_rounded, title: 'Không còn việc chờ duyệt'),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.xs, SboxSpace.lg, SboxSpace.xxl),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: SboxSpace.sm),
                  itemBuilder: (_, i) => _card(shown[i]),
                ),
        ),
      ),
    ]);
  }

  Widget _chip(String kind, String label) => Padding(
        padding: const EdgeInsets.only(right: SboxSpace.sm),
        child: ChoiceChip(
          label: Text(label),
          selected: _kind == kind,
          onSelected: (_) => setState(() => _kind = kind),
        ),
      );

  Widget _card(Map<String, dynamic> it) {
    final kind = BossInboxKind.of('${it['kind']}');
    final key = _key(it);
    final busy = _busy.contains(key);
    final selected = _selected.contains(key);
    final amount = it['amount'];
    void toggle() => setState(() => selected ? _selected.remove(key) : _selected.add(key));
    return Material(
      color: selected ? SboxColors.brand50 : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: SboxRadius.lgAll,
        side: BorderSide(color: selected ? SboxColors.brand300 : SboxColors.border),
      ),
      child: InkWell(
        borderRadius: SboxRadius.lgAll,
        onLongPress: toggle,
        onTap: _selected.isNotEmpty ? toggle : null,
        child: Padding(
          padding: const EdgeInsets.all(SboxSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: kind.tone.bg, borderRadius: SboxRadius.mdAll),
                child: Icon(kind.icon, size: 20, color: kind.tone.fg),
              ),
              const SizedBox(width: SboxSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${it['person'] ?? ''}',
                          style: SboxType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (it['urgent'] == true) const SboxStatusChip(label: 'Gấp', tone: SboxTone.danger),
                  ]),
                  Text(tr('${it['title'] ?? kind.label}'), style: SboxType.smallStyle(kind.tone.fg)),
                  if ((it['detail'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: SboxSpace.xxs),
                      child: Text('${it['detail']}',
                          style: SboxType.smallStyle(SboxColors.textMuted), maxLines: 3, overflow: TextOverflow.ellipsis),
                    ),
                ]),
              ),
              if (amount is num && amount != 0)
                Padding(
                  padding: const EdgeInsets.only(left: SboxSpace.sm),
                  child: Text(SboxFmt.money(amount), style: SboxType.moneyStyle(c: SboxColors.text)),
                ),
            ]),
            const SizedBox(height: SboxSpace.sm),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(SboxSpace.sm),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                TextButton(
                  onPressed: () => _decide([it], approve: false),
                  child: Text(tr(it['kind'] == 'penalty' ? 'Hủy phạt' : 'Từ chối'),
                      style: const TextStyle(color: SboxColors.dangerText)),
                ),
                const SizedBox(width: SboxSpace.sm),
                FilledButton.icon(
                  onPressed: () => _decide([it], approve: true),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(tr('Duyệt')),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
