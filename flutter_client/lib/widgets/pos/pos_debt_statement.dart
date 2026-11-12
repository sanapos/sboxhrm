import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../utils/pos_report_open.dart';
import '../reports/report_drill_sheet.dart';
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

  /// Chứng từ gốc của dòng sổ: bán / trả hàng khách → hóa đơn; nhập / trả NCC → phiếu nhập / trả. Còn lại không có.
  static bool _canOpen(Map<String, dynamic> r) {
    // Phiếu thu nợ khách: mở đơn đã trừ nợ (gắn đơn hoặc «Trừ nợ đơn: HD…» trong ghi chú).
    if ('${r['docType']}' == 'Payment') {
      final oid = '${r['orderId'] ?? ''}';
      return (oid.isNotEmpty && oid != 'null') || RegExp(r'HD\d{6,}').hasMatch('${r['note'] ?? ''}');
    }
    final id = '${r['docId'] ?? ''}';
    if (id.isEmpty || id.startsWith('0000')) return false;
    return const {'Sale', 'SaleCancel', 'Return', 'ReturnVoid', 'Receipt', 'ReceiptCancel', 'PurchaseReturn', 'PurchaseReturnCancel'}
        .contains('${r['docType']}');
  }

  void _openDoc(Map<String, dynamic> r) {
    if (!_canOpen(r)) return;
    final id = '${r['docId']}';
    switch ('${r['docType']}') {
      case 'Payment':
        PosReportOpen.debtPaymentOrders(context,
            orderId: '${r['orderId'] ?? ''}', note: '${r['note'] ?? ''}', paymentNo: '${r['docNo'] ?? ''}');
      case 'Sale' || 'SaleCancel' || 'Return' || 'ReturnVoid':
        PosReportOpen.sale(context, id);
      case 'Receipt' || 'ReceiptCancel':
        PosReportOpen.purchaseReceipt(context, id);
      case 'PurchaseReturn' || 'PurchaseReturnCancel':
        PosReportOpen.purchaseReturn(context, id);
    }
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

  /// Ô «phát sinh tăng / giảm» → các chứng từ trong sổ có cột đó > 0; tổng khớp số trên ô.
  void _drillSide(List<Map<String, dynamic>> items, String field, String title) {
    final rows = items.where((r) => _d(r[field]) > 0).toList();
    showReportDrillSheet(
      context,
      title: title,
      subtitle: '${_dmy(_from)} – ${_dmy(_to)}',
      total: 'Tổng ${SboxFmt.money(_d(_data[field]))}',
      emptyText: 'Không có chứng từ',
      rows: [
        for (final r in rows)
          ReportDrillRow(
            title: '${r['docLabel'] ?? r['docType'] ?? ''}${'${r['docNo'] ?? ''}'.isEmpty ? '' : ' · ${r['docNo']}'}',
            subtitle: [_at(r['at']), if ('${r['note'] ?? ''}'.isNotEmpty) '${r['note']}'].join(' · '),
            trailing: SboxFmt.money(_d(r[field])),
            trailingColor: field == 'increase' ? SboxColors.dangerText : SboxColors.successText,
            icon: Icons.receipt_long_outlined,
            onTap: _canOpen(r) ? () => _openDoc(r) : null,
          ),
      ],
    );
  }

  /// Đầu kỳ / cuối kỳ: số dư = đầu kỳ + tăng − giảm; mỗi dòng mở danh sách thành phần.
  void _drillBalance(List<Map<String, dynamic>> items, {required bool closing}) {
    final opening = _d(_data['opening']);
    final inc = _d(_data['increase']);
    final dec = _d(_data['decrease']);
    final close = _d(_data['closing']);
    showReportDrillSheet(
      context,
      title: closing ? 'Cuối kỳ' : 'Đầu kỳ',
      subtitle: '${_dmy(_from)} – ${_dmy(_to)}',
      showCount: false,
      note: closing
          ? 'Cuối kỳ = Đầu kỳ + ${widget.increaseLabel} − ${widget.decreaseLabel} = ${SboxFmt.money(opening)} + '
              '${SboxFmt.money(inc)} − ${SboxFmt.money(dec)} = ${SboxFmt.money(close)}.'
          : 'Đầu kỳ = số dư công nợ sau mọi chứng từ trước ngày ${_dmy(_from)}. '
              'Đổi «Kỳ» sang khoảng sớm hơn để xem các chứng từ tạo ra số dư này.',
      rows: [
        ReportDrillRow(title: 'Đầu kỳ', trailing: SboxFmt.money(opening), icon: Icons.flag_outlined),
        if (closing) ...[
          ReportDrillRow(
            title: widget.increaseLabel,
            trailing: '+${SboxFmt.money(inc)}',
            trailingColor: SboxColors.dangerText,
            icon: Icons.trending_up,
            onTap: () => _drillSide(items, 'increase', widget.increaseLabel),
          ),
          ReportDrillRow(
            title: widget.decreaseLabel,
            trailing: '−${SboxFmt.money(dec)}',
            trailingColor: SboxColors.successText,
            icon: Icons.trending_down,
            onTap: () => _drillSide(items, 'decrease', widget.decreaseLabel),
          ),
          ReportDrillRow(title: 'Cuối kỳ', trailing: SboxFmt.money(close), icon: Icons.account_balance_wallet_outlined),
        ],
      ],
    );
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
            SboxKpi(label: 'Đầu kỳ', value: SboxFmt.money(opening), icon: Icons.flag_outlined,
                onTap: () => _drillBalance(items, closing: false)),
            SboxKpi(label: widget.increaseLabel, value: SboxFmt.money(_d(_data['increase'])), icon: Icons.trending_up, tone: SboxTone.danger,
                onTap: () => _drillSide(items, 'increase', widget.increaseLabel)),
            SboxKpi(label: widget.decreaseLabel, value: SboxFmt.money(_d(_data['decrease'])), icon: Icons.trending_down, tone: SboxTone.success,
                onTap: () => _drillSide(items, 'decrease', widget.decreaseLabel)),
            SboxKpi(label: 'Cuối kỳ', value: SboxFmt.money(closing), icon: Icons.account_balance_wallet_outlined, tone: closing > 0 ? SboxTone.warning : SboxTone.neutral,
                onTap: () => _drillBalance(items, closing: true)),
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
          onRowTap: _openDoc,
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
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text('${r['docNo']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SboxType.smallStyle(_canOpen(r) ? SboxColors.primary : SboxColors.textMuted)),
                    ),
                    if (_canOpen(r)) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.open_in_new_rounded, size: 12, color: SboxColors.primary),
                    ],
                  ]),
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
            SboxColumn(label: 'Ghi chú', flex: 2, minWidth: 180, hideOnMobile: true, text: (r) => '${r['note'] ?? ''}'),
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
