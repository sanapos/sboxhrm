import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_customer.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_product.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../utils/pos_html_print.dart';
import '../../utils/pos_print_template_loader.dart';
import '../../utils/pos_print_template_v2_codec.dart';
import '../../utils/pos_purchase_product_lookup.dart';
import '../../utils/pos_sell_unit_views.dart';
import '../../utils/pos_vietnamese_money_words.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_customer_form_dialog.dart';
import '../../widgets/pos/pos_discount_editor_dialog.dart';
import '../../widgets/pos/pos_empty_cart_brand.dart';
import '../../widgets/pos/pos_product_image.dart';
import '../../widgets/pos/pos_product_unit_view.dart';
import '../../widgets/pos/pos_quote_care_sheet.dart';
import '../../widgets/pos/pos_sale_quick_notes_widgets.dart';
import '../../widgets/pos/pos_sell_product_grid.dart';
import '../../widgets/pos/pos_form_keyboard.dart';
import '../../widgets/pos/pos_theme.dart';

enum _RowExpand { note, price }

enum _ComposerStage { catalog, cart, checkout }

/// Dòng giỏ báo giá — cùng nghiệp vụ dòng bán: size, ghi chú, CK.
class _QLine {
  _QLine({
    required this.line,
    this.product,
    this.views = const [],
    this.viewKey,
  }) {
    noteCtrl.text = line.lineNote ?? '';
    priceCtrl.text = line.unitPrice == 0
        ? ''
        : NumberFormat('#,##0', 'vi_VN').format(line.unitPrice);
    discountCtrl.text = line.discountAmount == 0
        ? ''
        : NumberFormat('#,##0', 'vi_VN').format(line.discountAmount);
    discountInput = line.discountAmount;
  }

  final PosQuoteLine line;
  PosProduct? product;
  List<PosProductUnitView> views;
  String? viewKey;
  bool discountIsPercent = false;
  double discountInput = 0;
  final noteCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final discountCtrl = TextEditingController();
  final selectedQuickNotes = <String>{};

  void dispose() {
    noteCtrl.dispose();
    priceCtrl.dispose();
    discountCtrl.dispose();
  }

  double get lineGross => (line.qty * line.unitPrice).clamp(0, double.infinity);
  double get lineNet =>
      (line.qty * line.unitPrice - line.discountAmount).clamp(0, double.infinity);
}

/// Tạo / sửa báo giá: giỏ phải = giỏ bán; Tạo báo giá = màn khách + CK đơn.
class PosQuoteComposerScreen extends StatefulWidget {
  const PosQuoteComposerScreen({super.key, this.quoteId});

  final String? quoteId;

  @override
  State<PosQuoteComposerScreen> createState() => _PosQuoteComposerScreenState();
}

class _PosQuoteComposerScreenState extends State<PosQuoteComposerScreen> {
  final _api = ApiService();
  final _custSearch = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _deposit = TextEditingController(text: '50');
  final _note = TextEditingController();
  final _money = NumberFormat('#,##0', 'vi_VN');

  PosCustomer? _customer;
  Timer? _custDebounce;
  List<PosCustomer> _custHits = [];
  String? _printTemplateId;
  List<PosPrintTemplate> _templates = [];
  String _depositPayment = 'Chuyển khoản';
  DateTime _validUntil = DateTime.now().add(const Duration(days: 15));
  final List<_QLine> _cart = [];
  bool _saving = false;
  bool _loading = false;
  _ComposerStage _stage = _ComposerStage.catalog;
  bool _discountIsPercent = false;
  bool _depositIsPercent = true;
  bool _discountPresetsVisible = false;
  bool _includeImages = false;
  Map<String, dynamic>? _commercialProfile;
  String? _savedQuoteId;
  String _quoteNo = '';
  String? _customerId;
  String? _expandedKey;
  _RowExpand? _expandMode;

  static const _depositPayments = ['Chuyển khoản', 'Tiền mặt'];
  static const _kiotBlue = PosTheme.kiotBlue;

  bool get _isEdit => widget.quoteId != null;

  String? get _activeQuoteId => widget.quoteId ?? _savedQuoteId;

  String _rowKey(_QLine r) =>
      '${r.line.productId ?? r.line.productName}|${r.line.unitName ?? ''}|${identityHashCode(r)}';

  String _clampDepositPayment(String? raw) {
    final v = (raw ?? '').trim();
    return _depositPayments.contains(v) ? v : 'Chuyển khoản';
  }

  double get _lineNetSum =>
      _cart.fold(0.0, (a, r) => a + r.lineNet);

  double get _preVatTotal =>
      (_lineNetSum - _orderDiscount).clamp(0, double.infinity);

  double get _depositInput =>
      double.tryParse(_deposit.text.replaceAll('.', '').replaceAll(',', '')) ??
      0;

  double get _depositAmount {
    if (_depositIsPercent) {
      return (_preVatTotal * _depositInput / 100).clamp(0, _total);
    }
    return _depositInput.clamp(0, _total);
  }

  @override
  void initState() {
    super.initState();
    _loadDefaultTemplate();
    _loadCommercialProfile();
    if (_isEdit) {
      _loadQuote();
    }
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

  Future<void> _loadDefaultTemplate() async {
    final list = await loadPosPrintTemplates(_api, PosPrintDocumentTypes.quote);
    if (!mounted) return;
    var html = list.where((t) {
      final raw = t.htmlContent.trim();
      if (!raw.startsWith('<') || PosPrintTemplateV2Codec.isV2Content(raw)) {
        return false;
      }
      final dt = t.documentType.toLowerCase();
      return dt.contains('quote') || dt.contains('baogia');
    }).toList();
    if (html.isEmpty) {
      html = list.where((t) {
        final raw = t.htmlContent.trim();
        return raw.startsWith('<') &&
            !PosPrintTemplateV2Codec.isV2Content(raw) &&
            (raw.contains('{Ten_Hang_Hoa}') || raw.contains('BEGIN_ITEMS'));
      }).toList();
    }
    final def = html.where((t) => t.isDefault).firstOrNull;
    setState(() {
      _templates = html;
      if (_printTemplateId == null ||
          html.every((t) => t.id != _printTemplateId)) {
        _printTemplateId = def?.id;
      }
    });
  }

  Future<void> _loadQuote() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getPosQuote(widget.quoteId!);
      if (!mounted) return;
      if (res['isSuccess'] != true || res['data'] is! Map) {
        setState(() => _loading = false);
        NotificationOverlayManager().showError(
          title: 'Không tải được',
          message: res['message']?.toString() ?? tr('Không tìm thấy báo giá'),
        );
        return;
      }
      final q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
      _custSearch.text = q.customerName ?? '';
      _note.text = q.note ?? '';
      _discount.text = _money.format(q.discount);
      for (final r in _cart) {
        r.dispose();
      }
      _cart
        ..clear()
        ..addAll(q.lines.map((l) => _QLine(line: l)));
      setState(() {
        _loading = false;
        _stage = _ComposerStage.cart;
        _discountIsPercent = false;
        _quoteNo = q.quoteNo;
        _customerId = q.customerId;
        if ((q.customerName ?? '').isNotEmpty ||
            (q.customerPhone ?? '').isNotEmpty) {
          _customer = PosCustomer(
            id: q.customerId ?? '',
            customerCode: '',
            name: q.customerName ?? '',
            phone: q.customerPhone,
            address: q.customerAddress,
            companyName: q.customerName,
          );
        }
        _depositPayment = _clampDepositPayment(q.paymentMethod);
        if (q.depositPercent != null && q.depositPercent! > 0) {
          _depositIsPercent = true;
          _deposit.text = q.depositPercent!.round().toString();
        } else if (q.depositAmount > 0) {
          _depositIsPercent = false;
          _deposit.text = _money.format(q.depositAmount);
        }
        _printTemplateId = q.printTemplateId ?? _printTemplateId;
        if (q.validUntil != null) _validUntil = q.validUntil!.toLocal();
      });
      for (final row in _cart) {
        unawaited(_hydrateRow(row));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Không tải được',
        message: e.toString(),
      );
    }
  }

  Future<void> _hydrateRow(_QLine row) async {
    final id = row.line.productId;
    if (id == null || id.isEmpty) return;
    try {
      final res = await _api.getPosProduct(id);
      if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
      final p = PosProduct.fromJson(Map<String, dynamic>.from(res['data'] as Map));
      final views = await loadPosSellUnitViews(_api, p);
      if (!mounted) return;
      PosProductUnitView? match;
      for (final v in views) {
        if (v.label == row.line.unitName) {
          match = v;
          break;
        }
      }
      final split = splitPosLineNote(row.line.lineNote, p.saleQuickNotes);
      setState(() {
        row.product = p;
        row.views = views;
        row.viewKey = match?.viewKey;
        row.selectedQuickNotes
          ..clear()
          ..addAll(split.selected);
        row.noteCtrl.text = split.extra;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _custDebounce?.cancel();
    _custSearch.dispose();
    _discount.dispose();
    _deposit.dispose();
    _note.dispose();
    for (final r in _cart) {
      r.dispose();
    }
    super.dispose();
  }

  void _onCustomerQuery(String q) {
    _custDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _custHits = []);
      return;
    }
    _custDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_searchCustomers(q));
    });
  }

  Future<void> _searchCustomers(String q) async {
    final res = await _api.getPosCustomers(search: q.trim(), pageSize: 12);
    if (!mounted) return;
    final data = res['data'];
    final raw = data is Map ? (data['items'] as List? ?? []) : <dynamic>[];
    setState(() {
      _custHits = [
        for (final e in raw)
          if (e is Map) PosCustomer.fromJson(Map<String, dynamic>.from(e)),
      ];
    });
  }

  void _pickCustomer(PosCustomer c) {
    setState(() {
      _customer = c;
      _custHits = [];
      _custSearch.text = c.companyName?.trim().isNotEmpty == true
          ? c.companyName!
          : c.name;
    });
  }

  void _clearCustomer() {
    setState(() {
      _customer = null;
      _custHits = [];
      _custSearch.clear();
    });
  }

  Future<void> _openAddCustomer({PosCustomer? edit}) async {
    final created = await showDialog<dynamic>(
      context: context,
      builder: (_) => PosCustomerFormDialog(customer: edit),
    );
    if (created == null || !mounted) return;
    if (created is Map) {
      _pickCustomer(PosCustomer.fromJson(Map<String, dynamic>.from(created)));
    }
  }

  List<PosProductUnitView> _viewsOf(PosProduct p) {
    if (posProductHasEmbeddedSellViews(p)) {
      return buildPosSellUnitViewsFromProduct(p);
    }
    return buildPosProductUnitViews(
      p,
      p.variants?.where((v) => v.isActive).toList() ?? const [],
      extraUnits: p.units?.where((u) => u.isDirectSale).toList() ?? const [],
    );
  }

  PosProductUnitView? _viewForPick(
    List<PosProductUnitView> views,
    PosPurchaseLookupPick pick,
  ) {
    for (final v in views) {
      if (pick.unitId != null && v.unitId == pick.unitId) return v;
      if (pick.variantId != null && v.variantId == pick.variantId) return v;
    }
    for (final v in views) {
      if (pick.unitLabel != null && v.label == pick.unitLabel) return v;
    }
    return pickDefaultSellUnitView(pick.product, views) ??
        (views.isEmpty ? null : views.first);
  }

  void _addPick(PosPurchaseLookupPick pick) {
    final p = pick.product;
    final qty = pick.qty ?? 1;
    final views = _viewsOf(p);
    final view = _viewForPick(views, pick);
    final unit = view?.label ?? pick.unitLabel ?? p.baseUnitName;
    final price = (view?.basePrice ?? 0) > 0 ? view!.basePrice : p.basePrice;
    final i = _cart.indexWhere((c) =>
        c.line.productId == p.id && (c.line.unitName ?? '') == unit);
    if (i >= 0) {
      setState(() => _cart[i].line.qty += qty);
      return;
    }
    final row = _QLine(
      line: PosQuoteLine(
        productId: p.id,
        productCode: view?.displayCode.isNotEmpty == true
            ? view!.displayCode
            : p.productCode,
        productName: p.name,
        unitName: unit,
        qty: qty,
        unitPrice: price,
        vatRate: p.vatExempt ? 0 : p.vatRate,
        warrantyMonths: p.warrantyMonths,
      ),
      product: p,
      views: views,
      viewKey: view?.viewKey,
    );
    setState(() {
      _cart.add(row);
    });
    if (views.length <= 1) {
      unawaited(_hydrateRow(row));
    }
  }

  void _removeRow(int i) {
    final row = _cart.removeAt(i);
    if (_expandedKey == _rowKey(row)) {
      _expandedKey = null;
      _expandMode = null;
    }
    row.dispose();
    setState(() {});
  }

  void _adjustQty(int i, double delta) {
    if (i < 0 || i >= _cart.length) return;
    final next = _cart[i].line.qty + delta;
    if (next <= 0) {
      _removeRow(i);
      return;
    }
    setState(() => _cart[i].line.qty = next);
  }

  void _toggleExpand(_QLine row, _RowExpand mode) {
    final key = _rowKey(row);
    setState(() {
      if (_expandedKey == key && _expandMode == mode) {
        _expandedKey = null;
        _expandMode = null;
      } else {
        _expandedKey = key;
        _expandMode = mode;
        if (mode == _RowExpand.price) {
          row.priceCtrl.text = _money.format(row.line.unitPrice);
          row.discountCtrl.text = row.discountIsPercent
              ? (row.discountInput == 0 ? '' : '${row.discountInput.round()}')
              : (row.line.discountAmount == 0
                  ? ''
                  : _money.format(row.line.discountAmount));
        }
      }
    });
  }

  void _applyNote(_QLine row) {
    row.line.lineNote = joinPosLineNoteParts(
      selectedQuickNotes: row.selectedQuickNotes,
      extraNote: row.noteCtrl.text,
    );
  }

  void _applyPrice(_QLine row) {
    final price = double.tryParse(
          row.priceCtrl.text.replaceAll('.', '').replaceAll(',', ''),
        ) ??
        row.line.unitPrice;
    row.line.unitPrice = price;
    final raw = double.tryParse(
          row.discountCtrl.text.replaceAll('.', '').replaceAll(',', ''),
        ) ??
        0;
    row.discountInput = raw;
    if (row.discountIsPercent) {
      row.line.discountAmount = (row.lineGross * raw / 100).clamp(0, row.lineGross);
    } else {
      row.line.discountAmount = raw.clamp(0, row.lineGross);
    }
  }

  void _switchView(_QLine row, PosProductUnitView v) {
    setState(() {
      row.viewKey = v.viewKey;
      row.line.unitName = v.label;
      if (v.basePrice > 0) {
        row.line.unitPrice = v.basePrice;
        row.priceCtrl.text = _money.format(v.basePrice);
      }
      if (v.displayCode.isNotEmpty) row.line.productCode = v.displayCode;
    });
  }

  double get _subTotal => _cart.fold(0.0, (a, r) => a + r.lineGross);
  double get _lineDiscountTotal =>
      _cart.fold(0.0, (a, r) => a + r.line.discountAmount);
  double get _lineVat => _cart.fold(0.0, (a, r) {
        final net = r.lineNet;
        return a + (net * r.line.vatRate / 100);
      });
  double get _lineSum => _cart.fold(0.0, (a, r) {
        return a + (r.lineNet * (1 + r.line.vatRate / 100));
      });
  double get _discountInput =>
      double.tryParse(_discount.text.replaceAll('.', '').replaceAll(',', '')) ??
      0;
  double get _orderDiscount {
    if (_discountIsPercent) {
      return (_lineSum * _discountInput / 100).clamp(0, _lineSum);
    }
    return _discountInput.clamp(0, _lineSum);
  }

  double get _total => (_lineSum - _orderDiscount).clamp(0, double.infinity);

  Map<String, double> get _cartQty {
    final m = <String, double>{};
    for (final r in _cart) {
      final id = r.line.productId;
      if (id == null || id.isEmpty) continue;
      m[id] = (m[id] ?? 0) + r.line.qty;
    }
    return m;
  }

  void _enterCheckout() {
    if (_cart.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu hàng',
        message: tr('Chọn ít nhất một hàng hóa / dịch vụ'),
      );
      return;
    }
    hidePosSoftKeyboard(alsoAfterMs: 0);
    setState(() {
      _stage = _ComposerStage.checkout;
      _expandedKey = null;
      _expandMode = null;
    });
  }

  void _openCart() => setState(() => _stage = _ComposerStage.cart);

  void _backToCatalog() => setState(() => _stage = _ComposerStage.catalog);

  void _onComposerBack({required bool wide}) {
    setState(() {
      if (_stage == _ComposerStage.checkout) {
        _stage = wide ? _ComposerStage.catalog : _ComposerStage.cart;
      } else {
        _stage = _ComposerStage.catalog;
      }
    });
  }

  bool _composerBlocksPop({required bool wide}) {
    if (_stage == _ComposerStage.checkout) return true;
    return !wide && _stage == _ComposerStage.cart;
  }

  String get _customerDisplayName {
    final walkIn = _custSearch.text.trim();
    if (_customer == null) return walkIn;
    return ((_customer!.companyName ?? '').trim().isNotEmpty
        ? _customer!.companyName!.trim()
        : _customer!.name);
  }

  Future<PosQuote?> _saveQuote({
    bool printAfter = false,
    bool popAfter = false,
    bool notify = true,
  }) async {
    if (_cart.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu hàng',
        message: tr('Chọn ít nhất một hàng hóa / dịch vụ'),
      );
      return null;
    }
    if (_customer == null && _custSearch.text.trim().isEmpty) {
      _custSearch.text = 'Khách lẻ';
    }
    _flushCartEdits();
    setState(() => _saving = true);
    final displayName = _customerDisplayName;
    String? asGuid(String? raw) {
      final s = (raw ?? '').trim();
      if (s.isEmpty) return null;
      return RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(s)
          ? s
          : null;
    }

    try {
      final custId = asGuid(_customer?.id ?? _customerId);
      final tplId = asGuid(_printTemplateId);
      final body = {
        if (custId != null) 'customerId': custId,
        'customerName': displayName,
        'customerPhone': _customer?.phone ?? '',
        'customerAddress': _customer?.address ?? '',
        'validUntil': _validUntil.toUtc().toIso8601String(),
        'discount': _orderDiscount,
        'note': _note.text.trim(),
        'paymentMethod': _depositPayment,
        'depositAmount': _depositAmount,
        'depositPercent': _depositIsPercent ? _depositInput : null,
        if (tplId != null) 'printTemplateId': tplId,
        'includeImages': _includeImages,
        'lines': _cart.map((r) => r.line.toInputJson()).toList(),
      };
      final quoteId = _activeQuoteId;
      final res = quoteId != null
          ? await _api.updatePosQuote(quoteId, body)
          : await _api.createPosQuote(body);
      if (!mounted) return null;
      setState(() => _saving = false);
      if (res['isSuccess'] != true || res['data'] is! Map) {
        NotificationOverlayManager().showError(
          title: quoteId != null ? 'Không lưu được' : 'Không tạo được',
          message: res['message']?.toString() ?? tr('Lưu thất bại'),
        );
        return null;
      }
      var q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
      final fromPut = q;
      if (q.id.isNotEmpty) {
        final again = await _api.getPosQuote(q.id);
        if (again['isSuccess'] == true && again['data'] is Map) {
          final fromGet =
              PosQuote.fromJson(Map<String, dynamic>.from(again['data'] as Map));
          q = fromGet.lines.length >= fromPut.lines.length ? fromGet : fromPut;
        }
      }
      final cartQty = _cart.fold<double>(0, (a, r) => a + r.line.qty);
      final savedQty = q.lines.fold<double>(0, (a, l) => a + l.qty);
      debugPrint(
          'POS_QUOTE_SAVE verify serverQty=$savedQty cartQty=$cartQty serverTotal=${q.total} cartTotal=$_total lines=${q.lines.length}/${_cart.length}');
      final linesMismatch = (q.lines.length - _cart.length).abs() > 0 ||
          (cartQty - savedQty).abs() > 0.01;
      if (linesMismatch && notify) {
        NotificationOverlayManager().showWarning(
          title: 'Đã lưu tổng — kiểm tra giỏ',
          message:
              'Máy chủ ${_money.format(q.total)} đ / SL ${savedQty.round()} — giỏ ${_money.format(_total)} đ / SL ${cartQty.round()}.',
        );
      }
      setState(() {
        _savedQuoteId = q.id;
        _quoteNo = q.quoteNo;
        _adoptSavedLineIds(q.lines);
        _printTemplateId = q.printTemplateId ?? _printTemplateId;
        if (q.depositPercent != null && q.depositPercent! > 0) {
          _depositIsPercent = true;
          _deposit.text = q.depositPercent!.round().toString();
        } else if (q.depositAmount > 0) {
          _depositIsPercent = false;
          _deposit.text = _money.format(q.depositAmount);
        }
      });
      if (notify) {
        NotificationOverlayManager().showSuccess(
          title: quoteId != null ? 'Đã lưu báo giá' : 'Đã tạo báo giá',
          message: '${q.quoteNo} · $displayName',
        );
      }
      if (printAfter) {
        final cartLines = _cart.map((r) => r.line).toList();
        var html = '';
        try {
          html = bindPosQuotePrintHtmlLocal(q, cartLines);
        } catch (_) {
          html = '';
        }
        if (html.trim().isEmpty || html.contains('XEM TRƯỚC')) {
          final buf = StringBuffer('<html><body><h2>BÁO GIÁ ${q.quoteNo}</h2><table>');
          for (final l in cartLines) {
            buf.write(
                '<tr><td>${l.productName}</td><td>${l.qty}</td><td>${l.unitPrice.round()}</td></tr>');
          }
          buf.write('</table></body></html>');
          html = buf.toString();
        }
        if (!mounted) return q;
        await showPosHtmlPrintDialog(
          context,
          title: 'BÁO GIÁ',
          htmlDocument: html,
          a4Paper: true,
        );
      }
      if (popAfter && mounted) Navigator.of(context).pop(true);
      return q;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _saving = false);
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: e.toString(),
      );
      return null;
    }
  }

  void _flushCartEdits() {
    for (final r in _cart) {
      _applyNote(r);
      _applyPrice(r);
      r.line.lineTotal = r.lineNet * (1 + r.line.vatRate / 100);
    }
  }

  void _adoptSavedLineIds(List<PosQuoteLine> saved) {
    if (saved.isEmpty) return;
    final leftover = [...saved];
    for (final r in _cart) {
      var i = leftover.indexWhere(
          (l) => r.line.id.isNotEmpty && l.id == r.line.id);
      if (i < 0 && (r.line.productId ?? '').isNotEmpty) {
        i = leftover.indexWhere((l) =>
            l.productId == r.line.productId &&
            (l.unitName ?? '') == (r.line.unitName ?? ''));
      }
      if (i < 0) {
        i = leftover.indexWhere((l) =>
            l.productName == r.line.productName &&
            (l.unitName ?? '') == (r.line.unitName ?? ''));
      }
      if (i < 0) continue;
      r.line.id = leftover[i].id;
      leftover.removeAt(i);
    }
  }

  Future<void> _save() =>
      _saveQuote(printAfter: true, popAfter: false);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final blocksPop = _composerBlocksPop(wide: wide);
    return PopScope(
      canPop: !blocksPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && blocksPop) _onComposerBack(wide: wide);
      },
      child: Scaffold(
        backgroundColor: PosTheme.background,
        appBar: AppBar(
          leading: blocksPop
              ? IconButton(
                  tooltip: _stage == _ComposerStage.checkout
                      ? tr('Quay lại giỏ hàng')
                      : tr('Quay lại chọn hàng'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _onComposerBack(wide: wide),
                )
              : null,
          title: Text(_stage == _ComposerStage.checkout
              ? tr('Khách hàng & chiết khấu')
              : (!wide && _stage == _ComposerStage.cart
                  ? tr('Giỏ hàng')
                  : (_isEdit
                      ? (_quoteNo.isEmpty ? tr('Sửa báo giá') : _quoteNo)
                      : tr('Chọn hàng báo giá')))),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _stage == _ComposerStage.checkout
                ? _checkoutPane()
                : _cartBody(wide: wide),
      ),
    );
  }

  Widget _cartBody({required bool wide}) {
    if (wide) {
      return Row(
        children: [
          Expanded(flex: 6, child: _catalogPane(listLayout: false)),
          Expanded(flex: 4, child: _cartPane()),
        ],
      );
    }
    if (_stage == _ComposerStage.cart) return _cartPane();
    return Column(
      children: [
        Expanded(child: _catalogPane(listLayout: true)),
        _mobileCartBar(),
      ],
    );
  }

  Widget _mobileCartBar() {
    final n = _cart.length;
    final qty = _cart.fold<double>(0, (a, r) => a + r.line.qty);
    return Material(
      color: Colors.white,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: _openCart,
          child: Container(
            height: 64,
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: PosTheme.border)),
            ),
            child: Row(
              children: [
                Badge(
                  isLabelVisible: n > 0,
                  label: Text(
                    qty == qty.roundToDouble()
                        ? '${qty.round()}'
                        : qty.toStringAsFixed(1),
                  ),
                  child: const Icon(Icons.shopping_cart_outlined,
                      color: _kiotBlue, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n == 0
                            ? tr('Giỏ hàng trống')
                            : tr('$n món · ${_money.format(_total)} đ'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _kiotBlue,
                        ),
                      ),
                      Text(
                        tr('Bấm để xem giỏ hàng'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: PosTheme.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _catalogPane({required bool listLayout}) {
    return PosSellProductGrid(
      api: _api,
      sellListLayout: listLayout,
      cartQtyByProductId: _cartQty,
      onPick: _addPick,
      onDecrement: (p) {
        final i = _cart.indexWhere((r) => r.line.productId == p.id);
        if (i < 0) return;
        _adjustQty(i, -1);
      },
    );
  }

  Widget _cartPane() {
    return Material(
      color: Colors.white,
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: PosTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Báo giá · ${_cart.length} món'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: PosTheme.textSecondary,
                    ),
                  ),
                ),
                if (MediaQuery.sizeOf(context).width < 960)
                  TextButton.icon(
                    onPressed: _backToCatalog,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('Thêm món')),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? PosEmptyCartBrand(
                    hint: tr('Bấm Thêm món để chọn hàng — chạm tên để ghi chú, chạm giá để chiết khấu'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final idx = _cart.length - 1 - i;
                      return _kiotCartRow(idx);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: PosTheme.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_lineDiscountTotal > 0)
                    _moneyRow('Chiết khấu SP', -_lineDiscountTotal),
                  _moneyRow('Tổng tiền (${_cart.length} món)', _total, bold: true),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _saving ? null : _enterCheckout,
                      style: FilledButton.styleFrom(
                        backgroundColor: _kiotBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        tr('Tiếp tục'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kiotCartRow(int i) {
    final row = _cart[i];
    final line = row.line;
    final key = _rowKey(row);
    final noteOn = _expandedKey == key && _expandMode == _RowExpand.note;
    final priceOn = _expandedKey == key && _expandMode == _RowExpand.price;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: noteOn || priceOn
                  ? _kiotBlue.withValues(alpha: 0.45)
                  : PosTheme.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => _removeRow(i),
                        borderRadius: BorderRadius.circular(10),
                        child: const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(Icons.delete_rounded,
                              size: 18, color: Color(0xFFDC2626)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PosProductImage(
                      productId: row.product?.id ?? line.productId,
                      imageUrl: row.product?.imageUrl,
                      updatedAt: row.product?.updatedAt,
                      size: 40,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => _toggleExpand(row, _RowExpand.note),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                label: line.productName,
                                child: Text(
                                  line.productName.isEmpty
                                      ? tr('Hàng hóa')
                                      : line.productName,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.25,
                                    fontWeight: FontWeight.w700,
                                    color: noteOn
                                        ? _kiotBlue
                                        : PosTheme.textPrimary,
                                    decoration: noteOn
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                ),
                              ),
                              if ((line.productCode ?? '').trim().isNotEmpty)
                                Text(
                                  line.productCode!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: PosTheme.textSecondary,
                                  ),
                                ),
                              if (!noteOn &&
                                  (line.lineNote ?? '').trim().isNotEmpty)
                                Text(
                                  'Ghi chú: ${line.lineNote}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: _kiotBlue),
                                ),
                              if (!priceOn && line.discountAmount > 0)
                                Text(
                                  'CK: -${_money.format(line.discountAmount)}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red.shade700),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _qtyStepper(i),
                    const SizedBox(width: 8),
                    SizedBox(width: 72, height: 36, child: _unitPicker(row)),
                    const Spacer(),
                    InkWell(
                      onTap: () => _toggleExpand(row, _RowExpand.price),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _money.format(row.lineNet),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: priceOn ? _kiotBlue : null,
                              ),
                            ),
                            Text(
                              _money.format(line.unitPrice),
                              style: TextStyle(
                                fontSize: 12,
                                color: _kiotBlue,
                                decoration: priceOn
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (noteOn) _noteEditor(row),
        if (priceOn) _priceEditor(row),
      ],
    );
  }

  Widget _qtyStepper(int i) {
    Widget btn(IconData icon, VoidCallback onTap) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF475569)),
          ),
        ),
      );
    }

    final qty = _cart[i].line.qty;
    final qtyText = qty == qty.roundToDouble() ? '${qty.round()}' : '$qty';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove_rounded, () => _adjustQty(i, -1)),
        SizedBox(
          width: 32,
          height: 36,
          child: Center(
            child: Text(
              qtyText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
              ),
            ),
          ),
        ),
        btn(Icons.add_rounded, () => _adjustQty(i, 1)),
      ],
    );
  }

  Widget _unitPicker(_QLine row) {
    final views = row.views;
    final label = row.line.unitName ?? '';
    if (views.length <= 1) {
      return Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _kiotBlue,
          ),
        ),
      );
    }
    return Material(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(10),
      child: PopupMenuButton<String>(
        tooltip: tr('Size / ĐVT'),
        initialValue: row.viewKey,
        onSelected: (key) {
          final v = views.where((x) => x.viewKey == key).firstOrNull;
          if (v != null) _switchView(row, v);
        },
        itemBuilder: (_) => [
          for (final v in views)
            PopupMenuItem<String>(
              value: v.viewKey,
              height: 48,
              child: Text(
                v.label,
                style: TextStyle(
                  fontWeight: v.viewKey == row.viewKey
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: _kiotBlue,
                ),
              ),
            ),
        ],
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kiotBlue,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more_rounded,
                    size: 16, color: _kiotBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _noteEditor(_QLine row) {
    final notes = row.product?.saleQuickNotes ?? const <String>[];
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: PosTheme.kiotBlueLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kiotBlue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PosLineQuickNotesPicker(
            quickNotes: notes,
            selected: row.selectedQuickNotes,
            onSelectedChanged: (next) {
              setState(() {
                row.selectedQuickNotes
                  ..clear()
                  ..addAll(next);
                _applyNote(row);
              });
            },
            extraController: row.noteCtrl,
            autofocusExtra: false,
            onExtraChanged: () => setState(() => _applyNote(row)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                setState(() {
                  _applyNote(row);
                  _expandedKey = null;
                  _expandMode = null;
                });
              },
              style: FilledButton.styleFrom(
                backgroundColor: _kiotBlue,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(tr('OK')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceEditor(_QLine row) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: PosTheme.kiotBlueLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kiotBlue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(tr('Đơn giá'), style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.priceCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'đ',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) => setState(() => _applyPrice(row)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(tr('Chiết khấu'), style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              _lineDiscChip(row, true),
              const SizedBox(width: 4),
              _lineDiscChip(row, false),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.discountCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    suffixText: row.discountIsPercent ? '%' : 'đ',
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) => setState(() => _applyPrice(row)),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: row.discountIsPercent
                ? buildPosDiscountPresetChips(
                    percents: const [5, 10, 15, 20, 25, 50],
                    onPickPercent: (p) => setState(() {
                      row.discountIsPercent = true;
                      row.discountCtrl.text = p.round().toString();
                      _applyPrice(row);
                    }),
                  )
                : buildPosDiscountMoneyPresetChips(
                    moneyFmt: _money,
                    baseAmount: row.lineGross,
                    onPickAmount: (a) => setState(() {
                      row.discountIsPercent = false;
                      row.discountCtrl.text = _money.format(a);
                      _applyPrice(row);
                    }),
                  ),
          ),
          if (row.line.discountAmount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('Chiết khấu dòng: -${_money.format(row.line.discountAmount)}'),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                setState(() {
                  _applyPrice(row);
                  _expandedKey = null;
                  _expandMode = null;
                });
              },
              style: FilledButton.styleFrom(
                backgroundColor: _kiotBlue,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(tr('Áp dụng')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineDiscChip(_QLine row, bool percent) {
    final on = row.discountIsPercent == percent;
    return InkWell(
      onTap: () => setState(() {
        row.discountIsPercent = percent;
        _applyPrice(row);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: on ? PosTheme.kiotBlueLight : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: on ? _kiotBlue : PosTheme.border),
        ),
        child: Text(
          percent ? '%' : 'đ',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: on ? _kiotBlue : PosTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _checkoutPane() {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              children: [
          Text(
            tr('${_cart.length} món · ${_money.format(_total)} đ'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: _kiotBlue,
            ),
          ),
          const SizedBox(height: 14),
          Text(tr('Khách hàng'),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _custSearch,
                  decoration: InputDecoration(
                    hintText: tr('Tìm khách (tên / SĐT / MST)'),
                    isDense: true,
                    prefixIcon:
                        const Icon(Icons.person_search_outlined, size: 22),
                    suffixIcon: _customer != null || _custSearch.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: _clearCustomer,
                          )
                        : null,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  onChanged: _onCustomerQuery,
                ),
              ),
              IconButton(
                tooltip: tr('Thêm khách hàng'),
                icon: const Icon(Icons.person_add_outlined, color: _kiotBlue),
                onPressed: () => _openAddCustomer(),
              ),
            ],
          ),
          if (_custHits.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                border: Border.all(color: PosTheme.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in _custHits.take(8))
                    ListTile(
                      dense: true,
                      title: Text(
                        (c.companyName ?? '').trim().isNotEmpty
                            ? c.companyName!
                            : c.name,
                      ),
                      subtitle: Text([
                        if ((c.taxCode ?? '').isNotEmpty) 'MST ${c.taxCode}',
                        c.phone,
                      ].where((e) => (e ?? '').isNotEmpty).join(' · ')),
                      onTap: () => _pickCustomer(c),
                    ),
                ],
              ),
            ),
          if (_customer != null) _customerCard(_customer!),
          const SizedBox(height: 14),
          if (_templates.isNotEmpty) ...[
            ClipRect(
              child: DropdownButtonFormField<String?>(
              value: _templates.any((t) => t.id == _printTemplateId)
                  ? _printTemplateId
                  : null,
              isExpanded: true,
              decoration: PosTheme.inputDecoration(label: 'Mẫu in A4'),
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
                    child: Text(t.shortLabel,
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
                    child: Text(t.shortLabel, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _printTemplateId = v),
            ),
            ),
            const SizedBox(height: 12),
          ],
          _moneyRow('Tổng tiền hàng', _subTotal),
          if (_lineDiscountTotal > 0)
            _moneyRow('Chiết khấu SP', -_lineDiscountTotal),
          if (_lineVat > 0) _moneyRow('Thuế', _lineVat),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                  width: 82,
                  child: Text(tr('Giảm giá'),
                      style: const TextStyle(fontSize: 13))),
              _orderDiscChip('%', true),
              const SizedBox(width: 4),
              _orderDiscChip('đ', false),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _discount,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: _discountIsPercent ? '%' : 'đ',
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  onTap: () => setState(() => _discountPresetsVisible = true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (_discountPresetsVisible)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _discountIsPercent
                  ? buildPosDiscountPresetChips(
                      onPickPercent: (p) => setState(() {
                        _discountIsPercent = true;
                        _discount.text = p.round().toString();
                      }),
                    )
                  : buildPosDiscountMoneyPresetChips(
                      moneyFmt: _money,
                      baseAmount: _lineSum,
                      onPickAmount: (a) => setState(() {
                        _discountIsPercent = false;
                        _discount.text = _money.format(a);
                      }),
                    ),
            ),
          if (_orderDiscount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('Chiết khấu đơn: -${_money.format(_orderDiscount)}'),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: Colors.red.shade700),
              ),
            ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final first = DateTime(now.year, now.month, now.day);
              final initial =
                  _validUntil.isBefore(first) ? first : _validUntil;
              final d = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: first,
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (d != null) setState(() => _validUntil = d);
            },
            child: InputDecorator(
              decoration: PosTheme.inputDecoration(label: 'Hạn báo giá'),
              child: Text(DateFormat('dd/MM/yyyy').format(_validUntil)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr('Tiền cọc thực hiện hợp đồng'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text(
            tr('Trên giá trị trước VAT: ${_money.format(_preVatTotal)} đ'),
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 82,
                child: Text(tr('Tiền cọc'),
                    style: const TextStyle(fontSize: 13)),
              ),
              _depositDiscChip('%', true),
              const SizedBox(width: 4),
              _depositDiscChip('đ', false),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _deposit,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: _depositIsPercent ? '%' : 'đ',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
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
                tr(
                    'Cọc: ${_money.format(_depositAmount)} đ (${_depositInput.round()}%)'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, color: _kiotBlue),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            tr('Hình thức thu cọc'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final e in _depositPayments)
                ChoiceChip(
                  label: Text(tr(e)),
                  selected: _depositPayment == e,
                  onSelected: (_) => setState(() => _depositPayment = e),
                ),
            ],
          ),
          _bankReceiveCard(),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _includeImages,
            onChanged: (v) => setState(() => _includeImages = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              tr('Đưa hình ảnh sản phẩm vào phiếu in (3×3 cm)'),
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: PosTheme.inputDecoration(label: 'Ghi chú đơn'),
          ),
          const SizedBox(height: 12),
          const Divider(),
          _moneyRow('Tổng cộng', _total, bold: true),
          Text(
            vietnameseMoneyInWords(_total.round()),
            style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade700,
                fontSize: 12),
          ),
        ],
            ),
          ),
          SafeArea(
            top: false,
            child: Material(
              elevation: 8,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.request_quote_outlined),
                    label: Text(_saving
                        ? tr('Đang lưu…')
                        : (_isEdit || _savedQuoteId != null
                            ? tr('Lưu & in phiếu')
                            : tr('Hoàn tất & in phiếu'))),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _depositDiscChip(String label, bool percent) {
    final on = _depositIsPercent == percent;
    return InkWell(
      onTap: () => setState(() => _depositIsPercent = percent),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: on ? _kiotBlue : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: on ? _kiotBlue : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _bankReceiveCard() {
    if (_depositPayment != 'Chuyển khoản') return const SizedBox.shrink();
    final acc = _profileText('bankAccountNumber', 'BankAccountNumber');
    final bank = _profileText('bankName', 'BankName');
    final holder = _profileText('bankAccountHolder', 'BankAccountHolder');
    final bits = [bank, acc, holder].where((e) => e.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        bits.isEmpty
            ? tr('Phiếu in lấy TK từ Hồ sơ thương mại — chưa cấu hình')
            : tr('Phiếu in đính kèm TK hồ sơ: $bits'),
        style: TextStyle(
          fontSize: 12,
          color: bits.isEmpty ? Colors.orange.shade800 : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _orderDiscChip(String label, bool percent) {
    final on = _discountIsPercent == percent;
    return InkWell(
      onTap: () => setState(() {
        _discountIsPercent = percent;
        _discountPresetsVisible = true;
      }),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: on ? _kiotBlue : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: on ? _kiotBlue : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _customerCard(PosCustomer c) {
    final company = (c.companyName ?? '').trim();
    final title = company.isNotEmpty ? company : c.name;
    final bits = <String>[
      if ((c.taxCode ?? '').isNotEmpty) 'MST ${c.taxCode}',
      if ((c.phone ?? '').isNotEmpty) c.phone!,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              const CircleAvatar(
                  radius: 16, child: Icon(Icons.apartment, size: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    if (bits.isNotEmpty)
                      Text(bits.join(' · '),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('Sửa khách'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _openAddCustomer(edit: c),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moneyRow(String label, double value, {bool bold = false}) {
    final text = value < 0
        ? '-${_money.format(-value)} đ'
        : '${_money.format(value)} đ';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr(label),
              style: TextStyle(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: bold ? _kiotBlue : null,
                fontSize: bold ? 15 : 13,
              ),
            ),
          ),
          Text(
            text,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? _kiotBlue : (value < 0 ? Colors.red.shade700 : null),
              fontSize: bold ? 16 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
