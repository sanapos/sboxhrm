import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../widgets/pos/pos_html_preview_stub.dart'
    if (dart.library.js_interop) '../widgets/pos/pos_html_preview_web.dart';
import 'pos_html_agent_print.dart';
import 'pos_print_template_defaults.dart';

import '../theme/sbox_tokens.dart';
const _blue = SboxColors.brand600;

/// In / chia sẻ PDF (Times + khổ/lề trong HTML). Không share raw HTML.
Future<bool> printOrSharePosHtml({
  required String htmlDocument,
  required String title,
  int copies = 1,
}) async {
  var html = htmlDocument.trim();
  if (html.isEmpty) return false;
  if (!html.toLowerCase().contains('<html')) {
    final setup = PosCommercialPageSetup.parse(html);
    html = wrapPosCommercialPrintHtml(html, setup);
  }
  final setup = PosCommercialPageSetup.parse(html);
  final page = setup.isA5 ? PdfPageFormat.a5 : PdfPageFormat.a4;
  final format = (setup.landscape ? page.landscape : page).copyWith(
    marginTop: 0,
    marginBottom: 0,
    marginLeft: 0,
    marginRight: 0,
  );
  try {
    final info = await Printing.info();
    // Plugin Android có convertHtml (WebView) nhưng không khai báo canConvertHtml.
    final canHtml =
        info.canConvertHtml || defaultTargetPlatform == TargetPlatform.android;
    // Android: mở hộp in hệ thống ngay, PDF dựng trong lúc hộp đang mở — trước đây chờ WebView
    // dựng PDF xong (~10 giây trên máy yếu) mới thấy hộp in. Hủy trong hộp in → không báo lỗi.
    if (defaultTargetPlatform == TargetPlatform.android && info.canPrint && canHtml) {
      var printed = false;
      for (var i = 0; i < copies.clamp(1, 10); i++) {
        final ok = await Printing.layoutPdf(
          name: title,
          format: format,
          onLayout: (f) => Printing.convertHtml(html: html, format: f),
        );
        if (!ok) break;
        printed = true;
      }
      return printed;
    }
    Uint8List? bytes;
    if (canHtml) {
      bytes = await Printing.convertHtml(html: html, format: format);
    }
    if (bytes != null && bytes.isNotEmpty) {
      if (info.canPrint) {
        for (var i = 0; i < copies.clamp(1, 10); i++) {
          await Printing.layoutPdf(
            name: title,
            format: format,
            onLayout: (_) async => bytes!,
          );
        }
        return true;
      }
      if (info.canShare) {
        await Printing.sharePdf(bytes: bytes, filename: '$title.pdf');
        return true;
      }
    }
    if (info.canPrint) {
      await Printing.layoutPdf(
        name: title,
        format: format,
        onLayout: (_) async {
          if (canHtml) {
            return Printing.convertHtml(html: html, format: format);
          }
          return Uint8List(0);
        },
      );
      return true;
    }
  } catch (_) {}
  if (!kIsWeb) {
    try {
      await Share.share(html, subject: title);
      return true;
    } catch (_) {}
  }
  return false;
}

/// Dialog xem trước + in HTML mẫu (K58/K80/A4/A5).
Future<void> showPosHtmlPrintDialog(
  BuildContext context, {
  required String title,
  required String htmlDocument,
  int initialCopies = 1,
  bool? a4Paper,
  /// Gọi một lần khi in thành công (VD: ghi lần in hóa đơn — mở xem rồi đóng không tính).
  Future<void> Function()? onPrinted,
  /// Hiện nút gửi máy in văn phòng A4/A5 qua Print Agent Windows (chứng từ khổ trang).
  bool agentPagePrint = false,
  String agentDocumentType = 'SaleInvoice',
  String? referenceNo,
  String? referenceId,
}) async {
  var printedOnce = false;
  Future<void> markPrinted() async {
    if (printedOnce || onPrinted == null) return;
    printedOnce = true;
    await onPrinted();
  }
  var copies = initialCopies.clamp(1, 10);
  final screenW = MediaQuery.sizeOf(context).width;
  final isMobile = !kIsWeb && screenW < 600;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenW * 0.95,
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
          minWidth: isMobile ? 0 : 720,
          minHeight: isMobile ? 0 : 520,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr(title),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(tr('Số bản in:'), style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: copies,
                    items: List.generate(
                      10,
                      (i) => DropdownMenuItem(value: i + 1, child: Text(tr('${i + 1}'))),
                    ),
                    onChanged: (v) {
                      if (v != null) setDlg(() => copies = v);
                    },
                  ),
                  if (!agentPagePrint) const Spacer(),
                  if (agentPagePrint)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: PosAgentPagePrintButton(
                          htmlDocument: htmlDocument,
                          copies: () => copies,
                          documentType: agentDocumentType,
                          referenceNo: referenceNo,
                          referenceId: referenceId,
                          onSent: markPrinted,
                        ),
                      ),
                    ),
                  if (kIsWeb)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _blue),
                      onPressed: () async {
                        for (var i = 0; i < copies; i++) {
                          await printPosHtmlDocument(htmlDocument);
                        }
                        await markPrinted();
                      },
                      icon: const Icon(Icons.print, size: 18),
                      label: Text(tr('In')),
                    )
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _blue),
                      onPressed: () async {
                        final ok = await printOrSharePosHtml(
                          htmlDocument: htmlDocument,
                          title: title,
                          copies: copies,
                        );
                        if (ok) await markPrinted();
                      },
                      icon: const Icon(Icons.print, size: 18),
                      label: Text(tr(isMobile ? 'In / PDF' : 'In')),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: SboxColors.slate300),
                    color: SboxColors.slate100,
                  ),
                  child: buildPosHtmlPreview(htmlDocument, a4Paper: a4Paper),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    ),
  );
}
