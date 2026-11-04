import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../screens/pos/pos_risk_report_screen.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_basics.dart';
import '../../widgets/sbox/sbox_charts.dart';
import 'boss_inbox_screen.dart';
import 'boss_reports_screen.dart';

/// Một vấn đề cần chủ để ý (một dòng trong khối «Cần xử lý»).
class _Issue {
  const _Issue(this.label, this.count, this.tone, this.icon, {this.amount, this.onTap});
  final String label;
  final int count;
  final SboxTone tone;
  final IconData icon;
  final double? amount;
  final VoidCallback? onTap;
}

/// SBOX BOSS — khối «Cần xử lý» trên Tổng quan: việc chờ duyệt, dấu hiệu gian lận hôm nay, ca thu ngân lệch quỹ,
/// hàng hết / lô hết hạn, đơn online chờ xác nhận, vận đơn lỗi. Bấm dòng nào mở thẳng màn xử lý.
class BossIssuesCard extends StatefulWidget {
  const BossIssuesCard({super.key, required this.refreshTick, this.onOpenInbox});

  /// Đổi giá trị = tải lại (Tổng quan làm mới).
  final int refreshTick;
  final VoidCallback? onOpenInbox;

  @override
  State<BossIssuesCard> createState() => _BossIssuesCardState();
}

class _BossIssuesCardState extends State<BossIssuesCard> {
  Map<String, int> _todos = const {};
  Map<String, dynamic> _risk = const {};
  Map<String, dynamic> _shifts = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BossIssuesCard old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load();
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final api = ApiService();
    final today = _ymd(DateTime.now());
    final results = await Future.wait([
      api.getOverviewTodos(),
      api.getPosRiskReport(from: today, to: today),
      api.getBossIssues(),
      api.getBossInbox(),
    ]);
    if (!mounted) return;
    setState(() {
      final t = results[0]['data'];
      _todos = {
        if (t is List)
          for (final it in t)
            if (it is Map) '${it['key']}': (it['count'] as num? ?? 0).toInt(),
      };
      final r = results[1]['data'];
      _risk = r is Map ? Map<String, dynamic>.from(r['summary'] as Map? ?? const {}) : const {};
      final s = results[2]['data'];
      _shifts = s is Map ? Map<String, dynamic>.from(s) : const {};
      final inbox = results[3]['data'];
      if (inbox is Map) bossInboxCount.value = (inbox['total'] as num? ?? 0).toInt();
      _loaded = true;
    });
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _showShiftDiffs() {
    final rows = [for (final s in (_shifts['cashierDiffs'] as List? ?? const [])) if (s is Map) s];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: SboxSpace.lg), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SboxSpace.lg, 0, SboxSpace.lg, SboxSpace.sm),
            child: Text(tr('Ca thu ngân lệch quỹ (2 ngày gần nhất)'), style: SboxType.titleSmStyle()),
          ),
          for (final s in rows)
            ListTile(
              leading: Icon(
                (s['difference'] as num? ?? 0) < 0 ? Icons.remove_circle_rounded : Icons.add_circle_rounded,
                color: (s['difference'] as num? ?? 0) < 0 ? SboxColors.danger : SboxColors.warning,
              ),
              title: Text('${s['closedByName'] ?? s['openedByName'] ?? tr('Không rõ')}'),
              subtitle: Text(
                '${tr('Máy tính')} ${SboxFmt.money(s['expectedCash'] as num?)} · ${tr('Đếm')} ${SboxFmt.money(s['countedCash'] as num?)}'
                '${(s['note'] ?? '').toString().isEmpty ? '' : '\n${s['note']}'}',
              ),
              trailing: Text(SboxFmt.money(s['difference'] as num?),
                  style: SboxType.moneyStyle(
                      c: (s['difference'] as num? ?? 0) < 0 ? SboxColors.dangerText : SboxColors.warningText)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final inbox = bossInboxCount.value;
    final riskOrders = (_risk['riskOrders'] as num? ?? 0).toInt();
    final highOrders = (_risk['highOrders'] as num? ?? 0).toInt();
    final diffs = (_shifts['cashierDiffs'] as List? ?? const []).length;
    final stale = (_shifts['staleOpenShifts'] as num? ?? 0).toInt();
    int t(String k) => _todos[k] ?? 0;
    final issues = <_Issue>[
      if (inbox > 0)
        _Issue('Việc chờ bạn duyệt', inbox, SboxTone.brand, Icons.fact_check_rounded, onTap: widget.onOpenInbox),
      if (riskOrders > 0)
        _Issue(
          highOrders > 0 ? 'Đơn nghi gian lận hôm nay ($highOrders mức cao)' : 'Đơn có dấu hiệu bất thường hôm nay',
          riskOrders,
          highOrders > 0 ? SboxTone.danger : SboxTone.warning,
          Icons.policy_rounded,
          amount: (_risk['amountAtRisk'] as num?)?.toDouble(),
          onTap: () => _push(const PosRiskReportScreen()),
        ),
      if (diffs > 0)
        _Issue('Ca thu ngân lệch quỹ', diffs, SboxTone.danger, Icons.point_of_sale_rounded,
            amount: (_shifts['cashierDiffTotal'] as num?)?.toDouble(), onTap: _showShiftDiffs),
      if (stale > 0) _Issue('Ca thu ngân mở quá 16 giờ chưa đóng', stale, SboxTone.warning, Icons.lock_clock_rounded),
      if (t('onlinePending') > 0)
        _Issue('Đơn online chờ xác nhận', t('onlinePending'), SboxTone.danger, Icons.shopping_bag_rounded),
      if (t('shippingIssue') > 0)
        _Issue('Vận đơn giao thất bại / hoàn hàng', t('shippingIssue'), SboxTone.danger, Icons.local_shipping_rounded),
      if (t('codPending') > 0) _Issue('Đơn COD chưa đối soát', t('codPending'), SboxTone.warning, Icons.payments_rounded),
      if (t('outOfStock') > 0)
        _Issue('Hàng đã hết', t('outOfStock'), SboxTone.danger, Icons.inventory_2_rounded,
            onTap: () => _push(const BossReportDetailScreen(type: BossReportType.stock))),
      if (t('lowStock') > 0)
        _Issue('Hàng dưới tồn tối thiểu', t('lowStock'), SboxTone.warning, Icons.inventory_rounded,
            onTap: () => _push(const BossReportDetailScreen(type: BossReportType.stock))),
      if (t('expiredLots') > 0)
        _Issue('Lô hàng đã hết hạn', t('expiredLots'), SboxTone.danger, Icons.event_busy_rounded,
            onTap: () => _push(const BossReportDetailScreen(type: BossReportType.stock))),
      if (t('nearExpiry') > 0)
        _Issue('Lô hàng sắp hết hạn', t('nearExpiry'), SboxTone.warning, Icons.event_rounded,
            onTap: () => _push(const BossReportDetailScreen(type: BossReportType.stock))),
    ];
    if (issues.isEmpty) {
      return SboxCard(
        child: Row(children: [
          const Icon(Icons.verified_rounded, color: SboxColors.success),
          const SizedBox(width: SboxSpace.md),
          Expanded(child: Text(tr('Không có vấn đề cần xử lý'), style: SboxType.bodyStrong())),
        ]),
      );
    }
    return SboxCard(
      title: 'Cần xử lý',
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (final i in issues)
          ListTile(
            dense: true,
            onTap: i.onTap,
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: i.tone.bg, borderRadius: SboxRadius.mdAll),
              child: Icon(i.icon, size: 19, color: i.tone.fg),
            ),
            title: Text(tr(i.label), style: SboxType.bodyStyle()),
            subtitle: i.amount == null || i.amount == 0 ? null : Text(SboxFmt.money(i.amount)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              SboxStatusChip(label: '${i.count}', tone: i.tone),
              if (i.onTap != null) const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
            ]),
          ),
      ]),
    );
  }
}
