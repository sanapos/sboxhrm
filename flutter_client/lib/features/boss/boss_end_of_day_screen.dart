import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_basics.dart';
import '../../widgets/sbox/sbox_charts.dart';

/// SBOX BOSS — «Cuối ngày»: báo cáo cuối ngày của cả cửa hàng / chi nhánh đang xem
/// (cùng số liệu với «Báo cáo cuối ngày» trên POS), chọn ngày bằng mũi tên hoặc lịch.
class BossEndOfDayScreen extends StatefulWidget {
  const BossEndOfDayScreen({super.key});

  @override
  State<BossEndOfDayScreen> createState() => _BossEndOfDayScreenState();
}

class _BossEndOfDayScreenState extends State<BossEndOfDayScreen> {
  late DateTime _day = _today();
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  int _seq = 0;
  String? _branch;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _branch = BranchSession.instance.currentId;
    BranchSession.instance.addListener(_onBranchChanged);
    _load();
  }

  @override
  void dispose() {
    BranchSession.instance.removeListener(_onBranchChanged);
    super.dispose();
  }

  void _onBranchChanged() {
    final id = BranchSession.instance.currentId;
    if (id == _branch) return;
    _branch = id;
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ApiService().getPosEndOfDayReport(from: _day, to: _day, filterBy: 'soldByEmployee');
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        _data = Map<String, dynamic>.from(r['data'] as Map);
      } else {
        _data = null;
        _error = r['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  void _shift(int days) {
    final next = _day.add(Duration(days: days));
    if (next.isAfter(_today())) return;
    _day = next;
    _load();
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: _today(),
    );
    if (picked == null) return;
    _day = DateTime(picked.year, picked.month, picked.day);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _day == _today();
    final d = _data;
    return Column(children: [
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SboxSpace.sm, vertical: SboxSpace.xs),
          child: Row(children: [
            IconButton(
              tooltip: tr('Ngày trước'),
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: InkWell(
                borderRadius: SboxRadius.mdAll,
                onTap: _pick,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: SboxSpace.sm),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.calendar_today_rounded, size: 16, color: SboxColors.brand600),
                    const SizedBox(width: SboxSpace.sm),
                    Text(
                      isToday ? tr('Hôm nay · ${_dmy(_day)}') : _dmy(_day),
                      style: SboxType.bodyStrong(),
                    ),
                  ]),
                ),
              ),
            ),
            IconButton(
              tooltip: tr('Ngày sau'),
              onPressed: isToday ? null : () => _shift(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: d == null
            ? (_error != null
                ? SboxEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Không tải được báo cáo',
                    message: _error,
                    action: SboxButton(label: 'Thử lại', onPressed: _load),
                  )
                : const SboxLoading(message: 'Đang tải báo cáo cuối ngày…'))
            : Stack(children: [
                RefreshIndicator(onRefresh: _load, child: _EndOfDayBody(data: d)),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
              ]),
      ),
    ]);
  }
}

String _dmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class _EndOfDayBody extends StatelessWidget {
  const _EndOfDayBody({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final payments = [for (final p in (data['payments'] as List? ?? const [])) if (p is Map) p];
    final products = [for (final p in (data['products'] as List? ?? const [])) if (p is Map) p];
    final discount =
        _num(data['orderDiscount']) + _num(data['voucherDiscount']) + _num(data['pointsDiscount']) + _num(data['lineDiscountTotal']);
    final canceled = _num(data['canceledCount']).toInt();
    return ListView(
      padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.md, SboxSpace.lg, SboxSpace.xxl),
      children: [
        Row(children: [
          Expanded(child: SboxMetricCard(label: 'Doanh thu thuần', value: SboxFmt.compact(_num(data['netSales'])))),
          const SizedBox(width: SboxSpace.md),
          Expanded(
            child: SboxMetricCard(
              label: 'Số đơn',
              value: SboxFmt.number(_num(data['orderCount'])),
              tone: SboxTone.neutral,
            ),
          ),
        ]),
        const SizedBox(height: SboxSpace.md),
        SboxCard(
          title: 'Tiền',
          child: Column(children: [
            _Line('Phải thu (gồm VAT, phụ thu, phí giao)', _num(data['payableTotal'])),
            _Line('Thực thu', _num(data['actualReceived']), strong: true),
            _Line('Ghi nợ khách', _num(data['debtTotal']), tone: SboxColors.warningText),
            _Line('Khách trả nợ cũ', _num(data['debtCollected'])),
            _Line('Hoàn tiền trả hàng', _num(data['refundPaid']), tone: SboxColors.dangerText),
            const Divider(height: SboxSpace.lg),
            _Line('Tiền mặt trong két', _num(data['drawerCash']), strong: true),
          ]),
        ),
        const SizedBox(height: SboxSpace.md),
        SboxCard(
          title: 'Theo phương thức thanh toán',
          child: SboxRankList(
            items: [
              for (final p in payments)
                SboxSlice(tr('${p['paymentMethod'] ?? 'Khác'}'), _num(p['total']),
                    caption: '${SboxFmt.number(_num(p['count']))} ${tr('lượt')}'),
            ],
            maxItems: 6,
          ),
        ),
        const SizedBox(height: SboxSpace.md),
        SboxCard(
          title: 'Cần để ý',
          child: Column(children: [
            _Line('Giảm giá (đơn, món, voucher, điểm)', discount, tone: SboxColors.warningText),
            _Line(
              tr('Đơn đã hủy ($canceled đơn)'),
              _num(data['canceledTotal']),
              tone: canceled > 0 ? SboxColors.dangerText : null,
            ),
            _Line('Hàng khách trả', _num(data['refundTotal'])),
          ]),
        ),
        const SizedBox(height: SboxSpace.md),
        SboxCard(
          title: 'Bán chạy nhất',
          child: SboxRankList(
            items: [
              for (final p in products)
                SboxSlice('${p['productName'] ?? ''}', _num(p['revenue']),
                    caption: '${tr('SL')} ${SboxFmt.qty(_num(p['qty']))}'),
            ],
            maxItems: 10,
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.strong = false, this.tone});

  final String label;
  final double value;
  final bool strong;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = tone ?? SboxColors.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SboxSpace.xs),
      child: Row(children: [
        Expanded(
          child: Text(tr(label), style: strong ? SboxType.bodyStrong() : SboxType.bodyStyle(SboxColors.textSecondary)),
        ),
        Text(SboxFmt.money(value), style: SboxType.moneyStyle(c: c).copyWith(fontWeight: strong ? FontWeight.w700 : null)),
      ]),
    );
  }
}
