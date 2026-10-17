import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_store_printer.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_printer_transport.dart';
import '../../utils/pos_store_printer_mapper.dart';
import '../../utils/pos_thermal_printer_service.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

final _money = NumberFormat('#,##0', 'vi_VN');
final _qty = NumberFormat('#,##0.##', 'vi_VN');
final _dt = DateFormat('dd/MM/yyyy HH:mm');

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Phiếu «Tổng kết ca» (xem + in K58/K80): tiền két theo loại thu / chi, kỳ vọng – đếm – lệch,
/// các phương thức thanh toán, số đơn và hàng đã bán trong ca.
Future<void> showPosShiftSummarySheet(BuildContext context, String shiftId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _ShiftSummarySheet(shiftId: shiftId),
  );
}

/// Dòng chữ của phiếu in (trái – phải canh theo số ký tự khổ giấy).
List<String> buildPosShiftSummaryLines(Map<String, dynamic> d, {int chars = 32}) {
  String lr(String l, String r) {
    final space = chars - l.length - r.length;
    return space >= 1 ? '$l${' ' * space}$r' : '$l\n${' ' * (chars - r.length).clamp(0, chars)}$r';
  }

  String m(dynamic v) => _money.format(_n(v));
  final rule = '-' * chars;
  final opened = parseApiUtcDateTime(d['openedAt']);
  final closed = parseApiUtcDateTime(d['closedAt']);
  final lines = <String>[
    if ('${d['storeName'] ?? ''}'.isNotEmpty) '${d['storeName']}',
    'Thu ngân: ${d['openedBy'] ?? ''}',
    if (opened != null) 'Mở ca: ${_dt.format(opened)}',
    closed != null ? 'Đóng ca: ${_dt.format(closed)}' : 'Ca đang mở',
    rule,
    lr('Số đơn', '${_n(d['orderCount']).toInt()}'),
    lr('Doanh thu', m(d['revenue'])),
    lr('Phải thu (gồm VAT, phí)', m(d['payable'])),
    rule,
    'THANH TOÁN',
    for (final p in (d['payments'] as List? ?? const []).whereType<Map>())
      lr('${p['paymentMethod']} (${p['count']})', m(p['total'])),
    rule,
    'TIỀN KÉT',
    lr('Đầu ca', m(d['openingCash'])),
    lr('+ Bán hàng tiền mặt', m(d['saleCash'])),
    if (_n(d['debtCash']) != 0) lr('+ Thu nợ khách', m(d['debtCash'])),
    if (_n(d['depositCash']) != 0) lr('+ Thu cọc', m(d['depositCash'])),
    if (_n(d['otherCashIn']) != 0) lr('+ Thu khác', m(d['otherCashIn'])),
    if (_n(d['refundCash']) != 0) lr('- Hoàn tiền trả hàng', m(d['refundCash'])),
    if (_n(d['depositRefundCash']) != 0) lr('- Hoàn cọc', m(d['depositRefundCash'])),
    if (_n(d['otherCashOut']) != 0) lr('- Chi khác', m(d['otherCashOut'])),
    lr('= Kỳ vọng', m(d['expectedCash'])),
    if (d['countedCash'] != null) lr('Đếm thực tế', m(d['countedCash'])),
    if (d['difference'] != null)
      lr(_n(d['difference']) == 0 ? 'Chênh lệch' : (_n(d['difference']) > 0 ? 'Thừa' : 'Thiếu'), m(_n(d['difference']).abs())),
    rule,
    'HÀNG ĐÃ BÁN',
    for (final p in (d['products'] as List? ?? const []).whereType<Map>()) ...[
      '${p['productName']}',
      lr('  SL ${_qty.format(_n(p['qty']))}', m(p['revenue'])),
    ],
  ];
  return lines;
}

/// In phiếu tổng kết ca: máy hóa đơn cục bộ (app) → máy in qua Agent (phiếu cuối ngày / hóa đơn).
Future<bool> printPosShiftSummary(Map<String, dynamic> d, {String paperSize = 'K80'}) async {
  final chars = paperSize == 'K58' ? 32 : 48;
  final lines = buildPosShiftSummaryLines(d, chars: chars);
  const title = 'TỔNG KẾT CA';
  final footer = 'In lúc ${_dt.format(DateTime.now())} · SBOX POS';
  await PosPrintOrchestrator.instance.refreshConfig();
  if (!kIsWeb) {
    final local = await PosThermalPrinterSettings.load();
    if (local.enabled) {
      try {
        var settings = await PosPrinterTransport.prepareLocalSettings(local);
        settings = settings.copyWith(paperSize: paperSize);
        final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
            settings: settings, title: title, lines: lines, footer: footer);
        if (await PosPrintOrchestrator.instance.dispatchLocalEscPos(
            bytes: bytes, showFeedback: false, successTitle: 'In tổng kết ca', settingsOverride: settings)) {
          return true;
        }
      } catch (e) {
        debugPrint('Shift summary local print failed: $e');
      }
    }
  }
  Future<bool> dispatch(String documentType) => PosPrintOrchestrator.instance.dispatchEscPosToAll(
        documentType: documentType,
        referenceNo: 'CA-${d['shiftId']}',
        skipDedup: true,
        showFeedback: true,
        successTitle: 'In tổng kết ca',
        buildBytes: (PosStorePrinter printer) async {
          final settings = toThermalSettings(printer).copyWith(paperSize: paperSize);
          return PosThermalPrinterService.buildTextEscPosBytes(
              settings: settings, title: title, lines: buildPosShiftSummaryLines(d, chars: settings.paperWidthMm <= 58 ? 32 : 48), footer: footer);
        },
      );
  for (final type in [PosCloudDocumentTypes.endOfDayReport, PosCloudDocumentTypes.saleInvoice]) {
    if (PosPrintOrchestrator.instance.resolvePrinters(type).isNotEmpty && await dispatch(type)) return true;
  }
  return false;
}

class _ShiftSummarySheet extends StatefulWidget {
  const _ShiftSummarySheet({required this.shiftId});
  final String shiftId;

  @override
  State<_ShiftSummarySheet> createState() => _ShiftSummarySheetState();
}

class _ShiftSummarySheetState extends State<_ShiftSummarySheet> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ApiService().getPosCashierShiftSummary(widget.shiftId);
    if (!mounted) return;
    setState(() {
      if (r['isSuccess'] == true && r['data'] is Map) {
        _d = Map<String, dynamic>.from(r['data'] as Map);
      } else {
        _error = r['message']?.toString() ?? 'Không tải được tổng kết ca';
      }
    });
  }

  Future<void> _print() async {
    final d = _d;
    if (d == null || _printing) return;
    setState(() => _printing = true);
    final ok = await printPosShiftSummary(d);
    if (!mounted) return;
    setState(() => _printing = false);
    if (!ok) {
      NotificationOverlayManager().showError(
        title: 'Chưa in được',
        message: tr('Chưa có máy in hóa đơn (máy cục bộ hoặc qua Print Agent).'),
      );
    }
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(tr(label), style: TextStyle(fontSize: 13, color: SboxColors.slate700))),
          Text(value,
              style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: color)),
        ]),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(tr(title), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    String m(dynamic v) => '${_money.format(_n(v))} đ';
    final diff = d?['difference'] == null ? null : _n(d!['difference']);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Tổng kết ca'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Flexible(
                child: d == null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: _error != null
                              ? Text(tr(_error!), style: const TextStyle(color: SboxColors.dangerText))
                              : const CircularProgressIndicator(color: PosTheme.kiotBlue),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          Text(
                            [
                              '${d['openedBy'] ?? ''}',
                              [
                                if (parseApiUtcDateTime(d['openedAt']) case final o?) _dt.format(o),
                                if (parseApiUtcDateTime(d['closedAt']) case final c?) '→ ${_dt.format(c)}' else '(đang mở)',
                              ].join(' '),
                            ].join(' · '),
                            style: TextStyle(fontSize: 12, color: SboxColors.slate600),
                          ),
                          _section('Bán hàng'),
                          _row('Số đơn', '${_n(d['orderCount']).toInt()}'),
                          _row('Doanh thu', m(d['revenue'])),
                          _row('Phải thu (gồm VAT, phí)', m(d['payable'])),
                          for (final p in (d['payments'] as List? ?? const []).whereType<Map>())
                            _row('  ${p['paymentMethod']} (${p['count']} phiếu)', m(p['total'])),
                          _section('Tiền két'),
                          _row('Đầu ca', m(d['openingCash'])),
                          _row('+ Bán hàng tiền mặt', m(d['saleCash'])),
                          if (_n(d['debtCash']) != 0) _row('+ Thu nợ khách', m(d['debtCash'])),
                          if (_n(d['depositCash']) != 0) _row('+ Thu cọc', m(d['depositCash'])),
                          if (_n(d['otherCashIn']) != 0) _row('+ Thu khác', m(d['otherCashIn'])),
                          if (_n(d['refundCash']) != 0) _row('− Hoàn tiền trả hàng', m(d['refundCash'])),
                          if (_n(d['depositRefundCash']) != 0) _row('− Hoàn cọc', m(d['depositRefundCash'])),
                          if (_n(d['otherCashOut']) != 0) _row('− Chi khác', m(d['otherCashOut'])),
                          _row('= Tiền két kỳ vọng', m(d['expectedCash']), bold: true),
                          if (d['countedCash'] != null) _row('Đếm thực tế', m(d['countedCash'])),
                          if (diff != null)
                            _row(diff == 0 ? 'Chênh lệch' : (diff > 0 ? 'Thừa' : 'Thiếu'), m(diff.abs()),
                                bold: true, color: diff == 0 ? SboxColors.successText : SboxColors.dangerText),
                          _section('Hàng đã bán (${(d['products'] as List? ?? const []).length})'),
                          for (final p in (d['products'] as List? ?? const []).whereType<Map>())
                            _row('${p['productName']} × ${_qty.format(_n(p['qty']))}', m(p['revenue'])),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: Text(tr('Đóng')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: d == null || _printing ? null : _print,
                    style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue, minimumSize: const Size(0, 48)),
                    icon: const Icon(Icons.print, size: 18),
                    label: Text(tr(_printing ? 'Đang in…' : 'In phiếu')),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
