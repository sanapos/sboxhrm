import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_customer.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_product.dart';
import '../../models/pos_quote.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_html_print.dart';
import '../../utils/pos_quote_document_wording.dart';
import 'pos_quote_document_wording_screen.dart';
import '../../utils/pos_quote_commercial.dart';
import '../../utils/pos_print_template_loader.dart';
import '../../utils/pos_print_template_v2_codec.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_customer_form_dialog.dart';
import '../../widgets/pos/pos_quote_care_sheet.dart';
import '../../widgets/pos/pos_theme.dart';

class PosQuoteEditorScreen extends StatefulWidget {
  const PosQuoteEditorScreen({super.key, this.quoteId});

  final String? quoteId;

  @override
  State<PosQuoteEditorScreen> createState() => _PosQuoteEditorScreenState();
}

class _PosQuoteEditorScreenState extends State<PosQuoteEditorScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _custSearch = TextEditingController();
  List<PosCustomer> _custHits = [];
  PosCustomer? _customer;
  final _note = TextEditingController();
  final _terms = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _deposit = TextEditingController(text: '50');
  final _money = NumberFormat('#,##0', 'vi_VN');
  DateTime _validUntil = DateTime.now().add(const Duration(days: 15));
  String? _customerId;
  String _status = 'Draft';
  String _quoteNo = '';
  String _commercialStage = 'None';
  String _depositPayment = 'Chuyển khoản';
  bool _depositIsPercent = true;
  Map<String, dynamic>? _commercialProfile;
  String? _printTemplateId;
  List<PosPrintTemplate> _templates = [];
  List<PosQuoteLine> _lines = [];
  List<PosQuoteDocument> _documents = [];
  bool _loading = false;
  bool _saving = false;
  bool _includeImages = false;
  bool _locked = false;

  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _loadCommercialProfile();
    if (widget.quoteId != null) _load();
  }

  Future<void> _loadCommercialProfile() async {
    final res = await _api.getPosCommercialProfile();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() {
        _commercialProfile =
            Map<String, dynamic>.from(res['data'] as Map);
      });
    }
  }

  String _profileText(String a, String b) {
    final m = _commercialProfile;
    if (m == null) return '';
    return (m[a] ?? m[b] ?? '').toString().trim();
  }

  double get _lineNetSum =>
      _lines.fold(0.0, (a, l) => a + l.lineTotal);

  double get _orderDiscount =>
      double.tryParse(_discount.text.replaceAll('.', '').replaceAll(',', '')) ??
      0;

  double get _preVatTotal =>
      (_lineNetSum - _orderDiscount).clamp(0, double.infinity);

  double get _depositInput =>
      double.tryParse(_deposit.text.replaceAll('.', '').replaceAll(',', '')) ??
      0;

  double get _depositAmount {
    if (_depositIsPercent) {
      return (_preVatTotal * _depositInput / 100).clamp(0, double.infinity);
    }
    return _depositInput.clamp(0, double.infinity);
  }

  Future<void> _loadTemplates() async {
    final list = await loadPosPrintTemplates(_api, PosPrintDocumentTypes.quote);
    if (!mounted) return;
    setState(() {
      // Bỏ mẫu JSON V2 (thermal) đã lưu nhầm cho báo giá — JSON V2 cũng
      // bắt đầu bằng `<!--…-->` nên không lọc được bằng `startsWith('<')`.
      _templates = list.where((t) {
        final raw = t.htmlContent.trim();
        return raw.startsWith('<') && !PosPrintTemplateV2Codec.isV2Content(raw);
      }).toList();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _custSearch.dispose();
    _note.dispose();
    _terms.dispose();
    _discount.dispose();
    _deposit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosQuote(widget.quoteId!);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['isSuccess'] != true || res['data'] is! Map) return;
    final q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
    _quoteNo = q.quoteNo;
    _status = q.status;
    _commercialStage = q.commercialStage;
    _locked = q.isLocked;
    _customerId = q.customerId;
    _name.text = q.customerName ?? '';
    _phone.text = q.customerPhone ?? '';
    _address.text = q.customerAddress ?? '';
    _note.text = q.note ?? '';
    _terms.text = q.terms ?? '';
    final pay = (q.paymentMethod ?? '').trim();
    _depositPayment =
        ['Chuyển khoản', 'Tiền mặt'].contains(pay) ? pay : 'Chuyển khoản';
    if (q.depositPercent != null && q.depositPercent! > 0) {
      _depositIsPercent = true;
      _deposit.text = q.depositPercent!.round().toString();
    } else if (q.depositAmount > 0) {
      _depositIsPercent = false;
      _deposit.text = _money.format(q.depositAmount);
    }
    _printTemplateId = q.printTemplateId;
    _discount.text = _money.format(q.discount);
    if (q.validUntil != null) _validUntil = q.validUntil!.toLocal();
    _lines = q.lines
        .map((l) => PosQuoteLine.fromJson({
              'id': l.id,
              'productId': l.productId,
              'productCode': l.productCode,
              'productName': l.productName,
              'unitName': l.unitName,
              'qty': l.qty,
              'unitPrice': l.unitPrice,
              'discountAmount': l.discountAmount,
              'vatRate': l.vatRate,
              'lineTotal': l.lineTotal,
              'lineNote': l.lineNote,
              'warrantyMonths': l.warrantyMonths,
            }))
        .toList();
    _documents = q.documents;
    setState(() {});
  }

  Map<String, dynamic> _body() => {
        'customerId': _customerId,
        'customerName': _name.text.trim(),
        'customerPhone': _phone.text.trim(),
        'customerAddress': _address.text.trim(),
        'validUntil': _validUntil.toUtc().toIso8601String(),
        'discount':
            double.tryParse(_discount.text.replaceAll('.', '').replaceAll(',', '')) ??
                0,
        'note': _note.text.trim(),
        'terms': _terms.text.trim(),
        'paymentMethod': _depositPayment,
        'depositAmount': _depositAmount,
        if (_depositIsPercent) 'depositPercent': _depositInput,
        'printTemplateId': _printTemplateId,
        'lines': _lines.map((l) => l.toInputJson()).toList(),
      };

  Future<bool> _save({bool popAfter = true}) async {
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu hàng',
        message: tr('Thêm ít nhất một dòng hàng / dịch vụ'),
      );
      return false;
    }
    setState(() => _saving = true);
    try {
      final res = widget.quoteId == null
          ? await _api.createPosQuote(_body())
          : await _api.updatePosQuote(widget.quoteId!, _body());
      if (!mounted) return false;
      setState(() => _saving = false);
      if (res['isSuccess'] != true) {
        NotificationOverlayManager().showError(
          title: 'Không lưu được',
          message: res['message']?.toString() ?? tr('Lưu thất bại'),
        );
        return false;
      }
      PosQuote? q;
      if (res['data'] is Map) {
        q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
      }
      NotificationOverlayManager().showSuccess(
        title: widget.quoteId == null ? 'Đã tạo báo giá' : 'Đã lưu',
        message: q?.quoteNo ?? _quoteNo,
      );
      if (widget.quoteId == null && q != null) {
        await printPosQuoteSlip(
          context,
          quoteId: q.id,
          quote: q,
          includeImages: _includeImages,
        );
      }
      if (popAfter && mounted) {
        Navigator.of(context).pop(true);
      } else if (widget.quoteId != null) {
        await _load();
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: e.toString(),
      );
      return false;
    }
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() fn,
      {bool pop = false}) async {
    if (widget.quoteId != null) {
      final ok = _locked ? true : await _save(popAfter: false);
      if (!ok) return;
    }
    final res = await fn();
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Thao tác thất bại',
        message: res['message']?.toString() ?? tr('Thao tác thất bại'),
      );
      return;
    }
    if (pop) {
      Navigator.of(context).pop(true);
      return;
    }
    await _load();
  }

  Future<String?> _askNote(String title) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          maxLines: 3,
          decoration: PosTheme.inputDecoration(label: 'Ghi chú chứng từ (tuỳ chọn)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('OK'))),
        ],
      ),
    );
    final note = c.text.trim();
    c.dispose();
    if (ok != true) return null;
    return note;
  }

  Future<void> _reloadDocuments() async {
    if (widget.quoteId == null) return;
    final res = await _api.getPosQuote(widget.quoteId!);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) return;
    final q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
    setState(() => _documents = q.documents);
  }

  Future<void> _openWording(PosQuoteDocument doc) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PosQuoteDocumentWordingScreen(
          quoteId: widget.quoteId!,
          document: doc,
        ),
      ),
    );
    if (changed == true) await _reloadDocuments();
  }

  Future<void> _editQuoteWording() async {
    if (widget.quoteId == null) return;
    PosQuoteDocument? doc;
    for (final d in _documents) {
      if (d.kind == 'Quote') {
        doc = d;
        break;
      }
    }
    if (doc == null) {
      setState(() => _saving = true);
      final res = await _api.createPosQuoteDocument(
        widget.quoteId!,
        'Quote',
        includeImages: _includeImages,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (res['isSuccess'] != true || res['data'] is! Map) {
        NotificationOverlayManager().showError(
          title: 'Chưa mở được',
          message: res['message']?.toString() ?? tr('Chưa có phiếu báo giá để sửa'),
        );
        return;
      }
      doc = PosQuoteDocument.fromJson(
        Map<String, dynamic>.from(res['data'] as Map),
      );
      await _reloadDocuments();
    }
    if (!mounted) return;
    await _openWording(doc);
  }

  void _printDocument(PosQuoteDocument d) {
    if (d.kind == 'Quote' && !posQuoteDocWordingIsCustom(d.htmlContent)) {
      printPosQuoteSlip(
        context,
        quoteId: widget.quoteId!,
        includeImages: _includeImages,
      );
      return;
    }
    if (d.htmlContent.trim().isEmpty) return;
    showPosHtmlPrintDialog(
      context,
      title: d.title,
      htmlDocument: d.htmlContent,
    );
  }

  Future<void> _previewKind(String kind) async {
    if (widget.quoteId == null) return;
    final res = await _api.previewPosQuoteDocument(
      widget.quoteId!,
      kind,
      includeImages: _includeImages,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(
        title: 'Không xem trước được',
        message: res['message']?.toString() ?? tr('Không xem trước được'),
      );
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final html = (data['htmlContent'] ?? data['HtmlContent'] ?? '').toString();
    final title = (data['title'] ?? data['Title'] ?? kind).toString();
    await showPosHtmlPrintDialog(context, title: title, htmlDocument: html);
  }

  Future<void> _createKind(String kind) async {
    if (widget.quoteId == null) return;
    final note = await _askNote(PosQuoteDocument.kindLabel(kind));
    if (note == null || !mounted) return;
    setState(() => _saving = true);
    final res = kind == 'StockIssue'
        ? await _api.createPosQuoteStockIssue(
            widget.quoteId!,
            note: note,
            includeImages: _includeImages,
          )
        : await _api.createPosQuoteDocument(
            widget.quoteId!,
            kind,
            note: note,
            includeImages: _includeImages,
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Lập chứng từ thất bại',
        message: res['message']?.toString() ?? tr('Lập chứng từ thất bại'),
      );
      return;
    }
    await _load();
    if (!mounted) return;
    if (res['data'] is Map) {
      final doc = PosQuoteDocument.fromJson(
          Map<String, dynamic>.from(res['data'] as Map));
      if (doc.htmlContent.isNotEmpty) {
        await showPosHtmlPrintDialog(
          context,
          title: doc.title,
          htmlDocument: doc.htmlContent,
        );
      }
    }
  }

  Future<void> _createPackage() async {
    if (widget.quoteId == null || _saving) return;
    final res = await _api.getPosQuote(widget.quoteId!);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(
        title: 'Không tải được',
        message: res['message']?.toString() ?? tr('Không tìm thấy báo giá'),
      );
      return;
    }
    final q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
    final ok = await createPosQuoteCommercialPackage(
      context,
      quote: q,
      includeImages: _includeImages,
    );
    if (ok && mounted) await _load();
  }

  Future<void> _addProduct() async {
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(tr('Tìm hàng / dịch vụ')),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: PosTheme.inputDecoration(label: 'Tên hoặc mã'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Hủy'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text),
                child: Text(tr('Tìm'))),
          ],
        );
      },
    );
    if (q == null || q.trim().isEmpty || !mounted) return;
    final res = await _api.getPosProducts(search: q.trim(), pageSize: 20);
    if (!mounted) return;
    final data = res['data'];
    final raw = data is Map ? (data['items'] as List? ?? []) : <dynamic>[];
    final products = raw
        .whereType<Map>()
        .map((e) => PosProduct.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (products.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không tìm thấy',
        message: tr('Không tìm thấy hàng hóa / dịch vụ'),
      );
      return;
    }
    final picked = await showDialog<PosProduct>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Chọn mặt hàng')),
        children: [
          for (final p in products)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Text('${p.productCode} · ${p.name}'),
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _lines.add(PosQuoteLine(
        productId: picked.id,
        productCode: picked.productCode,
        productName: picked.name,
        unitName: picked.baseUnitName,
        qty: 1,
        unitPrice: picked.basePrice,
        vatRate: picked.vatExempt ? 0 : picked.vatRate,
        warrantyMonths: picked.warrantyMonths,
      ));
    });
  }

  Future<void> _editLine(int i) async {
    final line = _lines[i];
    final qty = TextEditingController(text: line.qty.toString());
    final price = TextEditingController(text: _money.format(line.unitPrice));
    final bh = TextEditingController(
        text: line.warrantyMonths == null ? '' : '${line.warrantyMonths}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line.productName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qty,
              keyboardType: TextInputType.number,
              decoration: PosTheme.inputDecoration(label: 'Số lượng'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: PosTheme.inputDecoration(label: 'Đơn giá (có thể sửa)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bh,
              keyboardType: TextInputType.number,
              decoration: PosTheme.inputDecoration(label: 'Bảo hành (tháng)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('OK'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      line.qty = double.tryParse(qty.text.replaceAll(',', '.')) ?? line.qty;
      line.unitPrice =
          double.tryParse(price.text.replaceAll('.', '').replaceAll(',', '')) ??
              line.unitPrice;
      line.warrantyMonths = int.tryParse(bh.text.trim());
    });
  }

  Widget _pipeline() {
    final stages = const [
      'Accepted',
      'Contracted',
      'Issued',
      'HandedOver',
      'Inspected',
      'Closed',
    ];
    final current = stages.indexOf(_commercialStage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Hồ sơ thương mại'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          tr('Hợp đồng / xuất kho / bàn giao / nghiệm thu — không phải hóa đơn bán.'),
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < stages.length; i++)
              Chip(
                label: Text(PosQuote.stageLabel(stages[i]),
                    style: const TextStyle(fontSize: 12)),
                backgroundColor: i <= current && current >= 0
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF3F4F6),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.quoteId != null)
          CheckboxListTile(
            value: _includeImages,
            onChanged: (v) => setState(() => _includeImages = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              tr('Đưa hình ảnh SP vào chứng từ in (3×3 cm)'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        if (widget.quoteId != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _previewKind('Quote'),
                child: Text(tr('Xem báo giá')),
              ),
              if (_commercialStage != 'Closed') ...[
                FilledButton.tonal(
                  onPressed: _saving ? null : () => _createKind('Contract'),
                  child: Text(tr('Lập hợp đồng')),
                ),
                FilledButton.tonal(
                  onPressed: _saving ? null : _createPackage,
                  child: Text(tr('Trọn bộ hồ sơ')),
                ),
                FilledButton.tonal(
                  onPressed: _saving ? null : () => _createKind('StockIssue'),
                  child: Text(tr('Xuất kho')),
                ),
                FilledButton.tonal(
                  onPressed: _saving ? null : () => _createKind('Handover'),
                  child: Text(tr('Bàn giao')),
                ),
                FilledButton.tonal(
                  onPressed: _saving ? null : () => _createKind('Acceptance'),
                  child: Text(tr('Nghiệm thu')),
                ),
                FilledButton.tonal(
                  onPressed:
                      _saving ? null : () => _createKind('PaymentRequest'),
                  child: Text(tr('Đề nghị thanh toán')),
                ),
              ],
            ],
          ),
        ],
        if (_documents.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final d in _documents)
            Card(
              child: ListTile(
                title: Text('${d.docNo} · ${d.title}'),
                subtitle: Text([
                  PosQuoteDocument.kindLabel(d.kind),
                  if (posQuoteDocWordingIsCustom(d.htmlContent)) 'Đã sửa lời riêng',
                  if (d.issuedAt != null)
                    DateFormat('dd/MM/yyyy HH:mm').format(d.issuedAt!.toLocal()),
                  if (d.stockIssueNo != null && d.stockIssueNo!.isNotEmpty)
                    'PXK ${d.stockIssueNo}',
                ].join('  ·  ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: tr('Sửa lời riêng chứng từ này'),
                      onPressed: () => _openWording(d),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    const Icon(Icons.print_outlined),
                    const SizedBox(width: 8),
                  ],
                ),
                onTap: () => _printDocument(d),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    final canEdit = !_locked &&
        (widget.quoteId == null
            ? (perm.canCreate('PosQuotes') || perm.canEdit('PosQuotes'))
            : perm.canEdit('PosQuotes'));
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(
          _quoteNo.isEmpty ? tr('Tạo báo giá') : _quoteNo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.quoteId != null) ...[
            IconButton(
              tooltip: tr('Sửa lời riêng báo giá này'),
              onPressed: _saving ? null : _editQuoteWording,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: tr('In phiếu báo giá'),
              onPressed: () => printPosQuoteSlip(
                context,
                quoteId: widget.quoteId!,
                includeImages: _includeImages,
              ),
              icon: const Icon(Icons.print_outlined),
            ),
            IconButton(
              tooltip: tr('Gọi khách'),
              onPressed: () => callPosQuoteCustomer(_phone.text),
              icon: const Icon(Icons.call_outlined),
            ),
            IconButton(
              tooltip: tr('Lịch CSKH'),
              onPressed: () => showPosQuoteCareSheet(
                context,
                quoteId: widget.quoteId!,
                quoteNo: _quoteNo,
                customerName: _name.text,
                customerPhone: _phone.text,
              ),
              icon: const Icon(Icons.history_edu_outlined),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text([
                  PosQuote.statusLabel(_status),
                  if (_status == 'Accepted')
                    PosQuote.stageLabel(_commercialStage),
                ].join(' · ')),
              ),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                    tr('Độc lập màn bán hàng — không trừ kho, không ghi doanh thu.'),
                    style: TextStyle(
                        color: Colors.grey.shade700, fontSize: 12.5)),
                const SizedBox(height: 12),
                if (canEdit)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _custSearch,
                          decoration: PosTheme.inputDecoration(
                            label: 'Tìm khách (tên / SĐT / MST)',
                          ),
                          onChanged: (q) async {
                            if (q.trim().length < 2) {
                              setState(() => _custHits = []);
                              return;
                            }
                            final res = await _api.getPosCustomers(
                                search: q.trim(), pageSize: 8);
                            if (!mounted) return;
                            final data = res['data'];
                            final raw = data is Map
                                ? (data['items'] as List? ?? [])
                                : <dynamic>[];
                            setState(() {
                              _custHits = raw
                                  .whereType<Map>()
                                  .map((e) => PosCustomer.fromJson(
                                      Map<String, dynamic>.from(e)))
                                  .toList();
                            });
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Thêm khách hàng'),
                        icon: const Icon(Icons.person_add_outlined,
                            color: PosTheme.kiotBlue),
                        onPressed: () async {
                          final created = await showDialog<dynamic>(
                            context: context,
                            builder: (_) => const PosCustomerFormDialog(),
                          );
                          if (created is Map && mounted) {
                            final c = PosCustomer.fromJson(
                                Map<String, dynamic>.from(created));
                            setState(() {
                              _customer = c;
                              _customerId = c.id;
                              _name.text =
                                  (c.companyName ?? '').trim().isNotEmpty
                                      ? c.companyName!
                                      : c.name;
                              _phone.text = c.phone ?? '';
                              _address.text = c.address ?? '';
                              _custHits = [];
                              _custSearch.text = _name.text;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                if (_custHits.isNotEmpty)
                  ..._custHits.take(6).map(
                        (c) => ListTile(
                          dense: true,
                          title: Text((c.companyName ?? '').trim().isNotEmpty
                              ? c.companyName!
                              : c.name),
                          subtitle: Text([
                            if ((c.taxCode ?? '').isNotEmpty) 'MST ${c.taxCode}',
                            c.phone,
                          ].where((e) => (e ?? '').isNotEmpty).join(' · ')),
                          onTap: () => setState(() {
                            _customer = c;
                            _customerId = c.id;
                            _name.text = (c.companyName ?? '').trim().isNotEmpty
                                ? c.companyName!
                                : c.name;
                            _phone.text = c.phone ?? '';
                            _address.text = c.address ?? '';
                            _custHits = [];
                            _custSearch.text = _name.text;
                          }),
                        ),
                      ),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  enabled: canEdit,
                  decoration: PosTheme.inputDecoration(label: 'Khách hàng / công ty'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phone,
                  enabled: canEdit,
                  decoration: PosTheme.inputDecoration(label: 'Số điện thoại'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _address,
                  enabled: canEdit,
                  decoration: PosTheme.inputDecoration(label: 'Địa chỉ'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Hạn báo giá')),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_validUntil)),
                  trailing: canEdit ? const Icon(Icons.event) : null,
                  onTap: !canEdit
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _validUntil,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 730)),
                          );
                          if (d != null) setState(() => _validUntil = d);
                        },
                ),
                const SizedBox(height: 8),
                if (canEdit)
                  OutlinedButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add),
                    label: Text(tr('Thêm hàng hóa / dịch vụ')),
                  ),
                const SizedBox(height: 8),
                for (var i = 0; i < _lines.length; i++)
                  Card(
                    child: ListTile(
                      title: Text(_lines[i].productName),
                      subtitle: Text([
                        '${_lines[i].qty} ${_lines[i].unitName ?? ''} × ${_money.format(_lines[i].unitPrice)} đ',
                        if ((_lines[i].warrantyMonths ?? 0) > 0)
                          'BH ${_lines[i].warrantyMonths} tháng',
                      ].join(' · ')),
                      trailing: canEdit
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _lines.removeAt(i)),
                            )
                          : null,
                      onTap: canEdit ? () => _editLine(i) : null,
                    ),
                  ),
                const SizedBox(height: 8),
                ClipRect(
                  child: DropdownButtonFormField<String?>(
                  value: _templates.any((t) => t.id == _printTemplateId)
                      ? _printTemplateId
                      : null,
                  isExpanded: true,
                  decoration:
                      PosTheme.inputDecoration(label: 'Mẫu báo giá A4'),
                  selectedItemBuilder: (ctx) => [
                    SizedBox(
                      width: double.infinity,
                      child: Text(tr('Mẫu mặc định cửa hàng'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false),
                    ),
                    for (final t in _templates)
                      SizedBox(
                        width: double.infinity,
                        child: Text(t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false),
                      ),
                  ],
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(tr('Mẫu mặc định cửa hàng'),
                          overflow: TextOverflow.ellipsis),
                    ),
                    for (final t in _templates)
                      DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(t.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: !canEdit
                      ? null
                      : (v) => setState(() => _printTemplateId = v),
                ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Tiền cọc thực hiện hợp đồng'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  tr('Trước VAT: ${_money.format(_preVatTotal)} đ'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('%'),
                      selected: _depositIsPercent,
                      onSelected: canEdit
                          ? (_) => setState(() => _depositIsPercent = true)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('đ'),
                      selected: !_depositIsPercent,
                      onSelected: canEdit
                          ? (_) => setState(() => _depositIsPercent = false)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _deposit,
                        enabled: canEdit,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          isDense: true,
                          suffixText: _depositIsPercent ? '%' : 'đ',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                if (_depositIsPercent && _depositInput > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr('Cọc: ${_money.format(_depositAmount)} đ'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: PosTheme.kiotBlue),
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final e in ['Chuyển khoản', 'Tiền mặt'])
                      ChoiceChip(
                        label: Text(tr(e)),
                        selected: _depositPayment == e,
                        onSelected: !canEdit
                            ? null
                            : (_) => setState(() => _depositPayment = e),
                      ),
                  ],
                ),
                if (_depositPayment == 'Chuyển khoản') ...[
                  const SizedBox(height: 6),
                  Builder(builder: (context) {
                    final acc =
                        _profileText('bankAccountNumber', 'BankAccountNumber');
                    final bank = _profileText('bankName', 'BankName');
                    final holder =
                        _profileText('bankAccountHolder', 'BankAccountHolder');
                    if (acc.isEmpty && bank.isEmpty) {
                      return Text(
                        tr('Chưa cấu hình TK nhận — Hồ sơ thương mại'),
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade800),
                      );
                    }
                    return Text(
                      [bank, acc, holder].where((e) => e.isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 12),
                    );
                  }),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _discount,
                  enabled: canEdit,
                  keyboardType: TextInputType.number,
                  decoration:
                      PosTheme.inputDecoration(label: 'Chiết khấu đơn (đ)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _note,
                  enabled: canEdit,
                  maxLines: 2,
                  decoration: PosTheme.inputDecoration(label: 'Ghi chú'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _terms,
                  enabled: canEdit,
                  maxLines: 3,
                  decoration: PosTheme.inputDecoration(
                      label: 'Điều khoản / hiệu lực mẫu'),
                ),
                const SizedBox(height: 20),
                if (widget.quoteId != null) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => printPosQuoteSlip(
                      context,
                      quoteId: widget.quoteId!,
                      includeImages: _includeImages,
                    ),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(tr('In phiếu báo giá')),
                  ),
                ],
                if (canEdit) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(),
                    child: Text(_saving ? tr('Đang lưu…') : tr('Lưu báo giá')),
                  ),
                ],
                if (widget.quoteId != null &&
                    (_status == 'Draft' || _status == 'Revised') &&
                    perm.canEdit('PosQuotes')) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () =>
                        _act(() => _api.sendPosQuote(widget.quoteId!)),
                    child: Text(tr('Gửi / phát hành')),
                  ),
                ],
                if (widget.quoteId != null &&
                    (_status == 'Sent' || _status == 'Revised') &&
                    perm.canApprove('PosQuotes')) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () =>
                        _act(() => _api.acceptPosQuote(widget.quoteId!)),
                    child: Text(tr('Khách chấp nhận')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _act(
                        () => _api.rejectPosQuote(widget.quoteId!),
                        pop: true),
                    child: Text(tr('Từ chối')),
                  ),
                ],
                if (widget.quoteId != null &&
                    _status != 'Accepted' &&
                    _status != 'Cancelled' &&
                    perm.canEdit('PosQuotes')) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _act(
                        () => _api.cancelPosQuote(widget.quoteId!),
                        pop: true),
                    child: Text(tr('Hủy báo giá')),
                  ),
                ],
                if (widget.quoteId != null) ...[
                  const SizedBox(height: 24),
                  _pipeline(),
                ],
                if (widget.quoteId != null &&
                    _status == 'Accepted' &&
                    _commercialStage == 'Inspected' &&
                    perm.canApprove('PosQuotes')) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        _act(() => _api.closePosQuote(widget.quoteId!)),
                    child: Text(tr('Đóng hồ sơ')),
                  ),
                ],
              ],
            ),
    );
  }
}
