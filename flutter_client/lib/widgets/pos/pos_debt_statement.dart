import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../sbox/sbox_ui.dart';

typedef PosStatementLoader = Future<Map<String, dynamic>> Function(DateTime from, DateTime to);

/// Sổ đối chiếu công nợ (khách / NCC): đầu kỳ, phát sinh tăng, giảm, cuối kỳ và số dư sau từng chứng từ.
/// Dùng chung cho chi tiết khách và nhà cung cấp — [loader] gọi API theo kỳ.
class PosDebtStatementView extends StatefulWidget {
  const PosDebtStatementView({
    super.key,
    required this.loader,
    this.increaseLabel = 'Phát sinh nợ',
    this.decreaseLabel = 'Đã trả / giảm',
    this.reloadToken = 0,
  });

  final PosStatementLoader loader;
  final String increaseLabel;
  final String decreaseLabel;

  /// Đổi số này để tải lại (vd. sau khi thu / trả nợ).
  final int reloadToken;

  @override
  State<PosDebtStatementView> createState() => _PosDebtStatementViewState();
}

class _PosDebtStatementViewState extends State<PosDebtStatementView> {
  static const _periods = {
    'thisMonth': 'Tháng này',
    'lastMonth': 'Tháng trước',
    'last3': '3 tháng',
    'thisYear': 'Năm nay',
    'custom': 'Chọn ngày…',
  };

  String _period = 'thisMonth';
  late DateTime _from;
  late DateTime _to;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    _setPeriod('thisMonth');
    _load();
  }

  @override
  void didUpdateWidget(covariant PosDebtStatementView old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken) _load();
  }

  void _setPeriod(String p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    _period = p;
    switch (p) {
      case 'lastMonth':
        _from = DateTime(n.year, n.month - 1, 1);
        _to = DateTime(n.year, n.month, 0);
      case 'last3':
        _from = DateTime(n.year, n.month - 2, 1);
        _to = today;
      case 'thisYear':
        _from = DateTime(n.year, 1, 1);
        _to = today;
      default:
        _from = DateTime(n.year, n.month, 1);
        _to = today;
    }
  }

  Future<void> _onPeriod(String p) async {
    if (p == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: DateTimeRange(start: _from, end: _to),
      );
      if (picked == null) return;
      setState(() {
        _period = 'custom';
        _from = picked.start;
        _to = picked.end;
      });
    } else {
      setState(() => _setPeriod(p));
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await widget.loader(_from, _to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _data = const {};
        _error = res['message']?.toString() ?? 'Không tải được sổ đối chiếu';
      }
    });
  }

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _dmy(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  /// Giờ trong sổ đã là giờ Việt Nam (không kèm Z) — không đổi múi giờ.
  static String _at(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}');
    if (d == null) return '—';
    return '${_dmy(d)} ${_two(d.hour)}:${_two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final items = (_data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final opening = _d(_data['opening']);
    final closing = _d(_data['closing']);
    final current = _d(_data['currentBalance']);
    final today = DateTime.now();
    final toToday = _to.year == today.year && _to.month == today.month && _to.day == today.day;
    // Sổ bắt đầu từ khi có tính năng; nếu số dư sổ lệch công nợ hiện tại thì báo để đối chiếu tay.
    final mismatch = !_loading && _error == null && toToday && (closing - current).abs() >= 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(SboxSpace.md),
        child: Wrap(
          spacing: SboxSpace.sm,
          runSpacing: SboxSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SboxFilterChip<String>(label: 'Kỳ', value: _period, options: _periods, onChanged: _onPeriod),
            Text('${_dmy(_from)} – ${_dmy(_to)}', style: SboxType.smallStyle(SboxColors.textMuted)),
          ],
        ),
      ),
      if (_loading)
        const Padding(padding: EdgeInsets.all(SboxSpace.lg), child: SboxLoading())
      else if (_error != null)
        SboxEmptyState(icon: Icons.error_outline, title: 'Không tải được', message: _error)
      else ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SboxSpace.md),
          child: SboxKpiStrip(maxColumns: 4, items: [
            SboxKpi(label: 'Đầu kỳ', value: SboxFmt.money(opening), icon: Icons.flag_outlined),
            SboxKpi(label: widget.increaseLabel, value: SboxFmt.money(_d(_data['increase'])), icon: Icons.trending_up, tone: SboxTone.danger),
            SboxKpi(label: widget.decreaseLabel, value: SboxFmt.money(_d(_data['decrease'])), icon: Icons.trending_down, tone: SboxTone.success),
            SboxKpi(label: 'Cuối kỳ', value: SboxFmt.money(closing), icon: Icons.account_balance_wallet_outlined, tone: closing > 0 ? SboxTone.warning : SboxTone.neutral),
          ]),
        ),
        if (mismatch)
          Padding(
            padding: const EdgeInsets.fromLTRB(SboxSpace.md, SboxSpace.sm, SboxSpace.md, 0),
            child: Text(
              tr('Số dư sổ ${SboxFmt.money(closing)} khác công nợ hiện tại ${SboxFmt.money(current)} — có thay đổi trước khi có sổ đối chiếu.'),
              style: SboxType.smallStyle(SboxColors.warningText),
            ),
          ),
        const SizedBox(height: SboxSpace.sm),
        SboxDataTable<Map<String, dynamic>>(
          rows: items,
          pageSize: 20,
          emptyTitle: 'Không có phát sinh trong kỳ',
          columns: [
            SboxColumn(label: 'Ngày', primary: true, minWidth: 130, text: (r) => _at(r['at'])),
            SboxColumn(
              label: 'Chứng từ',
              flex: 2,
              minWidth: 170,
              cell: (r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(tr('${r['docLabel'] ?? r['docType'] ?? ''}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.bodyStyle()),
                if ('${r['docNo'] ?? ''}'.isNotEmpty)
                  Text('${r['docNo']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.textMuted)),
              ]),
            ),
            // Một cột có dấu: + tăng nợ (đỏ), − giảm nợ (xanh) — điện thoại hiện ngay góc phải thẻ.
            SboxColumn(
              label: 'Phát sinh',
              numeric: true,
              minWidth: 120,
              cell: (r) {
                final delta = _d(r['increase']) - _d(r['decrease']);
                return Text('${delta > 0 ? '+' : '−'}${SboxFmt.money(delta.abs())}',
                    textAlign: TextAlign.right,
                    style: SboxType.bodyStyle(delta > 0 ? SboxColors.dangerText : SboxColors.successText));
              },
            ),
            SboxColumn(
              label: 'Số dư',
              numeric: true,
              minWidth: 120,
              cell: (r) => Text(SboxFmt.money(_d(r['balance'])),
                  textAlign: TextAlign.right, style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
            ),
            SboxColumn(label: 'Ghi chú', minWidth: 180, hideOnMobile: true, text: (r) => '${r['note'] ?? ''}'),
          ],
        ),
      ],
    ]);
  }
}

/// Mở sổ đối chiếu thành trang riêng (NCC).
Future<void> showPosDebtStatementPage(
  BuildContext context, {
  required String title,
  String? subtitle,
  required PosStatementLoader loader,
  String increaseLabel = 'Phát sinh nợ',
  String decreaseLabel = 'Đã trả / giảm',
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (ctx) => Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(title: Text(tr('Sổ đối chiếu công nợ'))),
      body: ListView(padding: const EdgeInsets.all(SboxSpace.md), children: [
        SboxPageHeader(title: title, subtitle: subtitle),
        const SizedBox(height: SboxSpace.md),
        SboxCard(
          padding: EdgeInsets.zero,
          child: PosDebtStatementView(loader: loader, increaseLabel: increaseLabel, decreaseLabel: decreaseLabel),
        ),
      ]),
    ),
  ));
}
