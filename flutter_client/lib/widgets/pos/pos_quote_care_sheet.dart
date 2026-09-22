import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../utils/pos_html_print.dart';
import '../../utils/pos_print_template_defaults.dart';
import '../../utils/pos_print_template_loader.dart';
import '../../utils/pos_print_template_renderer.dart';
import '../../utils/pos_print_template_v2_codec.dart';
import '../../utils/pos_vietnamese_money_words.dart';
import '../../widgets/notification_overlay.dart';
import 'pos_theme.dart';

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
  if (q != null && useLines.isNotEmpty) {
    try {
      html = bindPosQuotePrintHtmlLocal(q, useLines);
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
}) {
  final data = posPrintSampleData(
    documentType: PosPrintDocumentTypes.quote,
    commercialProfile: commercialProfile,
  );
  data.addAll(_quoteHeaderData(q, lineItems));
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

Future<String> bindPosQuotePrintHtml(
    ApiService api, PosQuote q, List<PosQuoteLine> lineItems) async {
  Map<String, dynamic>? profile;
  try {
    final profileRes = await api.getPosCommercialProfile();
    if (profileRes['isSuccess'] == true && profileRes['data'] is Map) {
      profile = Map<String, dynamic>.from(profileRes['data'] as Map);
    }
  } catch (_) {}

  String render(String templateHtml) => renderPosPrintTemplateHtml(
        templateHtml,
        data: () {
          final data = posPrintSampleData(
            documentType: PosPrintDocumentTypes.quote,
            commercialProfile: profile,
          );
          data.addAll(_quoteHeaderData(q, lineItems));
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
        lineItems: _quoteLineItems(lineItems),
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
      if (_printHtmlMatchesQuoteLines(html, _quoteLineItems(lineItems))) {
        return html;
      }
    }
  } catch (_) {}
  return bindPosQuotePrintHtmlLocal(q, lineItems, commercialProfile: profile);
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

Map<String, String> _quoteHeaderData(PosQuote q, List<PosQuoteLine> lines) {
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
    'Dieu_Khoan': q.terms ?? '',
    'Ghi_Chu': q.note ?? '',
    'Nguoi_Bao_Gia': q.quotedBy ?? q.issuedBy ?? '',
    'Nguoi_Ban': q.quotedBy ?? '',
    'Ten_Hang_Hoa': use.isEmpty
        ? ''
        : (use.length == 1
            ? use.first.productName
            : '${use.first.productName} +${use.length - 1}'),
    'Bao_Hanh': use.any((l) => (l.warrantyMonths ?? 0) > 0)
        ? '${use.where((l) => (l.warrantyMonths ?? 0) > 0).map((l) => l.warrantyMonths).first} tháng'
        : '12 tháng',
  };
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
      content: text,
      nextFollowUpAt: _kind == 'FollowUp' ? _followUp : null,
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
                                a.content,
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
