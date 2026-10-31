import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../services/pos_product_image_cache.dart';
import '../../utils/api_datetime.dart';
import '../../utils/pos_area_dims.dart';
import '../../utils/pos_commercial_profile_local.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../utils/pos_html_print.dart';
import '../../utils/pos_quote_document_wording.dart';
import '../../utils/pos_quote_export.dart';
import '../../utils/pos_print_template_defaults.dart';
import '../../utils/pos_print_template_loader.dart';
import '../../utils/pos_print_template_renderer.dart';
import '../../utils/pos_print_template_v2_codec.dart';
import '../../utils/pos_vietnamese_money_words.dart';
import '../../widgets/notification_overlay.dart';
import 'pos_quote_care_card.dart';
import 'pos_theme.dart';

import '../../theme/sbox_tokens.dart';
Future<void> openPosQuoteZalo(String? phone) async {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    NotificationOverlayManager().showWarning(
      title: 'Chưa có SĐT',
      message: tr('Không gọi Zalo được vì chưa có số điện thoại'),
    );
    return;
  }
  final uri = Uri.parse('https://zalo.me/$digits');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    NotificationOverlayManager().showError(
      title: 'Không mở được Zalo',
      message: digits,
    );
  }
}

Future<void> openPosQuoteFacebook({String? phone, String? name}) async {
  final q = (phone ?? '').trim().isNotEmpty
      ? phone!.trim()
      : (name ?? '').trim();
  if (q.isEmpty) {
    NotificationOverlayManager().showWarning(
      title: 'Chưa có khách',
      message: tr('Không mở Facebook được vì chưa có tên hoặc số điện thoại'),
    );
    return;
  }
  final uri = Uri.parse(
    'https://www.facebook.com/search/top/?q=${Uri.encodeComponent(q)}',
  );
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    NotificationOverlayManager().showError(
      title: 'Không mở được Facebook',
      message: q,
    );
  }
}

Future<void> callPosQuoteCustomer(String? phone) async {
  final raw = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  if (raw.isEmpty) {
    NotificationOverlayManager().showWarning(
      title: 'Chưa có SĐT',
      message: tr('Báo giá này chưa có số điện thoại khách'),
    );
    return;
  }
  final uri = Uri(scheme: 'tel', path: raw);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    NotificationOverlayManager().showError(
      title: 'Không gọi được',
      message: raw,
    );
  }
}

Future<void> printPosQuoteSlip(
  BuildContext context, {
  required String quoteId,
  PosQuote? quote,
  List<PosQuoteLine>? lines,
  bool includeImages = false,
  bool includeStamp = true,
}) async {
  final api = ApiService();
  var html = '';
  var title = quote?.quoteSlip?.title ?? 'BÁO GIÁ';
  PosQuote? q = quote;
  var useLines = lines ?? q?.lines ?? const <PosQuoteLine>[];
  if (q == null || useLines.isEmpty) {
    final res = await api.getPosQuote(quoteId);
    if (res['isSuccess'] == true && res['data'] is Map) {
      q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
      if (useLines.isEmpty) useLines = q.lines;
    }
  }
  // Báo giá đã lưu: in đúng bản PDF máy chủ dựng — trùng với Xuất PDF / Word / gửi khách.
  if (lines == null && q != null && q.id.isNotEmpty) {
    if (!context.mounted) return;
    await PosQuoteExport.run(
      context,
      quote: q,
      action: 'print',
    );
    return;
  }
  if (q != null) {
    final custom = posQuoteSavedWordingHtml(q.documents, 'Quote');
    if (custom != null) {
      if (!context.mounted) return;
      await showPosHtmlPrintDialog(
        context,
        title: q.quoteSlip?.title ?? 'BÁO GIÁ',
        htmlDocument: custom,
        a4Paper: true,
      );
      return;
    }
  }
  // Báo giá đã lưu: lấy từ máy chủ — đủ đợt thanh toán, số HĐ, số đã thu, mẫu của cửa hàng.
  if (lines == null) {
    final server = await posQuoteServerDocument(
      quoteId,
      PosPrintDocumentTypes.quote,
      includeImages: includeImages,
      includeStamp: includeStamp,
      api: api,
    );
    if (server != null) {
      if (!context.mounted) return;
      posQuoteWarnIfStale(server);
      await showPosHtmlPrintDialog(
        context,
        title: title,
        htmlDocument: server.html,
        a4Paper: true,
      );
      return;
    }
  }
  if (q != null && useLines.isNotEmpty) {
    Map<String, dynamic>? profile;
    try {
      final profileRes = await api.getPosCommercialProfile();
      final local = await loadLocalCommercialProfile();
      if (profileRes['isSuccess'] == true && profileRes['data'] is Map) {
        profile = mergeCommercialProfile(
          Map<String, dynamic>.from(profileRes['data'] as Map),
          local,
        );
      } else if (local.isNotEmpty) {
        profile = local;
      }
    } catch (_) {}
    PosSellStoreSettings? store;
    try {
      store = await PosSellStoreSettings.load();
    } catch (_) {}
    List<Map<String, String>>? rendered;
    if (includeImages) {
      rendered = await _quoteLineItemsWithImages(api, useLines);
    }
    try {
      html = bindPosQuotePrintHtmlLocal(
        q,
        useLines,
        commercialProfile: profile,
        storeName: store?.storeName,
        storeAddress: store?.address,
        storePhone: store?.phone,
        includeStamp: includeStamp,
        renderedLines: rendered,
      );
    } catch (_) {
      html = '';
    }
    if (html.trim().isEmpty) {
      try {
        html = await bindPosQuotePrintHtml(api, q, useLines);
      } catch (_) {
        html = '';
      }
    }
    if (html.trim().isNotEmpty) title = 'BÁO GIÁ';
  }
  // Chỉ gọi preview API khi không có dòng hàng — preview hay dính mẫu Aquafina.
  if (html.trim().isEmpty && useLines.isEmpty) {
    final preview = await api.previewPosQuoteDocument(
      quoteId,
      'Quote',
      includeImages: includeImages,
    );
    if (preview['isSuccess'] == true && preview['data'] is Map) {
      final data = Map<String, dynamic>.from(preview['data'] as Map);
      html = (data['htmlContent'] ?? data['HtmlContent'] ?? '').toString();
      title = (data['title'] ?? data['Title'] ?? title).toString();
    }
  }
  if (html.trim().isEmpty) {
    final slip = q?.quoteSlip?.htmlContent ?? '';
    if (slip.isNotEmpty && !slip.contains('XEM TRƯỚC')) {
      html = slip;
      title = q?.quoteSlip?.title ?? title;
    }
  }
  if (!context.mounted) return;
  if (html.trim().isEmpty) {
    NotificationOverlayManager().showError(
      title: 'Chưa có phiếu',
      message: tr('Không tạo được bảng báo giá'),
    );
    return;
  }
  await showPosHtmlPrintDialog(
    context,
    title: title,
    htmlDocument: html,
    a4Paper: true,
  );
}

/// Bản in một chứng từ do máy chủ dựng.
class PosQuoteServerDoc {
  const PosQuoteServerDoc({
    required this.html,
    this.isCustomWording = false,
    this.isStale = false,
    this.docId,
  });

  final String html;

  /// In đúng lời văn đã sửa riêng của chứng từ.
  final bool isCustomWording;

  /// Lời văn sửa riêng không còn khớp số liệu báo giá (giá, dòng hàng, đã thu… đã đổi sau khi sửa).
  final bool isStale;
  final String? docId;
}

/// Chứng từ dựng trên máy chủ: [docId] → đúng chứng từ đó (lời văn sửa riêng / mẫu chọn riêng);
/// không có → số liệu hiện tại + mẫu ([templateId] / mẫu báo giá / mặc định). Bọc lại khổ + lề
/// giống trình soạn mẫu. null khi offline / lỗi — dùng bản cục bộ.
Future<PosQuoteServerDoc?> posQuoteServerDocument(
  String quoteId,
  String kind, {
  bool includeImages = false,
  bool includeStamp = true,
  String? docNo,
  String? docId,
  String? templateId,
  ApiService? api,
}) async {
  if (quoteId.isEmpty) return null;
  try {
    final res = await (api ?? ApiService()).previewPosQuoteDocument(
      quoteId,
      kind,
      includeImages: includeImages,
      includeStamp: includeStamp,
      docNo: docNo,
      docId: docId,
      templateId: templateId,
    );
    if (res['isSuccess'] != true || res['data'] is! Map) return null;
    final data = res['data'] as Map;
    final html = (data['htmlContent'] ?? data['HtmlContent'] ?? '').toString();
    if (html.trim().isEmpty || html.contains('XEM TRƯỚC')) return null;
    final body = RegExp(r'<body[^>]*>([\s\S]*)</body>', caseSensitive: false)
            .firstMatch(html)
            ?.group(1) ??
        html;
    return PosQuoteServerDoc(
      html: wrapPosPrintHtmlDocument(body, paperSize: PosPrintPaperSizes.a4),
      isCustomWording: data['isCustomWording'] == true,
      isStale: data['isStale'] == true,
      docId: data['docId']?.toString(),
    );
  } catch (_) {
    return null;
  }
}

Future<String?> posQuoteServerDocumentHtml(
  String quoteId,
  String kind, {
  bool includeImages = false,
  bool includeStamp = true,
  String? docNo,
  String? docId,
  String? templateId,
  ApiService? api,
}) async =>
    (await posQuoteServerDocument(
      quoteId,
      kind,
      includeImages: includeImages,
      includeStamp: includeStamp,
      docNo: docNo,
      docId: docId,
      templateId: templateId,
      api: api,
    ))
        ?.html;

/// Không lấy được bản máy chủ → đang dùng bản dựng trên máy (thiếu đợt thanh toán / bảo hành từng dòng…).
void posQuoteWarnOfflineCopy() {
  NotificationOverlayManager().showWarning(
    title: 'Đang dùng bản in tạm trên máy',
    message: tr('Không tải được bản chứng từ từ máy chủ (mất mạng?) — bản này có thể thiếu tiến độ '
        'thanh toán, bảo hành từng dòng, thời gian thực hiện. Có mạng hãy in / xuất lại trước khi gửi khách.'),
  );
}

/// Nhắc khi bản sửa lời văn riêng đã cũ so với số liệu báo giá.
void posQuoteWarnIfStale(PosQuoteServerDoc doc) {
  if (!doc.isStale) return;
  NotificationOverlayManager().showWarning(
    title: 'Lời văn sửa riêng đã cũ',
    message: tr('Báo giá đã đổi (giá, dòng hàng hoặc tiền đã thu) sau khi sửa lời văn — '
        'bản in vẫn giữ nội dung đã sửa. Vào «Lịch sử / Khôi phục theo mẫu» để cập nhật.'),
  );
}

String bindPosQuotePrintHtmlLocal(
  PosQuote q,
  List<PosQuoteLine> lineItems, {
  Map<String, dynamic>? commercialProfile,
  String? storeName,
  String? storeAddress,
  String? storePhone,
  bool includeStamp = true,
  List<Map<String, String>>? renderedLines,
}) {
  final data = posPrintSampleData(
    documentType: PosPrintDocumentTypes.quote,
    commercialProfile: commercialProfile,
    storeName: storeName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    fillSamples: false,
  );
  final items = _withLineVatRates(q, lineItems, renderedLines ?? _quoteLineItems(lineItems));
  data.addAll(_quoteHeaderData(q, lineItems, profile: commercialProfile));
  data.addAll(_lineFlags(items));
  if (!includeStamp) {
    data['Con_Dau'] = '<div style="height:48px"></div>';
  }
  for (final k in const [
    'So_Luong',
    'Don_Gia',
    'Ma_Hang',
    'Don_Vi_Tinh',
    'Ma_Vach',
    'STT',
  ]) {
    data.remove(k);
  }
  return renderPosPrintTemplateHtml(
    posPrintDefaultHtml(
      documentType: PosPrintDocumentTypes.quote,
      paperSize: PosPrintPaperSizes.a4,
    ),
    data: data,
    lineItems: items,
    wrapDocument: true,
    paperSize: PosPrintPaperSizes.a4,
  );
}

/// Hợp đồng / đề nghị TT / bàn giao / nghiệm thu — mẫu A4 cục bộ, không dùng HTML cũ đã lưu.
String bindPosCommercialPrintHtmlLocal(
  PosQuote q, {
  required String documentType,
  String? docNo,
  bool includeStamp = true,
  Map<String, dynamic>? commercialProfile,
  String? storeName,
  String? storeAddress,
  String? storePhone,
}) {
  final lines = q.lines;
  final data = posPrintSampleData(
    documentType: documentType,
    commercialProfile: commercialProfile,
    storeName: storeName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    fillSamples: false,
  );
  final items = _withLineVatRates(q, lines, _quoteLineItems(lines));
  data.addAll(_quoteHeaderData(q, lines, profile: commercialProfile));
  data.addAll(_lineFlags(items));
  final no = (docNo == null || docNo.isEmpty) ? q.quoteNo : docNo;
  data.addAll({
    'Tieu_De_In': PosPrintDocumentTypes.all[documentType] ?? 'Chứng từ',
    'So_Chung_Tu': no,
    'So_Hop_Dong': documentType == PosPrintDocumentTypes.contract ? no : '',
  });
  if (!includeStamp) {
    data['Con_Dau'] = '<div style="height:48px"></div>';
  }
  for (final k in const [
    'So_Luong',
    'Don_Gia',
    'Ma_Hang',
    'Don_Vi_Tinh',
    'Ma_Vach',
    'STT',
  ]) {
    data.remove(k);
  }
  return renderPosPrintTemplateHtml(
    posPrintDefaultHtml(
      documentType: documentType,
      paperSize: PosPrintPaperSizes.a4,
    ),
    data: data,
    lineItems: items,
    wrapDocument: true,
    paperSize: PosPrintPaperSizes.a4,
  );
}

Future<String> bindPosQuotePrintHtml(
    ApiService api, PosQuote q, List<PosQuoteLine> lineItems) async {
  Map<String, dynamic>? profile;
  try {
    final profileRes = await api.getPosCommercialProfile();
    final local = await loadLocalCommercialProfile();
    if (profileRes['isSuccess'] == true && profileRes['data'] is Map) {
      profile = mergeCommercialProfile(
        Map<String, dynamic>.from(profileRes['data'] as Map),
        local,
      );
    } else if (local.isNotEmpty) {
      profile = local;
    }
  } catch (_) {}

  final lines = _withLineVatRates(q, lineItems, await _quoteLineItemsWithImages(api, lineItems));
  String render(String templateHtml) => renderPosPrintTemplateHtml(
        templateHtml,
        data: () {
          final data = posPrintSampleData(
            documentType: PosPrintDocumentTypes.quote,
            commercialProfile: profile,
            fillSamples: false,
          );
          data.addAll(_quoteHeaderData(q, lineItems, profile: profile));
          for (final k in const [
            'So_Luong',
            'Don_Gia',
            'Ma_Hang',
            'Don_Vi_Tinh',
            'Ma_Vach',
            'STT',
          ]) {
            data.remove(k);
          }
          return data;
        }(),
        lineItems: lines,
        wrapDocument: true,
        paperSize: PosPrintPaperSizes.a4,
      );

  try {
    final list = await loadPosPrintTemplates(api, PosPrintDocumentTypes.quote);
    final htmlTemplates = list.where((t) {
      final raw = t.htmlContent.trim();
      return raw.startsWith('<') && !PosPrintTemplateV2Codec.isV2Content(raw);
    }).toList();
    PosPrintTemplate? tpl;
    final id = q.printTemplateId;
    if (id != null && id.isNotEmpty) {
      tpl = htmlTemplates.where((t) => t.id == id).firstOrNull;
    }
    tpl ??= htmlTemplates.where((t) => t.isDefault).firstOrNull ??
        htmlTemplates.firstOrNull;
    final remote = (tpl?.htmlContent ?? '').trim();
    if (remote.isNotEmpty && _templateCanBindQuoteLines(remote)) {
      final html = render(remote);
      if (_printHtmlMatchesQuoteLines(html, lines)) {
        return html;
      }
    }
  } catch (_) {}
  return bindPosQuotePrintHtmlLocal(
    q,
    lineItems,
    commercialProfile: profile,
  );
}

bool _templateCanBindQuoteLines(String html) {
  final raw = posPrintRestoreItemMarkers(html);
  if (raw.contains('XEM TRƯỚC')) return false;
  return raw.contains('{Ten_Hang_Hoa}') ||
      raw.contains('BEGIN_ITEMS') ||
      raw.contains('begin-items');
}

bool _printHtmlMatchesQuoteLines(
    String html, List<Map<String, String>> items) {
  if (html.trim().isEmpty || html.contains('XEM TRƯỚC')) return false;
  if (items.length < 2) {
    final name = items.isEmpty ? '' : (items.first['Ten_Hang_Hoa'] ?? '');
    return name.isEmpty || html.contains(name);
  }
  final second = items[1]['Ten_Hang_Hoa'] ?? '';
  return second.isEmpty || html.contains(second);
}

/// Thành tiền in trên chứng từ — SL × đơn giá − CK dòng, chưa cộng VAT (khớp máy chủ PosQuoteDocumentHtml.LineNet).
double _quoteLineAmount(PosQuoteLine l) =>
    (l.qty * l.unitPrice - l.discountAmount).clamp(0.0, double.infinity).roundToDouble();

Map<String, String> _quoteHeaderData(
  PosQuote q,
  List<PosQuoteLine> lines, {
  Map<String, dynamic>? profile,
}) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final day = DateFormat('dd/MM/yyyy');
  final now = DateTime.now();
  final use = lines.isNotEmpty ? lines : q.lines;
  final rate = q.vatPercent ?? 8;
  final t = PosQuoteVat.compute(use, mode: q.vatMode, rate: rate, discount: q.discount);
  final vat = t.vat;
  final total = t.total;
  final rateText = rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toStringAsFixed(1);
  // Có VAT → mẫu in kiểu riêng (cột thuế suất, trước thuế · tiền thuế · tổng sau thuế) — khớp máy chủ.
  final hasVat = _quoteHasVat(q, vat);
  final netSum = use.fold<double>(0, (a, l) => a + _quoteLineAmount(l));
  final lineRates = {for (final l in use) l.vatRate};
  String prof(String a, String b) =>
      (profile?[a] ?? profile?[b] ?? '').toString().trim();
  final quoteTerms = (q.terms ?? '').trim();
  final storeTerms = prof('defaultTerms', 'DefaultTerms');
  final policy = prof('warrantyPolicy', 'WarrantyPolicy');
  final months = use.any((l) => (l.warrantyMonths ?? 0) > 0)
      ? '${use.where((l) => (l.warrantyMonths ?? 0) > 0).map((l) => l.warrantyMonths).first} tháng'
      : '';
  // Cọc: số tiền hoặc % đã nhập trên báo giá (% tính trên giá trị trước VAT — khớp màn soạn và máy chủ).
  // Không tự gán 50%.
  final pct = q.depositPercent ?? 0;
  final deposit = q.depositAmount > 0
      ? q.depositAmount
      : (pct > 0 ? (t.preVat * pct / 100).roundToDouble() : 0.0);
  final remain = (total - deposit).clamp(0.0, double.infinity).toDouble();
  final pctText = pct > 0
      ? (pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1))
      : '';
  String two(int v) => v.toString().padLeft(2, '0');
  final customer = (q.customerName ?? '').trim();
  final request = deposit > 0 ? deposit : total;
  return {
    'Tieu_De_In': 'BÁO GIÁ',
    'PaperSize': 'A4',
    'Ngay_So': two(now.day),
    'Thang': two(now.month),
    'Nam': '${now.year}',
    'Ngay_HD_So': two(now.day),
    'Thang_HD': two(now.month),
    'Nam_HD': '${now.year}',
    'Ngay_Hop_Dong': day.format(now),
    'Ben_A_Ten': customer,
    'Nguoi_Dai_Dien_Khach': customer,
    'Dia_Diem_Thi_Cong': q.customerAddress ?? '',
    'Tam_Ung': deposit > 0 ? money.format(deposit) : '',
    'Tien_Coc': deposit > 0 ? money.format(deposit) : '',
    'Phan_Tram_Coc': pctText,
    'Coc_Tinh_Tren': pctText.isEmpty ? '' : (hasVat ? 'giá trị trước VAT' : 'giá trị báo giá'),
    'Tien_Coc_Bang_Chu':
        deposit > 0 ? vietnameseMoneyInWords(deposit.round()) : '',
    'Con_Lai_Hop_Dong': money.format(remain),
    'Con_Lai_Bang_Chu': vietnameseMoneyInWords(remain.round()),
    'Da_Thanh_Toan': '',
    'Da_Thanh_Toan_Hien': '0',
    'Con_Phai_Thu': money.format(total),
    'Con_Phai_Thu_Bang_Chu': vietnameseMoneyInWords(total.round()),
    'De_Nghi_Dot': deposit > 0 ? 'Tạm ứng / đặt cọc' : 'Thanh toán',
    'De_Nghi_So_Tien': money.format(request),
    'De_Nghi_Bang_Chu': vietnameseMoneyInWords(request.round()),
    'Ton_Tai': 'Không có.',
    'Ma_Don_Hang': q.quoteNo,
    'Ma_Bao_Gia': q.quoteNo,
    'So_Chung_Tu': q.quoteNo,
    'Ngay': day.format(now),
    'Gio': DateFormat('HH:mm').format(now),
    'Khach_Hang': q.customerName ?? '',
    'Ten_Cong_Ty_Khach': q.customerName ?? '',
    'SDT': q.customerPhone ?? '',
    'Dia_Chi_Khach_Hang': q.customerAddress ?? '',
    'Han_Bao_Gia': q.validUntil == null ? '' : day.format(q.validUntil!.toLocal()),
    'Tong_Tien_Hang': money.format(netSum),
    'Chiet_Khau_Hoa_Don': money.format(q.discount),
    'Tien_Thue': q.vatMode == PosQuoteVat.included
        ? (vat > 0 ? '(đã gồm ${money.format(vat)})' : '')
        : money.format(vat),
    'Thue': money.format(vat),
    'VAT': money.format(vat),
    'Thue_Suat': q.vatMode == PosQuoteVat.included || q.vatMode == PosQuoteVat.added
        ? '$rateText%'
        : (hasVat && lineRates.length == 1 ? '${_rateText(lineRates.first)}%' : ''),
    'Co_VAT': hasVat ? '1' : '',
    'Ghi_Chu_Gia': !hasVat ? '' : (q.vatMode == PosQuoteVat.included ? 'đã gồm VAT' : 'chưa VAT'),
    'Hien_Truoc_Thue': hasVat && (t.preVat - netSum).abs() >= 0.5 ? '1' : '',
    'Cach_Tinh_VAT': q.vatMode == PosQuoteVat.included
        ? 'Giá đã bao gồm VAT $rateText%'
        : q.vatMode == PosQuoteVat.added
            ? 'Giá chưa bao gồm VAT, cộng VAT $rateText%'
            : q.vatMode == PosQuoteVat.none
                ? 'Không tính VAT'
                : (hasVat ? 'VAT theo từng mặt hàng' : ''),
    'Gia_Tri_Truoc_VAT': money.format(t.preVat),
    'Tong_Cong': money.format(total),
    'Khach_Can_Tra': money.format(total),
    'Tong_Cong_Bang_Chu': vietnameseMoneyInWords(total.round()),
    'Hinh_Thuc_Thanh_Toan': q.paymentMethod ?? '',
    'Dieu_Khoan': quoteTerms.isNotEmpty ? quoteTerms : storeTerms,
    'Ghi_Chu': q.note ?? '',
    'Nguoi_Bao_Gia': q.quotedBy ?? q.issuedBy ?? '',
    'Nguoi_Ban': q.quotedBy ?? '',
    'Ten_Hang_Hoa': use.isEmpty
        ? ''
        : (use.length == 1
            ? use.first.productName
            : '${use.first.productName} +${use.length - 1}'),
    'Bao_Hanh': policy.isNotEmpty ? policy : (months.isNotEmpty ? months : 'Theo chính sách bảo hành của Bên B'),
  };
}

bool _quoteHasVat(PosQuote q, double vat) => q.vatMode != PosQuoteVat.none && vat > 0;

String _rateText(double r) => r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);

/// Cột «Thuế suất» từng dòng (mẫu báo giá có VAT): % chung của báo giá hoặc % của mặt hàng.
List<Map<String, String>> _withLineVatRates(
  PosQuote q,
  List<PosQuoteLine> lines,
  List<Map<String, String>> items,
) {
  final use = lines.isNotEmpty ? lines : q.lines;
  final t = PosQuoteVat.compute(use, mode: q.vatMode, rate: q.vatPercent ?? 8, discount: q.discount);
  final hasVat = _quoteHasVat(q, t.vat);
  final common = q.vatMode == PosQuoteVat.included || q.vatMode == PosQuoteVat.added;
  for (var i = 0; i < items.length; i++) {
    final r = common ? (q.vatPercent ?? 8) : (i < use.length ? use[i].vatRate : 0.0);
    items[i]['Thue_Suat_Dong'] = hasVat ? '${_rateText(r)}%' : '';
  }
  return items;
}

/// Cột Hình ảnh / Bảo hành chỉ hiện khi có dòng dùng tới (khối IF trong mẫu).
Map<String, String> _lineFlags(List<Map<String, String>> items) => {
      'Co_Anh':
          items.any((l) => (l['Hinh_Anh'] ?? '').trim().isNotEmpty) ? '1' : '',
      'Co_Bao_Hanh_Dong':
          items.any((l) => (l['Bao_Hanh'] ?? '').trim().isNotEmpty) ? '1' : '',
    };

Future<List<Map<String, String>>> loadPosQuoteLineImages(
  ApiService api,
  List<PosQuoteLine> lines, {
  List<String?>? imageUrls,
}) =>
    _quoteLineItemsWithImages(api, lines, imageUrls: imageUrls);

Future<List<Map<String, String>>> _quoteLineItemsWithImages(
  ApiService api,
  List<PosQuoteLine> lines, {
  List<String?>? imageUrls,
}) async {
  final rows = _quoteLineItems(lines);
  for (var i = 0; i < lines.length && i < rows.length; i++) {
    final id = lines[i].productId;
    final url = imageUrls != null && i < imageUrls.length ? imageUrls[i] : null;
    if ((id == null || id.isEmpty) && (url == null || url.trim().isEmpty)) {
      continue;
    }
    final tag = await _quoteProductImageTag(api, id, imageUrl: url);
    if (tag.isNotEmpty) rows[i]['Hinh_Anh'] = tag;
  }
  return rows;
}

Future<String> _quoteProductImageTag(
  ApiService api,
  String? productId, {
  String? imageUrl,
}) async {
  final paths = <String>[
    if (imageUrl != null && imageUrl.trim().isNotEmpty) imageUrl.trim(),
    if (productId != null && productId.isNotEmpty)
      ApiService.posProductImagePath(productId),
  ];
  final cache = PosProductImageCacheManager.instance;
  for (final path in paths) {
    final url = api.getFileUrl(path);
    if (url.isEmpty) continue;
    final bytes = await cache.loadBytes(
      url: url,
      key: 'quote_print_${productId ?? ''}_$path',
      headers: url.startsWith(ApiService.baseUrl) ? api.imageAuthHeaders : const {},
    );
    if (bytes == null || bytes.length < 32) continue;
    final png = bytes[0] == 0x89 && bytes[1] == 0x50;
    final jpg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (!png && !jpg) continue;
    final b64 = base64Encode(bytes);
    final mime = png ? 'image/png' : 'image/jpeg';
    return '<img src="data:$mime;base64,$b64" alt="" width="113" height="113" '
        'style="width:113px;height:113px;object-fit:contain;display:block;margin:auto"/>';
  }
  return '';
}

List<Map<String, String>> _quoteLineItems(List<PosQuoteLine> lines) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final qty = NumberFormat('0.##', 'vi_VN');
  var i = 1;
  return [
    for (final l in lines)
      {
        'STT': '${i++}',
        'Ma_Hang': l.productCode ?? '',
        'Ten_Hang_Hoa': l.productName,
        'Don_Vi_Tinh': l.unitName ?? '',
        'So_Luong': qty.format(l.qty),
        'Don_Gia': money.format(l.unitPrice),
        'Thanh_Tien': money.format(_quoteLineAmount(l)),
        'Chiet_Khau': money.format(l.discountAmount),
        'Ghi_Chu': l.lineNote ?? '',
        'Chieu_Dai': formatPosDim(l.length),
        'Chieu_Rong': formatPosDim(l.width),
        'Chieu_Cao': formatPosDim(l.height),
        'Bao_Hanh':
            (l.warrantyMonths ?? 0) > 0 ? '${l.warrantyMonths} tháng' : '',
        'Hinh_Anh': '',
      },
  ];
}

Future<void> showPosQuoteCareSheet(
  BuildContext context, {
  required String quoteId,
  required String quoteNo,
  String? customerName,
  String? customerPhone,
  bool openForm = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PosQuoteCareSheet(
      quoteId: quoteId,
      quoteNo: quoteNo,
      customerName: customerName,
      customerPhone: customerPhone,
      openForm: openForm,
    ),
  );
}

class _PosQuoteCareSheet extends StatefulWidget {
  const _PosQuoteCareSheet({
    required this.quoteId,
    required this.quoteNo,
    this.customerName,
    this.customerPhone,
    this.openForm = false,
  });

  final String quoteId;
  final String quoteNo;
  final String? customerName;
  final String? customerPhone;

  /// Mở sẵn ô ghi lần chăm sóc mới (bấm «Ghi lần chăm sóc»); mặc định chỉ xem dòng thời gian.
  final bool openForm;

  @override
  State<_PosQuoteCareSheet> createState() => _PosQuoteCareSheetState();
}

class _PosQuoteCareSheetState extends State<_PosQuoteCareSheet> {
  final _api = ApiService();
  final _note = TextEditingController();
  String _kind = 'Note';
  int? _score;
  DateTime? _followUp;
  bool _loading = true;
  bool _saving = false;
  List<PosQuoteActivity> _items = [];

  /// Ô ghi lần chăm sóc mới đang mở (đóng → dòng thời gian chiếm cả sheet).
  late bool _formOpen = widget.openForm;
  bool _formAutoOpened = false;

  /// Hiện cả ghi chép tự động (tạo báo giá, đổi trạng thái, thu tiền…) xen giữa các lần chăm sóc.
  bool _showSystem = false;

  /// Cả khách hàng: báo giá khác + chăm sóc trên các báo giá đó.
  bool _wholeCustomer = false;
  bool _histLoaded = false;
  List<Map<String, dynamic>> _otherQuotes = [];
  List<({PosQuoteActivity a, String quoteNo})> _histItems = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final res = await _api.getPosQuoteCustomerHistory(widget.quoteId);
    if (!mounted) return;
    final data = res['data'];
    if (res['isSuccess'] != true || data is! Map) {
      setState(() => _histLoaded = true);
      return;
    }
    setState(() {
      _histLoaded = true;
      _otherQuotes = [
        for (final e in (data['quotes'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ];
      _histItems = [
        for (final e in (data['activities'] as List? ?? const []))
          if (e is Map && e['activity'] is Map)
            (
              a: PosQuoteActivity.fromJson(Map<String, dynamic>.from(e['activity'] as Map)),
              quoteNo: (e['quoteNo'] ?? '').toString(),
            ),
      ];
    });
  }

  Widget _scopeToggle() {
    final n = _otherQuotes.length;
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: false, label: Text(tr('Báo giá này'))),
        ButtonSegment(value: true, label: Text(tr(n > 0 ? 'Cả khách hàng ($n BG khác)' : 'Cả khách hàng'))),
      ],
      selected: {_wholeCustomer},
      onSelectionChanged: (v) => setState(() => _wholeCustomer = v.first),
    );
  }

  static const _systemKinds = {'Created', 'Edit', 'Status', 'Payment', 'Contract'};

  Future<void> _editActivity(PosQuoteActivity a) async {
    final text = TextEditingController(text: a.displayContent.trim());
    var kind = const {'Note', 'Call', 'Meeting', 'FollowUp'}.contains(a.kind) ? a.kind : 'Note';
    int? score = a.score;
    DateTime? next = a.nextFollowUpAt?.toLocal();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Sửa lần ghi chăm sóc')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                value: kind,
                decoration: PosTheme.inputDecoration(label: 'Loại'),
                items: const [
                  DropdownMenuItem(value: 'Note', child: Text('Ghi chú')),
                  DropdownMenuItem(value: 'Call', child: Text('Gọi điện')),
                  DropdownMenuItem(value: 'Meeting', child: Text('Gặp khách')),
                  DropdownMenuItem(value: 'FollowUp', child: Text('Hẹn chăm sóc')),
                ],
                onChanged: (v) => setD(() => kind = v ?? kind),
              ),
              const SizedBox(height: 8),
              TextField(controller: text, maxLines: 3, decoration: PosTheme.inputDecoration(label: 'Nội dung')),
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (var i = 0; i <= 10; i++)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('$i'),
                    selected: score == i,
                    onSelected: (_) => setD(() => score = i),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(next == null ? tr('Hẹn lần sau') : DateFormat('dd/MM HH:mm').format(next!)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: next ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d == null || !ctx.mounted) return;
                    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(next ?? DateTime.now()));
                    setD(() => next = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
                  },
                ),
                if (next != null)
                  IconButton(tooltip: tr('Bỏ hẹn'), icon: const Icon(Icons.close, size: 18), onPressed: () => setD(() => next = null)),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (text.text.trim().isEmpty) return;
    if (kind == 'FollowUp' && next == null) {
      NotificationOverlayManager().showWarning(title: 'Chưa chọn ngày hẹn', message: tr('Chọn ngày giờ hẹn chăm sóc lại'));
      return;
    }
    final res = await _api.updatePosQuoteActivity(
      widget.quoteId,
      a.id,
      kind: kind,
      content: score == null ? text.text.trim() : PosQuoteActivity.encodeContent(text.text, score!),
      nextFollowUpAt: next,
      clearFollowUp: next == null,
      potentialScore: score,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Chưa sửa được', message: res['message']?.toString() ?? '');
      return;
    }
    await _load();
  }

  Future<void> _deleteActivity(PosQuoteActivity a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xoá lần ghi này?')),
        content: Text(a.displayContent.trim()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xoá'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosQuoteActivity(widget.quoteId, a.id);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Chưa xoá được', message: res['message']?.toString() ?? '');
      return;
    }
    await _load();
  }

  Widget _activityTile(PosQuoteActivity a, {String? quoteNo, bool isLast = false}) {
    final editable = quoteNo == null && !_systemKinds.contains(a.kind);
    return PosCareTimelineTile(
      activity: a,
      quoteNo: quoteNo,
      isLast: isLast,
      trailing: editable
          ? SizedBox(
              width: 28,
              height: 22,
              child: PopupMenuButton<String>(
                tooltip: tr('Sửa / xoá'),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (v) => v == 'edit' ? _editActivity(a) : _deleteActivity(a),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('Xoá'))),
                ],
              ),
            )
          : null,
    );
  }

  List<Widget> _customerHistory() {
    if (!_histLoaded) {
      return const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))];
    }
    if (_otherQuotes.isEmpty) {
      return [Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('Khách chưa có báo giá nào khác'))))];
    }
    final money = NumberFormat('#,##0', 'vi_VN');
    return [
      if (_histItems.isNotEmpty) ...[
        Text(tr('Lần chăm sóc trước'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        for (var i = 0; i < _histItems.length; i++)
          _activityTile(_histItems[i].a, quoteNo: _histItems[i].quoteNo, isLast: i == _histItems.length - 1),
        const Divider(height: 20),
      ],
      Text(tr('Báo giá khác của khách'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      const SizedBox(height: 4),
      for (final q in _otherQuotes)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.request_quote_outlined, size: 20),
          title: Text('${q['quoteNo'] ?? ''} · ${q['statusText'] ?? ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text([
            '${money.format((q['total'] as num?) ?? 0)} đ',
            if (q['createdAt'] != null)
              DateFormat('dd/MM/yyyy').format(
                  (parseApiUtcDateTime(q['createdAt'].toString()) ?? DateTime.now()).toLocal()),
            if (((q['revision'] as num?) ?? 1) > 1) 'bản sửa ${q['revision']}',
          ].join(' · ')),
        ),
    ];
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosQuoteActivities(widget.quoteId);
    if (!mounted) return;
    final data = res['data'];
    final raw = data is Map ? (data['items'] as List? ?? []) : <dynamic>[];
    setState(() {
      _loading = false;
      _items = raw
          .whereType<Map>()
          .map((e) => PosQuoteActivity.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // Điền sẵn điểm tiềm năng lần chấm gần nhất — chỉ chỉnh khi khách đổi ý.
      _score ??= _items.where((a) => a.score != null).map((a) => a.score).firstOrNull;
      // Chưa chăm sóc lần nào → mở sẵn ô ghi (không có gì để xem).
      if (!_formAutoOpened && !_items.any(isPosCareActivity)) _formOpen = true;
      _formAutoOpened = true;
    });
  }

  Future<void> _add() async {
    final text = _note.text.trim();
    if (_score == null) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa chấm điểm',
        message: tr('Chọn độ tiềm năng khách từ 0 đến 10'),
      );
      return;
    }
    if (text.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu nội dung',
        message: tr('Nhập nội dung làm việc với khách'),
      );
      return;
    }
    if (_kind == 'FollowUp' && _followUp == null) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa chọn ngày hẹn',
        message: tr('Chọn ngày giờ hẹn chăm sóc lại'),
      );
      return;
    }
    setState(() => _saving = true);
    final res = await _api.createPosQuoteActivity(
      widget.quoteId,
      kind: _kind,
      content: PosQuoteActivity.encodeContent(text, _score!),
      nextFollowUpAt: _followUp,
      potentialScore: _score,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: res['message']?.toString() ?? tr('Ghi lịch thất bại'),
      );
      return;
    }
    _note.clear();
    _followUp = null;
    _kind = 'Note';
    _formOpen = false;
    NotificationOverlayManager().showSuccess(
      title: 'Đã ghi',
      message: tr('Đã thêm vào lịch chăm sóc khách'),
    );
    await _load();
  }

  Widget _form() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SboxColors.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _kind,
                isDense: true,
                decoration: PosTheme.inputDecoration(label: 'Loại'),
                items: const [
                  DropdownMenuItem(value: 'Note', child: Text('Ghi chú')),
                  DropdownMenuItem(value: 'Call', child: Text('Gọi điện')),
                  DropdownMenuItem(value: 'Meeting', child: Text('Gặp khách')),
                  DropdownMenuItem(value: 'FollowUp', child: Text('Hẹn chăm sóc')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _kind = v);
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _followUp ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d == null || !context.mounted) return;
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_followUp ?? DateTime.now()),
                );
                setState(() {
                  _followUp = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0);
                });
              },
              icon: const Icon(Icons.event, size: 18),
              label: Text(_followUp == null
                  ? tr(_kind == 'FollowUp' ? 'Chọn hạn' : 'Hẹn lần sau')
                  : DateFormat('dd/MM HH:mm').format(_followUp!)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tr('Độ tiềm năng khách (0–10)'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var n = 0; n <= 10; n++)
              ChoiceChip(
                label: Text('$n'),
                selected: _score == n,
                selectedColor: PosQuoteActivity.scoreColor(n).withValues(alpha: 0.22),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _score == n ? PosQuoteActivity.scoreColor(n) : SboxColors.slate700,
                ),
                onSelected: (_) => setState(() => _score = n),
              ),
          ],
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _potentialSummary(_items),
            style: TextStyle(fontSize: 12, color: SboxColors.slate700),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          maxLines: 3,
          decoration: PosTheme.inputDecoration(
            label: 'Nội dung làm việc với khách',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _add,
          icon: const Icon(Icons.check),
          label: Text(_saving ? tr('Đang lưu…') : tr('Lưu lần chăm sóc')),
        ),
      ]),
    );
  }

  List<Widget> _timeline() {
    if (_loading) {
      return const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))];
    }
    final list = _showSystem ? _items : _items.where(isPosCareActivity).toList();
    if (list.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(tr('Chưa có lần chăm sóc nào'), style: const TextStyle(color: SboxColors.slate500))),
        ),
      ];
    }
    return [
      for (var i = 0; i < list.length; i++) _activityTile(list[i], isLast: i == list.length - 1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final phone = (widget.customerPhone ?? '').trim();
    final systemCount = _items.where((a) => !isPosCareActivity(a)).length;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        // Một danh sách cuộn chung: ô ghi mở ra không bóp dòng thời gian còn vài dòng (C20 ngang thấp).
        child: ListView(
          children: [
            Text(
              '${tr('Chăm sóc khách')} · ${widget.quoteNo}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if ((widget.customerName ?? '').isNotEmpty || phone.isNotEmpty)
              Text(
                [if ((widget.customerName ?? '').isNotEmpty) widget.customerName!, if (phone.isNotEmpty) phone]
                    .join(' · '),
                style: TextStyle(color: SboxColors.slate700),
              ),
            if (!_loading) ...[
              const SizedBox(height: 4),
              Text(posCareSummary(_items), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _formOpen
                  ? OutlinedButton.icon(
                      onPressed: () => setState(() => _formOpen = false),
                      icon: const Icon(Icons.expand_less, size: 18),
                      label: Text(tr('Ẩn ô ghi')),
                    )
                  : FilledButton.icon(
                      onPressed: () => setState(() => _formOpen = true),
                      icon: const Icon(Icons.add_comment_outlined, size: 18),
                      label: Text(tr('Ghi lần chăm sóc')),
                    ),
              if (phone.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    // Gọi xong ghi kết quả cuộc gọi luôn.
                    setState(() {
                      _kind = 'Call';
                      _formOpen = true;
                    });
                    callPosQuoteCustomer(widget.customerPhone);
                  },
                  icon: const Icon(Icons.call, size: 18),
                  label: Text(tr('Gọi khách')),
                ),
            ]),
            if (_formOpen) ...[
              const SizedBox(height: 10),
              _form(),
            ],
            const Divider(height: 24),
            _scopeToggle(),
            if (!_wholeCustomer && systemCount > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(tr('Hiện thao tác hệ thống ($systemCount)')),
                    selected: _showSystem,
                    onSelected: (v) => setState(() => _showSystem = v),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            ...(_wholeCustomer ? _customerHistory() : _timeline()),
          ],
        ),
      ),
    );
  }

  String _potentialSummary(List<PosQuoteActivity> items) {
    final scores = [for (final a in items) if (a.score != null) a.score!];
    if (scores.isEmpty) return tr('Chưa có điểm tiềm năng');
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    final latest = scores.first;
    final avgText =
        avg == avg.roundToDouble() ? avg.toInt().toString() : avg.toStringAsFixed(1);
    return tr('Lần gần nhất $latest/10 · trung bình $avgText/10 (${scores.length} lần)');
  }
}
