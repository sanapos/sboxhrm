import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../theme/sbox_tokens.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_template_defaults.dart';

/// Máy in văn phòng (A4/A5) của cửa hàng gắn Print Agent Windows — nhận chứng từ khổ trang dạng PDF.
List<PosStorePrinter> posAgentPagePrinters() => PosPrintOrchestrator.instance.printers
    .where((p) =>
        p.isActive &&
        !p.isDeviceLocal &&
        p.isUsb &&
        (p.paperSize == 'A4' || p.paperSize == 'A5'))
    .toList();

/// HTML mẫu khổ trang → PDF → lệnh in PdfBase64 tới máy [printer] (Agent Windows in qua driver).
/// Trả null khi đã gửi, hoặc lý do lỗi.
Future<String?> sendPosHtmlToAgent({
  required String htmlDocument,
  required PosStorePrinter printer,
  int copies = 1,
  String documentType = 'SaleInvoice',
  String? referenceNo,
  String? referenceId,
}) async {
  var html = htmlDocument.trim();
  if (html.isEmpty) return 'Mẫu in trống';
  if (!html.toLowerCase().contains('<html')) {
    html = wrapPosCommercialPrintHtml(html, PosCommercialPageSetup.parse(html));
  }
  final setup = PosCommercialPageSetup.parse(html);
  final format = (setup.isA5 ? PdfPageFormat.a5 : PdfPageFormat.a4).copyWith(
    marginTop: 0,
    marginBottom: 0,
    marginLeft: 0,
    marginRight: 0,
  );
  Uint8List? pdf;
  try {
    pdf = await Printing.convertHtml(html: html, format: format);
  } catch (e) {
    return 'Không tạo được PDF ($e)';
  }
  if (pdf.length < 5 || pdf[0] != 0x25 || pdf[1] != 0x50) {
    return 'Không tạo được PDF';
  }
  final res = await ApiService().createPosPrintJob(
    documentType: documentType,
    payloadFormat: 'PdfBase64',
    payload: base64Encode(pdf),
    copies: copies.clamp(1, 10),
    referenceNo: referenceNo,
    referenceId: referenceId,
    printerId: printer.id,
  );
  if (res['isSuccess'] == true) return null;
  return (res['message'] ?? 'Gửi lệnh in thất bại').toString();
}

/// Nút «Máy in A4 (Agent)» trong hộp xem trước — ẩn khi cửa hàng chưa có máy in văn phòng qua Agent.
class PosAgentPagePrintButton extends StatefulWidget {
  const PosAgentPagePrintButton({
    super.key,
    required this.htmlDocument,
    required this.copies,
    this.documentType = 'SaleInvoice',
    this.referenceNo,
    this.referenceId,
    this.onSent,
  });

  final String htmlDocument;
  final int Function() copies;
  final String documentType;
  final String? referenceNo;
  final String? referenceId;
  final Future<void> Function()? onSent;

  @override
  State<PosAgentPagePrintButton> createState() => _PosAgentPagePrintButtonState();
}

class _PosAgentPagePrintButtonState extends State<PosAgentPagePrintButton> {
  List<PosStorePrinter> _printers = const [];
  bool _busy = false;
  String? _status;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _printers = posAgentPagePrinters();
    _load();
  }

  Future<void> _load() async {
    try {
      await PosPrintOrchestrator.instance
          .refreshConfig()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (mounted) setState(() => _printers = posAgentPagePrinters());
  }

  Future<void> _send(PosStorePrinter p) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final err = await sendPosHtmlToAgent(
      htmlDocument: widget.htmlDocument,
      printer: p,
      copies: widget.copies(),
      documentType: widget.documentType,
      referenceNo: widget.referenceNo,
      referenceId: widget.referenceId,
    );
    if (err == null) await widget.onSent?.call();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err != null;
      _status = err ?? '${tr('Đã gửi lệnh in tới')} ${p.name}';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_printers.isEmpty || kIsWeb) return const SizedBox.shrink();
    final icon = _busy
        ? const SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.print_outlined, size: 18);
    final Widget button = _printers.length == 1
        ? OutlinedButton.icon(
            onPressed: _busy ? null : () => _send(_printers.first),
            icon: icon,
            label: Text('${tr('Máy in')} ${_printers.first.name}'),
          )
        : PopupMenuButton<PosStorePrinter>(
            enabled: !_busy,
            onSelected: _send,
            itemBuilder: (_) => [
              for (final p in _printers)
                PopupMenuItem(value: p, child: Text('${p.name} · ${p.paperSize}')),
            ],
            child: IgnorePointer(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: icon,
                label: Text(tr('Máy in A4 (Agent)')),
              ),
            ),
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_status != null)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                _status!,
                style: TextStyle(
                  fontSize: 12,
                  color: _error ? SboxColors.danger : SboxColors.brand600,
                ),
              ),
            ),
          ),
        button,
        const SizedBox(width: 8),
      ],
    );
  }
}
