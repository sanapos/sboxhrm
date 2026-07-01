import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/cash_transaction.dart';
import '../models/pos_customer.dart';
import '../models/pos_product.dart';
import '../models/pos_print_template.dart';
import '../models/pos_sale_order.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/responsive_helper.dart';
import '../utils/store_role_helper.dart';
import '../services/api_service.dart';
import '../utils/pos_purchase_product_lookup.dart';
import '../utils/pos_sale_order_print.dart';
import '../utils/pos_sell_print_settings.dart';
import '../utils/pos_sell_store_settings.dart';
import '../utils/pos_sell_unit_views.dart';
import '../widgets/pos/pos_barcode_keyboard_scope.dart';
import '../widgets/pos/pos_sell_product_grid.dart';
import '../widgets/notification_overlay.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../screens/pos/pos_product_editor_page.dart';
import '../widgets/pos/pos_discount_editor_dialog.dart';
import '../widgets/pos/pos_customer_form_dialog.dart';
import '../widgets/pos/pos_product_image.dart';
import '../widgets/pos/pos_product_unit_view.dart';
import '../widgets/pos/pos_purchase_product_search_bar.dart';
import '../widgets/pos/pos_sell_print_popover.dart';
import '../widgets/pos/pos_sell_store_settings_dialog.dart';
import '../widgets/pos/pos_sale_quick_notes_widgets.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos/pos_hub_scope.dart';
import 'pos_sale_order_editor_screen.dart';
import 'pos/pos_end_of_day_screen.dart';
import 'pos_reports_screen.dart';
import 'pos_sale_return_screen.dart';
import '../widgets/pos/pos_cash_voucher_dialog.dart';
import '../widgets/pos/pos_pick_sale_order_dialog.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Tỷ lệ / khoảng cách màn bán hàng theo KiotViet.
abstract final class _KiotLayout {
  static const topBarHeight = 48.0;
  static const bottomBarHeight = 40.0;
  static const cartRowHeight = 50.0;
  static const cartHeaderHeight = 30.0;
  static const sidePadding = 16.0;
  static const sectionGap = 12.0;

  /// Panel thanh toán = đúng 50% màn hình (phần còn lại cho sản phẩm / giỏ).
  static double paymentPanelWidth(double screenW) => screenW * 0.5;

  static const compactSectionGap = 8.0;

  static const wStt = 26.0;
  static const wDel = 30.0;
  static const wImg = 36.0;
  static const gapAfterImg = 8.0;
  static const wNameMin = 140.0;
  static const wQty = 64.0;
  static const wUnit = 72.0;
  static const wPrice = 96.0;
  static const wTotal = 100.0;

  static double get tableMinWidth =>
      wStt + wDel + wImg + gapAfterImg + wNameMin + wQty + wUnit + wPrice + wTotal + 20;
}

class _PosPaymentSource {
  const _PosPaymentSource({
    required this.key,
    required this.label,
    required this.methodLabel,
    required this.methodType,
    this.bankAccountId,
  });

  final String key;
  final String label;
  final String methodLabel;
  final PaymentMethodType methodType;
  final String? bankAccountId;

  static const cashKey = 'cash';

  static const cash = _PosPaymentSource(
    key: cashKey,
    label: 'Tiền mặt',
    methodLabel: 'Tiền mặt',
    methodType: PaymentMethodType.cash,
  );

  factory _PosPaymentSource.fromBank(BankAccount account) {
    final short = account.bankShortName ?? account.bankName;
    final tail = account.accountNumber.length > 4
        ? account.accountNumber.substring(account.accountNumber.length - 4)
        : account.accountNumber;
    return _PosPaymentSource(
      key: account.id,
      label: '$short ·$tail',
      methodLabel: '${account.bankName} ${account.accountNumber}',
      methodType: PaymentMethodType.bankTransfer,
      bankAccountId: account.id,
    );
  }
}

class _SellPaymentLine {
  _SellPaymentLine({required this.sourceKey});

  String sourceKey;
  double amount = 0;
  final TextEditingController amountCtrl = TextEditingController();

  void dispose() => amountCtrl.dispose();
}

enum _SellMode { quick, normal, delivery }

enum _CartRowExpand { note, priceDiscount }

class _SellCartLine {
  _SellCartLine({
    required this.rowId,
    required this.product,
    this.variantId,
    this.unitId,
    this.variant,
    required this.activeViewKey,
    required this.unitLabel,
    required this.displayCode,
    required this.unitPrice,
    required this.unitViews,
    this.qty = 1,
    this.lineNote,
    this.discountIsPercent = false,
    this.discountInput = 0,
  })  : noteCtrl = TextEditingController(),
        priceCtrl = TextEditingController(
          text: unitPrice == unitPrice.roundToDouble()
              ? unitPrice.toStringAsFixed(0)
              : unitPrice.toStringAsFixed(2),
        ),
        discountCtrl = TextEditingController(
          text: discountInput == 0
              ? '0'
              : (discountInput == discountInput.roundToDouble()
                  ? discountInput.toStringAsFixed(0)
                  : discountInput.toStringAsFixed(2)),
        );

  final int rowId;
  final PosProduct product;
  String? variantId;
  String? unitId;
  PosProductVariant? variant;
  String activeViewKey;
  String unitLabel;
  String displayCode;
  double unitPrice;
  double qty;
  List<PosProductUnitView> unitViews;
  String? lineNote;
  bool discountIsPercent;
  double discountInput;
  final Set<String> selectedQuickNotes = {};
  final TextEditingController noteCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController discountCtrl;

  void dispose() {
    noteCtrl.dispose();
    priceCtrl.dispose();
    discountCtrl.dispose();
  }

  PosProductUnitView get activeView => unitViews.firstWhere(
        (v) => v.viewKey == activeViewKey,
        orElse: () => unitViews.first,
      );

  String get lineKey => '${product.id}|$activeViewKey';

  double get maxQty => activeView.onHandQty;
  double get lineGross => unitPrice * qty;

  double get discountAmount {
    if (discountInput <= 0) return 0;
    if (discountIsPercent) {
      return (lineGross * discountInput / 100).clamp(0, lineGross);
    }
    return discountInput.clamp(0, lineGross);
  }

  double get lineTotal => lineGross - discountAmount;
}

class _SellInvoiceTab {
  _SellInvoiceTab({required this.id});

  final int id;
  String get label => 'Hóa đơn $id';

  final List<_SellCartLine> cart = [];
  bool discountIsPercent = false;
  double discountInput = 0;
  double discount = 0;
  String paymentMethod = 'Tiền mặt';
  double paidAmount = 0;
  bool paidManuallyEdited = false;
  final List<_SellPaymentLine> paymentLines = [];
  bool paymentsManuallyEdited = false;
  String? note;
  PosCustomer? customer;
  String? deliveryAddress;
  String? deliveryPhone;
  String? deliveryPartner;
  String? sellerEmployeeId;
  final _noteCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController();
  final _customerSearchCtrl = TextEditingController();
  final _deliveryAddressCtrl = TextEditingController();
  final _deliveryPhoneCtrl = TextEditingController();
  final _deliveryPartnerCtrl = TextEditingController();

  void dispose() {
    _noteCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    _customerSearchCtrl.dispose();
    _deliveryAddressCtrl.dispose();
    _deliveryPhoneCtrl.dispose();
    _deliveryPartnerCtrl.dispose();
    for (final line in cart) {
      line.dispose();
    }
    for (final pay in paymentLines) {
      pay.dispose();
    }
  }

  void _clearPaymentLines() {
    for (final pay in paymentLines) {
      pay.dispose();
    }
    paymentLines.clear();
  }

  void reset() {
    for (final line in cart) {
      line.dispose();
    }
    cart.clear();
    _clearPaymentLines();
    paymentLines.add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
    discountIsPercent = false;
    discountInput = 0;
    discount = 0;
    paymentMethod = 'Tiền mặt';
    paidAmount = 0;
    paidManuallyEdited = false;
    paymentsManuallyEdited = false;
    note = null;
    customer = null;
    deliveryAddress = null;
    deliveryPhone = null;
    deliveryPartner = null;
    sellerEmployeeId = null;
    _noteCtrl.clear();
    _discountCtrl.text = '0';
    _paidCtrl.clear();
    _customerSearchCtrl.clear();
    _deliveryAddressCtrl.clear();
    _deliveryPhoneCtrl.clear();
    _deliveryPartnerCtrl.clear();
  }

  void applyDiscount(double baseAfterLineDiscount) {
    if (discountIsPercent) {
      discount = (baseAfterLineDiscount * discountInput / 100).clamp(0, baseAfterLineDiscount);
    } else {
      discount = discountInput.clamp(0, baseAfterLineDiscount);
    }
  }
}

class PosSellScreen extends StatefulWidget {
  const PosSellScreen({super.key});

  @override
  State<PosSellScreen> createState() => _PosSellScreenState();
}

class _PosSellScreenState extends State<PosSellScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');
  final _printBtnKey = GlobalKey();
  final _tabScrollCtrl = ScrollController();
  final _productSearchFocus = FocusNode();
  final _customerSearchFocus = FocusNode();
  final _productGridKey = GlobalKey<PosSellProductGridState>();

  int _nextTabSeq = 2;
  final List<_SellInvoiceTab> _tabs = [_SellInvoiceTab(id: 1)];
  int _activeTab = 0;
  _SellMode _sellMode = _SellMode.quick;
  PosSellPrintSettings _printSettings = const PosSellPrintSettings();
  PosSellStoreSettings _storeSettings = const PosSellStoreSettings();
  bool _checkingOut = false;
  List<PosCustomer> _customerSuggestions = [];
  List<_PosPaymentSource> _paymentSources = const [_PosPaymentSource.cash];
  int _nextCartRowId = 1;
  int? _expandedCartRowId;
  _CartRowExpand? _expandedCartMode;
  List<Map<String, dynamic>> _sellSellers = [];
  bool _canPickSeller = false;
  String? _defaultSellerEmployeeId;
  /// 0 = sản phẩm, 1 = giỏ / thanh toán (chỉ mobile)
  int _mobilePage = 0;

  _SellInvoiceTab get _tab => _tabs[_activeTab];

  void _collapseExpandedCartRow() {
    if (_expandedCartRowId == null) return;
    setState(() {
      _expandedCartRowId = null;
      _expandedCartMode = null;
    });
  }

  void _toggleCartRowExpand(int rowId, _CartRowExpand mode) {
    setState(() {
      if (_expandedCartRowId == rowId && _expandedCartMode == mode) {
        _expandedCartRowId = null;
        _expandedCartMode = null;
        return;
      }
      _expandedCartRowId = rowId;
      _expandedCartMode = mode;
      if (mode == _CartRowExpand.priceDiscount) {
        final line = _tab.cart.firstWhere((l) => l.rowId == rowId);
        line.priceCtrl.text = line.unitPrice == line.unitPrice.roundToDouble()
            ? line.unitPrice.toStringAsFixed(0)
            : line.unitPrice.toStringAsFixed(2);
      }
      if (mode == _CartRowExpand.note) {
        final line = _tab.cart.firstWhere((l) => l.rowId == rowId);
        _initLineNoteSelection(line);
      }
    });
  }

  void _initLineNoteSelection(_SellCartLine line) {
    final split = splitPosLineNote(line.lineNote, line.product.saleQuickNotes);
    line.selectedQuickNotes
      ..clear()
      ..addAll(split.selected);
    line.noteCtrl.text = split.extra;
  }

  void _applyLineNoteFromPicker(_SellCartLine line) {
    line.lineNote = joinPosLineNoteParts(
      selectedQuickNotes: line.selectedQuickNotes,
      extraNote: line.noteCtrl.text,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabs.first.paymentLines.add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
    _loadPrintSettings();
    _loadStoreSettings();
    _loadPaymentSources();
    _loadSellSellers();
    _ensurePosPrintTemplates();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  Future<void> _loadPaymentSources() async {
    final res = await _api.getBankAccounts();
    if (!mounted) return;
    final sources = <_PosPaymentSource>[_PosPaymentSource.cash];
    if (res['isSuccess'] == true && res['data'] is List) {
      for (final raw in res['data'] as List) {
        final account = BankAccount.fromJson(raw as Map<String, dynamic>);
        if (account.isActive) {
          sources.add(_PosPaymentSource.fromBank(account));
        }
      }
    }
    setState(() => _paymentSources = sources);
  }

  Future<void> _loadSellSellers() async {
    final res = await _api.getPosSellSellers();
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! List) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final list = (res['data'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final canPick = StoreRoleHelper.isManagerOrAbove(auth.userRole);
    Map<String, dynamic>? self;
    for (final item in list) {
      if (item['isSelf'] == true) {
        self = item;
        break;
      }
    }
    self ??= list.isNotEmpty ? list.first : null;
    final defaultId = self?['employeeId']?.toString();

    setState(() {
      _sellSellers = list;
      _canPickSeller = canPick;
      _defaultSellerEmployeeId = defaultId;
      for (final t in _tabs) {
        t.sellerEmployeeId ??= defaultId;
      }
    });
  }

  _PosPaymentSource _sourceByKey(String key) {
    return _paymentSources.firstWhere(
      (s) => s.key == key,
      orElse: () => _PosPaymentSource.cash,
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _tabScrollCtrl.dispose();
    _productSearchFocus.dispose();
    _customerSearchFocus.dispose();
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.f3) {
      _productSearchFocus.requestFocus();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f4) {
      _customerSearchFocus.requestFocus();
      return true;
    }
    return false;
  }

  Future<void> _loadPrintSettings() async {
    final s = await PosSellPrintSettings.load();
    if (mounted) setState(() => _printSettings = s);
  }

  Future<void> _loadStoreSettings() async {
    final s = await PosSellStoreSettings.load();
    if (mounted) setState(() => _storeSettings = s);
  }

  Future<void> _ensurePosPrintTemplates() async {
    await _api.getPosPrintTemplates(
      documentType: PosPrintDocumentTypes.saleInvoice,
    );
  }

  void _newTab() {
    setState(() {
      final tab = _SellInvoiceTab(id: _nextTabSeq++);
      tab.paymentLines.add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
      _tabs.add(tab);
      _activeTab = _tabs.length - 1;
      _customerSuggestions = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tabScrollCtrl.hasClients) return;
      _tabScrollCtrl.animateTo(
        _tabScrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _closeTab(int index) async {
    if (_tabs[index].cart.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Đóng hóa đơn'),
          content: Text(
            '${_tabs[index].label} đang có ${_tabs[index].cart.length} sản phẩm. Bạn có chắc muốn đóng?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (_tabs.length <= 1) {
      setState(() {
        _tab.reset();
        _customerSuggestions = [];
        _syncPaidAmount();
      });
      return;
    }
    setState(() {
      _tabs[index].dispose();
      _tabs.removeAt(index);
      if (_activeTab > index) {
        _activeTab--;
      } else if (_activeTab >= _tabs.length) {
        _activeTab = _tabs.length - 1;
      }
      _customerSuggestions = [];
    });
  }

  void _selectTab(int index) {
    if (index == _activeTab) return;
    setState(() {
      _activeTab = index;
      _customerSuggestions = [];
      _syncPaidAmount();
    });
  }

  double get _subTotal =>
      _tab.cart.fold(0.0, (a, c) => a + c.lineGross);

  double get _lineDiscountTotal =>
      _tab.cart.fold(0.0, (a, c) => a + c.discountAmount);

  double get _afterLineDiscount => (_subTotal - _lineDiscountTotal).clamp(0, double.infinity);

  void _recalcTotals() {
    _tab.applyDiscount(_afterLineDiscount);
  }

  double get _total => (_afterLineDiscount - _tab.discount).clamp(0, double.infinity);

  double get _effectivePaidAmount {
    if (_tab.paymentLines.isNotEmpty) {
      return _tab.paymentLines.fold(0.0, (a, p) => a + p.amount);
    }
    final fromCtrl = _parseMoneyInput(_tab._paidCtrl.text);
    if (_tab._paidCtrl.text.trim().isNotEmpty) return fromCtrl;
    return _tab.paidAmount;
  }

  double get _changeAmount =>
      (_effectivePaidAmount - _total).clamp(0, double.infinity);

  double get _dueAmount =>
      (_total - _effectivePaidAmount).clamp(0, double.infinity);

  static double _parseMoneyInput(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.isEmpty) return 0;
    return double.tryParse(cleaned) ?? 0;
  }

  double get _vatAmount => 0;

  Future<void> _addPick(PosPurchaseLookupPick pick, {bool mergeIfSame = false}) async {
    final p = pick.product;
    final views = await loadPosSellUnitViews(_api, p);
    if (!mounted || views.isEmpty) return;

    final view = pickUnitView(
          views,
          variantId: pick.variantId,
          unitId: pick.unitId,
          unitLabel: pick.unitLabel,
        ) ??
        views.first;

    if (p.productType != PosProductType.combo && view.onHandQty <= 0) {
      NotificationOverlayManager().showError(
        title: 'Hết hàng',
        message: '${p.name} (${view.label}) không còn tồn kho',
      );
      return;
    }

    PosProductVariant? variant;
    if (view.variantId != null) {
      variant = await _resolveVariant(p.id, view.variantId!);
    }

    setState(() {
      if (mergeIfSame) {
        final idx = _tab.cart.indexWhere((l) =>
            l.product.id == p.id &&
            l.variantId == view.variantId &&
            l.unitId == view.unitId);
        if (idx >= 0) {
          _tab.cart[idx].qty += 1;
          _syncPaidAmount();
          return;
        }
      }
      _tab.cart.add(_SellCartLine(
        rowId: _nextCartRowId++,
        product: p,
        variantId: view.variantId,
        unitId: view.unitId,
        variant: variant,
        activeViewKey: view.viewKey,
        unitLabel: view.label,
        displayCode: view.displayCode,
        unitPrice: view.basePrice,
        unitViews: views,
        qty: 1,
      ));
      _syncPaidAmount();
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _onBarcodeScanned(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    final pick = await lookupOrPickPosProduct(context, _api, trimmed);
    if (!mounted) return;
    if (pick == null) {
      NotificationOverlayManager().showWarning(
        title: 'Không tìm thấy sản phẩm',
        message: 'Mã vạch "$trimmed" không có trong danh mục hàng hóa',
      );
      return;
    }
    await _addPick(pick, mergeIfSame: true);
  }

  Future<void> _openNewProduct() async {
    final saved = await PosProductEditorPage.open(
      context,
      productType: PosProductType.goods,
    );
    if (saved == true && mounted) {
      ScreenRefreshNotifier.refreshPosProducts();
      ScreenRefreshNotifier.refreshPosSellProductGrid();
      _productGridKey.currentState?.reload();
    }
  }

  Future<PosProductVariant?> _resolveVariant(String productId, String variantId) async {
    final res = await _api.getPosProductVariants(productId);
    if (res['isSuccess'] != true || res['data'] is! List) return null;
    return (res['data'] as List)
        .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
        .where((v) => v.id == variantId)
        .firstOrNull;
  }

  void _syncPaidAmount() {
    _recalcTotals();
    if (_tab.paymentsManuallyEdited) {
      _tab.paidAmount = _effectivePaidAmount;
      return;
    }
    if (_tab.paymentLines.isEmpty) {
      _tab.paymentLines.add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
    }
    final first = _tab.paymentLines.first;
    first.amount = _total;
    first.amountCtrl.text = _moneyFmt.format(_total);
    _tab.paidAmount = _total;
    _tab.paidManuallyEdited = false;
    _tab._paidCtrl.text = _moneyFmt.format(_total);
  }

  void _onDiscountInputChanged(String raw) {
    final v = _parseMoneyInput(raw);
    setState(() {
      _tab.discountInput = v;
      _recalcTotals();
      if (!_tab.paidManuallyEdited && !_tab.paymentsManuallyEdited) {
        _tab.paidAmount = _total;
        _tab._paidCtrl.text = _moneyFmt.format(_total);
      }
    });
  }

  void _setDiscountMode(bool isPercent) {
    if (_tab.discountIsPercent == isPercent) return;
    setState(() {
      _tab.discountIsPercent = isPercent;
      _tab.discountInput = 0;
      _tab._discountCtrl.text = '0';
      _recalcTotals();
      if (!_tab.paidManuallyEdited && !_tab.paymentsManuallyEdited) {
        _tab.paidAmount = _total;
        _tab._paidCtrl.text = _moneyFmt.format(_total);
      }
    });
  }

  void _removeLine(int index) => setState(() {
        _tab.cart[index].dispose();
        if (_expandedCartRowId == _tab.cart[index].rowId) {
          _expandedCartRowId = null;
          _expandedCartMode = null;
        }
        _tab.cart.removeAt(index);
        _syncPaidAmount();
      });

  void _adjustQty(_SellCartLine line, double delta) {
    setState(() {
      final next = line.qty + delta;
      if (next <= 0) {
        line.dispose();
        if (_expandedCartRowId == line.rowId) {
          _expandedCartRowId = null;
          _expandedCartMode = null;
        }
        _tab.cart.remove(line);
      } else if (line.product.productType != PosProductType.combo && next > line.maxQty) {
        return;
      } else {
        line.qty = next;
      }
      _syncPaidAmount();
    });
  }

  Future<void> _switchUnit(_SellCartLine line, PosProductUnitView view) async {
    final views = await loadPosSellUnitViews(_api, line.product);
    if (!mounted) return;
    final fresh = views
            .where((v) => v.viewKey == view.viewKey)
            .firstOrNull ??
        view;
    PosProductVariant? variant;
    if (fresh.variantId != null) {
      variant = await _resolveVariant(line.product.id, fresh.variantId!);
    }
    if (!mounted) return;
    setState(() {
      line.unitViews = views;
      line.activeViewKey = fresh.viewKey;
      line.unitLabel = fresh.label;
      line.displayCode = fresh.displayCode;
      line.unitPrice = fresh.basePrice;
      line.priceCtrl.text = fresh.basePrice == fresh.basePrice.roundToDouble()
          ? fresh.basePrice.toStringAsFixed(0)
          : fresh.basePrice.toStringAsFixed(2);
      line.variantId = fresh.variantId;
      line.unitId = fresh.unitId;
      line.variant = variant;
      if (!line.discountIsPercent && line.discountInput > line.lineGross) {
        line.discountInput = 0;
      }
      _syncPaidAmount();
    });
  }

  void _applyLinePriceInput(_SellCartLine line, String raw) {
    final price = _parseMoneyInput(raw);
    line.unitPrice = price.clamp(0, double.infinity);
    if (!line.discountIsPercent && line.discountInput > line.lineGross) {
      line.discountInput = 0;
      line.discountCtrl.text = '0';
    }
    _syncPaidAmount();
  }

  void _applyOrderDiscountPreset(double percent) {
    setState(() {
      _tab.discountIsPercent = true;
      _tab.discountInput = percent;
      _tab._discountCtrl.text = percent % 1 == 0
          ? percent.toStringAsFixed(0)
          : percent.toStringAsFixed(2);
      _recalcTotals();
      if (!_tab.paidManuallyEdited && !_tab.paymentsManuallyEdited) {
        _tab.paidAmount = _total;
        _tab._paidCtrl.text = _moneyFmt.format(_total);
      }
    });
  }

  void _applyOrderDiscountAmountPreset(double amount) {
    setState(() {
      _tab.discountIsPercent = false;
      final capped = amount.clamp(0, _afterLineDiscount).toDouble();
      _tab.discountInput = capped;
      _tab._discountCtrl.text = _moneyFmt.format(capped);
      _recalcTotals();
      if (!_tab.paidManuallyEdited && !_tab.paymentsManuallyEdited) {
        _tab.paidAmount = _total;
        _tab._paidCtrl.text = _moneyFmt.format(_total);
      }
    });
  }

  void _applyLineDiscountPreset(_SellCartLine line, double percent) {
    setState(() {
      line.discountIsPercent = true;
      line.discountInput = percent;
      line.discountCtrl.text = percent % 1 == 0
          ? percent.toStringAsFixed(0)
          : percent.toStringAsFixed(2);
      _syncPaidAmount();
    });
  }

  void _applyLineDiscountAmountPreset(_SellCartLine line, double amount) {
    setState(() {
      line.discountIsPercent = false;
      final capped = amount.clamp(0, line.lineGross).toDouble();
      line.discountInput = capped;
      line.discountCtrl.text = _moneyFmt.format(capped);
      _syncPaidAmount();
    });
  }

  void _setLineDiscountMode(_SellCartLine line, bool isPercent) {
    if (line.discountIsPercent == isPercent) return;
    setState(() {
      line.discountIsPercent = isPercent;
      line.discountInput = 0;
      line.discountCtrl.text = '0';
      _syncPaidAmount();
    });
  }

  Future<void> _searchCustomers(String q) async {
    if (q.trim().length < 2) {
      setState(() => _customerSuggestions = []);
      return;
    }
    final res = await _api.getPosCustomers(search: q.trim(), pageSize: 8);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final items = (res['data'] as Map)['items'] as List? ?? [];
      setState(() {
        _customerSuggestions = items
            .map((e) => PosCustomer.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    }
  }

  Future<void> _openAddCustomer() async {
    final created = await showDialog<dynamic>(
      context: context,
      builder: (_) => const PosCustomerFormDialog(),
    );
    if (created == null || !mounted) return;
    if (created is Map<String, dynamic>) {
      final c = PosCustomer.fromJson(created);
      setState(() {
        _tab.customer = c;
        _tab._customerSearchCtrl.text = c.name;
        _customerSuggestions = [];
      });
    }
  }

  Future<void> _checkout() async {
    if (_tab.cart.isEmpty) return;

    final paid = _effectivePaidAmount;
    final due = (_total - paid).clamp(0, double.infinity);
    if (due > 0 && _tab.customer == null) {
      NotificationOverlayManager().showError(
        title: 'Thiếu khách hàng',
        message: 'Chọn khách hàng để ghi nợ phần còn thiếu (${_moneyFmt.format(due)})',
      );
      return;
    }

    setState(() => _checkingOut = true);

    final complete = _sellMode != _SellMode.normal;
    final body = <String, dynamic>{
      'lines': _tab.cart
          .map((c) => {
                'productId': c.product.id,
                if (c.variantId != null) 'variantId': c.variantId,
                if (c.unitId != null) 'unitId': c.unitId,
                'qty': c.qty,
                'unitPrice': c.unitPrice,
                if (c.discountAmount > 0) 'discountAmount': c.discountAmount,
                if (c.lineNote != null && c.lineNote!.isNotEmpty) 'lineNote': c.lineNote,
              })
          .toList(),
      'discount': _tab.discount,
      'paidAmount': paid > 0 ? paid : _total,
      'paymentMethod': _tab.paymentLines.length == 1
          ? _sourceByKey(_tab.paymentLines.first.sourceKey).methodLabel
          : _tab.paymentLines
              .where((p) => p.amount > 0)
              .map((p) => _sourceByKey(p.sourceKey).methodLabel)
              .join(' + '),
      'payments': _tab.paymentLines
          .where((p) => p.amount > 0)
          .map((p) {
            final src = _sourceByKey(p.sourceKey);
            return {
              'amount': p.amount,
              'paymentMethod': src.methodLabel,
              if (src.bankAccountId != null) 'bankAccountId': src.bankAccountId,
            };
          })
          .toList(),
      'note': _tab.note,
      'complete': complete,
      'isDelivery': _sellMode == _SellMode.delivery,
      if (_sellMode == _SellMode.delivery) ...{
        if (_tab.deliveryAddress != null && _tab.deliveryAddress!.isNotEmpty)
          'deliveryAddress': _tab.deliveryAddress,
        if (_tab.deliveryPhone != null && _tab.deliveryPhone!.isNotEmpty)
          'deliveryPhone': _tab.deliveryPhone,
        if (_tab.deliveryPartner != null && _tab.deliveryPartner!.isNotEmpty)
          'deliveryPartner': _tab.deliveryPartner,
      },
      if (_tab.customer != null) ...{
        'customerId': _tab.customer!.id,
        'customerName': _tab.customer!.name,
      },
      if ((_tab.sellerEmployeeId ?? _defaultSellerEmployeeId) != null)
        'soldByEmployeeId': _tab.sellerEmployeeId ?? _defaultSellerEmployeeId,
      'salesChannel': _sellMode == _SellMode.delivery
          ? 'Bán giao hàng'
          : _sellMode == _SellMode.normal
              ? 'Bán thường'
              : 'Bán nhanh',
    };

    final res = await _api.createPosSale(body);
    if (!mounted) return;
    setState(() => _checkingOut = false);

    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Thanh toán thất bại',
      );
      return;
    }

    final data = res['data'] as Map<String, dynamic>?;
    final orderId = data?['id']?.toString();
    final orderNo = data?['orderNo']?.toString() ?? '';

    NotificationOverlayManager().showSuccess(
      title: complete ? 'Thanh toán thành công' : 'Đã lưu đơn tạm',
      message: 'Mã đơn: $orderNo',
    );

    if (orderId != null && _printSettings.autoPrint) {
      await _maybePrintOrder(orderId);
    }

    if (_sellMode == _SellMode.normal && orderId != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PosSaleOrderEditorScreen(orderId: orderId),
        ),
      );
    }

    setState(() {
      _tab.reset();
      _tab.sellerEmployeeId = _defaultSellerEmployeeId;
      _syncPaidAmount();
    });
  }

  Future<void> _maybePrintOrder(String orderId) async {
    final res = await _api.getPosSale(orderId);
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    final order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
    await printPosSaleOrder(
      context: context,
      order: order,
      branchName: _storeSettings.storeName.isNotEmpty ? _storeSettings.storeName : null,
      storeAddress: _storeSettings.address.isNotEmpty ? _storeSettings.address : null,
      storePhone: _storeSettings.phone.isNotEmpty ? _storeSettings.phone : null,
      mergeSameItems: _printSettings.mergeSameItems,
      copies: _printSettings.copies,
      templateId: _printSettings.templateId,
    );
  }

  Future<void> _openPrintSettings() async {
    final box = _printBtnKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = box?.localToGlobal(Offset.zero) ?? const Offset(200, 60);
    final updated = await showPosSellPrintPopover(
      context,
      initial: _printSettings,
      anchor: Offset(offset.dx - 260, offset.dy + (box?.size.height ?? 40)),
    );
    if (updated != null && mounted) setState(() => _printSettings = updated);
  }

  Future<void> _openStoreSettings() async {
    final updated = await showPosSellStoreSettingsDialog(
      context,
      initial: _storeSettings,
    );
    if (updated == null || !mounted) return;
    await updated.save();
    setState(() => _storeSettings = updated);
  }

  Future<void> _openPosMenu() async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canCash = perm.canCreate('CashTransaction') ||
        (perm.isLoaded && perm.canView('CashTransaction'));
    final canReturn = perm.canEdit('PosProducts') || perm.canCreate('PosSell');
    final canReport = perm.canView('PosSalesReport') || perm.canView('PosProducts');

    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final topRight = box != null && overlay != null
        ? box.localToGlobal(box.size.topRight(Offset.zero), ancestor: overlay)
        : Offset(MediaQuery.sizeOf(context).width - 8, 56);

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(topRight.dx - 240, topRight.dy, topRight.dx, topRight.dy + 8),
      items: [
        const PopupMenuItem(
          value: 'store_settings',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.store_outlined, size: 20),
            title: Text('Thiết lập cửa hàng'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'eod',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.summarize_outlined, size: 20),
            title: Text('Xem báo cáo cuối ngày'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canReport)
          const PopupMenuItem(
            value: 'reports',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.analytics_outlined, size: 20),
              title: Text('Báo cáo doanh thu / tồn kho'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canReturn)
          const PopupMenuItem(
            value: 'pick_return',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.assignment_return_outlined, size: 20),
              title: Text('Chọn hóa đơn trả hàng'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canReturn)
          const PopupMenuItem(
            value: 'return',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.keyboard_return, size: 20),
              title: Text('Trả hàng'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canCash)
          const PopupMenuItem(
            value: 'receipt',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.call_received, size: 20, color: Colors.green),
              title: Text('Lập phiếu thu'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canCash)
          const PopupMenuItem(
            value: 'payment',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.call_made, size: 20, color: Colors.red),
              title: Text('Lập phiếu chi'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'store_settings':
        await _openStoreSettings();
      case 'eod':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PosEndOfDayScreen()),
        );
      case 'reports':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PosReportsScreen()),
        );
      case 'pick_return':
        final order = await showPosPickSaleOrderDialog(context);
        if (!mounted || order == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PosSaleReturnScreen(orderId: order.id)),
        );
      case 'return':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PosSaleReturnScreen()),
        );
      case 'receipt':
        final customer = _tab.customer?.name;
        await showPosCashVoucherDialog(
          context,
          type: CashTransactionType.income,
          contactName: customer,
        );
      case 'payment':
        await showPosCashVoucherDialog(
          context,
          type: CashTransactionType.expense,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canSell = perm.canView('PosSell') || perm.canView('PosProducts');
    if (!canSell) {
      return const Scaffold(
        body: Center(child: Text('Bạn không có quyền truy cập màn hình bán hàng')),
      );
    }

    return PosBarcodeKeyboardScope(
      enabled: !_checkingOut,
      ignoreFocusNodes: [_customerSearchFocus],
      onBarcode: _onBarcodeScanned,
      child: Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1024;
            final isMobile = Responsive.isMobile(context);
            final isNormal = _sellMode == _SellMode.normal;
            if (isMobile && !wide) {
              return _buildMobileShell(perm, isNormal);
            }
            return Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: wide
                      ? (isNormal
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: PosSellProductGrid(
                                    key: _productGridKey,
                                    api: _api,
                                    onPick: (pick) => _addPick(pick),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: _buildNormalOrderPanel(perm),
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _buildCartPanel(showFooterTotal: false),
                                ),
                                Expanded(
                                  child: _buildPaymentSidebar(
                                    perm,
                                    width: constraints.maxWidth * 0.5,
                                  ),
                                ),
                              ],
                            ))
                      : Column(
                          children: [
                            Expanded(
                              flex: isNormal ? 5 : 3,
                              child: isNormal
                                  ? PosSellProductGrid(
                                      key: _productGridKey,
                                      api: _api,
                                      onPick: (pick) => _addPick(pick),
                                    )
                                  : _buildCartPanel(showFooterTotal: false),
                            ),
                            if (isNormal)
                              SizedBox(
                                height: 360,
                                child: _buildNormalOrderPanel(perm, compact: true),
                              )
                            else
                              _buildPaymentSidebar(
                                perm,
                                width: constraints.maxWidth,
                                compact: true,
                              ),
                          ],
                        ),
                ),
                _buildBottomBar(),
              ],
            );
          },
        ),
      ),
    ),
    );
  }

  Widget _buildTopBar() {
    return Material(
      color: _kiotBlue,
      child: Container(
        height: _KiotLayout.topBarHeight,
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: PosPurchaseProductSearchBar(
                  api: _api,
                  sellMode: true,
                  focusNode: _productSearchFocus,
                  hintText: 'Tìm hàng hóa (F3)',
                  onPick: (pick) => _addPick(pick),
                  onBarcodePick: (pick) => _addPick(pick, mergeIfSame: true),
                  onAddProduct: _openNewProduct,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 36,
                child: Scrollbar(
                  controller: _tabScrollCtrl,
                  thumbVisibility: true,
                  interactive: true,
                  child: ListView(
                    controller: _tabScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    children: [
                      for (var i = 0; i < _tabs.length; i++) ...[
                        _invoiceTabChip(i),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Thêm hóa đơn',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _kiotBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 22),
                        onPressed: _newTab,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Thêm',
              icon: const Icon(Icons.menu, size: 24, color: Colors.white),
              onPressed: _openPosMenu,
            ),
            IconButton(
              key: _printBtnKey,
              visualDensity: VisualDensity.compact,
              tooltip: 'Thiết lập in',
              icon: const Icon(Icons.print_outlined, size: 22, color: Colors.white),
              onPressed: _openPrintSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _invoiceTabChip(int index) {
    final active = index == _activeTab;
    final tab = _tabs[index];
    return Material(
      color: active ? Colors.white : Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _selectTab(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? _kiotBlue : Colors.white,
                ),
              ),
              if (_tabs.length > 1) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _closeTab(index),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: active ? Colors.grey.shade600 : Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartPanel({required bool showFooterTotal}) {
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildKiotCartList()),
          if (showFooterTotal) _buildCartFooter(),
        ],
      ),
    );
  }

  Widget _buildCartFooter() {
    _recalcTotals();
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: _KiotLayout.sidePadding),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: PosTheme.border)),
        color: Color(0xFFFAFBFC),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, size: 16, color: PosTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _tab._noteCtrl,
              decoration: const InputDecoration(
                hintText: 'Ghi chú đơn hàng',
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => _tab.note = v.trim().isEmpty ? null : v,
            ),
          ),
          Text(
            'Tổng tiền hàng (${_tab.cart.length})',
            style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary),
          ),
          const SizedBox(width: 10),
          Text(
            _moneyFmt.format(_total),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kiotBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildCartHeader() {
    const hdr = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: PosTheme.textSecondary,
    );
    return Container(
      height: _KiotLayout.cartHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: _KiotLayout.sidePadding),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: _KiotLayout.wStt, child: const Text('STT', style: hdr)),
          SizedBox(width: _KiotLayout.wDel),
          SizedBox(width: _KiotLayout.wDel + _KiotLayout.wImg + _KiotLayout.gapAfterImg),
          const Expanded(child: Text('Mặt hàng / Mã vạch', style: hdr)),
          SizedBox(
            width: _KiotLayout.wQty,
            child: const Text('SL', style: hdr, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _KiotLayout.wUnit,
            child: const Text('ĐVT', style: hdr, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _KiotLayout.wPrice,
            child: const Text('Đơn giá', style: hdr, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _KiotLayout.wTotal,
            child: const Text('Thành tiền', style: hdr, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildKiotCartList() {
    if (_tab.cart.isEmpty) {
      return Center(
        child: Text(
          'Tìm và thêm hàng hóa vào hóa đơn',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final needHScroll = box.maxWidth < _KiotLayout.tableMinWidth;
        Widget table = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCartHeader(),
            Expanded(
              child: Scrollbar(
                thumbVisibility: _tab.cart.length > 7,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _tab.cart.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 12, endIndent: 12, color: PosTheme.border),
                  itemBuilder: (ctx, i) {
                    final line = _tab.cart[_tab.cart.length - 1 - i];
                    final index = _tab.cart.length - i;
                    return _buildKiotCartRow(line, index, _tab.cart.length - 1 - i);
                  },
                ),
              ),
            ),
          ],
        );
        if (!needHScroll) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _KiotLayout.tableMinWidth,
            child: table,
          ),
        );
      },
    );
  }

  Widget _buildKiotCartRow(_SellCartLine line, int index, int cartIndex) {
    final isExpanded = _expandedCartRowId == line.rowId;
    final noteExpanded = isExpanded && _expandedCartMode == _CartRowExpand.note;
    final priceExpanded = isExpanded && _expandedCartMode == _CartRowExpand.priceDiscount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _KiotLayout.cartRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _KiotLayout.sidePadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _KiotLayout.wStt,
                  child: Text('$index',
                      style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
                ),
                SizedBox(
                  width: _KiotLayout.wDel,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    onPressed: () => _removeLine(cartIndex),
                  ),
                ),
                PosProductImage(
                  productId: line.product.id,
                  imageUrl: line.product.imageUrl,
                  size: _KiotLayout.wImg,
                  borderRadius: 4,
                ),
                SizedBox(width: _KiotLayout.gapAfterImg),
                Expanded(
                  child: InkWell(
                    onTap: () => _toggleCartRowExpand(line.rowId, _CartRowExpand.note),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(line.product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: noteExpanded ? _kiotBlue : null,
                              decoration: noteExpanded
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationColor: _kiotBlue,
                            )),
                        if (line.displayCode.isNotEmpty)
                          Text(line.displayCode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: PosTheme.textSecondary)),
                        Text(
                          'Tồn: ${_qtyFmt.format(line.product.onHandQty)}',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            color: line.product.onHandQty <= 0
                                ? Colors.red.shade700
                                : PosTheme.textSecondary,
                          ),
                        ),
                        if (!noteExpanded &&
                            line.lineNote != null &&
                            line.lineNote!.isNotEmpty)
                          Text('↳ ${line.lineNote}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: _kiotBlue)),
                        if (!priceExpanded && line.discountAmount > 0)
                          Text(
                            'CK: -${_moneyFmt.format(line.discountAmount)}',
                            style: TextStyle(fontSize: 10, color: Colors.red.shade700),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: _KiotLayout.wQty,
                  child: Center(child: _qtyControls(line)),
                ),
                SizedBox(
                  width: _KiotLayout.wUnit,
                  child: Center(child: _unitDropdown(line)),
                ),
                SizedBox(
                  width: _KiotLayout.wPrice,
                  child: InkWell(
                    onTap: () =>
                        _toggleCartRowExpand(line.rowId, _CartRowExpand.priceDiscount),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _moneyFmt.format(line.unitPrice),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            color: _kiotBlue,
                            decoration: priceExpanded
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            decorationColor: _kiotBlue,
                          ),
                        ),
                        if (line.discountAmount > 0 && !priceExpanded)
                          Text(
                            '-${_moneyFmt.format(line.discountAmount)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 10, color: Colors.red.shade700),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: _KiotLayout.wTotal,
                  child: InkWell(
                    onTap: () =>
                        _toggleCartRowExpand(line.rowId, _CartRowExpand.priceDiscount),
                    child: Text(
                      _moneyFmt.format(line.lineTotal),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: priceExpanded ? _kiotBlue : PosTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (noteExpanded) _buildCartLineNoteEditor(line),
        if (priceExpanded) _buildCartLinePriceEditor(line),
      ],
    );
  }

  Widget _buildCartLineNoteEditor(_SellCartLine line) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(
            _KiotLayout.sidePadding, 0, _KiotLayout.sidePadding, 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: PosTheme.kiotBlueLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _kiotBlue.withValues(alpha: 0.25)),
        ),
        child: PosLineQuickNotesPicker(
          quickNotes: line.product.saleQuickNotes,
          selected: line.selectedQuickNotes,
          onSelectedChanged: (next) => setState(() {
            line.selectedQuickNotes
              ..clear()
              ..addAll(next);
            _applyLineNoteFromPicker(line);
          }),
          extraController: line.noteCtrl,
          onExtraChanged: () => setState(() => _applyLineNoteFromPicker(line)),
        ),
      ),
    );
  }

  Widget _buildCartLinePriceEditor(_SellCartLine line) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(
            _KiotLayout.sidePadding, 0, _KiotLayout.sidePadding, 6),
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
                const Text('Đơn giá', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                    onChanged: (v) => setState(() => _applyLinePriceInput(line, v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Chiết khấu', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                _lineDiscountChip(line, true),
                const SizedBox(width: 4),
                _lineDiscountChip(line, false),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.discountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      suffixText: line.discountIsPercent ? '%' : 'đ',
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) => setState(() {
                      line.discountInput = _parseMoneyInput(v);
                      _syncPaidAmount();
                    }),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: line.discountIsPercent
                  ? buildPosDiscountPresetChips(
                      percents: const [5, 10, 15, 20, 25, 50],
                      onPickPercent: (p) => _applyLineDiscountPreset(line, p),
                    )
                  : buildPosDiscountMoneyPresetChips(
                      moneyFmt: _moneyFmt,
                      baseAmount: line.lineGross,
                      onPickAmount: (a) => _applyLineDiscountAmountPreset(line, a),
                    ),
            ),
            if (line.discountAmount > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Chiết khấu dòng: -${_moneyFmt.format(line.discountAmount)}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _lineDiscountChip(_SellCartLine line, bool isPercent) {
    final selected = line.discountIsPercent == isPercent;
    return Material(
      color: selected ? PosTheme.kiotBlueLight : Colors.white,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: () => _setLineDiscountMode(line, isPercent),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: selected ? _kiotBlue : PosTheme.border),
          ),
          child: Text(
            isPercent ? '%' : 'đ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? _kiotBlue : PosTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNormalOrderPanel(PermissionProvider perm, {bool compact = false}) {
    _recalcTotals();
    final canPay = perm.canCreate('PosSell') || perm.canCreate('PosProducts');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: compact
            ? const Border(top: BorderSide(color: PosTheme.border))
            : const Border(left: BorderSide(color: PosTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: _buildKiotCartList(),
          ),
          Container(
            height: 36,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: PosTheme.border)),
              color: Color(0xFFFAFBFC),
            ),
            padding: const EdgeInsets.symmetric(horizontal: _KiotLayout.sidePadding),
            child: Row(
              children: [
                const Icon(Icons.edit_outlined, size: 15, color: PosTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _tab._noteCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Ghi chú đơn hàng',
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) => _tab.note = v.trim().isEmpty ? null : v,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                _KiotLayout.sidePadding,
                6,
                _KiotLayout.sidePadding,
                4,
              ),
              children: [_buildPaymentSummaryContent()],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _KiotLayout.sidePadding,
              0,
              _KiotLayout.sidePadding,
              12,
            ),
            child: FilledButton(
              onPressed: _tab.cart.isEmpty || _checkingOut || !canPay ? null : _checkout,
              style: FilledButton.styleFrom(
                backgroundColor: _kiotBlue,
                minimumSize: Size(double.infinity, compact ? 44 : 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: _checkingOut
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('THANH TOÁN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitDropdown(_SellCartLine line) {
    if (line.unitViews.length <= 1) {
      return Text(
        line.unitLabel,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: _kiotBlue),
      );
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: line.activeViewKey,
        isDense: true,
        isExpanded: true,
        alignment: Alignment.center,
        style: const TextStyle(fontSize: 12, color: _kiotBlue),
        selectedItemBuilder: (ctx) => line.unitViews
            .map((v) => Center(
                  child: Text(
                    v.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _kiotBlue),
                  ),
                ))
            .toList(),
        items: line.unitViews
            .map((v) => DropdownMenuItem(
                  value: v.viewKey,
                  alignment: Alignment.center,
                  child: Text(v.label, textAlign: TextAlign.center),
                ))
            .toList(),
        onChanged: (key) {
          if (key == null) return;
          final view = line.unitViews.firstWhere((v) => v.viewKey == key);
          _switchUnit(line, view);
        },
      ),
    );
  }

  Widget _buildPaymentSummaryContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _tab._customerSearchCtrl,
                focusNode: _customerSearchFocus,
                decoration: InputDecoration(
                  hintText: 'Tìm khách hàng (F4)',
                  isDense: true,
                  prefixIcon: const Icon(Icons.person_search_outlined, size: 18),
                  suffixIcon: _tab.customer != null
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() {
                            _tab.customer = null;
                            _tab._customerSearchCtrl.clear();
                            _customerSuggestions = [];
                          }),
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                style: const TextStyle(fontSize: 12),
                onChanged: _searchCustomers,
              ),
            ),
            IconButton(
              tooltip: 'Thêm khách hàng',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.person_add_outlined, size: 20, color: _kiotBlue),
              onPressed: _openAddCustomer,
            ),
          ],
        ),
        if (_customerSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              border: Border.all(color: PosTheme.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView(
              shrinkWrap: true,
              children: _customerSuggestions
                  .map((c) => ListTile(
                        dense: true,
                        title: Text(c.name, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          [c.phone, c.customerCode]
                              .where((e) => e != null && e.isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => setState(() {
                          _tab.customer = c;
                          _tab._customerSearchCtrl.text = c.name;
                          _customerSuggestions = [];
                          if (_sellMode == _SellMode.delivery) {
                            if (c.phone != null && c.phone!.isNotEmpty) {
                              _tab.deliveryPhone = c.phone;
                              _tab._deliveryPhoneCtrl.text = c.phone!;
                            }
                            if (c.address != null && c.address!.isNotEmpty) {
                              _tab.deliveryAddress = c.address;
                              _tab._deliveryAddressCtrl.text = c.address!;
                            }
                          }
                        }),
                      ))
                  .toList(),
            ),
          ),
        if (_sellSellers.isNotEmpty) ...[
          const SizedBox(height: 6),
          _canPickSeller
              ? DropdownButtonFormField<String>(
                  value: _tab.sellerEmployeeId ?? _defaultSellerEmployeeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Người bán',
                    isDense: true,
                    prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  items: _sellSellers
                      .map((s) => DropdownMenuItem<String>(
                            value: s['employeeId']?.toString(),
                            child: Text(
                              s['displayName']?.toString() ?? '—',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .where((item) => item.value != null && item.value!.isNotEmpty)
                      .toList(),
                  onChanged: (v) => setState(() => _tab.sellerEmployeeId = v),
                )
              : _summaryRow(
                  'Người bán',
                  _sellSellers
                          .where((s) =>
                              s['employeeId']?.toString() ==
                              (_tab.sellerEmployeeId ?? _defaultSellerEmployeeId))
                          .map((s) => s['displayName']?.toString())
                          .firstOrNull ??
                      '—',
                ),
        ],
        const SizedBox(height: 6),
        _summaryRow('Tổng tiền hàng (${_tab.cart.length})', _moneyFmt.format(_subTotal)),
        if (_lineDiscountTotal > 0) ...[
          const SizedBox(height: 2),
          _summaryRow('Chiết khấu SP', '-${_moneyFmt.format(_lineDiscountTotal)}'),
        ],
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              width: 82,
              child: Text('Giảm giá', style: TextStyle(fontSize: 12)),
            ),
            _discountModeChip('%', true),
            const SizedBox(width: 4),
            _discountModeChip('đ', false),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _tab._discountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  suffixText: _tab.discountIsPercent ? '%' : 'đ',
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: _onDiscountInputChanged,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _tab.discountIsPercent
              ? buildPosDiscountPresetChips(onPickPercent: _applyOrderDiscountPreset)
              : buildPosDiscountMoneyPresetChips(
                  moneyFmt: _moneyFmt,
                  baseAmount: _afterLineDiscount,
                  onPickAmount: _applyOrderDiscountAmountPreset,
                ),
        ),
        if (_tab.discount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Chiết khấu đơn: -${_moneyFmt.format(_tab.discount)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
        if (_sellMode == _SellMode.delivery) ...[
          const SizedBox(height: 12),
          const Text('Giao hàng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _tab._deliveryPhoneCtrl,
            decoration: const InputDecoration(
              hintText: 'SĐT người nhận',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: (v) => _tab.deliveryPhone = v.trim().isEmpty ? null : v.trim(),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _tab._deliveryAddressCtrl,
            decoration: const InputDecoration(
              hintText: 'Địa chỉ giao hàng',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            maxLines: 2,
            onChanged: (v) => _tab.deliveryAddress = v.trim().isEmpty ? null : v.trim(),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _tab._deliveryPartnerCtrl,
            decoration: const InputDecoration(
              hintText: 'Đối tác giao (GHN, GHTK...)',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: (v) => _tab.deliveryPartner = v.trim().isEmpty ? null : v.trim(),
          ),
        ],
        const SizedBox(height: 6),
        _summaryRow('VAT', _moneyFmt.format(_vatAmount)),
        const SizedBox(height: 6),
        _summaryRow('Khách cần trả', _moneyFmt.format(_total), bold: true, blue: true),
        if (_tab.customer != null && _tab.customer!.currentDebt > 0) ...[
          const SizedBox(height: 4),
          _summaryRow('Nợ cũ KH', _moneyFmt.format(_tab.customer!.currentDebt)),
        ],
        const SizedBox(height: 6),
        _buildPaymentSplits(),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _summaryRow(
            'Tổng thanh toán',
            _moneyFmt.format(_effectivePaidAmount),
            bold: true,
          ),
        ),
        if (_changeAmount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _summaryRow('Tiền trả khách', _moneyFmt.format(_changeAmount)),
          ),
        if (_dueAmount > 0) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _summaryRow('Nợ đơn này', _moneyFmt.format(_dueAmount),
                bold: true, blue: true),
          ),
          if (_tab.customer != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _summaryRow(
                'Tổng nợ sau đơn',
                _moneyFmt.format(_tab.customer!.currentDebt + _dueAmount),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildPaymentSplits() {
    if (_tab.paymentLines.isEmpty) {
      _tab.paymentLines.add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Thanh toán (nhiều nguồn)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: _addPaymentLine,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Thêm', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        ..._tab.paymentLines.asMap().entries.map((entry) {
          final index = entry.key;
          final pay = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _paymentSources.any((s) => s.key == pay.sourceKey)
                          ? pay.sourceKey
                          : _PosPaymentSource.cashKey,
                      isExpanded: true,
                      isDense: true,
                      style: const TextStyle(fontSize: 12, color: PosTheme.textPrimary),
                      items: _paymentSources
                          .map((s) => DropdownMenuItem(
                                value: s.key,
                                child: Text(
                                  s.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => pay.sourceKey = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: pay.amountCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) => _onPaymentLineAmountChanged(pay, v),
                  ),
                ),
                if (_tab.paymentLines.length > 1)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    onPressed: () => _removePaymentLine(index),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _addPaymentLine() {
    setState(() {
      _tab.paymentsManuallyEdited = true;
      final src = _paymentSources.length > 1
          ? _paymentSources[1]
          : _PosPaymentSource.cash;
      final line = _SellPaymentLine(sourceKey: src.key);
      final remain = (_total - _effectivePaidAmount).clamp(0, double.infinity);
      line.amount = remain.toDouble();
      line.amountCtrl.text = remain > 0 ? _moneyFmt.format(remain) : '';
      _tab.paymentLines.add(line);
    });
  }

  void _removePaymentLine(int index) {
    setState(() {
      _tab.paymentLines[index].dispose();
      _tab.paymentLines.removeAt(index);
      _tab.paymentsManuallyEdited = true;
    });
  }

  void _onPaymentLineAmountChanged(_SellPaymentLine pay, String raw) {
    setState(() {
      _tab.paymentsManuallyEdited = true;
      pay.amount = _parseMoneyInput(raw);
    });
  }

  Widget _qtyControls(_SellCartLine line) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          icon: const Icon(Icons.remove, size: 15),
          onPressed: () => _adjustQty(line, -1),
        ),
        SizedBox(
          width: 36,
          child: Text(
            line.qty == line.qty.roundToDouble()
                ? line.qty.toStringAsFixed(0)
                : line.qty.toStringAsFixed(2),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          icon: const Icon(Icons.add, size: 15, color: _kiotBlue),
          onPressed: () => _adjustQty(line, 1),
        ),
      ],
    );
  }

  Widget _buildPaymentSidebar(PermissionProvider perm, {required double width, bool compact = false}) {
    _recalcTotals();
    final canPay = perm.canCreate('PosSell') || perm.canCreate('PosProducts');

    final summary = _buildPaymentSummaryContent();

    final payButton = FilledButton(
      onPressed: _tab.cart.isEmpty || _checkingOut || !canPay ? null : _checkout,
      style: FilledButton.styleFrom(
        backgroundColor: _kiotBlue,
        minimumSize: Size(double.infinity, compact ? 44 : 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: _checkingOut
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Text('THANH TOÁN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
    );

    return Container(
      width: compact ? double.infinity : width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: compact
            ? const Border(top: BorderSide(color: PosTheme.border))
            : const Border(left: BorderSide(color: PosTheme.border)),
      ),
      child: compact
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                _KiotLayout.sidePadding,
                10,
                _KiotLayout.sidePadding,
                10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [summary, payButton],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      _KiotLayout.sidePadding,
                      8,
                      _KiotLayout.sidePadding,
                      6,
                    ),
                    children: [summary],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _KiotLayout.sidePadding,
                    0,
                    _KiotLayout.sidePadding,
                    14,
                  ),
                  child: payButton,
                ),
              ],
            ),
    );
  }

  Widget _discountModeChip(String label, bool isPercent) {
    final selected = _tab.discountIsPercent == isPercent;
    return Material(
      color: selected ? PosTheme.kiotBlueLight : Colors.white,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: () => _setDiscountMode(isPercent),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: selected ? _kiotBlue : PosTheme.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? _kiotBlue : PosTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, bool blue = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: bold ? 16 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: blue ? _kiotBlue : PosTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Mobile layout (Android / iOS) ───────────────────────────────────────

  Widget _buildMobileShell(PermissionProvider perm, bool isNormal) {
    _recalcTotals();
    final inHub = PosHubScope.of(context);
    return Column(
      children: [
        _buildMobileTopBar(),
        Expanded(
          child: _mobilePage == 0
              ? PosSellProductGrid(
                  key: _productGridKey,
                  api: _api,
                  onPick: (pick) => _addPick(pick),
                )
              : (isNormal
                  ? _buildMobileCartCheckout(perm)
                  : _buildPaymentSidebar(
                      perm,
                      width: MediaQuery.sizeOf(context).width,
                      compact: true,
                    )),
        ),
        if (_mobilePage == 0 && _tab.cart.isNotEmpty) _buildMobileFloatingCartBar(),
        if (inHub && _mobilePage == 0) _buildMobileModePill(),
        if (!inHub) _buildMobilePageNav(),
        if (!inHub) _buildMobileModeBar(),
      ],
    );
  }

  Widget _buildMobileTopBar() {
    return Material(
      color: _kiotBlue,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: PosPurchaseProductSearchBar(
                        api: _api,
                        sellMode: true,
                        focusNode: _productSearchFocus,
                        hintText: 'Tìm hàng / quét mã',
                        onPick: (pick) => _addPick(pick),
                        onBarcodePick: (pick) =>
                            _addPick(pick, mergeIfSame: true),
                        onAddProduct: _openNewProduct,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: _openPosMenu,
                  ),
                  IconButton(
                    key: _printBtnKey,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.print_outlined,
                        color: Colors.white, size: 22),
                    onPressed: _openPrintSettings,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildMobileCustomerPriceRows(),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView(
                  controller: _tabScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _tabs.length; i++) ...[
                      _invoiceTabChip(i),
                      const SizedBox(width: 6),
                    ],
                    Material(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _newTab,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(Icons.add, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCustomerPriceRows() {
    return Column(
      children: [
        _mobileSelectRow(
          icon: Icons.person_outline,
          label: _tab.customer?.name ?? 'Khách lẻ',
          onTap: () => setState(() => _mobilePage = 1),
        ),
        const SizedBox(height: 6),
        _mobileSelectRow(
          icon: Icons.sell_outlined,
          label: 'Bảng giá chung',
          onTap: () {
            NotificationOverlayManager().showInfo(
              title: 'Bảng giá',
              message: 'Đang dùng bảng giá chung của cửa hàng',
            );
          },
        ),
      ],
    );
  }

  Widget _mobileSelectRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMobilePaymentScreen(PermissionProvider perm) async {
    if (_tab.cart.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: const Text('Thanh toán'),
            backgroundColor: Colors.white,
            foregroundColor: PosTheme.textPrimary,
            elevation: 0,
          ),
          body: _buildPaymentSidebar(
            perm,
            width: MediaQuery.sizeOf(ctx).width,
            compact: true,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileFloatingCartBar() {
    return Material(
      elevation: 4,
      color: Colors.white,
      child: InkWell(
        onTap: () => setState(() => _mobilePage = 1),
        child: Container(
          height: PosTheme.mobileCartBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: PosTheme.border)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _kiotBlue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_tab.cart.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_tab.cart.length} món · ${_moneyFmt.format(_total)} đ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: PosTheme.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.shopping_cart_checkout,
                  color: _kiotBlue, size: 20),
              const SizedBox(width: 4),
              const Text(
                'Giỏ hàng',
                style: TextStyle(
                  color: _kiotBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobilePageNav() {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: PosTheme.mobileBottomNavHeight,
          child: Row(
            children: [
              Expanded(
                child: _mobileNavItem(
                  index: 0,
                  icon: Icons.grid_view_rounded,
                  label: 'Sản phẩm',
                ),
              ),
              Expanded(
                child: _mobileNavItem(
                  index: 1,
                  icon: Icons.receipt_long_outlined,
                  label: 'Giỏ hàng',
                  badge: _tab.cart.length,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileNavItem({
    required int index,
    required IconData icon,
    required String label,
    int badge = 0,
  }) {
    final active = _mobilePage == index;
    return InkWell(
      onTap: () => setState(() => _mobilePage = index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                icon,
                size: 22,
                color: active ? _kiotBlue : PosTheme.textSecondary,
              ),
              if (badge > 0)
                Positioned(
                  right: -8,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? _kiotBlue : PosTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileModePill() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              _modePillTab('Đặt hàng', _SellMode.quick),
              _modePillTab('Bán hàng', _SellMode.normal),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_horiz, size: 20),
                onPressed: _openPosMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modePillTab(String label, _SellMode mode) {
    final active = _sellMode == mode ||
        (mode == _SellMode.normal && _sellMode == _SellMode.delivery);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _sellMode = mode),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? PosTheme.kiotBlueLight : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? PosTheme.kiotBlue : PosTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileModeBar() {
    return Material(
      color: const Color(0xFFF8FAFC),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: [
              _modeTab('Bán nhanh', _SellMode.quick, Icons.flash_on_outlined),
              const SizedBox(width: 8),
              _modeTab('Bán thường', _SellMode.normal, Icons.receipt_long_outlined),
              const SizedBox(width: 8),
              _modeTab(
                  'Giao hàng', _SellMode.delivery, Icons.local_shipping_outlined),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCartCheckout(PermissionProvider perm) {
    final canPay = perm.canCreate('PosSell') || perm.canCreate('PosProducts');
    final inHub = PosHubScope.of(context);
    return ColoredBox(
      color: const Color(0xFFF3F4F6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inHub)
            Material(
              color: Colors.white,
              child: ListTile(
                dense: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _mobilePage = 0),
                ),
                title: const Text(
                  'Giỏ hàng',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Expanded(
            child: _tab.cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'Giỏ hàng trống',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => setState(() => _mobilePage = 0),
                          icon: const Icon(Icons.add_shopping_cart, size: 18),
                          label: const Text('Chọn sản phẩm'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _tab.cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final cartIndex = _tab.cart.length - 1 - i;
                      final line = _tab.cart[cartIndex];
                      final index = _tab.cart.length - i;
                      return _buildMobileCartCard(line, index, cartIndex);
                    },
                  ),
          ),
          if (_tab.cart.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: PosTheme.border)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPaymentSummaryContent(),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tổng (${_tab.cart.length} món)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: PosTheme.textSecondary,
                                  ),
                                ),
                                Text(
                                  '${_moneyFmt.format(_total)} đ',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: _kiotBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _tab.cart.isEmpty ||
                                      _checkingOut ||
                                      !canPay
                                  ? null
                                  : () => _openMobilePaymentScreen(perm),
                              style: FilledButton.styleFrom(
                                backgroundColor: _kiotBlue,
                                minimumSize: const Size(0, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _checkingOut
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'THANH TOÁN',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileCartCard(
      _SellCartLine line, int index, int cartIndex) {
    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PosProductImage(
                productId: line.product.id,
                imageUrl: line.product.imageUrl,
                size: 52,
                borderRadius: 8,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (line.displayCode.isNotEmpty)
                      Text(
                        line.displayCode,
                        style: const TextStyle(
                          fontSize: 11,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${_moneyFmt.format(line.unitPrice)} đ / ${line.unitLabel}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kiotBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Colors.red),
                onPressed: () => _removeLine(cartIndex),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _mobileQtyButton(
                icon: Icons.remove,
                onTap: line.qty > 1
                    ? () => _adjustQty(line, -1)
                    : null,
              ),
              Expanded(
                child: Text(
                  _qtyFmt.format(line.qty),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _mobileQtyButton(
                icon: Icons.add,
                onTap: () => _adjustQty(line, 1),
                primary: true,
              ),
              const SizedBox(width: 12),
              Text(
                '${_moneyFmt.format(line.lineTotal)} đ',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: PosTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mobileQtyButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    return Material(
      color: primary
          ? _kiotBlue.withValues(alpha: 0.1)
          : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 36,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? Colors.grey.shade400
                : (primary ? _kiotBlue : PosTheme.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final isNormal = _sellMode == _SellMode.normal;
    if (Responsive.isMobile(context)) {
      return _buildMobileModeBar();
    }
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PosTheme.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isNormal)
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: PosTheme.border)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_outlined, size: 15, color: PosTheme.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _tab._noteCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Ghi chú đơn hàng',
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (v) => _tab.note = v.trim().isEmpty ? null : v,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              height: _KiotLayout.bottomBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Spacer(),
                  _modeTab('Bán nhanh', _SellMode.quick, Icons.flash_on_outlined),
                  const SizedBox(width: 8),
                  _modeTab('Bán thường', _SellMode.normal, Icons.receipt_long_outlined),
                  const SizedBox(width: 8),
                  _modeTab('Bán giao hàng', _SellMode.delivery, Icons.local_shipping_outlined),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeTab(String label, _SellMode mode, IconData icon) {
    final active = _sellMode == mode;
    return InkWell(
      onTap: () => setState(() => _sellMode = mode),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? PosTheme.kiotBlueLight : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? _kiotBlue : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? _kiotBlue : PosTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? _kiotBlue : PosTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
