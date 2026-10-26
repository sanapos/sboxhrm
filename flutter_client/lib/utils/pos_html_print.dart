import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../widgets/pos/pos_html_preview_stub.dart'
    if (dart.library.js_interop) '../widgets/pos/pos_html_preview_web.dart';
import 'pos_html_agent_print.dart';
import 'pos_print_template_defaults.dart';

import '../theme/sbox_tokens.dart';
import 'pos_busy.dart';
const _blue = SboxColors.brand600;

bool _pdfBytesOk(Uint8List? bytes) {
  if (bytes == null || bytes.length < 5) return false;
  return bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}

/// Lý do lần in HTML gần nhất thất bại (hiện trong hộp in — snackbar bị hộp che mất).
String? posHtmlPrintLastError;

/// In / chia sẻ PDF (Times + khổ/lề trong HTML). Không share raw HTML.
Future<bool> printOrSharePosHtml({
  required String htmlDocument,
  required String title,
  int copies = 1,
}) async {
  posHtmlPrintLastError = null;
  var html = htmlDocument.trim();
  if (html.isEmpty) {
    posHtmlPrintLastError = 'Mẫu in trống';
    return false;
  }
  if (!html.toLowerCase().contains('<html')) {
    final setup = PosCommercialPageSetup.parse(html);
    html = wrapPosCommercialPrintHtml(html, setup);
  }
  final setup = PosCommercialPageSetup.parse(html);
  final format = (setup.isA5 ? PdfPageFormat.a5 : PdfPageFormat.a4).copyWith(
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
    if (!canHtml) {
      posHtmlPrintLastError = 'Thiết bị không hỗ trợ chuyển HTML sang PDF';
      return false;
    }
    // Android: mở hộp in hệ thống ngay, PDF dựng trong lúc hộp đang mở — trước đây chờ WebView
    // dựng PDF xong (~10 giây trên máy yếu) mới thấy hộp in. Hủy trong hộp in → không báo lỗi.
    if (defaultTargetPlatform == TargetPlatform.android && info.canPrint) {
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
    Object? convertError;
    try {
      bytes = await Printing.convertHtml(html: html, format: format);
    } catch (e) {
      convertError = e;
    }
    if (!_pdfBytesOk(bytes)) {
      debugPrint('printOrSharePosHtml: convertHtml lỗi ($convertError) — thử in qua hộp in hệ thống');
      if (!info.canPrint) {
        posHtmlPrintLastError = 'Không tạo được PDF (${convertError ?? 'PDF rỗng'})';
        return false;
      }
      // Một số máy (WebView ngoài màn hình) chỉ dựng PDF được trong lúc hộp in hệ thống đang mở.
      final ok = await Printing.layoutPdf(
        name: title,
        format: format,
        onLayout: (f) => Printing.convertHtml(html: html, format: f),
      );
      return ok;
    }
    final pdf = bytes!;
    if (info.canPrint) {
      for (var i = 0; i < copies.clamp(1, 10); i++) {
        await Printing.layoutPdf(
          name: title,
          format: format,
          onLayout: (_) async => pdf,
        );
      }
      return true;
    }
    if (info.canShare) {
      await Printing.sharePdf(bytes: pdf, filename: '$title.pdf');
      return true;
    }
  } catch (e) {
    debugPrint('printOrSharePosHtml: $e');
    posHtmlPrintLastError = '$e';
  }
  posHtmlPrintLastError ??= 'Máy không có dịch vụ in / chia sẻ';
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
  PosBusy.hideLayer(); // lớp «Đang mở…» không nằm sau hộp này
  // Ô nhập phía sau (ghi chú báo giá…) còn focus → bàn phím ảo bật đè lên trang xem trước.
  FocusManager.instance.primaryFocus?.unfocus();
  var copies = initialCopies.clamp(1, 10);
  var printing = false;
  String? printError;
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
                      onPressed: printing
                          ? null
                          : () async {
                              setDlg(() {
                                printing = true;
                                printError = null;
                              });
                              final ok = await printOrSharePosHtml(
                                htmlDocument: htmlDocument,
                                title: title,
                                copies: copies,
                              );
                              if (ok) await markPrinted();
                              if (!ctx.mounted) return;
                              setDlg(() {
                                printing = false;
                                // Hủy trong hộp in hệ thống: không có lý do lỗi → không báo.
                                if (!ok && posHtmlPrintLastError != null) {
                                  printError = posHtmlPrintLastError;
                                }
                              });
                            },
                      icon: printing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.print, size: 18),
                      label: Text(tr(isMobile ? 'In / PDF' : 'In')),
                    ),
                ],
              ),
            ),
            if (printError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '${tr('Không in được')}: $printError',
                  style: const TextStyle(color: SboxColors.danger, fontSize: 13),
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
