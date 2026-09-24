import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_tr.dart';
import '../models/pos_quote.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart';
import '../models/pos_print_template.dart';
import '../utils/pos_html_print.dart';
import '../utils/pos_quote_document_wording.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_quote_care_sheet.dart';

/// Hỏi chèn dấu treo trước khi in / xuất / gửi. Null = hủy.
Future<bool?> askPosQuoteStamp(BuildContext context) async {
  var stamp = true;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(tr('Xuất báo giá')),
        content: CheckboxListTile(
          value: stamp,
          onChanged: (v) => setLocal(() => stamp = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(tr('Chèn dấu treo')),
          subtitle: Text(
            tr('Đóng dấu công ty lên chữ ký khi in, xuất hoặc gửi.'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, stamp),
            child: Text(tr('Tiếp tục')),
          ),
        ],
      ),
    ),
  );
}

/// Xuất / chia sẻ báo giá: Excel, Word, PDF (in), Zalo, Email, Facebook.
class PosQuoteExport {
  PosQuoteExport._();

  static Future<void> exportExcel(
    BuildContext context, {
    required String quoteId,
    required String quoteNo,
    bool includeImages = false,
  }) async {
    final bytes = await ApiService().downloadPosQuoteExport(
      quoteId,
      'excel',
      includeImages: includeImages,
    );
    if (!context.mounted) return;
    if (bytes == null || bytes.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Không xuất được',
        message: tr('Không tạo file Excel'),
      );
      return;
    }
    final name = 'BaoGia_$quoteNo.xlsx';
    await saveAndOpenFileBytes(
      bytes,
      name,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    NotificationOverlayManager().showSuccess(
      title: 'Đã xuất Excel',
      message: name,
    );
  }

  static Future<void> exportWord(
    BuildContext context, {
    required String quoteId,
    required String quoteNo,
    bool includeImages = false,
    bool includeStamp = true,
    PosQuote? quote,
  }) async {
    final local = await _localWordBytes(quote, includeStamp: includeStamp);
    final bytes = local ??
        await ApiService().downloadPosQuoteExport(
          quoteId,
          'word',
          includeImages: includeImages,
        );
    if (!context.mounted) return;
    if (bytes == null || bytes.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Không xuất được',
        message: tr('Không tạo file Word'),
      );
      return;
    }
    final name = 'BaoGia_$quoteNo.doc';
    await saveAndOpenFileBytes(bytes, name, 'application/msword');
    NotificationOverlayManager().showSuccess(
      title: 'Đã xuất Word',
      message: name,
    );
  }

  static Future<void> exportPdf(
    BuildContext context, {
    required String quoteId,
    required String quoteNo,
    bool includeImages = false,
    bool includeStamp = true,
    PosQuote? quote,
  }) async {
    if (quote != null) {
      final saved = posQuoteSavedWordingHtml(quote.documents, 'Quote');
      if (saved != null && saved.trim().isNotEmpty) {
        if (!context.mounted) return;
        await showPosHtmlPrintDialog(
          context,
          title: 'BÁO GIÁ $quoteNo',
          htmlDocument: saved,
          a4Paper: true,
        );
        return;
      }
    }
    if (quote != null && quote.lines.isNotEmpty) {
      final html = bindPosQuotePrintHtmlLocal(
        quote,
        quote.lines,
        commercialProfile: await _profile(),
        includeStamp: includeStamp,
      );
      if (!context.mounted) return;
      await showPosHtmlPrintDialog(
        context,
        title: 'BÁO GIÁ $quoteNo',
        htmlDocument: html,
        a4Paper: true,
      );
      return;
    }
    final html = await ApiService().fetchPosQuoteExportHtml(
      quoteId,
      includeImages: includeImages,
    );
    if (!context.mounted) return;
    if (html == null || html.trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Không xuất được',
        message: tr('Không mở xem trước in PDF'),
      );
      return;
    }
    await showPosHtmlPrintDialog(
      context,
      title: 'BÁO GIÁ $quoteNo',
      htmlDocument: html,
      a4Paper: true,
    );
  }

  static Future<void> shareQuote(
    BuildContext context, {
    required String quoteId,
    required String quoteNo,
    required String customerName,
    required String channel,
    bool includeImages = false,
    bool includeStamp = true,
    PosQuote? quote,
  }) async {
    final local = await _localWordBytes(quote, includeStamp: includeStamp);
    final bytes = local ??
        await ApiService().downloadPosQuoteExport(
      quoteId,
      'word',
      includeImages: includeImages,
    );
    final summary =
        'Báo giá $quoteNo — $customerName\nVui lòng xem file đính kèm.';
    final name = 'BaoGia_$quoteNo.doc';
    final fileBytes = bytes == null ? null : Uint8List.fromList(bytes);

    switch (channel) {
      case 'email':
        if (fileBytes != null && fileBytes.isNotEmpty) {
          await Share.shareXFiles(
            [
              XFile.fromData(
                fileBytes,
                name: name,
                mimeType: 'application/msword',
              ),
            ],
            text: summary,
            subject: 'Báo giá $quoteNo',
          );
        } else {
          final uri = Uri.parse(
            'mailto:?subject=${Uri.encodeComponent('Báo giá $quoteNo')}'
            '&body=${Uri.encodeComponent(summary)}',
          );
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case 'zalo':
        if (fileBytes != null && fileBytes.isNotEmpty) {
          await Share.shareXFiles(
            [
              XFile.fromData(
                fileBytes,
                name: name,
                mimeType: 'application/msword',
              ),
            ],
            text: summary,
          );
        } else {
          final uri = Uri.parse(
              'https://zalo.me/share?url=${Uri.encodeComponent(summary)}');
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case 'facebook':
        final uri = Uri.parse(
          'https://www.facebook.com/sharer/sharer.php?quote=${Uri.encodeComponent(summary)}',
        );
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        break;
      default:
        if (fileBytes != null && fileBytes.isNotEmpty) {
          await Share.shareXFiles(
            [
              XFile.fromData(
                fileBytes,
                name: name,
                mimeType: 'application/msword',
              ),
            ],
            text: summary,
          );
        } else {
          await Share.share(summary);
        }
    }
  }

  static Future<Map<String, dynamic>?> _profile() async {
    try {
      final res = await ApiService().getPosCommercialProfile();
      if (res['isSuccess'] == true && res['data'] is Map) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> exportPng(
    BuildContext context, {
    required String html,
    required String fileName,
  }) async {
    final png = await htmlToPngBytes(html);
    if (!context.mounted) return;
    if (png == null || png.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Không xuất được',
        message: tr('Không tạo được ảnh PNG'),
      );
      return;
    }
    await saveAndOpenFileBytes(png, fileName, 'image/png');
    NotificationOverlayManager().showSuccess(
      title: 'Đã xuất PNG',
      message: fileName,
    );
  }

  static Future<Uint8List?> htmlToPngBytes(String html) async {
    final raw = html.trim();
    if (raw.isEmpty) return null;
    final pdfBytes = await Printing.convertHtml(
      html: raw,
      format: PdfPageFormat.a4,
    );
    final images = <ui.Image>[];
    await for (final raster in Printing.raster(pdfBytes, dpi: 110)) {
      images.add(await raster.toImage());
      if (images.length >= 3) break;
    }
    if (images.isEmpty) return null;
    final width = images.first.width;
    final height = images.fold<int>(0, (a, im) => a + im.height);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    var y = 0.0;
    for (final im in images) {
      canvas.drawImage(im, ui.Offset(0, y), ui.Paint());
      y += im.height.toDouble();
    }
    final picture = recorder.endRecording();
    final out = await picture.toImage(width, height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    for (final im in images) {
      im.dispose();
    }
    picture.dispose();
    out.dispose();
    return data?.buffer.asUint8List();
  }

  static Future<PosQuote> ensureLines(PosQuote quote) async {
    if (quote.lines.isNotEmpty && quote.documents.isNotEmpty) return quote;
    final res = await ApiService().getPosQuote(quote.id);
    if (res['isSuccess'] == true && res['data'] is Map) {
      return PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
    }
    return quote;
  }

  static String? docNoOf(PosQuote quote, String documentType) {
    for (final d in quote.documents) {
      if (d.kind == documentType && d.docNo.isNotEmpty) return d.docNo;
    }
    return null;
  }

  static Future<String> renderHtml(
    PosQuote quote, {
    required String documentType,
    String? docNo,
    bool includeStamp = true,
  }) async {
    final saved = posQuoteSavedWordingHtml(quote.documents, documentType);
    if (saved != null) return saved;
    final profile = await _profile();
    if (documentType == PosPrintDocumentTypes.quote) {
      return bindPosQuotePrintHtmlLocal(
        quote,
        quote.lines,
        commercialProfile: profile,
        includeStamp: includeStamp,
      );
    }
    return bindPosCommercialPrintHtmlLocal(
      quote,
      documentType: documentType,
      docNo: docNo ?? docNoOf(quote, documentType) ?? quote.quoteNo,
      includeStamp: includeStamp,
      commercialProfile: profile,
    );
  }

  /// In / xuất / chia sẻ dùng chung cho báo giá, hợp đồng, bàn giao, nghiệm thu.
  static Future<void> run(
    BuildContext context, {
    required PosQuote quote,
    required String action,
    String documentType = PosPrintDocumentTypes.quote,
  }) async {
    final needsStamp = action == 'print' ||
        action == 'word' ||
        action == 'pdf' ||
        action == 'png' ||
        action == 'email' ||
        action == 'zalo' ||
        action == 'facebook';
    var stamp = true;
    if (needsStamp) {
      final picked = await askPosQuoteStamp(context);
      if (picked == null || !context.mounted) return;
      stamp = picked;
    }
    final full = await ensureLines(quote);
    if (!context.mounted) return;
    final no = docNoOf(full, documentType) ?? full.quoteNo;
    Future<String> html() => renderHtml(
          full,
          documentType: documentType,
          docNo: no,
          includeStamp: stamp,
        );
    switch (action) {
      case 'print':
        final body = await html();
        if (!context.mounted) return;
        await showPosHtmlPrintDialog(
          context,
          title: no,
          htmlDocument: body,
          a4Paper: true,
        );
      case 'excel':
        await exportExcel(context, quoteId: full.id, quoteNo: full.quoteNo);
      case 'word':
        if (documentType == PosPrintDocumentTypes.quote) {
          await exportWord(
            context,
            quoteId: full.id,
            quoteNo: no,
            includeStamp: stamp,
            quote: full,
          );
        } else {
          final body = await html();
          if (!context.mounted) return;
          final doc =
              '<html><head><meta charset="utf-8"></head><body>$body</body></html>';
          await saveAndOpenFileBytes(
            utf8.encode(doc),
            '${documentType}_$no.doc',
            'application/msword',
          );
          NotificationOverlayManager().showSuccess(
            title: 'Đã xuất Word',
            message: '${documentType}_$no.doc',
          );
        }
      case 'pdf':
        final body = await html();
        if (!context.mounted) return;
        await showPosHtmlPrintDialog(
          context,
          title: no,
          htmlDocument: body,
          a4Paper: true,
        );
      case 'png':
        final body = await html();
        if (!context.mounted) return;
        await exportPng(context, html: body, fileName: '${documentType}_$no.png');
      case 'email':
      case 'zalo':
      case 'facebook':
        await shareQuote(
          context,
          quoteId: full.id,
          quoteNo: no,
          customerName: full.customerName ?? '',
          channel: action,
          includeStamp: stamp,
          quote: full,
        );
      case 'call':
        await callPosQuoteCustomer(full.customerPhone);
      case 'zaloCall':
        await openPosQuoteZalo(full.customerPhone);
      case 'facebookLink':
        await openPosQuoteFacebook(
          phone: full.customerPhone,
          name: full.customerName,
        );
      case 'care':
        await showPosQuoteCareSheet(
          context,
          quoteId: full.id,
          quoteNo: full.quoteNo,
          customerName: full.customerName,
          customerPhone: full.customerPhone,
        );
    }
  }

  static Future<Uint8List?> _localWordBytes(
    PosQuote? quote, {
    required bool includeStamp,
  }) async {
    if (quote == null) return null;
    final saved = posQuoteSavedWordingHtml(quote.documents, 'Quote');
    if (saved != null && saved.trim().isNotEmpty) {
      final doc = saved.toLowerCase().contains('<html')
          ? saved
          : '<html><head><meta charset="utf-8"></head><body>$saved</body></html>';
      return Uint8List.fromList(utf8.encode(doc));
    }
    if (quote.lines.isEmpty) return null;
    final html = bindPosQuotePrintHtmlLocal(
      quote,
      quote.lines,
      commercialProfile: await _profile(),
      includeStamp: includeStamp,
    );
    if (html.trim().isEmpty) return null;
    final doc = '<html><head><meta charset="utf-8"></head><body>$html</body></html>';
    return Uint8List.fromList(utf8.encode(doc));
  }
}
