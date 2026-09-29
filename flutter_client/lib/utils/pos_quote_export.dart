import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_tr.dart';
import '../models/pos_quote.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart';
import 'export_permission_guard.dart';
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

  /// Tệp gửi khách: PDF A4 (máy chủ dựng) → ảnh PNG (dựng trên máy) → Word (.doc) nếu hai cách trên lỗi.
  static Future<({Uint8List bytes, String name, String mime})?> _shareFile({
    required String quoteId,
    required String html,
    required String fileBase,
  }) async {
    if (html.trim().isNotEmpty) {
      final pdf = await ApiService().exportPosQuotePdfFromHtml(quoteId, html: html, fileName: fileBase);
      if (pdf['isSuccess'] == true && pdf['data'] is List && (pdf['data'] as List).isNotEmpty) {
        return (
          bytes: Uint8List.fromList(List<int>.from(pdf['data'] as List)),
          name: '$fileBase.pdf',
          mime: 'application/pdf',
        );
      }
      try {
        final png = await htmlToPngBytes(html);
        if (png != null && png.isNotEmpty) {
          return (bytes: png, name: '$fileBase.png', mime: 'image/png');
        }
      } catch (_) {}
      final doc = html.toLowerCase().contains('<html')
          ? html
          : '<html><head><meta charset="utf-8"></head><body>$html</body></html>';
      return (bytes: Uint8List.fromList(utf8.encode(doc)), name: '$fileBase.doc', mime: 'application/msword');
    }
    return null;
  }

  /// Gửi báo giá / chứng từ cho khách qua Email, Zalo, Facebook (Messenger) hoặc ứng dụng khác.
  /// Điện thoại: mở bảng chia sẻ kèm file PDF → chọn Zalo / Messenger / Gmail.
  /// Web: tải PDF về máy rồi mở Zalo Web / Messenger / thư để đính kèm.
  static Future<void> shareQuote(
    BuildContext context, {
    required String quoteId,
    required String quoteNo,
    required String customerName,
    required String channel,
    required String html,
    String? customerPhone,
    String title = 'Báo giá',
  }) async {
    NotificationOverlayManager().showInfo(
      title: 'Đang chuẩn bị file…',
      message: tr('Dựng PDF khổ A4 để gửi khách'),
    );
    final file = await _shareFile(quoteId: quoteId, html: html, fileBase: 'BaoGia_$quoteNo');
    if (!context.mounted) return;
    final who = customerName.trim().isEmpty ? '' : ' — $customerName';
    final summary = '$title $quoteNo$who\nKính gửi Quý khách file $title đính kèm.';
    if (file == null) {
      NotificationOverlayManager().showError(title: 'Không tạo được file', message: tr('Vui lòng thử lại'));
      return;
    }
    final phone = (customerPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    if (kIsWeb) {
      // Trình duyệt máy tính không gửi file thẳng sang Zalo / Messenger được → tải file rồi mở cửa sổ chat.
      await saveAndOpenFileBytes(file.bytes, file.name, file.mime);
      final Uri target = switch (channel) {
        'zalo' => Uri.parse(phone.isNotEmpty ? 'https://zalo.me/$phone' : 'https://chat.zalo.me/'),
        'facebook' => Uri.parse('https://www.facebook.com/messages/'),
        _ => Uri.parse('mailto:?subject=${Uri.encodeComponent('$title $quoteNo')}'
            '&body=${Uri.encodeComponent(summary)}'),
      };
      await launchUrl(target, mode: LaunchMode.externalApplication);
      NotificationOverlayManager().showSuccess(
        title: 'Đã tải ${file.name}',
        message: tr(channel == 'email'
            ? 'Đính kèm file vừa tải vào thư đang mở.'
            : 'Kéo thả file vừa tải vào cuộc trò chuyện ${channel == 'zalo' ? 'Zalo' : 'Messenger'} để gửi khách.'),
      );
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final result = await Share.shareXFiles(
      [XFile.fromData(file.bytes, name: file.name, mimeType: file.mime)],
      text: summary,
      subject: '$title $quoteNo',
      sharePositionOrigin: origin,
    );
    if (result.status == ShareResultStatus.unavailable) {
      await saveAndOpenFileBytes(file.bytes, file.name, file.mime);
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
    String? quoteId,
  }) async {
    Uint8List? png;
    try {
      png = await htmlToPngBytes(html, quoteId: quoteId);
    } catch (_) {}
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

  /// HTML → ảnh PNG (tối đa 3 trang ghép dọc). Có [quoteId] → PDF do máy chủ dựng (chạy cả trên web).
  static Future<Uint8List?> htmlToPngBytes(String html, {String? quoteId}) async {
    final raw = html.trim();
    if (raw.isEmpty) return null;
    Uint8List? pdfBytes;
    if (quoteId != null) {
      final res = await ApiService().exportPosQuotePdfFromHtml(quoteId, html: raw, fileName: 'anh');
      if (res['isSuccess'] == true && res['data'] is List) {
        pdfBytes = Uint8List.fromList(List<int>.from(res['data'] as List));
      }
    }
    pdfBytes ??= kIsWeb
        ? null
        : await Printing.convertHtml(
            html: raw,
            format: PdfPageFormat.a4,
          );
    if (pdfBytes == null || pdfBytes.isEmpty) return null;
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

  static final _docxTemplateCache = <String, (bool, DateTime)>{};

  /// Cửa hàng có mẫu Word (giữ bố cục) đang bật cho loại chứng từ này? (nhớ 60 giây)
  static Future<bool> hasDocxTemplate(String documentType) async {
    final hit = _docxTemplateCache[documentType];
    if (hit != null && DateTime.now().difference(hit.$2) < const Duration(seconds: 60)) {
      return hit.$1;
    }
    final res = await ApiService().getPosPrintTemplates(documentType: documentType);
    final has = res['isSuccess'] == true &&
        res['data'] is List &&
        (res['data'] as List).whereType<Map>().any((t) => t['isDocx'] == true && t['isActive'] != false);
    _docxTemplateCache[documentType] = (has, DateTime.now());
    return has;
  }

  /// Xuất từ mẫu Word của cửa hàng (server điền dữ liệu; PDF tạo bằng LibreOffice).
  static Future<void> exportFromWordTemplate(
    BuildContext context, {
    required PosQuote quote,
    required String documentType,
    required bool pdf,
  }) async {
    final no = docNoOf(quote, documentType) ?? quote.quoteNo;
    NotificationOverlayManager().showInfo(
      title: pdf ? 'Đang tạo PDF…' : 'Đang tạo Word…',
      message: tr('Điền dữ liệu vào mẫu Word của cửa hàng'),
    );
    final res = await ApiService().exportPosQuoteFile(
      quote.id,
      kind: documentType,
      format: pdf ? 'pdf' : 'docx',
    );
    if (!context.mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: pdf ? 'Không tạo được PDF' : 'Không tạo được Word',
        message: res['message']?.toString() ?? tr('Vui lòng thử lại'),
      );
      return;
    }
    await saveAndOpenFileBytes(
      List<int>.from(res['data'] as List),
      '${documentType}_$no.${pdf ? 'pdf' : 'docx'}',
      pdf
          ? 'application/pdf'
          : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
  }

  /// Tải file PDF thật (A4, đúng bố cục đang in) do máy chủ dựng; lỗi / mất mạng
  /// → mở hộp in của máy như trước (chọn "Lưu PDF").
  static Future<void> exportServerPdf(
    BuildContext context, {
    required String quoteId,
    required String html,
    required String fileName,
  }) async {
    NotificationOverlayManager().showInfo(
      title: 'Đang tạo PDF…',
      message: tr('Máy chủ dựng file PDF khổ A4'),
    );
    final res = await ApiService()
        .exportPosQuotePdfFromHtml(quoteId, html: html, fileName: fileName);
    if (!context.mounted) return;
    if (res['isSuccess'] == true) {
      await saveAndOpenFileBytes(
        List<int>.from(res['data'] as List),
        '$fileName.pdf',
        'application/pdf',
      );
      return;
    }
    NotificationOverlayManager().showError(
      title: 'Không tạo được PDF trên máy chủ',
      message: '${res['message'] ?? ''} — ${tr('mở hộp in để lưu PDF')}',
    );
    await showPosHtmlPrintDialog(
      context,
      title: fileName,
      htmlDocument: html,
      a4Paper: true,
    );
  }

  /// In / xuất / chia sẻ dùng chung cho báo giá, hợp đồng, bàn giao, nghiệm thu.
  static Future<void> run(
    BuildContext context, {
    required PosQuote quote,
    required String action,
    String documentType = PosPrintDocumentTypes.quote,
  }) async {
    // Xuất file / gửi file cho khách cần quyền «Xuất» của Báo giá (in trực tiếp chỉ cần Xem).
    const exportActions = {'excel', 'word', 'pdf', 'png', 'email', 'zalo', 'facebook'};
    if (exportActions.contains(action) && !ensureCanExport(context, 'PosQuotes')) return;
    // Có mẫu Word giữ bố cục → Word / PDF lấy từ mẫu đó (không hỏi con dấu HTML).
    if ((action == 'word' || action == 'pdf') && await hasDocxTemplate(documentType)) {
      if (!context.mounted) return;
      await exportFromWordTemplate(context,
          quote: quote, documentType: documentType, pdf: action == 'pdf');
      return;
    }
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
    try {
      await _runAction(context, quote: quote, action: action, documentType: documentType, stamp: stamp);
    } catch (e) {
      NotificationOverlayManager().showError(
        title: 'Không thực hiện được',
        message: tr('Lỗi khi xuất / chia sẻ: $e'),
      );
    }
  }

  static Future<void> _runAction(
    BuildContext context, {
    required PosQuote quote,
    required String action,
    required String documentType,
    required bool stamp,
  }) async {
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
        await exportServerPdf(context,
            quoteId: full.id, html: body, fileName: '${documentType}_$no');
      case 'png':
        final body = await html();
        if (!context.mounted) return;
        await exportPng(context, html: body, fileName: '${documentType}_$no.png', quoteId: full.id);
      case 'email':
      case 'zalo':
      case 'facebook':
        final body = await html();
        if (!context.mounted) return;
        await shareQuote(
          context,
          quoteId: full.id,
          quoteNo: no,
          customerName: full.customerName ?? '',
          customerPhone: full.customerPhone,
          channel: action,
          html: body,
          title: switch (documentType) {
            PosPrintDocumentTypes.quote => 'Báo giá',
            _ => 'Chứng từ',
          },
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
