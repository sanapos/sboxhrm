import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/cash_transaction.dart';
import '../models/pos_customer.dart';
import '../models/pos_price_list.dart';
import '../models/pos_product.dart';
import '../models/pos_print_template.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/responsive_helper.dart';
import '../utils/store_role_helper.dart';
import '../services/api_service.dart';
import '../services/pos_sell_catalog_cache.dart';
import '../utils/pos_purchase_product_lookup.dart';
import '../utils/pos_combo_stock.dart';
import '../utils/pos_kitchen_print.dart';
import '../utils/pos_print_config_session.dart';
import '../utils/pos_print_orchestrator.dart';
import '../utils/pos_sale_order_print.dart';
import '../utils/pos_sell_print_settings.dart';
import '../utils/pos_sell_stock_patch.dart';
import '../utils/pos_sell_store_settings.dart';
import '../utils/pos_sell_tax.dart';
import '../utils/pos_sell_unit_views.dart';
import '../utils/pos_vietqr_helper.dart';
import '../widgets/pos/pos_vietqr_payment_panel.dart';
import '../utils/pos_thermal_printer_settings.dart';
import '../utils/pos_price_list_resolver.dart';
import '../utils/pos_product_type_picker.dart';
import '../widgets/pos/pos_sell_mobile_print_settings_screen.dart';
import '../widgets/pos/pos_barcode_keyboard_scope.dart';
import '../widgets/pos_barcode_scanner.dart';
import '../widgets/pos/pos_sell_product_grid.dart';
import '../widgets/notification_overlay.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../utils/navigation_notifier.dart';
import '../screens/pos/pos_product_editor_page.dart';
import '../widgets/pos/pos_discount_editor_dialog.dart';
import '../widgets/pos/pos_customer_form_dialog.dart';
import '../widgets/pos/pos_product_image.dart';
import '../widgets/pos/pos_product_unit_view.dart';
import '../widgets/pos/pos_purchase_product_search_bar.dart';
import '../widgets/pos/pos_pending_warehouse_print_sheet.dart';
import '../widgets/pos/pos_sell_print_popover.dart';
import '../widgets/pos/pos_sell_store_settings_dialog.dart';
import '../widgets/pos/pos_sale_quick_notes_widgets.dart';
import '../widgets/pos/pos_serial_capture_dialog.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos/pos_hub_scope.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import 'pos/pos_end_of_day_screen.dart';
import 'pos_reports_screen.dart';
import 'pos_sale_return_screen.dart';
import 'pos_sale_return_list_screen.dart';
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

  factory _PosPaymentSource.fromVietQR(BankAccount account) {
    final short = account.bankShortName ?? account.bankName;
    return _PosPaymentSource(
      key: 'vietqr_${account.id}',
      label: 'VietQR · $short',
      methodLabel: 'VietQR',
      methodType: PaymentMethodType.vietQR,
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
    this.vatRate = 8,
    this.vatExempt = false,
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
  PosProduct product;
  String? variantId;
  String? unitId;
  PosProductVariant? variant;
  String activeViewKey;
  String unitLabel;
  String displayCode;
  double unitPrice;
  double qty;
  /// Số lượng đã gửi in báo kho (theo dòng giỏ hiện tại).
  double warehouseSlipPrintedQty = 0;
  List<PosProductUnitView> unitViews;
  String? lineNote;
  bool discountIsPercent;
  double discountInput;
  double vatRate;
  bool vatExempt;
  List<String> serialNumbers = [];
  List<String> serialImeis = [];
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
  double vatRate = 8;
  bool vatExempt = false;
  String paymentMethod = 'Tiền mặt';
  double paidAmount = 0;
  bool paidManuallyEdited = false;
  final List<_SellPaymentLine> paymentLines = [];
  bool paymentsManuallyEdited = false;
  String? note;
  PosCustomer? customer;
  String priceListLabel = 'Bảng giá chung';
  String? priceListId;
  String? deliveryAddress;
  String? deliveryPhone;
  String? deliveryPartner;
  String? sellerEmployeeId;
  String? voucherCode;
  double voucherDiscount = 0;
  String? voucherName;
  double pointsToRedeem = 0;
  double pointsDiscount = 0;
  String? draftOrderId;
  String? draftOrderNo;
  bool _voucherValidating = false;
  final _voucherCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController();
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
    _voucherCtrl.dispose();
    _pointsCtrl.dispose();
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

  void reset({double defaultVatRate = 8}) {
    for (final line in cart) {
      line.dispose();
    }
    cart.clear();
    _clearPaymentLines();
    paymentLines.add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
    discountIsPercent = false;
    discountInput = 0;
    discount = 0;
    vatRate = defaultVatRate;
    vatExempt = false;
    paymentMethod = 'Tiền mặt';
    paidAmount = 0;
    paidManuallyEdited = false;
    paymentsManuallyEdited = false;
    note = null;
    customer = null;
    priceListLabel = 'Bảng giá chung';
    priceListId = null;
    deliveryAddress = null;
    deliveryPhone = null;
    deliveryPartner = null;
    sellerEmployeeId = null;
    voucherCode = null;
    voucherDiscount = 0;
    voucherName = null;
    pointsToRedeem = 0;
    pointsDiscount = 0;
    draftOrderId = null;
    draftOrderNo = null;
    _voucherCtrl.clear();
    _pointsCtrl.clear();
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
  final _searchBarKey = GlobalKey<PosPurchaseProductSearchBarState>();
  final _tabScrollCtrl = ScrollController();
  final _productSearchFocus = FocusNode();
  final _customerSearchFocus = FocusNode();
  final _productGridKey = GlobalKey<PosSellProductGridState>();

  int _nextTabSeq = 2;
  final List<_SellInvoiceTab> _tabs = [_SellInvoiceTab(id: 1)];
  int _activeTab = 0;
  _SellMode _sellMode = _SellMode.quick;
  PosSellPrintSettings _printSettings = const PosSellPrintSettings();
  PosThermalPrinterSettings _thermalPrintSettings =
      const PosThermalPrinterSettings();
  PosSellStoreSettings _storeSettings = const PosSellStoreSettings();
  bool _checkingOut = false;
  bool _warehousePrinting = false;
  final List<PendingWarehousePrintJob> _failedWarehousePrints = [];
  final Set<String> _checkoutPrintGuard = {};
  bool _mobileMergeSameOnAdd = true;
  bool _mobileProductPickerOpen = false;
  List<PosCustomer> _customerSuggestions = [];
  List<_PosPaymentSource> _paymentSources = const [_PosPaymentSource.cash];
  List<BankAccount> _bankAccounts = [];
  int _nextCartRowId = 1;
  int? _expandedCartRowId;
  _CartRowExpand? _expandedCartMode;
  List<Map<String, dynamic>> _sellSellers = [];
  bool _canPickSeller = false;
  String? _defaultSellerEmployeeId;
  List<PosPriceList> _priceLists = [];
  final Map<String, Map<String, double>> _priceOverrideCache = {};
  int _expiringLotCount = 0;
  int _expiredLotCount = 0;
  bool _expiryBannerDismissed = false;
  _SellInvoiceTab get _tab => _tabs[_activeTab];

  String? get _storeId =>
      Provider.of<AuthProvider>(context, listen: false).user?.storeId;

  Map<String, double> get _currentPriceOverrides {
    final id = _tab.priceListId;
    if (id == null || id.isEmpty) return const {};
    return _priceOverrideCache[id] ?? const {};
  }

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
    PosPrintConfigSession.instance.warmUp();
    _loadPaymentSources();
    _loadSellSellers();
    _loadPriceLists();
    _loadExpiryLotSummary();
    HardwareKeyboard.instance.addHandler(_onKey);
    ScreenRefreshNotifier.posSellStockPatch.addListener(_syncCartStockFromPatch);
  }

  Future<void> _loadPaymentSources() async {
    var res = await _api.getPosBankAccounts();
    if (res['isSuccess'] != true) {
      res = await _api.getBankAccounts();
    }
    if (!mounted) return;

    final accounts = <BankAccount>[];
    if (res['isSuccess'] == true && res['data'] is List) {
      for (final raw in res['data'] as List) {
        final account = BankAccount.fromJson(raw as Map<String, dynamic>);
        if (account.isActive) accounts.add(account);
      }
    }

    final sources = <_PosPaymentSource>[_PosPaymentSource.cash];
    if (accounts.isNotEmpty) {
      final qrAccount = PosVietQrHelper.resolveAccount(
        accounts,
        preferredId: _storeSettings.vietQrBankAccountId,
      );
      if (qrAccount != null) {
        sources.add(_PosPaymentSource.fromVietQR(qrAccount));
      }
      for (final account in accounts) {
        sources.add(_PosPaymentSource.fromBank(account));
      }
    }

    setState(() {
      _bankAccounts = accounts;
      _paymentSources = sources;
    });
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

  Future<void> _loadPriceLists() async {
    final res = await _api.getPosPriceLists();
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      // Bảng giá lỗi không chặn bán hàng — dùng giá gốc SP
      return;
    }
    if (res['data'] is! List) return;

    final lists = (res['data'] as List)
        .map((e) => PosPriceList.fromJson(e as Map<String, dynamic>))
        .toList();
    PosPriceList? defaultList;
    for (final l in lists) {
      if (l.isDefault) {
        defaultList = l;
        break;
      }
    }
    defaultList ??= lists.isNotEmpty ? lists.first : null;

    setState(() {
      _priceLists = lists;
      if (_tab.priceListId == null && defaultList != null) {
        _tab.priceListId = defaultList.id;
        _tab.priceListLabel = defaultList.name;
      }
    });

    if (_tab.priceListId != null) {
      await _ensurePriceOverrides(_tab.priceListId!);
      if (mounted) _applyPriceListToCart();
    }
  }

  Future<Map<String, double>> _ensurePriceOverrides(String priceListId) async {
    final cached = _priceOverrideCache[priceListId];
    if (cached != null) return cached;

    final res = await _api.getPosPriceListResolvedPrices(priceListId);
    final map = res['isSuccess'] == true && res['data'] is List
        ? buildPosPriceOverrideMap(res['data'] as List)
        : <String, double>{};
    _priceOverrideCache[priceListId] = map;
    return map;
  }

  void _applyPriceListToCart() {
    final overrides = _currentPriceOverrides;
    if (overrides.isEmpty) return;
    for (final line in _tab.cart) {
      final price = resolvePosPriceListPrice(
        overrides,
        productId: line.product.id,
        variantId: line.variantId,
        unitId: line.unitId,
      );
      if (price != null) {
        line.unitPrice = price;
        line.priceCtrl.text = price == price.roundToDouble()
            ? price.toStringAsFixed(0)
            : price.toStringAsFixed(2);
      }
      if (line.unitViews != null) {
        line.unitViews = applyPosPriceListToViews(
          line.unitViews!,
          line.product,
          overrides,
        );
      }
    }
  }

  Future<void> _selectPriceList(PosPriceList list) async {
    await _ensurePriceOverrides(list.id);
    if (!mounted) return;
    setState(() {
      _tab.priceListId = list.id;
      _tab.priceListLabel = list.name;
      _applyPriceListToCart();
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
    ScreenRefreshNotifier.posSellStockPatch.removeListener(_syncCartStockFromPatch);
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
    final thermal = await PosThermalPrinterSettings.load();
    if (mounted) {
      setState(() {
        _printSettings = s;
        _thermalPrintSettings = thermal;
      });
      PosPrintConfigSession.instance.invalidate(warehouseTemplateOnly: true);
      PosPrintConfigSession.instance.warmUp(
        warehouseTemplateId: s.warehouseTemplateId,
      );
    }
  }

  Future<void> _loadStoreSettings() async {
    final s = await PosSellStoreSettings.load();
    if (mounted) {
      setState(() {
        _storeSettings = s;
        for (final t in _tabs) {
          t.vatRate = s.defaultVatRate;
        }
      });
    }
  }

  void _newTab() {
    setState(() {
      final tab = _SellInvoiceTab(id: _nextTabSeq++);
      tab.vatRate = _storeSettings.defaultVatRate;
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
        _tab.reset(defaultVatRate: _storeSettings.defaultVatRate);
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

  double get _merchandiseAfterPromo =>
      (_total - _tab.voucherDiscount - _tab.pointsDiscount).clamp(0, double.infinity);

  List<PosSellTaxLine> get _taxLines => _tab.cart
      .map((c) => PosSellTaxLine(
            lineTotal: c.lineTotal,
            vatRate: c.vatRate,
            vatExempt: c.vatExempt,
          ))
      .toList();

  double get _vatAmount {
    final net = _storeSettings.taxMode == PosSellTaxMode.perItem ? _total : _merchandiseAfterPromo;
    return PosSellTax.vatAmount(
      mode: _storeSettings.taxMode,
      netTotal: net,
      orderVatRate: _tab.vatRate,
      orderVatExempt: _tab.vatExempt,
      lines: _taxLines,
    );
  }

  double get _grandTotal {
    if (_storeSettings.taxMode == PosSellTaxMode.perItem) {
      final base = PosSellTax.grandTotal(
        mode: _storeSettings.taxMode,
        netTotal: _total,
        vatAmount: _vatAmount,
      );
      return (base - _tab.voucherDiscount - _tab.pointsDiscount).clamp(0, double.infinity);
    }
    return PosSellTax.grandTotal(
      mode: _storeSettings.taxMode,
      netTotal: _merchandiseAfterPromo,
      vatAmount: _vatAmount,
    );
  }

  double get _effectivePaidAmount {
    if (_tab.paymentLines.isNotEmpty) {
      return _tab.paymentLines.fold(0.0, (a, p) => a + p.amount);
    }
    final fromCtrl = _parseMoneyInput(_tab._paidCtrl.text);
    if (_tab._paidCtrl.text.trim().isNotEmpty) return fromCtrl;
    return _tab.paidAmount;
  }

  double get _changeAmount =>
      (_effectivePaidAmount - _grandTotal).clamp(0, double.infinity);

  double get _dueAmount =>
      (_grandTotal - _effectivePaidAmount).clamp(0, double.infinity);

  static double _parseMoneyInput(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.isEmpty) return 0;
    return double.tryParse(cleaned) ?? 0;
  }

  void _notifyPaymentUi(VoidCallback? onMutate) {
    if (onMutate != null) {
      onMutate();
    } else if (mounted) {
      setState(() {});
    }
  }

  double _cartQtyFor({
    required String productId,
    String? variantId,
    String? unitId,
  }) {
    return _tab.cart
        .where((l) =>
            l.product.id == productId &&
            l.variantId == variantId &&
            l.unitId == unitId)
        .fold(0.0, (a, l) => a + l.qty);
  }

  Map<String, double> _componentReservation({String? excludeProductId}) {
    final lines = <CartLineForStock>[];
    for (final l in _tab.cart) {
      if (excludeProductId != null && l.product.id == excludeProductId) continue;
      lines.add(
        CartLineForStock(
          productId: l.product.id,
          productType: l.product.productType,
          qty: l.qty,
          comboLines: l.product.comboLines ?? const [],
        ),
      );
    }
    return buildComponentReservation(lines);
  }

  bool _validateStockQty(
    PosProduct p,
    PosProductUnitView view,
    double requiredQty, {
    bool warnLow = true,
  }) {
    if (p.productType == PosProductType.service) {
      return true;
    }
    if (p.productType == PosProductType.combo) {
      final reserved = _componentReservation(excludeProductId: p.id);
      final err = comboStockErrorMessage(
        combo: p,
        requiredComboQty: requiredQty,
        componentReserved: reserved,
      );
      if (err != null) {
        NotificationOverlayManager().showError(
          title: 'Không đủ tồn combo',
          message: err,
        );
        return false;
      }
      return true;
    }
    if (view.onHandQty < requiredQty) {
      NotificationOverlayManager().showError(
        title: view.onHandQty <= 0 ? 'Hết hàng' : 'Không đủ tồn',
        message: '${p.name} (${view.label}): còn ${_qtyFmt.format(view.onHandQty)}, '
            'cần ${_qtyFmt.format(requiredQty)}',
      );
      return false;
    }
    if (warnLow &&
        p.minStockQty > 0 &&
        view.onHandQty - requiredQty < p.minStockQty &&
        view.onHandQty > 0) {
      NotificationOverlayManager().showWarning(
        title: 'Sắp hết hàng',
        message:
            '${p.name} sẽ còn ${_qtyFmt.format(view.onHandQty - requiredQty)} sau khi bán',
      );
    }
    return true;
  }

  bool _validateStockForAdd(
    PosProduct p,
    PosProductUnitView view, {
    required double addQty,
  }) {
    final inCart = _cartQtyFor(
      productId: p.id,
      variantId: view.variantId,
      unitId: view.unitId,
    );
    return _validateStockQty(p, view, inCart + addQty);
  }

  bool _validateFullCartStock() {
    final seen = <String>{};
    for (final line in _tab.cart) {
      final key = '${line.product.id}|${line.variantId}|${line.unitId}';
      if (seen.contains(key)) continue;
      seen.add(key);
      final total = _cartQtyFor(
        productId: line.product.id,
        variantId: line.variantId,
        unitId: line.unitId,
      );
      if (!_validateStockQty(
        line.product,
        line.activeView,
        total,
        warnLow: false,
      )) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loadExpiryLotSummary() async {
    final res = await _api.getPosStockLotsExpiringSummary(days: 30);
    if (!mounted || res['isSuccess'] != true) return;
    final data = res['data'];
    if (data is! Map) return;
    setState(() {
      _expiringLotCount =
          (data['expiringSoonLotCount'] ?? data['ExpiringSoonLotCount'] as num?)?.toInt() ?? 0;
      _expiredLotCount =
          (data['expiredLotCount'] ?? data['ExpiredLotCount'] as num?)?.toInt() ?? 0;
    });
  }

  Future<void> _maybeWarnProductExpiry(PosProduct p, {String? variantId}) async {
    if (!p.trackExpiry) return;
    final res = await _api.getPosStockLotsByProduct(p.id, variantId: variantId);
    if (!mounted || res['isSuccess'] != true) return;
    final data = res['data'];
    if (data is! Map) return;
    final isExpired = data['isExpired'] == true || data['IsExpired'] == true;
    final isExpiringSoon =
        data['isExpiringSoon'] == true || data['IsExpiringSoon'] == true;
    if (!isExpired && !isExpiringSoon) return;

    final days = (data['daysUntilExpiry'] ?? data['DaysUntilExpiry'] as num?)?.toInt();
    final lotNo = (data['nearestLotNo'] ?? data['NearestLotNo'])?.toString();
    final expiryRaw = data['nearestExpiry'] ?? data['NearestExpiry'];
    DateTime? expiry;
    if (expiryRaw != null) expiry = DateTime.tryParse(expiryRaw.toString())?.toLocal();

    if (isExpired) {
      NotificationOverlayManager().showWarning(
        title: 'Lô đã hết HSD',
        message: '${p.name}${lotNo != null ? ' · lô $lotNo' : ''}'
            '${expiry != null ? ' · HSD ${_dateFmt.format(expiry)}' : ''}',
      );
    } else {
      NotificationOverlayManager().showWarning(
        title: 'Lô sắp hết HSD',
        message: '${p.name}: còn ${days ?? '?'} ngày'
            '${lotNo != null ? ' · lô $lotNo' : ''}',
      );
    }
  }

  Widget _buildExpiryLotBanner() {
    final total = _expiringLotCount + _expiredLotCount;
    if (total <= 0 || _expiryBannerDismissed) return const SizedBox.shrink();
    final isExpired = _expiredLotCount > 0;
    return Material(
      color: isExpired ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              isExpired ? Icons.error_outline : Icons.schedule,
              size: 18,
              color: isExpired ? const Color(0xFFB91C1C) : const Color(0xFFB45309),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isExpired
                    ? 'Có $_expiredLotCount lô đã hết HSD'
                        '${_expiringLotCount > 0 ? ', $_expiringLotCount lô sắp hết' : ''}'
                    : 'Có $_expiringLotCount lô sắp hết HSD trong 30 ngày',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isExpired ? const Color(0xFFB91C1C) : const Color(0xFFB45309),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PosReportsScreen(initialTab: 2)),
              ),
              child: const Text('Xem', style: TextStyle(fontSize: 12)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => setState(() => _expiryBannerDismissed = true),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPick(PosPurchaseLookupPick pick, {bool mergeIfSame = false}) async {
    final p = pick.product;
    var views = await loadPosSellUnitViews(_api, p);
    views = applyPosPriceListToViews(views, p, _currentPriceOverrides);
    if (!mounted || views.isEmpty) return;

    final view = pickUnitView(
          views,
          variantId: pick.variantId,
          unitId: pick.unitId,
          unitLabel: pick.unitLabel,
        ) ??
        views.first;

    if (!_validateStockForAdd(p, view, addQty: 1)) return;

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
          if (!_validateStockForAdd(p, view, addQty: 1)) return;
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
        vatRate: p.vatExempt ? 0 : p.vatRate,
        vatExempt: p.vatExempt,
      ));
      _syncPaidAmount();
    });
    HapticFeedback.lightImpact();
    await _maybeWarnProductExpiry(p, variantId: view.variantId);
  }

  Future<void> _resumeDraftFromList() async {
    final picked = await showPosPickSaleOrderDialog(
      context,
      purpose: PosPickSaleOrderPurpose.resumeDraft,
    );
    if (!mounted || picked == null) return;
    await _loadDraftIntoActiveTab(picked.id);
  }

  Future<Map<String, PosProduct>> _resolveDraftProducts(
      Iterable<PosSaleOrderLine> lines) async {
    final ids = lines
        .map((l) => l.productId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final resolved = <String, PosProduct>{};

    for (final id in ids) {
      final fromGrid = _productGridKey.currentState?.findCatalogProduct(id);
      if (fromGrid != null) resolved[id] = fromGrid;
    }

    final storeId = _storeId?.trim() ?? '';
    if (storeId.isNotEmpty) {
      final cached = await PosSellCatalogCache.instance.read(storeId);
      if (cached != null) {
        for (final p in cached.items) {
          if (ids.contains(p.id) && !resolved.containsKey(p.id)) {
            resolved[p.id] = p;
          }
        }
      }
    }

    final missing = ids.where((id) => !resolved.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final responses =
          await Future.wait(missing.map((id) => _api.getPosProduct(id)));
      for (var i = 0; i < missing.length; i++) {
        final res = responses[i];
        if (res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
          resolved[missing[i]] =
              PosProduct.fromJson(res['data'] as Map<String, dynamic>);
        }
      }
    }
    return resolved;
  }

  Future<Map<String, PosProductVariant>> _resolveDraftVariants(
    Map<String, PosProduct> products,
    Iterable<PosSaleOrderLine> lines,
  ) async {
    final byProduct = <String, String>{};
    for (final line in lines) {
      final vid = line.variantId;
      if (vid != null && vid.isNotEmpty) {
        byProduct[line.productId] = vid;
      }
    }
    final resolved = <String, PosProductVariant>{};
    final fetchProductIds = <String>[];

    for (final entry in byProduct.entries) {
      final p = products[entry.key];
      if (p == null) continue;
      final embedded = p.variants
          ?.where((v) => v.id == entry.value)
          .firstOrNull;
      if (embedded != null) {
        resolved[entry.value] = embedded;
      } else {
        fetchProductIds.add(entry.key);
      }
    }

    final uniqueFetch = fetchProductIds.toSet().toList();
    if (uniqueFetch.isNotEmpty) {
      final responses = await Future.wait(
        uniqueFetch.map((pid) => _api.getPosProductVariants(pid)),
      );
      for (var i = 0; i < uniqueFetch.length; i++) {
        final res = responses[i];
        if (res['isSuccess'] != true || res['data'] is! List) continue;
        final variants = (res['data'] as List)
            .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>));
        final wanted = byProduct[uniqueFetch[i]];
        if (wanted == null) continue;
        final match = variants.where((v) => v.id == wanted).firstOrNull;
        if (match != null) resolved[wanted] = match;
      }
    }
    return resolved;
  }

  Future<void> _loadDraftIntoActiveTab(String orderId) async {
    final res = await _api.getPosSale(orderId);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map<String, dynamic>) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tải được đơn tạm',
      );
      return;
    }
    final order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
    if (order.status != 'Draft') {
      NotificationOverlayManager().showError(
        title: 'Không phải đơn tạm',
        message: 'Chỉ tiếp tục được đơn ở trạng thái tạm',
      );
      return;
    }

    setState(() {
      _tab.reset(defaultVatRate: _storeSettings.defaultVatRate);
      _tab.draftOrderId = order.id;
      _tab.draftOrderNo = order.orderNo;
      _tab.sellerEmployeeId = _defaultSellerEmployeeId;
    });

    final products = await _resolveDraftProducts(order.lines);
    if (!mounted) return;
    final variants = await _resolveDraftVariants(products, order.lines);
    if (!mounted) return;

    final cartLines = <_SellCartLine>[];
    for (final line in order.lines) {
      if (line.productId.isEmpty) continue;
      final p = products[line.productId];
      if (p == null) continue;

      var views = posProductHasEmbeddedSellViews(p)
          ? buildPosSellUnitViewsFromProduct(p)
          : await loadPosSellUnitViews(_api, p);
      views = applyPosPriceListToViews(views, p, _currentPriceOverrides);
      final view = pickUnitView(
            views,
            variantId: line.variantId,
            unitLabel: line.unitName,
          ) ??
          views.first;
      PosProductVariant? variant;
      if (line.variantId != null && line.variantId!.isNotEmpty) {
        variant = variants[line.variantId!];
      }
      final cartLine = _SellCartLine(
        rowId: _nextCartRowId++,
        product: p,
        variantId: line.variantId,
        unitId: view.unitId,
        variant: variant,
        activeViewKey: view.viewKey,
        unitLabel: line.unitName ?? view.label,
        displayCode: view.displayCode,
        unitPrice: line.unitPrice,
        unitViews: views,
        qty: line.qty,
        lineNote: line.lineNote,
        discountInput: line.discountAmount,
        vatRate: p.vatExempt ? 0 : p.vatRate,
        vatExempt: p.vatExempt,
      );
      if (line.lineNote != null && line.lineNote!.isNotEmpty) {
        cartLine.noteCtrl.text = line.lineNote!;
      }
      cartLines.add(cartLine);
    }

    if (!mounted) return;
    setState(() {
      _tab.cart.addAll(cartLines);
      _tab.discount = order.discount;
      _tab.discountInput = order.discount;
      _tab.discountIsPercent = false;
      _tab._discountCtrl.text = order.discount == order.discount.roundToDouble()
          ? order.discount.toStringAsFixed(0)
          : order.discount.toStringAsFixed(2);
      _tab.note = order.note;
      _tab._noteCtrl.text = order.note ?? '';
      _tab.paidAmount = order.paidAmount;
      _tab.paidManuallyEdited = order.paidAmount > 0;
      _tab.priceListLabel = order.priceListName ?? _tab.priceListLabel;
      _tab.voucherCode = order.voucherCode;
      _tab.voucherDiscount = order.voucherDiscount;
      if (order.voucherCode != null) {
        _tab._voucherCtrl.text = order.voucherCode!;
      }
      _tab.pointsToRedeem = order.pointsRedeemed;
      _tab.pointsDiscount = order.pointsDiscount;
      if (order.pointsRedeemed > 0) {
        _tab._pointsCtrl.text = order.pointsRedeemed.toStringAsFixed(0);
      }
      if (order.customerId != null && order.customerId!.isNotEmpty) {
        _tab.customer = PosCustomer(
          id: order.customerId!,
          customerCode: order.customerCode ?? '',
          name: order.customerName ?? 'Khách hàng',
          phone: order.customerPhone,
        );
        _tab._customerSearchCtrl.text = order.customerName ?? '';
      }
      if (order.isDelivery) {
        _sellMode = _SellMode.delivery;
        _tab.deliveryAddress = order.deliveryAddress;
        _tab.deliveryPhone = order.deliveryPhone;
        _tab.deliveryPartner = order.deliveryPartner;
        _tab._deliveryAddressCtrl.text = order.deliveryAddress ?? '';
        _tab._deliveryPhoneCtrl.text = order.deliveryPhone ?? '';
        _tab._deliveryPartnerCtrl.text = order.deliveryPartner ?? '';
      }
      _syncPaidAmount();
    });

    NotificationOverlayManager().showSuccess(
      title: 'Đã tải đơn tạm',
      message: order.orderNo,
    );
  }

  Future<void> _onBarcodeScanned(String code, {bool mergeIfSame = true}) async {
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
    await _addPick(pick, mergeIfSame: mergeIfSame);
  }

  Future<void> _openNewProduct() async {
    final type = await showPosProductTypePicker(context);
    if (type == null || !mounted) return;
    final saved = await PosProductEditorPage.open(
      context,
      productType: type,
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
    first.amount = _grandTotal;
    first.amountCtrl.text = _moneyFmt.format(_grandTotal);
    _tab.paidAmount = _grandTotal;
    _tab.paidManuallyEdited = false;
    _tab._paidCtrl.text = _moneyFmt.format(_grandTotal);
  }

  void _onDiscountInputChanged(String raw, {VoidCallback? onMutate}) {
    final v = _parseMoneyInput(raw);
    setState(() {
      _tab.discountInput = v;
      if (!_tab.paidManuallyEdited && !_tab.paymentsManuallyEdited) {
        _syncPaidAmount();
      } else {
        _recalcTotals();
      }
    });
    _notifyPaymentUi(onMutate);
  }

  void _setDiscountMode(bool isPercent, {VoidCallback? onMutate}) {
    if (_tab.discountIsPercent == isPercent) return;
    setState(() {
      _tab.discountIsPercent = isPercent;
      _tab.discountInput = 0;
      _tab._discountCtrl.text = '0';
      if (!_tab.paidManuallyEdited && !_tab.paymentsManuallyEdited) {
        _syncPaidAmount();
      } else {
        _recalcTotals();
      }
    });
    _notifyPaymentUi(onMutate);
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
    final next = line.qty + delta;
    if (next <= 0) {
      setState(() {
        line.dispose();
        if (_expandedCartRowId == line.rowId) {
          _expandedCartRowId = null;
          _expandedCartMode = null;
        }
        _tab.cart.remove(line);
        _syncPaidAmount();
      });
      return;
    }
    if (delta > 0) {
      final others = _cartQtyFor(
            productId: line.product.id,
            variantId: line.variantId,
            unitId: line.unitId,
          ) -
          line.qty;
      if (!_validateStockQty(line.product, line.activeView, others + next)) {
        return;
      }
    } else if (line.product.productType == PosProductType.goods &&
        next > line.maxQty) {
      return;
    }
    setState(() {
      line.qty = next;
      if (line.warehouseSlipPrintedQty > next) {
        line.warehouseSlipPrintedQty = next;
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
      line.warehouseSlipPrintedQty = 0;
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

  void _applyOrderDiscountPreset(double percent, {VoidCallback? onMutate}) {
    setState(() {
      _tab.discountIsPercent = true;
      _tab.discountInput = percent;
      _tab._discountCtrl.text = percent % 1 == 0
          ? percent.toStringAsFixed(0)
          : percent.toStringAsFixed(2);
      if (!_tab.paidManuallyEdited && !_tab.paymentsManuallyEdited) {
        _syncPaidAmount();
      } else {
        _recalcTotals();
      }
    });
    _notifyPaymentUi(onMutate);
  }

  void _applyOrderDiscountAmountPreset(double amount, {VoidCallback? onMutate}) {
    setState(() {
      _tab.discountIsPercent = false;
      final capped = amount.clamp(0, _afterLineDiscount).toDouble();
      _tab.discountInput = capped;
      _tab._discountCtrl.text = _moneyFmt.format(capped);
      if (!_tab.paidManuallyEdited && !_tab.paymentsManuallyEdited) {
        _syncPaidAmount();
      } else {
        _recalcTotals();
      }
    });
    _notifyPaymentUi(onMutate);
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
      _selectCustomer(PosCustomer.fromJson(created));
    }
  }

  void _selectCustomer(PosCustomer c) {
    setState(() {
      _tab.customer = c;
      _tab._customerSearchCtrl.text = c.name;
      _customerSuggestions = [];
      _tab.pointsToRedeem = 0;
      _tab.pointsDiscount = 0;
      _tab._pointsCtrl.clear();
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
    });
  }

  Future<void> _applyVoucher({VoidCallback? onMutate}) async {
    final code = _tab._voucherCtrl.text.trim();
    if (code.isEmpty) {
      setState(() {
        _tab.voucherCode = null;
        _tab.voucherDiscount = 0;
        _tab.voucherName = null;
      });
      _syncPaidAmount();
      _notifyPaymentUi(onMutate);
      return;
    }
    setState(() => _tab._voucherValidating = true);
    try {
      final res = await _api.validatePosVoucher(
        code: code,
        orderAmount: _total,
        customerId: _tab.customer?.id,
      );
      if (!mounted) return;
      if (res['isSuccess'] != true || res['data'] is! Map) {
        NotificationOverlayManager().showError(
          title: 'Voucher',
          message: res['message']?.toString() ?? 'Không kiểm tra được mã',
        );
        return;
      }
      final data = res['data'] as Map<String, dynamic>;
      if (data['valid'] != true) {
        setState(() {
          _tab.voucherCode = null;
          _tab.voucherDiscount = 0;
          _tab.voucherName = null;
        });
        NotificationOverlayManager().showError(
          title: 'Voucher không hợp lệ',
          message: data['message']?.toString() ?? '',
        );
        return;
      }
      final discount = (data['discountAmount'] is num)
          ? (data['discountAmount'] as num).toDouble()
          : double.tryParse('${data['discountAmount']}') ?? 0;
      setState(() {
        _tab.voucherCode = code.toUpperCase();
        _tab.voucherDiscount = discount;
        _tab.voucherName = data['name']?.toString();
      });
      _recalcPointsDiscount(onMutate: onMutate);
      _syncPaidAmount();
      _notifyPaymentUi(onMutate);
      NotificationOverlayManager().showSuccess(
        title: 'Voucher',
        message: 'Giảm ${_moneyFmt.format(discount)} đ',
      );
    } finally {
      if (mounted) setState(() => _tab._voucherValidating = false);
    }
  }

  void _recalcPointsDiscount({VoidCallback? onMutate}) {
    const pointValue = 100.0;
    final maxBase = (_total - _tab.voucherDiscount).clamp(0, double.infinity);
    var points = double.tryParse(_tab._pointsCtrl.text.replaceAll(',', '')) ?? 0;
    if (points <= 0 || _tab.customer == null) {
      _tab.pointsToRedeem = 0;
      _tab.pointsDiscount = 0;
      return;
    }
    if (points > _tab.customer!.pointBalance) {
      points = _tab.customer!.pointBalance;
      _tab._pointsCtrl.text = points == points.roundToDouble()
          ? points.toStringAsFixed(0)
          : points.toString();
    }
    var discount = points * pointValue;
    if (discount > maxBase) {
      points = (maxBase / pointValue).floorToDouble();
      discount = points * pointValue;
      _tab._pointsCtrl.text = points.toStringAsFixed(0);
    }
    _tab.pointsToRedeem = points;
    _tab.pointsDiscount = discount;
    _notifyPaymentUi(onMutate);
  }

  Future<bool> _collectSerialsBeforeCheckout() async {
    final needsSerial = _tab.cart
        .where((c) => c.product.needsSerialCapture)
        .toList();
    if (needsSerial.isEmpty) return true;

    for (final line in needsSerial) {
      if (line.qty != line.qty.roundToDouble()) {
        NotificationOverlayManager().showError(
          title: 'Seri máy',
          message: 'Số lượng phải là số nguyên: ${line.product.name}',
        );
        return false;
      }
    }

    final captured = await showPosSerialCaptureDialog(
      context,
      lines: needsSerial
          .map(
            (c) => (
              rowId: c.rowId,
              product: c.product,
              displayName: c.product.name,
              qty: c.qty,
            ),
          )
          .toList(),
    );
    if (captured == null) return false;

    for (final line in needsSerial) {
      final data = captured[line.rowId];
      if (data == null) continue;
      line.serialNumbers = List<String>.from(data.serials);
      line.serialImeis = List<String>.from(data.imeis);
    }
    return true;
  }

  Future<void> _checkout() async {
    if (_checkingOut || _tab.cart.isEmpty) return;

    final paid = _effectivePaidAmount;
    final due = (_grandTotal - paid).clamp(0, double.infinity);
    if (due > 0 && _tab.customer == null) {
      NotificationOverlayManager().showError(
        title: 'Thiếu khách hàng',
        message: 'Chọn khách hàng để ghi nợ phần còn thiếu (${_moneyFmt.format(due)})',
      );
      return;
    }

    const complete = true;
    if (!_validateFullCartStock()) return;

    if (!await _collectSerialsBeforeCheckout()) return;

    setState(() => _checkingOut = true);
    try {
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
                  if (c.serialNumbers.isNotEmpty) 'serialNumbers': c.serialNumbers,
                  if (c.serialImeis.any((e) => e.trim().isNotEmpty)) 'serialImeis': c.serialImeis,
                })
            .toList(),
        'discount': _tab.discount,
        'paidAmount': paid,
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
        if (_tab.priceListId != null) 'priceListId': _tab.priceListId,
        if (_tab.priceListLabel.isNotEmpty) 'priceListName': _tab.priceListLabel,
        if (_tab.voucherCode != null && _tab.voucherCode!.isNotEmpty)
          'voucherCode': _tab.voucherCode,
        if (_tab.pointsToRedeem > 0) 'pointsToRedeem': _tab.pointsToRedeem,
      };

      final res = _tab.draftOrderId != null
          ? await _api.updatePosSale(_tab.draftOrderId!, body)
          : await _api.createPosSale(body);
      if (!mounted) return;

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
        title: 'Thanh toán thành công',
        message: 'Mã đơn: $orderNo',
      );

      final soldLines = _cartStockLinesFromCart();
      final alreadySentToWarehouse = _warehouseAlreadyPrintedMap();

      setState(() {
        _tab.reset(defaultVatRate: _storeSettings.defaultVatRate);
        _tab.sellerEmployeeId = _defaultSellerEmployeeId;
        _syncPaidAmount();
      });

      _patchLocalStock(soldLines);
      ScreenRefreshNotifier.refreshPosAfterStockChange(reloadSellCatalog: false);

      if (orderId != null && _printSettings.autoPrint) {
        await _maybePrintOrder(orderId);
      }
      if (orderId != null &&
          _printSettings.warehousePrintMode == PosWarehousePrintMode.auto) {
        await _maybePrintWarehouseSlip(
          orderId,
          alreadyPrinted: alreadySentToWarehouse,
        );
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  List<PosSellStockLineDelta> _cartStockLinesFromCart() {
    final raw = <PosSellStockLineDelta>[];
    for (final l in _tab.cart) {
      if (l.product.productType == PosProductType.service) continue;
      if (l.product.productType == PosProductType.combo) {
        for (final cl in l.product.comboLines ?? const <PosComboLine>[]) {
          raw.add(
            PosSellStockLineDelta(
              productId: cl.componentProductId,
              qty: cl.qty * l.qty,
            ),
          );
        }
        continue;
      }
      raw.add(
        PosSellStockLineDelta(
          productId: l.product.id,
          variantId: l.variantId,
          qty: l.qty,
        ),
      );
    }
    return mergeStockLineDeltas(raw);
  }

  void _patchLocalStock(List<PosSellStockLineDelta> lines) {
    if (lines.isEmpty) return;
    _productGridKey.currentState?.applyStockLinePatches(lines);
    if (!mounted) return;
    setState(() {
      for (final line in _tab.cart) {
        line.product = applyPosSellStockLines(line.product, lines);
        line.unitViews = buildPosSellUnitViewsFromProduct(line.product);
      }
    });
  }

  void _syncCartStockFromPatch() {
    final lines = ScreenRefreshNotifier.posSellStockPatch.value;
    if (lines == null || lines.isEmpty || !mounted) return;
    setState(() {
      for (final line in _tab.cart) {
        line.product = applyPosSellStockLines(line.product, lines);
        line.unitViews = buildPosSellUnitViewsFromProduct(line.product);
      }
    });
  }

  double _warehouseSlipPendingQty(_SellCartLine line) =>
      (line.qty - line.warehouseSlipPrintedQty).clamp(0.0, double.infinity);

  bool _hasWarehouseSlipPending() =>
      _tab.cart.any((l) => _warehouseSlipPendingQty(l) > 0);

  int _warehouseSlipPendingLineCount() =>
      _tab.cart.where((l) => _warehouseSlipPendingQty(l) > 0).length;

  List<PosSaleOrderLine> _warehouseSlipPendingLinesFromCart() {
    final lines = <PosSaleOrderLine>[];
    for (final l in _tab.cart) {
      final pending = _warehouseSlipPendingQty(l);
      if (pending <= 0) continue;
      if (l.product.productType == PosProductType.combo) {
        lines.addAll(
          expandComboToWarehouseLines(
            combo: l.product,
            comboQty: pending,
            lineNote: l.lineNote,
          ),
        );
        continue;
      }
      lines.add(
        PosSaleOrderLine(
          productId: l.product.id,
          variantId: l.variantId,
          productName: l.product.name,
          unitName: l.unitLabel,
          qty: pending,
          unitPrice: l.unitPrice,
          lineNote: l.lineNote,
        ),
      );
    }
    return lines;
  }

  Map<String, double> _warehouseAlreadyPrintedMap() {
    final map = <String, double>{};
    for (final line in _tab.cart) {
      if (line.warehouseSlipPrintedQty <= 0) continue;
      final key = '${line.product.id}|${line.variantId ?? ''}';
      map[key] = (map[key] ?? 0) + line.warehouseSlipPrintedQty;
    }
    return map;
  }

  void _markWarehouseSlipPrintedLines(List<PosSaleOrderLine> printedLines) {
    for (final pl in printedLines) {
      for (final cartLine in _tab.cart) {
        if (cartLine.product.id != pl.productId) continue;
        if ((cartLine.variantId ?? '') != (pl.variantId ?? '')) continue;
        cartLine.warehouseSlipPrintedQty =
            (cartLine.warehouseSlipPrintedQty + pl.qty).clamp(0, cartLine.qty);
        break;
      }
    }
  }

  void _enqueueFailedWarehousePrints(
    WarehouseSlipPrintResult result,
    PosSaleOrder order,
  ) {
    final jobs = result.toPendingJobs(order: order, tabId: _tab.id);
    if (jobs.isEmpty) return;
    setState(() {
      for (final job in jobs) {
        _failedWarehousePrints.removeWhere((j) => j.id == job.id);
        _failedWarehousePrints.insert(0, job);
      }
    });
  }

  void _removeFailedWarehouseJob(PendingWarehousePrintJob job) {
    setState(() => _failedWarehousePrints.removeWhere((j) => j.id == job.id));
  }

  void _clearFailedWarehouseJobsForTab(int tabId) {
    setState(
      () => _failedWarehousePrints.removeWhere((j) => j.tabId == tabId),
    );
  }

  void _applyWarehousePrintResult({
    required WarehouseSlipPrintResult result,
    required PosSaleOrder order,
    required int lineCount,
    required String successTitle,
  }) {
    if (result.anySuccess) {
      setState(() => _markWarehouseSlipPrintedLines(result.printedLines));
    }
    if (result.hasFailures) {
      _enqueueFailedWarehousePrints(result, order);
    }
    if (result.anySuccess && !result.hasFailures) {
      NotificationOverlayManager().showSuccess(
        title: successTitle,
        message: result.summaryMessage(lineCount: lineCount),
      );
    } else if (result.anySuccess && result.hasFailures) {
      NotificationOverlayManager().showWarning(
        title: 'In kho một phần',
        message: result.summaryMessage(lineCount: lineCount),
      );
    } else if (result.noPrinterLines.isNotEmpty && result.failCount == 0) {
      NotificationOverlayManager().showWarning(
        title: 'Không in được phiếu xuất kho',
        message: result.summaryMessage(lineCount: lineCount),
      );
    } else if (result.failCount > 0) {
      NotificationOverlayManager().showError(
        title: 'In kho thất bại',
        message: result.summaryMessage(lineCount: lineCount),
      );
    } else {
      NotificationOverlayManager().showWarning(
        title: 'Không in được phiếu xuất kho',
        message: 'Kiểm tra máy in, Print Agent hoặc gán SP → máy in kho',
      );
    }
  }

  String? get _warehouseBranchName =>
      _storeSettings.storeName.isNotEmpty ? _storeSettings.storeName : null;

  String? get _warehouseStoreAddress =>
      _storeSettings.address.isNotEmpty ? _storeSettings.address : null;

  String? get _warehouseStorePhone =>
      _storeSettings.phone.isNotEmpty ? _storeSettings.phone : null;

  Future<void> _openPendingPrintQueue() async {
    if (_failedWarehousePrints.isEmpty) {
      NotificationOverlayManager().showInfo(
        title: 'Không có phiếu treo',
        message: 'Tất cả phiếu xuất kho đã in thành công',
      );
      return;
    }
    await showPendingWarehousePrintSheet(
      context: context,
      jobs: List.unmodifiable(_failedWarehousePrints),
      printers: PosPrintOrchestrator.instance.printers,
      onDismiss: _removeFailedWarehouseJob,
      onDismissAll: () {
        setState(() => _failedWarehousePrints.clear());
        if (mounted) Navigator.pop(context);
      },
      onRetry: (job, method, {overridePrinterId}) async {
        final result = await printWarehouseSlipWithMethod(
          context: context,
          order: job.order,
          method: method,
          branchName: _warehouseBranchName,
          storeAddress: _warehouseStoreAddress,
          storePhone: _warehouseStorePhone,
          templateId: _printSettings.warehouseTemplateId,
          overridePrinterId: overridePrinterId ?? job.printerId,
        );
        if (!mounted) return result;
        if (result.anySuccess) {
          _markWarehouseSlipPrintedLines(result.printedLines);
          if (!result.hasFailures) {
            _removeFailedWarehouseJob(job);
          } else {
            _enqueueFailedWarehousePrints(result, job.order);
          }
        }
        return result;
      },
    );
    if (mounted) setState(() {});
  }

  void _onWarehouseSlipButtonTap() {
    if (_warehousePrinting || _checkingOut) return;
    if (!_hasWarehouseSlipPending()) {
      NotificationOverlayManager().showInfo(
        title: 'Đã báo kho',
        message: _tab.cart.isEmpty
            ? 'Giỏ hàng trống'
            : 'Tất cả hàng trong giỏ đã gửi kho. Thêm hàng mới để in tiếp.',
      );
      return;
    }
    _printWarehouseSlipFromCart();
  }

  Future<void> _printWarehouseSlipFromCart() async {
    final pendingLines = _warehouseSlipPendingLinesFromCart();
    if (pendingLines.isEmpty || _warehousePrinting || _checkingOut) return;
    setState(() => _warehousePrinting = true);
    try {
      final order = buildWarehouseSlipOrderFromCart(
        lines: pendingLines,
        note: _tab.note,
        customerName: _tab.customer?.name,
      );
      final result = await printWarehouseSlipForOrder(
        order: order,
        branchName: _warehouseBranchName,
        storeAddress: _warehouseStoreAddress,
        storePhone: _warehouseStorePhone,
        templateId: _printSettings.warehouseTemplateId,
      );
      if (!mounted) return;
      _applyWarehousePrintResult(
        result: result,
        order: order,
        lineCount: pendingLines.length,
        successTitle: 'Đã gửi kho',
      );
    } finally {
      if (mounted) setState(() => _warehousePrinting = false);
    }
  }

  Future<void> _maybePrintWarehouseSlip(
    String orderId, {
    Map<String, double> alreadyPrinted = const {},
  }) async {
    if (orderId.isEmpty) return;
    final res = await _api.getPosSale(orderId);
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    var order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
    order = filterWarehouseSlipOrder(order, alreadyPrinted);
    if (order.lines.isEmpty) return;

    final result = await printWarehouseSlipForOrder(
      order: order,
      branchName: _warehouseBranchName,
      storeAddress: _warehouseStoreAddress,
      storePhone: _warehouseStorePhone,
      templateId: _printSettings.warehouseTemplateId,
    );
    if (!mounted) return;
    _applyWarehousePrintResult(
      result: result,
      order: order,
      lineCount: order.lines.length,
      successTitle: 'Đã gửi kho',
    );
  }

  Future<void> _maybePrintOrder(String orderId) async {
    if (orderId.isEmpty || _checkoutPrintGuard.contains(orderId)) return;
    _checkoutPrintGuard.add(orderId);
    try {
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
        vietQrImageUrl: _buildVietQrImageUrlForOrder(order),
      );
    } finally {
      _checkoutPrintGuard.remove(orderId);
    }
  }

  Future<void> _openPrintSettings() async {
    if (Responsive.isMobile(context)) {
      final result = await Navigator.of(context)
          .push<(PosSellPrintSettings, PosThermalPrinterSettings)>(
        MaterialPageRoute(
          builder: (_) => PosSellMobilePrintSettingsScreen(
            initialPrintSettings: _printSettings,
            initialThermalSettings: _thermalPrintSettings,
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _printSettings = result.$1;
          _thermalPrintSettings = result.$2;
        });
        PosPrintConfigSession.instance.invalidate(warehouseTemplateOnly: true);
        PosPrintConfigSession.instance.warmUp(
          warehouseTemplateId: result.$1.warehouseTemplateId,
        );
      }
      return;
    }
    final box = _printBtnKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    final offset = box != null
        ? box.localToGlobal(Offset.zero)
        : Offset((screen.width - 320) / 2, 72);
    final updated = await showPosSellPrintPopover(
      context,
      initial: _printSettings,
      anchor: Offset(
        offset.dx - (box != null ? 260 : 0),
        offset.dy + (box?.size.height ?? 40),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _printSettings = updated);
      PosPrintConfigSession.instance.invalidate(warehouseTemplateOnly: true);
      PosPrintConfigSession.instance.warmUp(
        warehouseTemplateId: updated.warehouseTemplateId,
      );
    }
  }

  Future<void> _openStoreSettings() async {
    final updated = await showPosSellStoreSettingsDialog(
      context,
      initial: _storeSettings,
    );
    if (updated == null || !mounted) return;
    await updated.save();
    setState(() {
      _storeSettings = updated;
      for (final t in _tabs) {
        t.vatRate = updated.defaultVatRate;
        t.vatExempt = false;
      }
      _syncPaidAmount();
    });
    await _loadPaymentSources();
  }

  double get _vietQrAmount =>
      _dueAmount > 0 ? _dueAmount : _grandTotal;

  String get _vietQrTransferNote =>
      PosVietQrHelper.transferNote(prefix: 'POS');

  Widget _buildVietQrPaymentSection({
    bool compact = false,
    VoidCallback? onMutate,
  }) {
    if (!_storeSettings.showVietQrAtPayment ||
        _bankAccounts.isEmpty ||
        _vietQrAmount <= 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        PosVietQrPaymentPanel(
          accounts: _bankAccounts,
          amount: _vietQrAmount,
          preferredAccountId: _storeSettings.vietQrBankAccountId,
          description: _vietQrTransferNote,
          compact: compact,
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              showPosVietQrPaymentDialog(
                context,
                accounts: _bankAccounts,
                amount: _vietQrAmount,
                preferredAccountId: _storeSettings.vietQrBankAccountId,
                description: _vietQrTransferNote,
              ).then((_) => onMutate?.call());
            },
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: const Text('Phóng to mã QR'),
          ),
        ),
      ],
    );
  }

  String? _buildVietQrImageUrlForOrder(PosSaleOrder order) {
    if (!_printSettings.printVietQrOnReceipt || _bankAccounts.isEmpty) {
      return null;
    }
    final account = PosVietQrHelper.resolveAccount(
      _bankAccounts,
      preferredId: _storeSettings.vietQrBankAccountId,
    );
    if (account == null) return null;
    final amount = order.total > 0 ? order.total : order.paidAmount;
    return PosVietQrHelper.qrImageUrl(
      account: account,
      amount: amount,
      description: PosVietQrHelper.transferNote(
        orderNo: order.orderNo,
        prefix: 'POS',
      ),
    );
  }

  Future<void> _openPosMenu() async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    final canCash = perm.canCreate('CashTransaction') ||
        (perm.isLoaded && perm.canView('CashTransaction'));
    final canReturn = perm.canEdit('PosProducts') || perm.canCreate('PosSell');
    final canReport = perm.canView('PosSalesReport') || perm.canView('PosProducts');
    final canSell = perm.canView('PosSell') || perm.canView('PosProducts');
    final accountName = user != null && user.fullName.trim().isNotEmpty
        ? user.fullName.trim()
        : (user?.email.isNotEmpty == true ? user!.email : 'Tài khoản');
    final accountSubtitle = user != null
        ? (user.email.isNotEmpty
            ? user.email
            : (user.position ?? user.department))
        : null;

    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final topRight = box != null && overlay != null
        ? box.localToGlobal(box.size.topRight(Offset.zero), ancestor: overlay)
        : Offset(MediaQuery.sizeOf(context).width - 8, 56);

    final isMobile = Responsive.isMobile(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(topRight.dx - 240, topRight.dy, topRight.dx, topRight.dy + 8),
      items: [
        if (isMobile)
          PopupMenuItem(
            value: 'toggle_merge',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.merge_type_outlined, size: 20),
              title: const Text('Tự động gộp cùng sản phẩm'),
              trailing: Icon(
                _mobileMergeSameOnAdd ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: _mobileMergeSameOnAdd ? _kiotBlue : PosTheme.textSecondary,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: 'print_settings',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.print_outlined, size: 20),
            title: Text('Thiết lập máy in'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
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
        if (canSell)
          const PopupMenuItem(
            value: 'resume_draft',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.playlist_add_check_outlined, size: 20),
              title: Text('Tiếp tục đơn tạm'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canReturn)
          const PopupMenuItem(
            value: 'return_list',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.list_alt_outlined, size: 20),
              title: Text('Danh sách trả hàng'),
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
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          enabled: false,
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: PosTheme.kiotBlueLight,
              child: Text(
                accountName.isNotEmpty ? accountName[0].toUpperCase() : 'S',
                style: const TextStyle(
                  color: PosTheme.kiotBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              accountName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: accountSubtitle != null && accountSubtitle.isNotEmpty
                ? Text(
                    accountSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  )
                : null,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.logout, size: 20, color: Colors.red),
            title: Text(
              'Đăng xuất',
              style: TextStyle(color: Colors.red.shade700),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'logout':
        await showPosLogoutDialog(context);
      case 'toggle_merge':
        setState(() => _mobileMergeSameOnAdd = !_mobileMergeSameOnAdd);
      case 'print_settings':
        await _openPrintSettings();
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
      case 'resume_draft':
        await _resumeDraftFromList();
      case 'return_list':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PosSaleReturnListScreen()),
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
      body: Builder(
        builder: (context) {
          final body = LayoutBuilder(
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
                _buildExpiryLotBanner(),
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
                                    storeId: _storeId,
                                    priceOverrides: _currentPriceOverrides,
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
                                      storeId: _storeId,
                                      priceOverrides: _currentPriceOverrides,
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
          );
          if (PosHubScope.of(context)) return body;
          return SafeArea(bottom: false, child: body);
        },
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
            PosPendingPrintIconButton(
              pendingCount: _failedWarehousePrints.length,
              onTap: _openPendingPrintQueue,
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

  Widget _invoiceTabChip(int index, {bool onBlue = true}) {
    final active = index == _activeTab;
    final tab = _tabs[index];
    final bg = onBlue
        ? (active ? Colors.white : Colors.white.withValues(alpha: 0.2))
        : (active ? PosTheme.kiotBlueLight : const Color(0xFFF1F5F9));
    final borderColor = onBlue
        ? (active ? Colors.white : Colors.white.withValues(alpha: 0.35))
        : (active ? PosTheme.kiotBlue : PosTheme.border);
    final textColor = onBlue
        ? (active ? _kiotBlue : Colors.white)
        : (active ? PosTheme.kiotBlue : PosTheme.textSecondary);
    final closeColor = onBlue
        ? (active ? Colors.grey.shade600 : Colors.white70)
        : PosTheme.textSecondary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _selectTab(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: textColor,
                ),
              ),
              if (_tabs.length > 1) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _closeTab(index),
                  child: Icon(Icons.close, size: 14, color: closeColor),
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
                          'Tồn: ${_qtyFmt.format(line.activeView.onHandQty)}',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            color: line.activeView.onHandQty <= 0
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
            child: _buildCheckoutActions(
              canPay: canPay,
              busy: _checkingOut,
              onComplete: _checkout,
              height: compact ? 44 : 48,
              radius: 6,
              completeLabel: 'THANH TOÁN',
              completeFontSize: 12,
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

  Widget _buildPaymentSummaryContent({
    bool forMobilePayment = false,
    VoidCallback? onMutate,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!forMobilePayment) ...[
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
                              _tab.pointsToRedeem = 0;
                              _tab.pointsDiscount = 0;
                              _tab._pointsCtrl.clear();
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
                          onTap: () => _selectCustomer(c),
                        ))
                    .toList(),
              ),
            ),
        ],
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
            _discountModeChip('%', true, onMutate: onMutate),
            const SizedBox(width: 4),
            _discountModeChip('đ', false, onMutate: onMutate),
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
                onChanged: (v) => _onDiscountInputChanged(v, onMutate: onMutate),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _tab.discountIsPercent
              ? buildPosDiscountPresetChips(
                  onPickPercent: (p) =>
                      _applyOrderDiscountPreset(p, onMutate: onMutate),
                )
              : buildPosDiscountMoneyPresetChips(
                  moneyFmt: _moneyFmt,
                  baseAmount: _afterLineDiscount,
                  onPickAmount: (a) =>
                      _applyOrderDiscountAmountPreset(a, onMutate: onMutate),
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
        const SizedBox(height: 8),
        if (_storeSettings.taxMode != PosSellTaxMode.perItem) ...[
          const Text('Thuế VAT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _vatRateChip('KCT', exempt: true, onMutate: onMutate),
              _vatRateChip('0%', rate: 0, onMutate: onMutate),
              _vatRateChip('5%', rate: 5, onMutate: onMutate),
              _vatRateChip('8%', rate: 8, onMutate: onMutate),
              _vatRateChip('10%', rate: 10, onMutate: onMutate),
            ],
          ),
        ] else
          Text(
            'Thuế VAT theo từng mặt hàng (thiết lập trên hàng hóa)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        if (_storeSettings.taxMode == PosSellTaxMode.perItem && _vatAmount > 0) ...[
          const SizedBox(height: 4),
          _summaryRow('VAT', _moneyFmt.format(_vatAmount)),
        ] else if (_storeSettings.taxMode != PosSellTaxMode.perItem) ...[
          if (_tab.vatExempt)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Không chịu thuế GTGT',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            )
          else if (_vatAmount > 0) ...[
            const SizedBox(height: 4),
            if (_storeSettings.taxMode == PosSellTaxMode.orderTotal)
              _summaryRow('Tiền hàng', _moneyFmt.format(_total)),
            _summaryRow(
              _storeSettings.taxMode == PosSellTaxMode.includedInPrice
                  ? 'VAT (${_tab.vatRate.toStringAsFixed(_tab.vatRate % 1 == 0 ? 0 : 1)}%)'
                  : 'VAT (${_tab.vatRate.toStringAsFixed(_tab.vatRate % 1 == 0 ? 0 : 1)}%)',
              _moneyFmt.format(_vatAmount),
            ),
            if (_storeSettings.taxMode == PosSellTaxMode.includedInPrice)
              _summaryRow(
                'Tiền hàng trước VAT',
                _moneyFmt.format(_total - _vatAmount),
              ),
          ],
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tab._voucherCtrl,
                decoration: InputDecoration(
                  hintText: 'Mã voucher',
                  isDense: true,
                  prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                style: const TextStyle(fontSize: 12),
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _applyVoucher(onMutate: onMutate),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: _tab._voucherValidating ? null : () => _applyVoucher(onMutate: onMutate),
              child: _tab._voucherValidating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Áp dụng', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_tab.voucherDiscount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _summaryRow(
              'Voucher${_tab.voucherName != null ? ' (${_tab.voucherName})' : ''}',
              '-${_moneyFmt.format(_tab.voucherDiscount)}',
            ),
          ),
        if (_tab.customer != null && _tab.customer!.pointBalance > 0) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tab._pointsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Đổi điểm (có ${_moneyFmt.format(_tab.customer!.pointBalance)})',
                    isDense: true,
                    prefixIcon: const Icon(Icons.stars_outlined, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) {
                    _recalcPointsDiscount(onMutate: onMutate);
                    _syncPaidAmount();
                  },
                ),
              ),
            ],
          ),
        ],
        if (_tab.pointsDiscount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _summaryRow(
              'Đổi ${_moneyFmt.format(_tab.pointsToRedeem)} điểm',
              '-${_moneyFmt.format(_tab.pointsDiscount)}',
            ),
          ),
        const SizedBox(height: 6),
        _summaryRow('Khách cần trả', _moneyFmt.format(_grandTotal), bold: true, blue: true),
        if (_tab.customer != null && _tab.customer!.currentDebt > 0) ...[
          const SizedBox(height: 4),
          _summaryRow('Nợ cũ KH', _moneyFmt.format(_tab.customer!.currentDebt)),
        ],
        const SizedBox(height: 6),
        _buildPaymentSplits(
          onMutate: onMutate,
          forMobile: forMobilePayment,
        ),
        _buildVietQrPaymentSection(
          compact: forMobilePayment,
          onMutate: onMutate,
        ),
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

  Widget _vatRateChip(
    String label, {
    double rate = 0,
    bool exempt = false,
    VoidCallback? onMutate,
  }) {
    final selected = exempt ? _tab.vatExempt : (!_tab.vatExempt && _tab.vatRate == rate);
    return Material(
      color: selected ? PosTheme.kiotBlueLight : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          setState(() {
            if (exempt) {
              _tab.vatExempt = true;
            } else {
              _tab.vatExempt = false;
              _tab.vatRate = rate;
            }
            if (!_tab.paidManuallyEdited && !_tab.paymentsManuallyEdited) {
              _syncPaidAmount();
            }
          });
          _notifyPaymentUi(onMutate);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? _kiotBlue : PosTheme.border),
          ),
          child: Text(
            label,
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

  Widget _buildPaymentSplits({
    VoidCallback? onMutate,
    bool forMobile = false,
  }) {
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
              onPressed: () => _addPaymentLine(onMutate: onMutate),
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
            child: forMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _paymentSources.any((s) => s.key == pay.sourceKey)
                              ? pay.sourceKey
                              : _PosPaymentSource.cashKey,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(fontSize: 13, color: PosTheme.textPrimary),
                          items: _paymentSources
                              .map((s) => DropdownMenuItem(
                                    value: s.key,
                                    child: Text(
                                      s.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => pay.sourceKey = v);
                            _notifyPaymentUi(onMutate);
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: pay.amountCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                labelText: 'Số tiền',
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                              style: const TextStyle(fontSize: 13),
                              onChanged: (v) =>
                                  _onPaymentLineAmountChanged(pay, v, onMutate: onMutate),
                            ),
                          ),
                          if (_tab.paymentLines.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.red),
                              onPressed: () =>
                                  _removePaymentLine(index, onMutate: onMutate),
                            ),
                        ],
                      ),
                    ],
                  )
                : Row(
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
                              _notifyPaymentUi(onMutate);
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
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) =>
                              _onPaymentLineAmountChanged(pay, v, onMutate: onMutate),
                        ),
                      ),
                      if (_tab.paymentLines.length > 1)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          icon: const Icon(Icons.close, size: 16, color: Colors.red),
                          onPressed: () => _removePaymentLine(index, onMutate: onMutate),
                        ),
                    ],
                  ),
          );
        }),
      ],
    );
  }

  void _addPaymentLine({VoidCallback? onMutate}) {
    setState(() {
      _tab.paymentsManuallyEdited = true;
      final src = _paymentSources.length > 1
          ? _paymentSources[1]
          : _PosPaymentSource.cash;
      final line = _SellPaymentLine(sourceKey: src.key);
      final remain = (_grandTotal - _effectivePaidAmount).clamp(0, double.infinity);
      line.amount = remain.toDouble();
      line.amountCtrl.text = remain > 0 ? _moneyFmt.format(remain) : '';
      _tab.paymentLines.add(line);
    });
    _notifyPaymentUi(onMutate);
  }

  void _removePaymentLine(int index, {VoidCallback? onMutate}) {
    setState(() {
      _tab.paymentLines[index].dispose();
      _tab.paymentLines.removeAt(index);
      _tab.paymentsManuallyEdited = true;
    });
    _notifyPaymentUi(onMutate);
  }

  void _onPaymentLineAmountChanged(
    _SellPaymentLine pay,
    String raw, {
    VoidCallback? onMutate,
  }) {
    setState(() {
      _tab.paymentsManuallyEdited = true;
      pay.amount = _parseMoneyInput(raw);
    });
    _notifyPaymentUi(onMutate);
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

  Widget _buildCheckoutActions({
    required bool canPay,
    required bool busy,
    required VoidCallback? onComplete,
    double height = 50,
    double radius = 10,
    String completeLabel = 'HOÀN TẤT',
    double completeFontSize = 12,
  }) {
    final showWarehouse =
        _printSettings.showWarehouseManualButton && _tab.cart.isNotEmpty;
    final pendingLines = _warehouseSlipPendingLineCount();
    final hasWarehousePending = pendingLines > 0;
    final warehouseBusy = _warehousePrinting || busy;

    Widget completeBtn({required bool expanded}) {
      return FilledButton(
        onPressed: _tab.cart.isEmpty || busy || !canPay ? null : onComplete,
        style: FilledButton.styleFrom(
          backgroundColor: _kiotBlue,
          minimumSize: Size(expanded ? double.infinity : 0, height),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: busy
            ? SizedBox(
                height: height * 0.44,
                width: height * 0.44,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    completeLabel,
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: completeFontSize,
                    ),
                  ),
                ),
              ),
      );
    }

    if (!showWarehouse) return completeBtn(expanded: true);

    final warehouseLabel = _warehousePrinting
        ? 'Đang in...'
        : hasWarehousePending
            ? (pendingLines > 1 ? 'Báo kho ($pendingLines)' : 'Báo kho')
            : 'Đã báo kho';

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: warehouseBusy ? null : _onWarehouseSlipButtonTap,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, height),
              foregroundColor: hasWarehousePending
                  ? _kiotBlue
                  : const Color(0xFF64748B),
              side: BorderSide(
                color: hasWarehousePending
                    ? _kiotBlue
                    : const Color(0xFFCBD5E1),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
            icon: _warehousePrinting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.orange.shade800,
                    ),
                  )
                : Icon(
                    hasWarehousePending
                        ? Icons.inventory_2_outlined
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
            label: Text(
              warehouseLabel,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: completeBtn(expanded: false)),
      ],
    );
  }

  Widget _buildPaymentSidebar(PermissionProvider perm, {required double width, bool compact = false}) {
    _recalcTotals();
    final canPay = perm.canCreate('PosSell') || perm.canCreate('PosProducts');

    final summary = _buildPaymentSummaryContent();

    final payButton = _buildCheckoutActions(
      canPay: canPay,
      busy: _checkingOut,
      onComplete: _checkout,
      height: compact ? 44 : 48,
      radius: 6,
      completeLabel: 'THANH TOÁN',
      completeFontSize: 12,
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

  Widget _discountModeChip(String label, bool isPercent, {VoidCallback? onMutate}) {
    final selected = _tab.discountIsPercent == isPercent;
    return Material(
      color: selected ? PosTheme.kiotBlueLight : Colors.white,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: () => _setDiscountMode(isPercent, onMutate: onMutate),
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
    final canPay = perm.canCreate('PosSell') || perm.canCreate('PosProducts');
    return Stack(
      children: [
        Column(
          children: [
            _buildMobileTopBar(),
            _buildExpiryLotBanner(),
            _buildMobileSellActionBar(),
            Expanded(child: _buildMobileSellCartBody()),
            _buildMobileCheckoutBar(perm, canPay),
            if (!inHub) _buildMobileModeBar(),
          ],
        ),
        Offstage(
          offstage: !_mobileProductPickerOpen,
          child: IgnorePointer(
            ignoring: !_mobileProductPickerOpen,
            child: _buildMobileProductPickerOverlay(),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileProductPickerOverlay() {
    return Material(
      color: const Color(0xFFF3F4F6),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: const Text('Chọn hàng hóa'),
              backgroundColor: Colors.white,
              foregroundColor: PosTheme.textPrimary,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _mobileProductPickerOpen = false),
              ),
              actions: [
                IconButton(
                  tooltip: 'Thêm hàng mới',
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    await _openNewProduct();
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            Expanded(
              child: PosSellProductGrid(
                key: _productGridKey,
                api: _api,
                storeId: _storeId,
                sellListLayout: true,
                priceOverrides: _currentPriceOverrides,
                cartQtyByProductId: _cartQtyByProductId(),
                onPick: (pick) async {
                  await _addPick(pick, mergeIfSame: _mobileMergeSameOnAdd);
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, double> _cartQtyByProductId() {
    final map = <String, double>{};
    for (final line in _tab.cart) {
      map[line.product.id] = (map[line.product.id] ?? 0) + line.qty;
    }
    return map;
  }

  void _goMobileSellHome() {
    if (PosHubScope.of(context)) {
      NavigationNotifier.posHubTab.value = 0;
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      NavigationNotifier.goBack();
    }
  }

  Widget _buildMobileTopBar() {
    final inHub = PosHubScope.of(context);
    final bar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inHub ? 4 : 12, 4, 4, 0),
          child: Row(
                children: [
                  if (inHub)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Về trang chủ',
                      icon: const Icon(Icons.home_outlined,
                          color: PosTheme.textPrimary),
                      onPressed: _goMobileSellHome,
                    ),
                  const Expanded(
                    child: Text(
                      'Bán hàng',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: PosTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Chọn bảng giá',
                    icon: const Icon(Icons.sell_outlined, color: PosTheme.kiotBlue),
                    onPressed: _openMobilePriceListPicker,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Quét liên tục',
                    icon: const Icon(Icons.qr_code_scanner,
                        color: PosTheme.kiotBlue),
                    onPressed: _openMobileContinuousScan,
                  ),
                  PosPendingPrintIconButton(
                    pendingCount: _failedWarehousePrints.length,
                    onTap: _openPendingPrintQueue,
                    iconColor: PosTheme.textPrimary,
                    compact: true,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.menu, color: PosTheme.textPrimary),
                    tooltip: 'Menu',
                    onPressed: _openPosMenu,
                  ),
                ],
              ),
            ),
            if (!inHub)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    controller: _tabScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _tabs.length; i++) ...[
                        _invoiceTabChip(i, onBlue: false),
                        const SizedBox(width: 6),
                      ],
                      Material(
                        color: PosTheme.kiotBlueLight,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _newTab,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.add,
                                color: PosTheme.kiotBlue, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1, color: PosTheme.border),
          ],
    );
    return Material(color: Colors.white, child: bar);
  }

  Widget _buildMobileSellActionBar() {
    return Material(
      color: const Color(0xFFFAFBFC),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openMobileProductPicker,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Hàng hóa', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PosTheme.kiotBlue,
                  side: const BorderSide(color: PosTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _openMobileCameraScan,
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Quét mã', style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: PosTheme.kiotBlue,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSellCartBody() {
    if (_tab.cart.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_scanner_rounded,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'Quét mã vạch để bán',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: PosTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Dùng nút Quét mã hoặc máy quét cắm USB.\nChọn Hàng hóa để thêm thủ công.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      itemCount: _tab.cart.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final cartIndex = _tab.cart.length - 1 - i;
        final line = _tab.cart[cartIndex];
        final index = _tab.cart.length - i;
        return _buildMobileCartCard(line, index, cartIndex);
      },
    );
  }

  Widget _buildMobileCheckoutBar(PermissionProvider perm, bool canPay) {
    final inHub = PosHubScope.of(context);
    final payLabel = _tab.cart.isEmpty
        ? 'Thanh toán'
        : 'TT · ${_moneyFmt.format(_grandTotal)}đ';
    return Material(
      elevation: 6,
      color: Colors.white,
      child: SafeArea(
        top: false,
        bottom: !inHub,
        child: Container(
          padding: EdgeInsets.fromLTRB(12, 8, 12, inHub ? 6 : 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: PosTheme.border)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tab.cart.isEmpty
                          ? 'Chưa có hàng'
                          : 'Tổng (${_tab.cart.length} món)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                    Text(
                      '${_moneyFmt.format(_grandTotal)} đ',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kiotBlue,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_bankAccounts.isNotEmpty && _vietQrAmount > 0) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Mã VietQR',
                  onPressed: () => showPosVietQrPaymentDialog(
                    context,
                    accounts: _bankAccounts,
                    amount: _vietQrAmount,
                    preferredAccountId: _storeSettings.vietQrBankAccountId,
                    description: _vietQrTransferNote,
                  ),
                  icon: const Icon(Icons.qr_code_2, color: _kiotBlue, size: 26),
                ),
              ],
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _tab.cart.isEmpty || _checkingOut || !canPay
                        ? null
                        : () => _openMobilePaymentScreen(perm),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kiotBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        payLabel,
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMobileCameraScan() async {
    final code = await scanBarcodeWithCamera(context);
    if (code != null && code.trim().isNotEmpty) {
      await _onBarcodeScanned(code, mergeIfSame: _mobileMergeSameOnAdd);
    }
  }

  Future<void> _openMobileContinuousScan() async {
    await scanBarcodeContinuously(
      context,
      onScan: (code) =>
          _onBarcodeScanned(code, mergeIfSame: _mobileMergeSameOnAdd),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openMobileLineDiscount(_SellCartLine line) async {
    final result = await showPosDiscountEditorSheet(
      context: context,
      title: 'Chiết khấu dòng',
      baseAmount: line.lineGross,
      initialInput: line.discountInput,
      initialIsPercent: line.discountIsPercent,
    );
    if (result == null || !mounted) return;
    setState(() {
      line.discountIsPercent = result.isPercent;
      line.discountInput = result.input;
      line.discountCtrl.text = result.input == 0
          ? '0'
          : (result.isPercent
              ? result.input.toStringAsFixed(
                  result.input % 1 == 0 ? 0 : 2)
              : _moneyFmt.format(result.input));
      _syncPaidAmount();
    });
  }

  Future<void> _openMobileLineNote(_SellCartLine line) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ghi chú sản phẩm',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                PosLineQuickNotesPicker(
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
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Xong'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _splitMobileCartLine(int cartIndex) {
    final line = _tab.cart[cartIndex];
    if (line.qty <= 1) return;
    setState(() {
      line.qty -= 1;
      final cloned = _SellCartLine(
        rowId: _nextCartRowId++,
        product: line.product,
        variantId: line.variantId,
        unitId: line.unitId,
        variant: line.variant,
        activeViewKey: line.activeViewKey,
        unitLabel: line.unitLabel,
        displayCode: line.displayCode,
        unitPrice: line.unitPrice,
        unitViews: line.unitViews,
        qty: 1,
        lineNote: line.lineNote,
        discountIsPercent: line.discountIsPercent,
        discountInput: line.discountInput,
      );
      cloned.selectedQuickNotes
        ..clear()
        ..addAll(line.selectedQuickNotes);
      cloned.noteCtrl.text = line.noteCtrl.text;
      _tab.cart.insert(cartIndex + 1, cloned);
      _syncPaidAmount();
    });
  }

  void _mergeMobileCartLine(int cartIndex) {
    final line = _tab.cart[cartIndex];
    final matches = <int>[];
    for (var i = 0; i < _tab.cart.length; i++) {
      if (i == cartIndex) continue;
      final other = _tab.cart[i];
      final sameIdentity = other.product.id == line.product.id &&
          other.variantId == line.variantId &&
          other.unitId == line.unitId;
      final sameNoteDiscount = (other.lineNote ?? '') == (line.lineNote ?? '') &&
          other.discountIsPercent == line.discountIsPercent &&
          (other.discountInput - line.discountInput).abs() < 0.0001;
      if (sameIdentity && sameNoteDiscount) {
        matches.add(i);
      }
    }
    if (matches.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không thể gộp',
        message: 'Chỉ gộp được dòng cùng sản phẩm, cùng ghi chú và cùng chiết khấu.',
      );
      return;
    }
    setState(() {
      var qtyToAdd = 0.0;
      for (final i in matches) {
        qtyToAdd += _tab.cart[i].qty;
      }
      line.qty += qtyToAdd;
      for (final i in matches.reversed) {
        _tab.cart[i].dispose();
        _tab.cart.removeAt(i);
      }
      _syncPaidAmount();
    });
  }

  void _openMobileProductPicker() {
    setState(() => _mobileProductPickerOpen = true);
  }

  Future<void> _openMobileCustomerPicker() async {
    final qCtrl = TextEditingController(text: _tab._customerSearchCtrl.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.72,
                minChildSize: 0.4,
                maxChildSize: 0.92,
                builder: (_, scroll) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Chọn khách hàng',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.person_add_outlined),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _openAddCustomer();
                            },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: qCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Tên, SĐT, mã khách...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          isDense: true,
                        ),
                        onChanged: (v) async {
                          await _searchCustomers(v);
                          setSheet(() {});
                        },
                      ),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline, size: 20),
                      ),
                      title: const Text('Khách lẻ'),
                      trailing: _tab.customer == null
                          ? const Icon(Icons.check, color: _kiotBlue)
                          : null,
                      onTap: () {
                        setState(() {
                          _tab.customer = null;
                          _tab._customerSearchCtrl.clear();
                          _customerSuggestions = [];
                        });
                        Navigator.pop(ctx);
                      },
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scroll,
                        itemCount: _customerSuggestions.length,
                        itemBuilder: (_, i) {
                          final c = _customerSuggestions[i];
                          return ListTile(
                            title: Text(c.name),
                            subtitle: Text(
                              [c.phone, c.customerCode]
                                  .where((e) => e != null && e.isNotEmpty)
                                  .join(' · '),
                            ),
                            onTap: () {
                              _selectCustomer(c);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    qCtrl.dispose();
  }

  Future<void> _openMobilePriceListPicker() async {
    if (_priceLists.isEmpty) {
      await _loadPriceLists();
    }
    final options = _priceLists.isNotEmpty
        ? _priceLists
        : [PosPriceList(id: '', name: 'Bảng giá chung')];
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Chọn bảng giá',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            ...options.map(
              (pl) => ListTile(
                title: Text(pl.name),
                subtitle: pl.isDefault ? const Text('Mặc định') : null,
                trailing: _tab.priceListId == pl.id ||
                        (_tab.priceListId == null &&
                            _tab.priceListLabel == pl.name)
                    ? const Icon(Icons.check, color: _kiotBlue)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  if (pl.id.isNotEmpty) {
                    await _selectPriceList(pl);
                  } else {
                    setState(() {
                      _tab.priceListId = null;
                      _tab.priceListLabel = pl.name;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMobilePaymentActionTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PosTheme.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: _kiotBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 11,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: PosTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMobilePaymentScreen(PermissionProvider perm) async {
    if (_tab.cart.isEmpty || _checkingOut) return;
    final canPay = perm.canCreate('PosSell') || perm.canCreate('PosProducts');
    var paying = false;
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
          body: StatefulBuilder(
            builder: (ctx, setPay) {
              _recalcTotals();
              final busy = paying || _checkingOut;
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                      children: [
                        _buildMobilePaymentActionTile(
                          icon: Icons.person_outline,
                          title: 'Khách hàng',
                          value: _tab.customer?.name ?? 'Khách lẻ',
                          onTap: busy
                              ? () {}
                              : () async {
                                  await _openMobileCustomerPicker();
                                  setPay(() {});
                                },
                        ),
                        const SizedBox(height: 8),
                        _buildMobilePaymentActionTile(
                          icon: Icons.sell_outlined,
                          title: 'Bảng giá',
                          value: _tab.priceListLabel,
                          onTap: busy
                              ? () {}
                              : () async {
                                  await _openMobilePriceListPicker();
                                  setPay(() {});
                                },
                        ),
                        const SizedBox(height: 14),
                        _buildPaymentSummaryContent(
                          forMobilePayment: true,
                          onMutate: busy ? null : () => setPay(() {}),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: _buildCheckoutActions(
                        canPay: canPay,
                        busy: busy,
                        completeLabel:
                            'TT · ${_moneyFmt.format(_grandTotal)}đ',
                        completeFontSize: 11,
                        onComplete: () async {
                          setPay(() => paying = true);
                          try {
                            await _checkout();
                          } finally {
                            if (ctx.mounted) {
                              setPay(() => paying = false);
                              if (_tab.cart.isEmpty) Navigator.pop(ctx);
                            }
                          }
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
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

  Widget _buildMobileCartCard(
      _SellCartLine line, int index, int cartIndex) {
    final hasNote = line.lineNote != null && line.lineNote!.isNotEmpty;
    final hasDiscount = line.discountAmount > 0;
    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PosProductImage(
                productId: line.product.id,
                imageUrl: line.product.imageUrl,
                size: 38,
                borderRadius: 6,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      '${_moneyFmt.format(line.unitPrice)} đ/${line.unitLabel}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _kiotBlue,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (action) {
                  switch (action) {
                    case 'note':
                      _openMobileLineNote(line);
                    case 'discount':
                      _openMobileLineDiscount(line);
                    case 'split':
                      if (line.qty > 1) _splitMobileCartLine(cartIndex);
                    case 'merge':
                      _mergeMobileCartLine(cartIndex);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'note',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.notes_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Ghi chú', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'discount',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.discount_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Chiết khấu', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'split',
                    height: 36,
                    enabled: line.qty > 1,
                    child: const Row(
                      children: [
                        Icon(Icons.call_split_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Tách dòng', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'merge',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.merge_type_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Gộp dòng', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => _removeLine(cartIndex),
              ),
            ],
          ),
          if (hasDiscount || hasNote) ...[
            const SizedBox(height: 2),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                if (hasDiscount)
                  Text(
                    'CK -${_moneyFmt.format(line.discountAmount)}',
                    style: TextStyle(fontSize: 10, color: Colors.red.shade700),
                  ),
                if (hasNote)
                  Text(
                    '↳ ${line.lineNote}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: _kiotBlue),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              _mobileQtyButton(
                icon: Icons.remove,
                onTap: line.qty > 1 ? () => _adjustQty(line, -1) : null,
                compact: true,
              ),
              SizedBox(
                width: 44,
                child: Text(
                  _qtyFmt.format(line.qty),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _mobileQtyButton(
                icon: Icons.add,
                onTap: () => _adjustQty(line, 1),
                primary: true,
                compact: true,
              ),
              const Spacer(),
              Text(
                '${_moneyFmt.format(line.lineTotal)} đ',
                style: const TextStyle(
                  fontSize: 14,
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
    bool compact = false,
  }) {
    final size = compact ? 32.0 : 40.0;
    final height = compact ? 30.0 : 36.0;
    return Material(
      color: primary
          ? _kiotBlue.withValues(alpha: 0.1)
          : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: size,
          height: height,
          child: Icon(
            icon,
            size: compact ? 16 : 18,
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
