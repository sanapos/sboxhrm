import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../services/pos_product_image_cache.dart';
import '../../utils/pos_area_dims.dart';
import '../../utils/pos_commercial_profile_local.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../utils/pos_html_print.dart';
import '../../utils/pos_quote_document_wording.dart';
import '../../utils/pos_print_template_defaults.dart';
import '../../utils/pos_print_template_loader.dart';
import '../../utils/pos_print_template_renderer.dart';
import '../../utils/pos_print_template_v2_codec.dart';
import '../../utils/pos_vietnamese_money_words.dart';
import '../../widgets/notification_overlay.dart';
import 'pos_theme.dart';

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
    try {
      html = bindPosQuotePrintHtmlLocal(
        q,
        useLines,
        commercialProfile: profile,
        storeName: store?.storeName,
        storeAddress: store?.address,
        storePhone: store?.phone,
        includeStamp: includeStamp,
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

String bindPosQuotePrintHtmlLocal(
  PosQuote q,
  List<PosQuoteLine> lineItems, {
  Map<String, dynamic>? commercialProfile,
  String? storeName,
  String? storeAddress,
  String? storePhone,
  bool includeStamp = true,
}) {
  final data = posPrintSampleData(
    documentType: PosPrintDocumentTypes.quote,
    commercialProfile: commercialProfile,
    storeName: storeName,
    storeAddress: storeAddress,
    storePhone: storePhone,
  );
  data.addAll(_quoteHeaderData(q, lineItems, profile: commercialProfile));
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
    lineItems: _quoteLineItems(lineItems),
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
  );
  data.addAll(_quoteHeaderData(q, lines, profile: commercialProfile));
  final money = NumberFormat('#,##0', 'vi_VN');
  final total = (lines.fold<double>(0, (a, l) => a + _quoteLineAmount(l)) -
          q.discount)
      .clamp(0.0, double.infinity);
  final deposit = q.depositAmount > 0
      ? q.depositAmount
      : (q.depositPercent != null && q.depositPercent! > 0
          ? total * q.depositPercent! / 100
          : total * 0.5);
  final day = DateFormat('dd/MM/yyyy').format(DateTime.now());
  final no = (docNo == null || docNo.isEmpty) ? q.quoteNo : docNo;
  data.addAll({
    'Ma_Bao_Gia': q.quoteNo,
    'So_Chung_Tu': no,
    'So_Hop_Dong': documentType == PosPrintDocumentTypes.contract ? no : q.quoteNo,
    'Ngay_Hop_Dong': day,
    'Ngay': day,
    'Dia_Diem_Thi_Cong': q.customerAddress ?? '',
    'Ten_Cong_Ty_Khach': q.customerName ?? '',
    'Nguoi_Dai_Dien_Khach': q.customerName ?? '',
    'Tam_Ung': money.format(deposit),
    'Tien_Coc': money.format(deposit),
    'Con_Lai_Hop_Dong': money.format((total - deposit).clamp(0, double.infinity)),
    'Ky_Han_Thi_Cong': 'Theo thỏa thuận',
    'Ky_Han_Thanh_Toan': '10 ngày kể từ ký hợp đồng',
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
    lineItems: _quoteLineItems(lines),
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

  final lines = await _quoteLineItemsWithImages(api, lineItems);
  String render(String templateHtml) => renderPosPrintTemplateHtml(
        templateHtml,
        data: () {
          final data = posPrintSampleData(
            documentType: PosPrintDocumentTypes.quote,
            commercialProfile: profile,
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

double _quoteLineAmount(PosQuoteLine l) {
  if (l.lineTotal > 0) return l.lineTotal;
  final net =
      (l.qty * l.unitPrice - l.discountAmount).clamp(0.0, double.infinity);
  return net * (1 + l.vatRate / 100);
}

Map<String, String> _quoteHeaderData(
  PosQuote q,
  List<PosQuoteLine> lines, {
  Map<String, dynamic>? profile,
}) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final day = DateFormat('dd/MM/yyyy');
  final now = DateTime.now();
  final use = lines.isNotEmpty ? lines : q.lines;
  final subTotal = use.fold<double>(0, (a, l) => a + l.qty * l.unitPrice);
  final lineSum = use.fold<double>(0, (a, l) => a + _quoteLineAmount(l));
  final vat = use.fold<double>(0, (a, l) {
    final net =
        (l.qty * l.unitPrice - l.discountAmount).clamp(0.0, double.infinity);
    return a + (_quoteLineAmount(l) - net);
  });
  final total = (lineSum - q.discount).clamp(0.0, double.infinity);
  String prof(String a, String b) =>
      (profile?[a] ?? profile?[b] ?? '').toString().trim();
  final quoteTerms = (q.terms ?? '').trim();
  final storeTerms = prof('defaultTerms', 'DefaultTerms');
  final policy = prof('warrantyPolicy', 'WarrantyPolicy');
  final months = use.any((l) => (l.warrantyMonths ?? 0) > 0)
      ? '${use.where((l) => (l.warrantyMonths ?? 0) > 0).map((l) => l.warrantyMonths).first} tháng'
      : '';
  return {
    'Tieu_De_In': 'BÁO GIÁ',
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
    'Tong_Tien_Hang': money.format(subTotal),
    'Chiet_Khau_Hoa_Don': money.format(q.discount),
    'Tien_Thue': money.format(vat),
    'Thue': money.format(vat),
    'VAT': money.format(vat),
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
    'Bao_Hanh': policy.isNotEmpty ? policy : (months.isNotEmpty ? months : '12 tháng'),
  };
}

Future<List<Map<String, String>>> _quoteLineItemsWithImages(
  ApiService api,
  List<PosQuoteLine> lines,
) async {
  final rows = _quoteLineItems(lines);
  for (var i = 0; i < lines.length && i < rows.length; i++) {
    final id = lines[i].productId;
    if (id == null || id.isEmpty) continue;
    final tag = await _quoteProductImageTag(api, id);
    if (tag.isNotEmpty) rows[i]['Hinh_Anh'] = tag;
  }
  return rows;
}

Future<String> _quoteProductImageTag(ApiService api, String productId) async {
  final path = ApiService.posProductImagePath(productId);
  final url = api.getFileUrl(path);
  if (url.isEmpty) return '';
  final bytes = await PosProductImageCacheManager.instance.loadBytes(
    url: url,
    key: 'quote_print_$productId',
    headers: api.imageAuthHeaders,
  );
  if (bytes == null || bytes.length < 32) return '';
  final mime = bytes.length > 3 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E
      ? 'image/png'
      : 'image/jpeg';
  final b64 = base64Encode(bytes);
  return '<img src="data:$mime;base64,$b64" alt="" '
      'style="width:3cm;height:3cm;object-fit:contain;display:block;margin:auto"/>';
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
    ),
  );
}

class _PosQuoteCareSheet extends StatefulWidget {
  const _PosQuoteCareSheet({
    required this.quoteId,
    required this.quoteNo,
    this.customerName,
    this.customerPhone,
  });

  final String quoteId;
  final String quoteNo;
  final String? customerName;
  final String? customerPhone;

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

  @override
  void initState() {
    super.initState();
    _load();
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
    setState(() => _saving = true);
    final res = await _api.createPosQuoteActivity(
      widget.quoteId,
      kind: _kind,
      content: PosQuoteActivity.encodeContent(text, _score!),
      nextFollowUpAt: _kind == 'FollowUp' ? _followUp : null,
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
    _score = null;
    NotificationOverlayManager().showSuccess(
      title: 'Đã ghi',
      message: tr('Đã thêm vào lịch chăm sóc khách'),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${tr('Lịch CSKH')} · ${widget.quoteNo}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if ((widget.customerName ?? '').isNotEmpty)
              Text(
                widget.customerName!,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => callPosQuoteCustomer(widget.customerPhone),
                  icon: const Icon(Icons.call, size: 18),
                  label: Text(tr('Gọi khách')),
                ),
                if ((widget.customerPhone ?? '').isNotEmpty)
                  Text(widget.customerPhone!,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
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
                      DropdownMenuItem(
                          value: 'FollowUp', child: Text('Hẹn chăm sóc')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _kind = v);
                    },
                  ),
                ),
                if (_kind == 'FollowUp') ...[
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
                        initialTime: TimeOfDay.fromDateTime(
                            _followUp ?? DateTime.now()),
                      );
                      setState(() {
                        _followUp = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          t?.hour ?? 9,
                          t?.minute ?? 0,
                        );
                      });
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_followUp == null
                        ? tr('Chọn hạn')
                        : DateFormat('dd/MM HH:mm').format(_followUp!)),
                  ),
                ],
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
                      fontWeight: FontWeight.w800,
                      color: _score == n
                          ? PosQuoteActivity.scoreColor(n)
                          : const Color(0xFF334155),
                    ),
                    onSelected: (_) => setState(() => _score = n),
                  ),
              ],
            ),
            if (_items.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _potentialSummary(_items),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
              icon: const Icon(Icons.add_comment_outlined),
              label: Text(_saving ? tr('Đang lưu…') : tr('Ghi lịch')),
            ),
            const Divider(height: 20),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(child: Text(tr('Chưa có lịch làm việc với khách')))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final a = _items[i];
                            final when = a.createdAt == null
                                ? ''
                                : DateFormat('dd/MM HH:mm')
                                    .format(a.createdAt!.toLocal());
                            final who = (a.employeeName ?? a.createdBy ?? '')
                                .trim();
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(_iconOf(a.kind), size: 20),
                              title: Text(
                                '${PosQuoteActivity.kindLabel(a.kind)} · $when',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              subtitle: Text([
                                if (a.score != null) 'Tiềm năng ${a.score}/10',
                                a.displayContent,
                                if (who.isNotEmpty) who,
                                if (a.nextFollowUpAt != null)
                                  'Hẹn ${DateFormat('dd/MM HH:mm').format(a.nextFollowUpAt!.toLocal())}',
                              ].join('\n')),
                            );
                          },
                        ),
            ),
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

  IconData _iconOf(String kind) => switch (kind) {
        'Call' => Icons.call,
        'Meeting' => Icons.groups_outlined,
        'FollowUp' => Icons.event_available_outlined,
        'Created' => Icons.request_quote_outlined,
        'Edit' => Icons.edit_outlined,
        'Status' => Icons.flag_outlined,
        _ => Icons.sticky_note_2_outlined,
      };
}
