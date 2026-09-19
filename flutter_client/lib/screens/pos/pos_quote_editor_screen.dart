import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_product.dart';
import '../../models/pos_quote.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_html_print.dart';
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
  final _note = TextEditingController();
  final _terms = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _money = NumberFormat('#,##0', 'vi_VN');
  DateTime _validUntil = DateTime.now().add(const Duration(days: 15));
  String? _customerId;
  String _status = 'Draft';
  String _quoteNo = '';
  String _commercialStage = 'None';
  List<PosQuoteLine> _lines = [];
  List<PosQuoteDocument> _documents = [];
  bool _loading = false;
  bool _saving = false;
  bool _locked = false;

  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    if (widget.quoteId != null) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    _terms.dispose();
    _discount.dispose();
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
        'lines': _lines.map((l) => l.toInputJson()).toList(),
      };

  Future<bool> _save() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Thêm ít nhất một dòng hàng / dịch vụ'))),
      );
      return false;
    }
    setState(() => _saving = true);
    final res = widget.quoteId == null
        ? await _api.createPosQuote(_body())
        : await _api.updatePosQuote(widget.quoteId!, _body());
    if (!mounted) return false;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Lưu thất bại')),
      );
      return false;
    }
    if (widget.quoteId == null && res['data'] is Map) {
      final q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
      if (!mounted) return true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PosQuoteEditorScreen(quoteId: q.id)),
      );
      return true;
    }
    await _load();
    return true;
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() fn,
      {bool pop = false}) async {
    if (widget.quoteId != null) {
      final ok = _locked ? true : await _save();
      if (!ok) return;
    }
    final res = await fn();
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Thao tác thất bại')),
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

  Future<void> _previewKind(String kind) async {
    if (widget.quoteId == null) return;
    final res = await _api.previewPosQuoteDocument(widget.quoteId!, kind);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Không xem trước được')),
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
        ? await _api.createPosQuoteStockIssue(widget.quoteId!, note: note)
        : await _api.createPosQuoteDocument(widget.quoteId!, kind, note: note);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Lập chứng từ thất bại')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Không tìm thấy'))),
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
      ));
    });
  }

  Future<void> _editLine(int i) async {
    final line = _lines[i];
    final qty = TextEditingController(text: line.qty.toString());
    final price = TextEditingController(text: _money.format(line.unitPrice));
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
        if (widget.quoteId != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _previewKind('Quote'),
                child: Text(tr('Xem báo giá')),
              ),
              if (_status == 'Accepted' && _commercialStage != 'Closed') ...[
                FilledButton.tonal(
                  onPressed: _saving ? null : () => _createKind('Contract'),
                  child: Text(tr('Lập hợp đồng')),
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
                  if (d.issuedAt != null)
                    DateFormat('dd/MM/yyyy HH:mm').format(d.issuedAt!.toLocal()),
                  if (d.stockIssueNo != null && d.stockIssueNo!.isNotEmpty)
                    'PXK ${d.stockIssueNo}',
                ].join('  ·  ')),
                trailing: const Icon(Icons.print_outlined),
                onTap: d.htmlContent.isEmpty
                    ? null
                    : () => showPosHtmlPrintDialog(
                          context,
                          title: d.title,
                          htmlDocument: d.htmlContent,
                        ),
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
        title: Text(_quoteNo.isEmpty ? tr('Tạo báo giá') : _quoteNo),
        actions: [
          if (widget.quoteId != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text([
                  PosQuote.statusLabel(_status),
                  if (_status == 'Accepted')
                    PosQuote.stageLabel(_commercialStage),
                ].join(' · ')),
              ),
            ),
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
                TextField(
                  controller: _name,
                  enabled: canEdit,
                  decoration: PosTheme.inputDecoration(label: 'Khách hàng'),
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
                      subtitle: Text(
                        '${_lines[i].qty} ${_lines[i].unitName ?? ''} × ${_money.format(_lines[i].unitPrice)} đ',
                      ),
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
                if (canEdit)
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? tr('Đang lưu…') : tr('Lưu báo giá')),
                  ),
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
                if (widget.quoteId != null &&
                    (_status == 'Accepted' || _documents.isNotEmpty)) ...[
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
