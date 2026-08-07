import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/cash_transaction.dart';
import '../models/pos_customer.dart';
import '../models/pos_price_list.dart';
import '../models/pos_product.dart';
import '../models/pos_print_template.dart';
import '../models/pos_sell_industry.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../models/cancel_return_reason_config.dart';
import '../models/customer_display_models.dart';
import '../utils/customer_display_media.dart';
import '../widgets/pos/pos_cancel_return_reason_dialog.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/responsive_helper.dart';
import '../utils/store_role_helper.dart';
import '../services/api_service.dart';
import '../services/customer_display_sync.dart';
import '../services/pos_sell_catalog_cache.dart';
import '../services/signalr_service.dart';
import '../utils/pos_purchase_product_lookup.dart';
import '../utils/pos_combo_stock.dart';
import '../utils/pos_kitchen_print.dart';
import '../utils/pos_cup_label_print.dart';
import '../utils/pos_pending_print_store.dart';
import '../utils/pos_table_label.dart';
import '../utils/pos_print_config_session.dart';
import '../utils/pos_print_orchestrator.dart';
import '../utils/pos_sale_order_print.dart';
import '../utils/pos_sell_print_settings.dart';
import '../utils/pos_sell_stock_patch.dart';
import '../utils/pos_device_identity.dart';
import '../utils/pos_floor_realtime.dart';
import '../utils/pos_browser_fullscreen.dart';
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
import '../widgets/pos/pos_sell_desktop_layout.dart';
import '../widgets/notification_overlay.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
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
import '../widgets/pos/pos_numeric_keypad.dart';
import 'pos/pos_end_of_day_screen.dart';
import 'pos/pos_resource_floor_screen.dart';
import 'pos/pos_session_redeem_sheet.dart';
import 'pos_reports_screen.dart';
import 'pos_sale_return_list_screen.dart';
import 'pos_sale_order_list_screen.dart';
import '../widgets/pos/pos_cash_voucher_dialog.dart';
import '../widgets/pos/pos_pick_sale_order_dialog.dart';
import '../utils/navigation_notifier.dart';
import '../utils/permission_navigation.dart';
import 'settings_hub_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Tỷ lệ / khoảng cách màn bán hàng theo KiotViet.
abstract final class _KiotLayout {
  static const topBarHeight = 48.0;
  static const bottomBarHeight = 40.0;
  static const cartRowHeight = 52.0;
  static const cartHeaderHeight = 28.0;
  static const sidePadding = 10.0;
  static const sectionGap = 12.0;

  /// Panel thanh toán = đúng 50% màn hình (phần còn lại cho sản phẩm / giỏ).
  static double paymentPanelWidth(double screenW) => screenW * 0.5;

  static const compactSectionGap = 8.0;

  static const wDel = 28.0;
  static const wNameMin = 120.0;
  /// Đủ chỗ cho − / SL / + trên cảm ứng (tránh tràn sang cột ĐVT).
  static const wQty = 118.0;
  /// Cột phải thu gọn để vừa nửa màn hình đơn hàng (14").
  static const wUnit = 48.0;
  static const wPrice = 72.0;
  static const wTotal = 80.0;

  static double get tableMinWidth =>
      wDel + wNameMin + wQty + wUnit + wPrice + wTotal + 20;
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
          text: tr(unitPrice == unitPrice.roundToDouble()
              ? unitPrice.toStringAsFixed(0)
              : unitPrice.toStringAsFixed(2)),
        ),
        discountCtrl = TextEditingController(
          text: tr(discountInput == 0
              ? '0'
              : (discountInput == discountInput.roundToDouble()
                  ? discountInput.toStringAsFixed(0)
                  : discountInput.toStringAsFixed(2))),
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
  /// Số lượng đã báo chế biến / gửi bếp (không báo lại nếu chưa tăng SL).
  double kitchenSentQty = 0;
  /// Số phần đã in tem ly (1 phần = 1 tem; không in lại phần đã in).
  double cupLabelPrintedQty = 0;
  /// SL hủy đã ghi nhưng chưa in (legacy / chờ Báo bếp). Hủy mới in ngay, không dùng field này.
  double kitchenCancelPendingQty = 0;
  List<PosProductUnitView> unitViews;
  String? lineNote;
  bool discountIsPercent;
  double discountInput;
  double vatRate;
  bool vatExempt;
  List<String> serialNumbers = [];
  List<String> serialImeis = [];
  /// Topping đã chọn trên dòng (id SP topping, tên, giá thêm / 1 phần món).
  List<_CartTopping> toppings = [];
  final Set<String> selectedQuickNotes = {};
  final TextEditingController noteCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController discountCtrl;

  double get toppingExtraPerUnit =>
      toppings.fold<double>(0, (s, t) => s + t.price);

  double get toppingExtraTotal => toppingExtraPerUnit * qty;

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
  double get lineGross => (unitPrice + toppingExtraPerUnit) * qty;

  /// Ghi chú phiếu bếp / màn khách: topping + ghi chú dòng.
  String? get noteWithToppings {
    final parts = <String>[];
    if (toppings.isNotEmpty) {
      parts.add(toppings.map((t) => t.name).join(', '));
    }
    final n = (lineNote ?? '').trim();
    if (n.isNotEmpty) parts.add(n);
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  /// SL còn chưa báo bếp (chỉ phần mới).
  double get kitchenPendingQty =>
      (qty - kitchenSentQty).clamp(0.0, double.infinity);

  /// SL còn chưa in tem ly.
  double get cupLabelPendingQty =>
      (qty - cupLabelPrintedQty).clamp(0.0, double.infinity);

  bool get kitchenFullySent => kitchenPendingQty <= 0 && qty > 0;

  double get discountAmount {
    if (discountInput <= 0) return 0;
    if (discountIsPercent) {
      return (lineGross * discountInput / 100).clamp(0, lineGross);
    }
    return discountInput.clamp(0, lineGross);
  }

  double get lineTotal => lineGross - discountAmount;
}

class _CartTopping {
  _CartTopping({
    required this.id,
    required this.name,
    required this.price,
  });

  final String id;
  final String name;
  final double price;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
      };

  static _CartTopping? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = (m['id'] ?? m['Id'] ?? '').toString();
    final name = (m['name'] ?? m['Name'] ?? '').toString();
    if (id.isEmpty && name.isEmpty) return null;
    final priceRaw = m['price'] ?? m['Price'];
    final price = priceRaw is num
        ? priceRaw.toDouble()
        : double.tryParse('$priceRaw') ?? 0;
    return _CartTopping(
      id: id.isEmpty ? name : id,
      name: name.isEmpty ? id : name,
      price: price,
    );
  }
}

List<_CartTopping> parseCartToppings(String? json) {
  if (json == null || json.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return [];
    return decoded
        .map(_CartTopping.tryParse)
        .whereType<_CartTopping>()
        .toList();
  } catch (_) {
    return [];
  }
}

class _SellInvoiceTab {
  _SellInvoiceTab({required this.id});

  final int id;

  /// Nhãn tab gọn: «HĐ N» — đỡ rối khi nhiều slot trên thanh trên.
  String get label {
    final head = 'HĐ $id';
    if (cart.isEmpty) return head;
    return '$head · ${cart.length}';
  }

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
  /// Optimistic lock version từ server (Gửi kèm khi Giữ đơn / TT).
  int lockVersion = 0;
  /// Slot cố định trên server (= id tab: Hóa đơn 1..N).
  int get invoiceSlot => id;
  /// true = máy khác đang giữ — chỉ xem, poll cập nhật dòng hàng.
  bool draftReadOnly = false;
  String? lockedByLabel;
  /// Số dòng / tổng trên server (để tô màu tab + phát hiện sync).
  int serverLineCount = 0;
  double serverTotal = 0;
  /// Có thay đổi giỏ chưa đẩy lên server — cấm poll đè lại hàng đã xóa.
  bool localDirty = false;
  String? serviceResourceId;
  String? resourceSessionId;
  DateTime? serviceStartedAt;
  String? serviceResourceName;
  String? serviceAreaName;
  int tableGuestCount = 0;
  /// Pause phiên bàn — đồng bộ billing timed.
  int accumulatedPauseMinutes = 0;
  DateTime? sessionPausedAt;
  bool sessionIsPaused = false;
  /// Giá giờ mặc định của bàn (khi SP PerHour giá 0).
  double? serviceDefaultHourlyRate;

  /// Đơn gắn bàn/phòng (BAN*) — không thuộc mô hình Hóa đơn 1/2/3.
  bool get isTableBound {
    if ((serviceResourceId ?? '').isNotEmpty) return true;
    if ((resourceSessionId ?? '').isNotEmpty) return true;
    final no = (draftOrderNo ?? '').trim().toUpperCase();
    return no.startsWith('BAN');
  }
  bool _voucherValidating = false;
  final _voucherCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: tr('0'));
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
    // Dòng CK sẽ thêm khi load nguồn TT (_ensureDefaultPaymentLines).
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
    lockVersion = 0;
    draftReadOnly = false;
    lockedByLabel = null;
    serverLineCount = 0;
    serverTotal = 0;
    localDirty = false;
    serviceResourceId = null;
    resourceSessionId = null;
    serviceStartedAt = null;
    serviceResourceName = null;
    serviceAreaName = null;
    tableGuestCount = 0;
    accumulatedPauseMinutes = 0;
    sessionPausedAt = null;
    sessionIsPaused = false;
    serviceDefaultHourlyRate = null;
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
  final _floorSearchCtrl = TextEditingController();
  final _floorSearchFocus = FocusNode();
  String _floorSearchQuery = '';
  String? _floorPendingOpenCode;
  int _floorPendingOpenToken = 0;
  final _customerSearchFocus = FocusNode();
  Timer? _customerSearchDebounce;
  final _productGridKey = GlobalKey<PosSellProductGridState>();

  int _nextTabSeq = 2;
  final List<_SellInvoiceTab> _tabs = [_SellInvoiceTab(id: 1)];
  /// Slot vừa đóng — bỏ qua nếu sync stale còn trả về (tránh HĐ hiện lại).
  final Map<int, DateTime> _recentlyClosedSlots = {};
  /// Sau khi máy này lưu Draft thành công — không để sync lật readOnly trong vài giây.
  DateTime? _ignoreReadOnlyUntil;
  Timer? _draftLockHeartbeat;
  final _floorRealtime = PosFloorRealtimeSubscription();
  bool _suspendDraftAutosave = false;
  /// Đơn đã nhả khóa khi về sơ đồ — không heartbeat/autosave gắn lại cho đến khi mở bàn lại.
  final Set<String> _floorReleasedOrderIds = {};
  Timer? _draftAutosaveTimer;
  bool _autosavingDraft = false;
  bool _pullingDraft = false;
  bool _syncInFlight = false;
  bool _syncPending = false;
  String? _posDeviceId;
  String? _posDeviceName;
  int _activeTab = 0;
  _SellMode _sellMode = _SellMode.quick;
  PosSellPrintSettings _printSettings = const PosSellPrintSettings();
  PosThermalPrinterSettings _thermalPrintSettings =
      const PosThermalPrinterSettings();
  /// In bill/tem lần TT này — độc lập thiết lập «tự động»; gieo từ settings.
  bool _quickPrintInvoice = false;
  bool _quickPrintCup = false;
  PosSellStoreSettings _storeSettings = const PosSellStoreSettings();
  PosStoreSellSettingsDto? _industrySettings;
  bool _checkingOut = false;
  bool _parking = false;
  bool _provisionalPrinting = false;
  bool _kitchenSending = false;
  /// Chờ warm-up + slot xong mới vẽ UI — tránh nhảy nháy dữ liệu lúc mở.
  bool _sellReady = false;
  bool _warehousePrinting = false;
  final List<PendingWarehousePrintJob> _failedWarehousePrints = [];
  final List<PendingSalePrintJob> _failedSalePrints = [];
  final List<PendingKitchenPrintJob> _failedKitchenPrints = [];
  final List<PendingCupLabelPrintJob> _failedCupPrints = [];
  Timer? _pendingPrintRetryTimer;
  bool _pendingPrintRetryBusy = false;
  /// Hủy bếp chờ gộp (món đã xóa khỏi giỏ sau khi báo).
  final List<KitchenTicketLine> _pendingKitchenCancels = [];
  /// Bàn vừa báo bếp — sơ đồ ép ẩn «chờ bếp» đến khi server khớp.
  Set<String> _kitchenClearedResourceIds = {};
  /// Bàn vừa in tạm tính — sơ đồ ép màu vàng cam đến khi server khớp.
  /// Luôn tạo Set mới khi đổi để floor remount/didUpdateWidget nhận thay đổi.
  Set<String> _billRequestedResourceIds = {};
  final Set<String> _checkoutPrintGuard = {};
  bool _mobileMergeSameOnAdd = true;
  bool _mobileProductPickerOpen = false;
  /// Bản nháp chọn hàng (chưa vào đơn) — chỉ đồng bộ khi bấm xác nhận.
  final Map<String, double> _pickerDraftQty = {};
  final Map<String, PosPurchaseLookupPick> _pickerDraftPicks = {};
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
    if (!_guardReadOnlyEdit()) return;
    setState(() {
      if (_expandedCartRowId == rowId && _expandedCartMode == mode) {
        // Đóng editor → mới commit ghi chú / CK / giá vào đơn (đồng bộ).
        final line = _tab.cart.where((l) => l.rowId == rowId).firstOrNull;
        if (line != null) {
          if (mode == _CartRowExpand.note) {
            _commitLineNote(line, scheduleSave: true);
          } else if (mode == _CartRowExpand.priceDiscount) {
            _commitLinePriceDiscount(line, scheduleSave: true);
          }
        }
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

  /// Chỉ cập nhật local — chưa đồng bộ.
  void _applyLineNoteFromPicker(_SellCartLine line) {
    line.lineNote = joinPosLineNoteParts(
      selectedQuickNotes: line.selectedQuickNotes,
      extraNote: line.noteCtrl.text,
    );
  }

  /// Xác nhận ghi chú → mới autosave/đồng bộ.
  void _commitLineNote(_SellCartLine line, {bool scheduleSave = true}) {
    if (!_guardReadOnlyEdit()) return;
    _applyLineNoteFromPicker(line);
    if (scheduleSave) _scheduleDraftAutosave();
  }

  /// Xác nhận giá + chiết khấu dòng → mới đồng bộ.
  void _commitLinePriceDiscount(_SellCartLine line, {bool scheduleSave = true}) {
    if (!_guardReadOnlyEdit()) return;
    final price = _parseMoneyInput(line.priceCtrl.text);
    line.unitPrice = price.clamp(0, double.infinity);
    line.discountInput = _parseMoneyInput(line.discountCtrl.text);
    if (!line.discountIsPercent && line.discountInput > line.lineGross) {
      line.discountInput = 0;
      line.discountCtrl.text = '0';
    }
    _syncPaidAmount();
    if (scheduleSave) _scheduleDraftAutosave();
  }

  @override
  void initState() {
    super.initState();
    _tabs.first.paymentLines
        .add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
    HardwareKeyboard.instance.addHandler(_onKey);
    ScreenRefreshNotifier.posSellStockPatch.addListener(_syncCartStockFromPatch);
    ScreenRefreshNotifier.posPriceLists.addListener(_onPriceListsChanged);
    ScreenRefreshNotifier.posSellIndustry.addListener(_onSellIndustryChanged);
    NavigationNotifier.posHandleSystemBack = _onSystemBack;
    _floorRealtime.start((_) {
      if (!mounted) return;
      unawaited(_syncHeldDraftTabs());
    });
    unawaited(_bootstrapSellScreen());
  }

  /// Gom tải cấu hình + slot một lần rồi mới mở UI (bỏ flicker setState rời).
  Future<void> _bootstrapSellScreen() async {
    await _ensurePosDeviceIdentity();
    if (!mounted) return;

    final storeFut = PosSellStoreSettings.load();
    final printFut = PosSellPrintSettings.load();
    final thermalFut = PosThermalPrinterSettings.load();
    final industryFut = _api.getPosSellSettings();
    final sellersFut = _api.getPosSellSellers();
    final priceListsFut = _api.getPosPriceLists();
    var banksFut = _api.getPosBankAccounts();

    final store = await storeFut;
    final printS = await printFut;
    final thermal = await thermalFut;
    final industryRes = await industryFut;
    final sellersRes = await sellersFut;
    final priceListsRes = await priceListsFut;
    var banksRes = await banksFut;
    if (banksRes['isSuccess'] != true) {
      banksRes = await _api.getBankAccounts();
    }
    if (!mounted) return;

    // Industry → sell mode
    PosStoreSellSettingsDto? industry;
    var sellMode = _SellMode.quick;
    if (industryRes['isSuccess'] == true && industryRes['data'] is Map) {
      industry = PosStoreSellSettingsDto.fromJson(
          Map<String, dynamic>.from(industryRes['data'] as Map));
      switch (industry.defaultSellMode) {
        case 'normal':
          sellMode = _SellMode.normal;
        case 'delivery':
          sellMode = _SellMode.delivery;
        default:
          sellMode = _SellMode.quick;
      }
    }

    // Sellers
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final sellers = <Map<String, dynamic>>[];
    if (sellersRes['isSuccess'] == true && sellersRes['data'] is List) {
      for (final e in sellersRes['data'] as List) {
        if (e is Map) sellers.add(Map<String, dynamic>.from(e));
      }
    }
    final canPick = StoreRoleHelper.isManagerOrAbove(auth.userRole);
    Map<String, dynamic>? self;
    for (final item in sellers) {
      if (item['isSelf'] == true) {
        self = item;
        break;
      }
    }
    self ??= sellers.isNotEmpty ? sellers.first : null;
    final defaultSellerId = self?['employeeId']?.toString();

    // Banks / payment sources
    final accounts = <BankAccount>[];
    if (banksRes['isSuccess'] == true && banksRes['data'] is List) {
      for (final raw in banksRes['data'] as List) {
        final account = BankAccount.fromJson(raw as Map<String, dynamic>);
        if (account.isActive) accounts.add(account);
      }
    }
    final sources = <_PosPaymentSource>[_PosPaymentSource.cash];
    if (accounts.isNotEmpty) {
      final qrAccount = PosVietQrHelper.resolveAccount(
        accounts,
        preferredId: store.vietQrBankAccountId,
      );
      if (qrAccount != null) {
        sources.add(_PosPaymentSource.fromVietQR(qrAccount));
      }
      for (final account in accounts) {
        sources.add(_PosPaymentSource.fromBank(account));
      }
    }

    // Price lists (meta only — overrides after UI ready)
    final priceLists = <PosPriceList>[];
    PosPriceList? defaultPriceList;
    if (priceListsRes['isSuccess'] == true && priceListsRes['data'] is List) {
      for (final e in priceListsRes['data'] as List) {
        priceLists.add(PosPriceList.fromJson(e as Map<String, dynamic>));
      }
      defaultPriceList = pickDefaultPosPriceList(priceLists);
    }

    setState(() {
      _storeSettings = store;
      _applyPrintSettings(printS);
      _thermalPrintSettings = thermal;
      _industrySettings = industry;
      _sellMode = sellMode;
      _sellSellers = sellers;
      _canPickSeller = canPick;
      _defaultSellerEmployeeId = defaultSellerId;
      _bankAccounts = accounts;
      _paymentSources = sources;
      _priceLists = priceLists;
      for (final t in _tabs) {
        t.vatRate = store.defaultVatRate;
        t.sellerEmployeeId ??= defaultSellerId;
        if (t.priceListId == null && defaultPriceList != null) {
          t.priceListId = defaultPriceList.id;
          t.priceListLabel = defaultPriceList.name;
        }
        _ensureDefaultPaymentLines(t);
      }
      _syncPaidAmount();
      // Mở UI sớm — hydrate slot/giỏ chạy nền (tránh spinner dài).
      _sellReady = true;
    });

    PosPrintConfigSession.instance.invalidate(warehouseTemplateOnly: true);
    PosPrintConfigSession.instance.warmUp(
      warehouseTemplateId: printS.warehouseTemplateId,
    );

    _applyCustomerDisplayConfig(industry);
    unawaited(_bootstrapCustomerDisplay());
    unawaited(_refreshSystemUnreadNotifications());
    unawaited(_loadExpiryLotSummary());
    if (_tab.priceListId != null) {
      unawaited(() async {
        await _ensurePriceOverrides(_tab.priceListId!, force: true);
        if (mounted) await _applyPriceListToCart();
      }());
    }

    // Print queue + invoice slots — không chặn first paint.
    unawaited(() async {
      await _loadPendingPrintQueueFromDisk();
      if (!mounted) return;
      _startPendingPrintAutoRetry();
      await _bootstrapInvoiceSlots();
    }());
  }

  Future<void> _bootstrapCustomerDisplay() async {
    await CustomerDisplaySync.instance.startListening();
    final hasSecondary =
        await CustomerDisplaySync.instance.hasSecondaryDisplay();
    if (mounted) {
      setState(() => _hasSecondaryCustomerDisplay = hasSecondary || kIsWeb);
    } else {
      _hasSecondaryCustomerDisplay = hasSecondary || kIsWeb;
    }
    if (!CustomerDisplaySync.instance.enabled) return;
    // Luôn đẩy state (kể cả máy 1 màn) để khi mở màn phụ / popup nhận được bill.
    await _refreshCustomerDisplayPromos();
    _scheduleCustomerDisplayPublish();
    if (_hasSecondaryCustomerDisplay &&
        CustomerDisplaySync.instance.config.autoOpenOnPos) {
      await CustomerDisplaySync.instance.openSecondary();
    }
  }

  Future<void> _ensurePosDeviceIdentity() async {
    final d = await PosDeviceIdentity.get();
    if (!mounted) return;
    _posDeviceId = d.id;
    _posDeviceName = d.name;
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

    _priceOverrideCache.clear();

    final lists = (res['data'] as List)
        .map((e) => PosPriceList.fromJson(e as Map<String, dynamic>))
        .toList();
    final defaultList = pickDefaultPosPriceList(lists);

    setState(() {
      _priceLists = lists;
      if (_tab.priceListId == null && defaultList != null) {
        _tab.priceListId = defaultList.id;
        _tab.priceListLabel = defaultList.name;
      }
    });

    if (_tab.priceListId != null) {
      await _ensurePriceOverrides(_tab.priceListId!, force: true);
      if (mounted) await _applyPriceListToCart();
    }
  }

  void _onPriceListsChanged() {
    _priceOverrideCache.clear();
    final id = _tab.priceListId;
    if (id == null || id.isEmpty) return;
    unawaited(() async {
      await _ensurePriceOverrides(id, force: true);
      if (mounted) await _applyPriceListToCart();
    }());
  }

  Future<Map<String, double>> _ensurePriceOverrides(
    String priceListId, {
    bool force = false,
  }) async {
    if (!force) {
      final cached = _priceOverrideCache[priceListId];
      if (cached != null) return cached;
    }

    final res = await _api.getPosPriceListResolvedPrices(priceListId);
    final map = res['isSuccess'] == true && res['data'] is List
        ? buildPosPriceOverrideMap(res['data'] as List)
        : <String, double>{};
    _priceOverrideCache[priceListId] = map;
    return map;
  }

  /// Gắn lại giá giỏ theo bảng hiện tại (overrides rỗng → về giá catalog).
  Future<void> _applyPriceListToCart({VoidCallback? onMutate}) async {
    final overrides = _currentPriceOverrides;
    for (final line in List<_SellCartLine>.from(_tab.cart)) {
      var views = posProductHasEmbeddedSellViews(line.product)
          ? buildPosSellUnitViewsFromProduct(line.product)
          : await loadPosSellUnitViews(_api, line.product);
      if (!mounted) return;
      views = applyPosPriceListToViews(views, line.product, overrides);
      final fresh = views
              .where((v) =>
                  v.viewKey == line.activeViewKey ||
                  (v.variantId == line.variantId && v.unitId == line.unitId))
              .firstOrNull ??
          (views.isNotEmpty ? views.first : null);
      line.unitViews = views;
      if (fresh == null) continue;
      line.activeViewKey = fresh.viewKey;
      line.unitLabel = fresh.label;
      line.displayCode = fresh.displayCode;
      line.unitId = fresh.unitId;
      line.variantId = fresh.variantId;
      line.unitPrice = fresh.basePrice;
      line.priceCtrl.text = fresh.basePrice == fresh.basePrice.roundToDouble()
          ? fresh.basePrice.toStringAsFixed(0)
          : fresh.basePrice.toStringAsFixed(2);
    }
    if (!mounted) return;
    // Đổi bảng giá: luôn phân bổ lại TT + ép rebuild panel (kể cả sheet mobile).
    _tab.paymentsManuallyEdited = false;
    _tab.paidManuallyEdited = false;
    setState(() => _syncPaidAmount());
    _notifyPaymentUi(onMutate);
  }

  Future<void> _selectPriceList(PosPriceList list, {VoidCallback? onMutate}) async {
    final overrides = await _ensurePriceOverrides(list.id, force: true);
    if (!mounted) return;
    _tab.priceListId = list.id;
    _tab.priceListLabel = list.name;
    await _applyPriceListToCart(onMutate: onMutate);
    _scheduleDraftAutosave();
    if (!mounted) return;
    NotificationOverlayManager().showSuccess(
      title: 'Đã đổi bảng giá',
      message: tr('${list.name} · ${overrides.length} mức giá'),
    );
  }

  Future<void> _clearPriceListSelection({
    String label = 'Bảng giá chung',
    VoidCallback? onMutate,
  }) async {
    _tab.priceListId = null;
    _tab.priceListLabel = label;
    await _applyPriceListToCart(onMutate: onMutate);
    _scheduleDraftAutosave();
  }

  _PosPaymentSource _sourceByKey(String key) {
    return _paymentSources.firstWhere(
      (s) => s.key == key,
      orElse: () => _PosPaymentSource.cash,
    );
  }

  @override
  void dispose() {
    if (identical(NavigationNotifier.posHandleSystemBack, _onSystemBack)) {
      NavigationNotifier.posHandleSystemBack = null;
    }
    if (_isPosFullscreen && !kIsWeb) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _pendingPrintRetryTimer?.cancel();
    _timedBillingTimer?.cancel();
    _stopDraftLockHeartbeat();
    _floorRealtime.dispose();
    _draftAutosaveTimer?.cancel();
    _customerSearchDebounce?.cancel();
    _customerDisplayPublishTimer?.cancel();
    final deviceId = _posDeviceId;
    final deviceName = _posDeviceName;
    if (deviceId != null && deviceName != null) {
      for (final t in _tabs) {
        final id = t.draftOrderId;
        if (id == null || id.isEmpty || t.draftReadOnly) continue;
        unawaited(_api.unlockPosSaleDraft(
          id,
          deviceId: deviceId,
          deviceName: deviceName,
        ));
      }
    }
    ScreenRefreshNotifier.posSellStockPatch.removeListener(_syncCartStockFromPatch);
    ScreenRefreshNotifier.posPriceLists.removeListener(_onPriceListsChanged);
    ScreenRefreshNotifier.posSellIndustry.removeListener(_onSellIndustryChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _tabScrollCtrl.dispose();
    _productSearchFocus.dispose();
    _floorSearchCtrl.dispose();
    _floorSearchFocus.dispose();
    _customerSearchFocus.dispose();
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  /// Nút Back Android: đang xem đơn bàn → về sơ đồ (không về trang chủ).
  Future<bool> _onSystemBack() async {
    if (!mounted) return false;
    if (_mobileProductPickerOpen) {
      setState(() => _mobileProductPickerOpen = false);
      return true;
    }
    if (_useFloorAsPrimary && !_floorMapVisible) {
      await _returnToFloorMap();
      return true;
    }
    return false;
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

  void _applyPrintSettings(PosSellPrintSettings s) {
    _printSettings = s;
    // Gieo chip nhanh từ thiết lập — user có thể bật/tắt cho lần TT này.
    _quickPrintInvoice = s.autoPrint;
    _quickPrintCup = s.shouldPrintCupOnPay;
  }

  Future<void> _loadPrintSettings() async {
    final s = await PosSellPrintSettings.load();
    final thermal = await PosThermalPrinterSettings.load();
    if (mounted) {
      setState(() {
        _applyPrintSettings(s);
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

  Future<void> _loadIndustrySettings() async {
    final res = await _api.getPosSellSettings();
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) return;

    final raw = Map<String, dynamic>.from(res['data'] as Map);
    final dto = PosStoreSellSettingsDto.fromJson(raw);
    final prev = _industrySettings;

    // Không nhảy F&B → bán lẻ khi API thiếu/lệch sellProfile.
    final profileRaw =
        (raw['sellProfile'] ?? raw['SellProfile'])?.toString().trim();
    final profileMissing = profileRaw == null || profileRaw.isEmpty;
    final wouldDowngradeToRetail = prev != null &&
        prev.sellProfile != PosSellProfile.retail &&
        (profileMissing || dto.sellProfile == PosSellProfile.retail) &&
        profileRaw?.toLowerCase() != 'retail' &&
        profileRaw != '0';
    final effective = wouldDowngradeToRetail
        ? dto.copyWith(
            sellProfile: prev.sellProfile,
            enableResources: prev.enableResources,
            showFloorPlan: prev.showFloorPlan,
            allowProvisionalBill: prev.allowProvisionalBill,
            enableHourlyBilling: prev.enableHourlyBilling,
            enableSessionPacks: prev.enableSessionPacks,
            requireResourceOnSale: prev.requireResourceOnSale,
            enableMultiDeviceDraftLock: prev.enableMultiDeviceDraftLock,
            promptGuestCountOnOpen: prev.promptGuestCountOnOpen,
            allowNegativeStock: prev.allowNegativeStock,
            defaultHourlyProductId: prev.defaultHourlyProductId,
          )
        : dto;

    final useFloor = (effective.showFloorPlan || effective.enableResources) &&
        (effective.sellProfile == PosSellProfile.restaurant ||
            effective.sellProfile == PosSellProfile.roomHourly ||
            effective.sellProfile == PosSellProfile.salon);
    final leavingTables = prev != null &&
        (prev.enableResources || prev.showFloorPlan) &&
        !effective.enableResources &&
        !effective.showFloorPlan;
    setState(() {
      _industrySettings = effective;
      if (useFloor && !_isTableOrderMode) _floorMapVisible = true;
      if (leavingTables || !useFloor) {
        _detachTableBindingsAfterIndustryLeave();
        _floorMapVisible = false;
      }
      switch (effective.defaultSellMode) {
        case 'normal':
          _sellMode = _SellMode.normal;
        case 'delivery':
          _sellMode = _SellMode.delivery;
        default:
          _sellMode = _SellMode.quick;
      }
    });
    _applyCustomerDisplayConfig(effective);
    unawaited(_refreshCustomerDisplayPromos());
    _scheduleCustomerDisplayPublish();
  }

  /// F&B → bán lẻ: bỏ gắn bàn trên tab để không kẹt UI đơn bàn.
  void _detachTableBindingsAfterIndustryLeave() {
    for (final t in _tabs) {
      t.serviceResourceId = null;
      t.resourceSessionId = null;
      t.serviceStartedAt = null;
      t.serviceResourceName = null;
      t.serviceAreaName = null;
      t.tableGuestCount = 0;
      t.accumulatedPauseMinutes = 0;
      t.sessionPausedAt = null;
      t.sessionIsPaused = false;
      t.serviceDefaultHourlyRate = null;
    }
  }

  void _onSellIndustryChanged() {
    unawaited(_loadIndustrySettings());
  }

  bool get _industryUsesTables =>
      _industrySettings?.enableResources == true ||
      _industrySettings?.showFloorPlan == true;

  bool get _showFloorPlan =>
      _industrySettings?.showFloorPlan == true ||
      _industrySettings?.enableResources == true;

  /// F&B / Bi-a / Salon: sơ đồ là màn chính khi bán hàng.
  bool get _useFloorAsPrimary {
    if (!_showFloorPlan) return false;
    final p = _industrySettings?.sellProfile;
    return p == PosSellProfile.restaurant ||
        p == PosSellProfile.roomHourly ||
        p == PosSellProfile.salon;
  }

  /// true = đang xem sơ đồ (chưa vào bàn).
  bool _floorMapVisible = true;
  /// Tăng sau thanh toán để remount sơ đồ (reload trạng thái bàn).
  int _floorMapEpoch = 0;
  /// Tổng tạm tính các bàn đang có đơn (đẩy từ sơ đồ).
  double _floorActiveSubtotal = 0;
  /// Số bàn đang mở / có đơn (đẩy từ sơ đồ).
  int _floorActiveOpenCount = 0;
  /// Tablet lớn (≥1024) + F&B: true = đang ở màn thanh toán riêng (sau khi
  /// bấm "Thanh toán" từ màn chọn món), false = đang ở màn chọn món/giỏ hàng.
  bool _tabletPaymentStage = false;
  Timer? _customerDisplayPublishTimer;
  List<CustomerDisplayPromoItem> _customerDisplayPromos = const [];
  /// Máy có display phụ thật (Android DisplayManager). Web luôn true (popup).
  bool _hasSecondaryCustomerDisplay = kIsWeb;
  /// Đang phóng toàn màn hình (browser fullscreen / immersive).
  bool _isPosFullscreen = false;
  int _systemUnreadNotifications = 0;

  void _scheduleCustomerDisplayPublish() {
    _customerDisplayPublishTimer?.cancel();
    _customerDisplayPublishTimer = Timer(const Duration(milliseconds: 180), () {
      unawaited(_publishCustomerDisplay());
    });
  }

  void _applyCustomerDisplayConfig([PosStoreSellSettingsDto? industry]) {
    final dto = industry ?? _industrySettings;
    final cfg = CustomerDisplayConfig.fromExtraJson(dto?.extraJson);
    CustomerDisplaySync.instance.applyConfig(cfg);
  }

  Future<void> _refreshCustomerDisplayPromos() async {
    final cfg = CustomerDisplaySync.instance.config;
    if (!cfg.enabled) return;
    // Resolve public-serve / Drive / Dropbox cho màn phụ.
    String pub(String? raw) => resolveCustomerDisplayMediaUrl(_api, raw);

    final videos = [
      for (final u in cfg.promoVideoUrls)
        if (pub(u).isNotEmpty)
          CustomerDisplayPromoItem(title: 'Giới thiệu', videoUrl: pub(u)),
    ];
    final customImages = [
      for (final u in cfg.promoImageUrls)
        if (pub(u).isNotEmpty)
          CustomerDisplayPromoItem(title: '', imageUrl: pub(u)),
    ];
    if (!cfg.useProductImages) {
      _customerDisplayPromos = [...videos, ...customImages];
      await CustomerDisplaySync.instance.publishIdle(
        promoItems: _customerDisplayPromos,
      );
      return;
    }
    try {
      final fromProducts = <CustomerDisplayPromoItem>[];
      final storeId = _storeId?.trim() ?? '';
      List<PosProduct> products = const [];
      if (storeId.isNotEmpty) {
        final cached = await PosSellCatalogCache.instance.read(storeId);
        products = cached?.items ?? const [];
      }
      if (products.isEmpty) {
        final res = await _api.getPosProducts(
          pageSize: 60,
          isDirectSale: true,
          sortBy: PosProductSortBy.name,
          sortDesc: false,
        );
        if (res['isSuccess'] == true && res['data'] is Map) {
          final items = (res['data'] as Map)['items'] ??
              (res['data'] as Map)['Items'];
          if (items is List) {
            products = [
              for (final e in items)
                if (e is Map)
                  PosProduct.fromJson(Map<String, dynamic>.from(e)),
            ];
          }
        }
      }
      for (final p in products) {
        final resolved = pub(p.imageUrl);
        if (resolved.isEmpty) continue;
        fromProducts.add(CustomerDisplayPromoItem(
          title: '',
          imageUrl: resolved,
        ));
        if (fromProducts.length >= 24) break;
      }
      // Thứ tự: video → ảnh upload → ảnh SP.
      _customerDisplayPromos = [
        ...videos,
        ...customImages,
        ...fromProducts,
      ];
    } catch (_) {
      _customerDisplayPromos = [...videos, ...customImages];
    }
    await CustomerDisplaySync.instance.publishIdle(
      promoItems: _customerDisplayPromos,
    );
  }

  Future<void> _publishCustomerDisplay() async {
    final sync = CustomerDisplaySync.instance;
    if (!sync.enabled) return;
    final bound = _tab.isTableBound || (_tab.serviceResourceId ?? '').isNotEmpty;
    final hasCart = _tab.cart.isNotEmpty;
    if (!bound && !hasCart) {
      await sync.publishIdle(promoItems: _customerDisplayPromos);
      return;
    }
    final lines = _tab.cart
        .map((c) => CustomerDisplayLine(
              name: c.product.name,
              qty: c.qty,
              unitPrice: c.unitPrice + c.toppingExtraPerUnit,
              lineTotal: c.lineTotal,
              unitLabel: c.unitLabel,
              imageUrl: c.product.imageUrl,
              note: c.noteWithToppings,
            ))
        .toList();
    final rawName = (_tab.serviceResourceName ?? '').trim();
    final label = rawName.isNotEmpty
        ? formatPosTableLabel(
            areaName: _tab.serviceAreaName,
            tableName: _tab.serviceResourceName,
          )
        : (hasCart ? 'Đơn hiện tại' : null);
    await sync.publishActive(
      tableLabel: label,
      areaName: _tab.serviceAreaName,
      orderNo: _tab.draftOrderNo,
      guestCount: _tab.tableGuestCount,
      lines: lines,
      subtotal: _subTotal,
      discount: _tab.discount + _tab.voucherDiscount + _tab.pointsDiscount,
      total: _grandTotal,
      storeName: _warehouseBranchName,
      promoItems: _customerDisplayPromos,
    );
  }

  Future<void> _togglePosFullscreen() async {
    if (kIsWeb) {
      final active = await togglePosBrowserFullscreen();
      if (!mounted) return;
      setState(() => _isPosFullscreen = active);
      return;
    }
    final next = !_isPosFullscreen;
    if (next) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (!mounted) return;
    setState(() => _isPosFullscreen = next);
  }

  Future<void> _refreshSystemUnreadNotifications() async {
    try {
      final summary = await _api.getNotificationSummary();
      final n = summary['unreadCount'];
      final count = n is int ? n : int.tryParse('$n') ?? 0;
      if (!mounted) return;
      setState(() => _systemUnreadNotifications = count);
    } catch (_) {}
  }

  void _openSystemNotifications() {
    if (NavigationNotifier.mainLayoutReady.value) {
      NavigationNotifier.goToNotifications();
      return;
    }
    NavigationNotifier.goToModule('Notification');
  }

  Future<void> _openCustomerDisplay() async {
    final sync = CustomerDisplaySync.instance;
    if (!sync.enabled) {
      NotificationOverlayManager().showWarning(
        title: 'Màn hình phụ',
        message: tr('Bật trong Cài đặt ngành hàng trước'),
      );
      return;
    }
    final hasSecondary = await sync.hasSecondaryDisplay();
    if (mounted) {
      setState(() => _hasSecondaryCustomerDisplay = hasSecondary || kIsWeb);
    }
    if (!hasSecondary && !kIsWeb) {
      if (!mounted) return;
      NotificationOverlayManager().showWarning(
        title: 'Máy chỉ có 1 màn hình',
        message: tr('Màn hình phụ chỉ mở khi thiết bị có display thứ hai (màn khách).'),
      );
      return;
    }
    await _refreshCustomerDisplayPromos();
    _scheduleCustomerDisplayPublish();
    final ok = await sync.openSecondary();
    if (!mounted) return;
    if (ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã mở màn hình phụ',
        message: tr('Ảnh/video | hóa đơn — chỉ trên màn khách'),
      );
    } else {
      NotificationOverlayManager().showWarning(
        title: 'Không mở được màn phụ',
        message: kIsWeb
            ? 'Cho phép popup hoặc mở #/customer-display trên màn khác'
            : 'Không phát hiện display phụ — không chiếu trên màn chính',
      );
    }
  }

  Future<void> _attachFloorResult(Map<String, dynamic> result) async {
    final orderId = result['saleOrderId']?.toString();
    final sessionId = result['sessionId']?.toString();
    final resourceId = result['resourceId']?.toString();
    final resourceName = result['resourceName']?.toString();
    final areaName = result['areaName']?.toString();
    final startedRaw = result['startedAt']?.toString();
    final startedAt = parsePosApiUtc(startedRaw);
    final guestRaw = result['guestCount'];
    final guestCount = guestRaw is num
        ? guestRaw.toInt()
        : int.tryParse('$guestRaw') ?? 0;
    final pauseAccumRaw = result['accumulatedPauseMinutes'];
    final pauseAccum = pauseAccumRaw is num
        ? pauseAccumRaw.toInt()
        : int.tryParse('$pauseAccumRaw') ?? 0;
    final pausedAt = parsePosApiUtc(result['pausedAt']?.toString());
    final isPaused = result['isPaused'] == true;
    final rateRaw = result['defaultHourlyRate'];
    final defaultRate = rateRaw is num
        ? rateRaw.toDouble()
        : double.tryParse('$rateRaw');
    final paidRaw = result['paidAmount'] ?? result['depositApplied'];
    final paidFromDeposit = paidRaw is num
        ? paidRaw.toDouble()
        : double.tryParse('$paidRaw');

    void applyPauseMeta(_SellInvoiceTab tab) {
      tab.accumulatedPauseMinutes = pauseAccum;
      tab.sessionPausedAt = pausedAt;
      tab.sessionIsPaused = isPaused;
      if (defaultRate != null) tab.serviceDefaultHourlyRate = defaultRate;
      if (paidFromDeposit != null && paidFromDeposit > 0) {
        tab.paidAmount = paidFromDeposit;
      }
    }
    if (orderId != null && orderId.isNotEmpty) {
      _floorReleasedOrderIds.remove(orderId);
      _suspendDraftAutosave = true;
      final forceClaim = result['forceClaim'] == true;
      await _openDraftOrder(
        orderId,
        silent: true,
        viewOnlyOnConflict: !forceClaim,
        forceClaim: forceClaim,
      );
      if (!mounted) return;
      if (_tab.draftOrderId != orderId) {
        NotificationOverlayManager().showError(
          title: 'Không vào được bàn',
          message: tr('Đơn tạm chưa tải — vẫn ở sơ đồ bàn'),
        );
        return;
      }
      if (forceClaim && _tab.draftReadOnly) {
        NotificationOverlayManager().showError(
          title: 'Không lấy được quyền',
          message: _tab.lockedByLabel != null
              ? 'Bàn vẫn đang mở trên ${_tab.lockedByLabel} — chờ máy đó về sơ đồ'
              : 'Máy kia vẫn đang giữ bàn — thử lại sau vài giây',
        );
        setState(() {
          _floorMapVisible = true;
          _tabletPaymentStage = false;
        });
        _suspendDraftAutosave = false;
        return;
      }
      // Chỉ rời sơ đồ khi đã tải được đơn vào tab.
      setState(() {
        _tab.serviceResourceId = resourceId ?? _tab.serviceResourceId;
        _tab.resourceSessionId = sessionId ?? _tab.resourceSessionId;
        _tab.serviceResourceName = resourceName ?? _tab.serviceResourceName;
        _tab.serviceAreaName = areaName ?? _tab.serviceAreaName;
        if (startedAt != null) _tab.serviceStartedAt = startedAt;
        _tab.serviceStartedAt ??= DateTime.now().toUtc();
        if (guestCount > 0) _tab.tableGuestCount = guestCount;
        applyPauseMeta(_tab);
        _tab.localDirty = false;
        _floorMapVisible = false;
        _tabletPaymentStage = false;
        _mobileProductPickerOpen = false;
      });
      // Giữ suspend=true cho tới khi verify xong — chặn autosave đè giỏ.
      await _verifyTableCartHydrated(orderId);
      if (!mounted) return;
      if (paidFromDeposit != null && paidFromDeposit > 0) {
        setState(() {
          _tab.paymentsManuallyEdited = true;
          final cash = _SellPaymentLine(sourceKey: _PosPaymentSource.cashKey);
          cash.amount = paidFromDeposit;
          cash.amountCtrl.text = _moneyFmt.format(paidFromDeposit);
          _tab.paymentLines
            ..clear()
            ..add(cash);
          _tab.paidAmount = paidFromDeposit;
          _tab._paidCtrl.text = _moneyFmt.format(paidFromDeposit);
        });
      }
      setState(() => _suspendDraftAutosave = false);
      _refreshTimedLineQtys();
      _scheduleCustomerDisplayPublish();
      unawaited(_syncHeldDraftTabs());
      return;
    }
    if (resourceId != null && resourceId.isNotEmpty) {
      _suspendDraftAutosave = false;
      setState(() {
        _tab.serviceResourceId = resourceId;
        _tab.resourceSessionId = sessionId;
        _tab.serviceResourceName = resourceName;
        _tab.serviceAreaName = areaName;
        _tab.serviceStartedAt = startedAt ?? DateTime.now().toUtc();
        if (guestCount > 0) _tab.tableGuestCount = guestCount;
        applyPauseMeta(_tab);
        _floorMapVisible = false;
        _tabletPaymentStage = false;
        _mobileProductPickerOpen = false;
      });
      _refreshTimedLineQtys();
      _scheduleCustomerDisplayPublish();
    }
  }

  /// Đang trong đơn của một bàn/phòng (không còn dùng tab Hóa đơn 1/2/3).
  bool get _isTableOrderMode => _industryUsesTables && _tab.isTableBound;

  Widget _buildTableGuestIconButton({
    Color iconColor = Colors.white,
    bool compact = false,
  }) {
    if (!_isTableOrderMode) return const SizedBox.shrink();
    final count = _tab.tableGuestCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: tr(count > 0 ? '$count khách' : 'Số khách'),
          onPressed:
              _tab.draftReadOnly ? null : () => unawaited(_editTableGuestCount()),
          icon: Icon(
            Icons.people_outline,
            size: 22,
            color: iconColor,
          ),
        ),
        if (count > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: compact ? PosTheme.kiotBlue : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: compact ? Colors.white : PosTheme.kiotBlue,
                  width: 1,
                ),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                tr(count > 99 ? '99+' : '$count'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: compact ? Colors.white : PosTheme.kiotBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editTableGuestCount() async {
    final sid = _tab.resourceSessionId;
    if (sid == null || sid.isEmpty || _tab.draftReadOnly) return;
    final ctrl = TextEditingController(
      text: tr('${_tab.tableGuestCount > 0 ? _tab.tableGuestCount : 2}'),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Số khách')),
        content: PosNoSoftKeyboardField(
          controller: ctrl,
          autofocus: true,
          allowDecimal: false,
          keypadTitle: 'Số khách',
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: tr('Số khách đang dùng bàn'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = (int.tryParse(ctrl.text.trim()) ?? 2).clamp(1, 99);
    final res = await _api.setPosResourceSessionGuests(sid, n);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() => _tab.tableGuestCount = n);
      _scheduleCustomerDisplayPublish();
    } else {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: res['message']?.toString() ?? 'Lỗi',
      );
    }
  }

  /// Về sơ đồ: nhả khóa ngay để máy khác mở/claim được.
  /// Chỉ xem (draftReadOnly) → không unlock / không «tạm rời» — giữ «Máy khác» của máy đang sửa.
  Future<void> _returnToFloorMap() async {
    _draftAutosaveTimer?.cancel();
    _stopDraftLockHeartbeat();
    _suspendDraftAutosave = true;
    final rid = _tab.serviceResourceId;
    final sid = _tab.resourceSessionId;
    final emptyCart = _tab.cart.isEmpty;
    final hasDraft = (_tab.draftOrderId ?? '').isNotEmpty;
    final draftId = _tab.draftOrderId;
    final wasViewOnly = _tab.draftReadOnly;

    // Đánh dấu nhả trước — chặn heartbeat/autosave gắn lại khóa.
    // Chỉ máy đang giữ khóa mới vào «tạm rời»; máy chỉ xem thoát ra không đụng khóa.
    if (!wasViewOnly && hasDraft && draftId != null && draftId.isNotEmpty) {
      _floorReleasedOrderIds.add(draftId);
      if (mounted) {
        setState(() {
          _tab.draftReadOnly = true;
          _tab.lockedByLabel = null;
        });
      }
    }

    // Đợi autosave đang chạy xong (không ghi thêm — tránh re-lock trước unlock).
    // Giới hạn ngắn — unlock phải chạy sớm để máy khác thấy «tạm rời» kịp thời.
    for (var i = 0; i < 30 && _autosavingDraft; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (!wasViewOnly && hasDraft && draftId != null && draftId.isNotEmpty) {
      final unlocked = await _unlockDraftQuietly(draftId);
      if (!unlocked && mounted) {
        NotificationOverlayManager().showWarning(
          title: 'Nhả khóa chưa chắc chắn',
          message: tr('Đã về sơ đồ — máy khác thử «Lấy quyền» sau vài giây nếu vẫn báo đang sửa'),
        );
      }
    }

    if (emptyCart && !hasDraft && (rid ?? '').isNotEmpty) {
      await _api.freePosServiceResource(rid!);
    } else if (emptyCart && !hasDraft && sid != null && sid.isNotEmpty) {
      await _api.closePosResourceSession(sid);
    }
    if (!mounted) return;
    setState(() {
      if (emptyCart && !hasDraft) {
        _tab.reset(defaultVatRate: _storeSettings.defaultVatRate);
        _tab.sellerEmployeeId = _defaultSellerEmployeeId;
        _syncPaidAmount();
        _pendingKitchenCancels.clear();
      } else if (hasDraft) {
        _tab.localDirty = false;
        _tab.draftReadOnly = true;
        _tab.lockedByLabel = null;
      }
      _floorMapVisible = true;
      _tabletPaymentStage = false;
      _mobileProductPickerOpen = false;
      _floorMapEpoch++;
      _suspendDraftAutosave = false;
    });
    _scheduleCustomerDisplayPublish();
  }

  Future<void> _openResourceFloor() async {
    if (_useFloorAsPrimary) {
      await _returnToFloorMap();
      return;
    }
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => PosResourceFloorScreen(
          manageMode: false,
          sellProfile: _industrySettings?.sellProfile,
          promptGuestCountOnOpen:
              _industrySettings?.promptGuestCountOnOpen == true,
          allowProvisionalBill:
              _industrySettings?.allowProvisionalBill != false,
          onResourceFreed: _onFloorResourceFreed,
          zeroPendingKitchenResourceIds: _kitchenClearedResourceIds,
          billRequestedResourceIds: _billRequestedResourceIds,
          releasedOrderIds: Set<String>.from(_floorReleasedOrderIds),
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _attachFloorResult(result);
  }

  /// Sơ đồ trả bàn trống / chuyển-tách bàn → hủy draft/session local nếu đúng bàn đang gắn.
  void _onFloorResourceFreed(String resourceId) {
    _draftAutosaveTimer?.cancel();
    _suspendDraftAutosave = true;
    final key = resourceId.toLowerCase();
    if (_billRequestedResourceIds.any((e) => e.toLowerCase() == key) ||
        _kitchenClearedResourceIds.any((e) => e.toLowerCase() == key)) {
      setState(() {
        _billRequestedResourceIds = {
          for (final e in _billRequestedResourceIds)
            if (e.toLowerCase() != key) e
        };
        _kitchenClearedResourceIds = {
          for (final e in _kitchenClearedResourceIds)
            if (e.toLowerCase() != key) e
        };
      });
    }
    final matchResource =
        (_tab.serviceResourceId ?? '').toLowerCase() == key;
    // Luôn tắt dirty nếu đang gắn đúng bàn — kể cả khi đang xem sơ đồ.
    if (matchResource) {
      _tab.localDirty = false;
    }
    if (!matchResource) {
      _suspendDraftAutosave = false;
      return;
    }
    final stayOnFloor = _floorMapVisible;
    setState(() {
      _tab.reset(defaultVatRate: _storeSettings.defaultVatRate);
      _tab.sellerEmployeeId = _defaultSellerEmployeeId;
      _syncPaidAmount();
      _pendingKitchenCancels.clear();
      _floorMapVisible = true;
      _tabletPaymentStage = false;
      // Đang ở sơ đồ (chuyển/gộp/tách): không remount — tránh mất optimistic + reload.
      if (!stayOnFloor) {
        _floorMapEpoch++;
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      _suspendDraftAutosave = false;
    });
  }

  Future<void> _kitchenSendCurrentTable() async {
    if (_kitchenSending || _checkingOut || _parking) return;
    if (_industrySettings?.sellProfile != PosSellProfile.restaurant) return;
    final sid = _tab.resourceSessionId;
    if (sid == null || sid.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa gắn bàn',
        message: tr('Chọn bàn trước khi báo chế biến'),
      );
      return;
    }

    final cancelLines = _collectKitchenCancelLines();
    final pendingLines =
        _tab.cart.where((l) => l.kitchenPendingQty > 0).toList();
    if (cancelLines.isEmpty && pendingLines.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không có thay đổi',
        message: tr('Chưa có món mới hoặc hủy chờ báo bếp'),
      );
      return;
    }

    setState(() => _kitchenSending = true);
    try {
    // 1) Gộp hủy → một phiếu + ghi log (in khi bấm báo bếp, không in từng lần giảm SL).
    if (cancelLines.isNotEmpty) {
      final voided = await _voidKitchenSentLines(cancelLines);
      if (!mounted) return;
      if (!voided) {
        // User hủy dialog lý do — giữ pending hủy, không gửi món mới.
        return;
      }
      setState(() {
        _pendingKitchenCancels.clear();
        for (final l in _tab.cart) {
          l.kitchenCancelPendingQty = 0;
        }
      });
    }

    if (pendingLines.isEmpty && cancelLines.isNotEmpty) {
      // Chỉ hủy — toast đã hiện trong _voidKitchenSentLines.
      return;
    }
    if (pendingLines.isEmpty) {
      return;
    }

    // 2) Đẩy draft lên server trước KitchenSend — chỉ máy đang giữ khóa mới được.
    if (!await _ensureCanEditActiveDraft()) return;
    if (!await _ensureLockHeldForTableEdit(_tab)) {
      NotificationOverlayManager().showError(
        title: 'Không giữ được bàn',
        message: _tab.lockedByLabel != null
            ? 'Bàn vẫn mở trên ${_tab.lockedByLabel}'
            : 'Thử lại sau vài giây',
      );
      return;
    }
    if (!await _awaitDraftAutosaveIdle(
          busyMessage: 'Đợi lưu xong rồi báo bếp lại')) {
      return;
    }
    await _ensureDeviceReady();
    if ((_posDeviceId ?? '').isEmpty || (_posDeviceName ?? '').isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiếu mã máy',
        message: tr('Không xác định được máy — mở lại app rồi thử báo bếp'),
      );
      return;
    }
    if (_tab.draftReadOnly) {
      NotificationOverlayManager().showWarning(
        title: 'Chỉ xem',
        message: _tab.lockedByLabel != null
            ? 'Bàn đang mở trên ${_tab.lockedByLabel} — không báo bếp được'
            : 'Máy khác đang mở bàn này — nhờ máy đó thoát về sơ đồ rồi mở lại',
      );
      return;
    }
    final orderId = _tab.draftOrderId;
    if (orderId != null && orderId.isNotEmpty) {
      _tab.draftReadOnly = false;
    }
    // Luôn persist — kể cả khi !localDirty (kitchenSentQty có thể vừa đổi).
    _tab.localDirty = true;
    final saved = await _persistDraftAutosave(
      forTab: _tab,
      showLockError: true,
      retryOnConflict: false,
    );
    if (!mounted) return;
    if (!saved) {
      NotificationOverlayManager().showError(
        title: 'Chưa lưu được đơn',
        message: tr('Không báo bếp được — kiểm tra máy đang giữ bàn'),
      );
      return;
    }

    final res = await _api.kitchenSendPosResourceSession(
      sid,
      deviceId: _posDeviceId,
      deviceName: _posDeviceName,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không gửi được',
      );
      return;
    }
    final data = res['data'] is Map ? res['data'] as Map : const {};
    final n = (data['sentLines'] as num?)?.toInt() ?? 0;
    final already = data['alreadyAllSent'] == true || n <= 0;
    final remoteVer = data['lockVersion'] is num
        ? (data['lockVersion'] as num).toInt()
        : int.tryParse('${data['lockVersion']}');

    final sendTicketLines = pendingLines
        .map((l) => KitchenTicketLine(
              productName: l.product.name,
              qty: l.kitchenPendingQty,
              unitName: l.unitLabel,
              note: l.noteWithToppings,
              productId: l.product.id,
            ))
        .where((l) => l.qty > 0)
        .toList();

    // Chỉ in khi server ghi nhận món mới. Nếu alreadyAllSent mà vẫn in
    // theo phiếu client → phiếu báo chế biến bị in lại (thường không liên tiếp
    // vì lệch đồng bộ / báo bếp từ sơ đồ trước đó).
    final shouldPrint = sendTicketLines.isNotEmpty && !already;
    if (shouldPrint) {
      if (mounted) {
        setState(() {
          for (final l in pendingLines) {
            l.kitchenSentQty = l.qty;
            l.kitchenCancelPendingQty = 0;
            l.warehouseSlipPrintedQty =
                l.warehouseSlipPrintedQty < l.kitchenSentQty
                    ? l.kitchenSentQty
                    : l.warehouseSlipPrintedQty;
          }
          if (remoteVer != null && remoteVer > 0) {
            _tab.lockVersion = remoteVer;
          }
          _tab.localDirty = true;
        });
      }
      await _persistDraftAutosave(forTab: _tab, retryOnConflict: true);
      if (!mounted) return;

      final kitchenOk = await printKitchenCompactSlip(
        tableName: formatPosTableLabel(
          areaName: _tab.serviceAreaName,
          tableName: _tab.serviceResourceName,
        ),
        isCancel: false,
        lines: sendTicketLines,
        senderName: _kitchenSenderName(),
        orderNo: _tab.draftOrderNo,
        waitForCompletion: false,
      );
      if (!kitchenOk) {
        _enqueueFailedKitchenPrint(
          PendingKitchenPrintJob(
            id: 'kitchen_${DateTime.now().millisecondsSinceEpoch}',
            isCancel: false,
            tableName: formatPosTableLabel(
              areaName: _tab.serviceAreaName,
              tableName: _tab.serviceResourceName,
            ),
            senderName: _kitchenSenderName(),
            orderNo: _tab.draftOrderNo,
            lines: sendTicketLines,
            errorMessage: 'Gửi lệnh in thất bại — kiểm tra máy in / giấy',
          ),
        );
      }
      if (_printSettings.cupLabelPrintMode.autoWithKitchen) {
        await _printCupLabelsForLines(pendingLines, showFeedback: false);
      }

      if (!mounted) return;
      final rid = _tab.serviceResourceId;
      if (rid != null && rid.isNotEmpty) {
        setState(() {
          _kitchenClearedResourceIds = {
            ..._kitchenClearedResourceIds,
            rid.toLowerCase(),
          };
        });
      }
      if (kitchenOk) {
        // Silent khi báo bếp + in OK; chỉ cảnh báo khi chưa in được phiếu.
        debugPrint('POS kitchen send OK: ${_tab.serviceResourceName}');
      } else {
        NotificationOverlayManager().showWarning(
          title: 'Đã báo bếp — chưa in phiếu',
          message: tr('Mở biểu tượng chờ in để in lại'),
        );
      }
      return;
    }

    // Không còn phiếu client — thật sự không có món mới.
    if (mounted) {
      setState(() {
        for (final l in _tab.cart) {
          l.kitchenSentQty = l.qty;
          l.kitchenCancelPendingQty = 0;
          l.warehouseSlipPrintedQty =
              l.warehouseSlipPrintedQty < l.kitchenSentQty
                  ? l.kitchenSentQty
                  : l.warehouseSlipPrintedQty;
        }
        if (remoteVer != null && remoteVer > 0) {
          _tab.lockVersion = remoteVer;
        }
        _tab.localDirty = true;
      });
      await _persistDraftAutosave(forTab: _tab, retryOnConflict: true);
    }

    if (!mounted) return;
    final rid = _tab.serviceResourceId;
    if (rid != null && rid.isNotEmpty) {
      setState(() {
        _kitchenClearedResourceIds = {
          ..._kitchenClearedResourceIds,
          rid.toLowerCase(),
        };
      });
    }
    NotificationOverlayManager().showSuccess(
      title: 'Không có món mới',
      message: _tab.serviceResourceName ?? 'Các món đã báo bếp rồi',
    );
    } finally {
      if (mounted) setState(() => _kitchenSending = false);
    }
  }

  /// Chỉ lấy SL hủy chờ in từ dòng giỏ — không cộng `_pendingKitchenCancels`
  /// cùng lúc (tránh in đúp khi trước đây ghi cả hai).
  List<KitchenTicketLine> _collectKitchenCancelLines() {
    final list = <KitchenTicketLine>[
      ..._pendingKitchenCancels,
    ];
    // Pending list đã có → không cộng thêm kitchenCancelPendingQty (legacy).
    if (_pendingKitchenCancels.isEmpty) {
      for (final l in _tab.cart) {
        if (l.kitchenCancelPendingQty <= 0) continue;
        list.add(KitchenTicketLine(
          productName: l.product.name,
          qty: l.kitchenCancelPendingQty,
          unitName: l.unitLabel,
          note: l.noteWithToppings,
          productId: l.product.id,
        ));
      }
    }
    // Gộp cùng tên+đơn vị.
    final merged = <String, KitchenTicketLine>{};
    for (final l in list) {
      final key = '${l.productName}|${l.unitName ?? ''}';
      final prev = merged[key];
      if (prev == null) {
        merged[key] = l;
      } else {
        merged[key] = KitchenTicketLine(
          productName: prev.productName,
          qty: prev.qty + l.qty,
          unitName: prev.unitName,
          note: prev.note ?? l.note,
          productId: prev.productId ?? l.productId,
        );
      }
    }
    return merged.values.toList();
  }

  String _kitchenSenderName() {
    final id = _tab.sellerEmployeeId ?? _defaultSellerEmployeeId;
    Map<String, dynamic>? seller;
    for (final s in _sellSellers) {
      if (s['employeeId']?.toString() == id) {
        seller = s;
        break;
      }
    }
    if (seller == null) {
      for (final s in _sellSellers) {
        if (s['isSelf'] == true) {
          seller = s;
          break;
        }
      }
    }
    String? pick(Map<String, dynamic>? s) {
      if (s == null) return null;
      for (final key in ['displayName', 'email', 'phone']) {
        final v = s[key]?.toString().trim();
        if (v != null && v.isNotEmpty && !_looksLikeDeviceName(v)) return v;
      }
      return null;
    }

    final fromSeller = pick(seller);
    if (fromSeller != null) return fromSeller;

    try {
      final user = Provider.of<AuthProvider>(context, listen: false).user;
      if (user != null) {
        final n = user.fullName.trim();
        if (n.isNotEmpty && !_looksLikeDeviceName(n)) return n;
        if (user.email.trim().isNotEmpty) return user.email.trim();
      }
    } catch (_) {}
    return 'Thu ngân';
  }

  bool _looksLikeDeviceName(String s) {
    final u = s.toUpperCase();
    return u.contains('SUNMI') ||
        u.contains('V2S') ||
        u.contains('_GL') ||
        u.startsWith('ANDROID') ||
        RegExp(r'^[A-Z0-9]{8,}$').hasMatch(u);
  }

  /// Đánh dấu tạm tính + in hóa đơn tạm — ở lại màn đơn hàng (không về sơ đồ).
  Future<void> _printProvisionalBill() async {
    if (_provisionalPrinting || _checkingOut || _parking) return;
    if (!(_industrySettings?.allowProvisionalBill ?? false)) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa cấp quyền',
        message: tr('Bật «Cho phép tạm tính» trong Thiết lập ngành'),
      );
      return;
    }
    if (_tab.cart.isEmpty) return;
    if (!await _ensureCanEditActiveDraft()) return;

    _refreshTimedLineQtys();

    setState(() => _provisionalPrinting = true);
    try {
      // Đợi autosave ngắn — tối đa ~1.6s rồi flush 1 lần.
      _suspendDraftAutosave = true;
      _draftAutosaveTimer?.cancel();
      try {
        for (var i = 0; i < 20 && _autosavingDraft; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
        if (_tab.localDirty || (_tab.draftOrderId ?? '').isEmpty) {
          final saved = await _persistDraftAutosave(
            forTab: _tab,
            showLockError: true,
            retryOnConflict: true,
          );
          if (!mounted) return;
          if (!saved) return;
        }
      } finally {
        _suspendDraftAutosave = false;
      }
      final orderId = _tab.draftOrderId;
      if (orderId == null || orderId.isEmpty) {
        NotificationOverlayManager().showError(
          title: 'Chưa lưu đơn',
          message: tr('Lưu đơn tạm trước khi in tạm tính'),
        );
        return;
      }

      final rid = _tab.serviceResourceId;
      final sidCached = _tab.resourceSessionId;

      final billFuture = () async {
        var billMarked = false;
        if (rid != null && rid.isNotEmpty) {
          final byRes =
              await _api.requestPosResourceBillByResource(rid, requested: true);
          if (byRes['isSuccess'] == true) {
            billMarked = true;
            final data = byRes['data'] is Map ? byRes['data'] as Map : null;
            final sid = (data?['sessionId'] ?? data?['SessionId'])?.toString();
            if (sid != null && sid.isNotEmpty) {
              _tab.resourceSessionId = sid;
            }
          }
        }
        if (!billMarked) {
          var sid = sidCached ?? _tab.resourceSessionId;
          if ((sid == null || sid.isEmpty)) {
            final probe = await _api.getPosSale(orderId);
            if (probe['isSuccess'] == true && probe['data'] is Map) {
              final m = probe['data'] as Map;
              sid =
                  (m['resourceSessionId'] ?? m['ResourceSessionId'])?.toString();
              if (sid != null && sid.isNotEmpty) {
                _tab.resourceSessionId = sid;
              }
            }
          }
          if (sid != null && sid.isNotEmpty) {
            final billRes =
                await _api.requestPosResourceBill(sid, requested: true);
            billMarked = billRes['isSuccess'] == true;
          }
        }
        return billMarked;
      }();

      final orderFuture = _api.getPosSale(orderId);
      final results = await Future.wait([billFuture, orderFuture]);
      if (!mounted) return;
      final billMarked = results[0] as bool;
      final res = results[1] as Map<String, dynamic>;

      if (rid != null && rid.isNotEmpty) {
        final key = rid.toLowerCase();
        setState(() {
          _billRequestedResourceIds = {..._billRequestedResourceIds, key};
        });
      }
      if (!billMarked) {
        NotificationOverlayManager().showWarning(
          title: 'Chưa lưu trạng thái tạm tính',
          message: tr('Đã tô màu bàn tạm — kiểm tra lại nếu reload mất màu'),
        );
      }

      if (res['isSuccess'] != true || res['data'] is! Map) {
        NotificationOverlayManager().showError(
          title: 'Không in tạm tính',
          message: res['message']?.toString() ?? 'Không tải được đơn',
        );
        return;
      }
      final map = Map<String, dynamic>.from(res['data'] as Map);
      map['soldBy'] = _kitchenSenderName();
      final order = PosSaleOrder.fromJson(map);

      // In nền — không thoát về sơ đồ bàn.
      unawaited(() async {
        final ok = await printPosSaleOrder(
          context: context,
          order: order,
          branchName: _storeSettings.storeName.isNotEmpty
              ? _storeSettings.storeName
              : null,
          storeAddress:
              _storeSettings.address.isNotEmpty ? _storeSettings.address : null,
          storePhone:
              _storeSettings.phone.isNotEmpty ? _storeSettings.phone : null,
          mergeSameItems: _printSettings.mergeSameItems,
          copies: _printSettings.copies,
          templateId: _printSettings.templateId,
          skipDedup: true,
          preferDevicePrintOnly: true,
          showFeedback: false,
          documentTitle: 'HÓA ĐƠN TẠM TÍNH',
        );
        if (!mounted) return;
        if (ok) {
          NotificationOverlayManager().showSuccess(
            title: 'Tạm tính',
            message: tr('Đã gửi in hóa đơn tạm tính'),
          );
        } else {
          NotificationOverlayManager().showError(
            title: 'In tạm tính thất bại',
            message: tr('Kiểm tra máy in — thử in lại'),
          );
        }
      }());
    } finally {
      if (mounted) setState(() => _provisionalPrinting = false);
    }
  }

  Future<CancelReturnReasonResult?> _promptKitchenVoidReason() async {
    final reasonCfg =
        CancelReturnReasonConfig.fromExtraJson(_industrySettings?.extraJson);
    if (!reasonCfg.enabled) {
      return const CancelReturnReasonResult(reason: '');
    }
    return showPosCancelReturnReasonDialog(
      context,
      config: reasonCfg,
      title: 'Lý do hủy món bếp',
    );
  }

  /// In phiếu hủy bếp + ghi log server (đánh dấu nếu đã tạm tính).
  /// [reasonResult] truyền sẵn nếu đã hỏi lý do trước khi sửa giỏ (tránh hủy dialog mà món đã mất).
  /// Trả về false nếu user hủy dialog lý do (chưa ghi log / chưa in).
  Future<bool> _voidKitchenSentLines(
    List<KitchenTicketLine> lines, {
    CancelReturnReasonResult? reasonResult,
  }) async {
    if (lines.isEmpty || !_isTableOrderMode) return true;
    final resolved = reasonResult ?? await _promptKitchenVoidReason();
    if (resolved == null || !mounted) return false;
    final ok = await printKitchenCompactSlip(
      tableName: formatPosTableLabel(
        areaName: _tab.serviceAreaName,
        tableName: _tab.serviceResourceName,
      ),
      isCancel: true,
      lines: lines,
      senderName: _kitchenSenderName(),
      orderNo: _tab.draftOrderNo,
      waitForCompletion: false,
    );
    final body = <String, dynamic>{
      'lines': lines
          .map((l) => {
                'productName': l.productName,
                'qty': l.qty,
                if ((l.unitName ?? '').isNotEmpty) 'unitName': l.unitName,
                if ((l.note ?? '').isNotEmpty) 'lineNote': l.note,
              })
          .toList(),
      if (_tab.draftOrderId != null) 'saleOrderId': _tab.draftOrderId,
      if (_tab.draftOrderNo != null) 'orderNo': _tab.draftOrderNo,
      if (_tab.resourceSessionId != null)
        'resourceSessionId': _tab.resourceSessionId,
      if (_tab.serviceResourceId != null)
        'serviceResourceId': _tab.serviceResourceId,
      'resourceName': formatPosTableLabel(
        areaName: _tab.serviceAreaName,
        tableName: _tab.serviceResourceName,
      ),
      'printed': ok,
      if (_posDeviceName != null) 'deviceName': _posDeviceName,
      if (resolved.reason.isNotEmpty) 'reason': resolved.reason,
      if ((resolved.detailNote ?? '').isNotEmpty)
        'detailNote': resolved.detailNote,
    };
    unawaited(_api.createPosKitchenVoids(body));
    if (!mounted) return true;
    if (ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã in phiếu hủy bếp',
        message: '${lines.length} món · ${_tab.serviceResourceName ?? ''}',
      );
    } else {
      _enqueueFailedKitchenPrint(
        PendingKitchenPrintJob(
          id: 'kcancel_${DateTime.now().millisecondsSinceEpoch}',
          isCancel: true,
          tableName: formatPosTableLabel(
            areaName: _tab.serviceAreaName,
            tableName: _tab.serviceResourceName,
          ),
          senderName: _kitchenSenderName(),
          orderNo: _tab.draftOrderNo,
          lines: lines,
          errorMessage: 'In phiếu hủy thất bại',
        ),
      );
      NotificationOverlayManager().showWarning(
        title: 'Đã ghi hủy — chưa in phiếu',
        message: tr('Mở chờ in để in lại phiếu hủy bếp'),
      );
    }
    return true;
  }

  int get _kitchenPendingLineCount =>
      _tab.cart.where((l) => l.kitchenPendingQty > 0).length;

  int get _kitchenCancelPendingCount {
    var n = _pendingKitchenCancels.length;
    for (final l in _tab.cart) {
      if (l.kitchenCancelPendingQty > 0) n++;
    }
    return n;
  }

  int get _kitchenActionCount =>
      _kitchenPendingLineCount + _kitchenCancelPendingCount;

  int get _cupLabelPendingCount {
    var n = 0;
    for (final l in _tab.cart) {
      if (l.cupLabelPendingQty > 0) n++;
    }
    return n;
  }

  Future<void> _printPendingCupLabels({bool showFeedback = true}) async {
    if (!_printSettings.cupLabelPrintMode.enabled) {
      if (showFeedback) {
        NotificationOverlayManager().showWarning(
          title: 'Tem ly tắt',
          message: tr('Bật trong Thiết lập máy in → Tem dán ly'),
        );
      }
      return;
    }
    final pending =
        _tab.cart.where((l) => l.cupLabelPendingQty > 0).toList();
    if (pending.isEmpty) {
      if (showFeedback) {
        NotificationOverlayManager().showWarning(
          title: 'Không có tem mới',
          message: tr('Mọi phần đã in tem hoặc giỏ trống'),
        );
      }
      return;
    }
    await _printCupLabelsForLines(pending, showFeedback: showFeedback);
  }

  Future<void> _printCupLabelsForLines(
    List<_SellCartLine> lines, {
    String? tableLabelOverride,
    String? orderNoOverride,
    bool showFeedback = true,
  }) async {
    if (lines.isEmpty) return;
    final table = (tableLabelOverride ??
            formatPosTableLabel(
              areaName: _tab.serviceAreaName,
              tableName: _tab.serviceResourceName,
            ))
        .trim();
    final orderNo = (orderNoOverride ?? _tab.draftOrderNo ?? '').trim();
    final tickets = <CupLabelTicket>[];
    for (final l in lines) {
      final pending = l.cupLabelPendingQty;
      if (pending <= 0) continue;
      final toppings = l.toppings.map((t) => t.name).join(', ');
      final noteOnly = (l.lineNote ?? '').trim();
      final whole = pending == pending.roundToDouble();
      final copies = whole ? pending.round().clamp(1, 99) : 1;
      if (whole && copies > 1) {
        for (var i = 0; i < copies; i++) {
          tickets.add(CupLabelTicket(
            productName: l.product.name,
            toppings: toppings.isEmpty ? null : toppings,
            note: noteOnly.isEmpty ? null : noteOnly,
            qtyLabel: '1/${copies}',
            tableLabel: table.isEmpty ? null : table,
            orderNo: orderNo.isEmpty ? null : orderNo,
          ));
        }
      } else {
        tickets.add(CupLabelTicket(
          productName: l.product.name,
          toppings: toppings.isEmpty ? null : toppings,
          note: noteOnly.isEmpty ? null : noteOnly,
          qtyLabel: _qtyFmt.format(pending),
          tableLabel: table.isEmpty ? null : table,
          orderNo: orderNo.isEmpty ? null : orderNo,
        ));
      }
    }
    if (tickets.isEmpty) return;
    final ok = await printCupLabels(
      tickets: tickets,
      showFeedback: showFeedback,
    );
    if (!ok) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'In tem ly thất bại',
          message: tr('Kiểm tra máy in nhiệt / Sunmi'),
        );
      }
      _enqueueFailedCupPrint(
        PendingCupLabelPrintJob(
          id: 'cup_${DateTime.now().millisecondsSinceEpoch}',
          tickets: tickets,
          tableLabel: table.isEmpty ? null : table,
          orderNo: orderNo.isEmpty ? null : orderNo,
          errorMessage: 'In tem ly thất bại',
        ),
      );
      return;
    }
    if (mounted) {
      setState(() {
        for (final l in lines) {
          l.cupLabelPrintedQty = l.qty;
        }
      });
    }
    if (showFeedback) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã in tem ly',
        message: '${tickets.length} tem',
      );
    }
  }

  bool _ensureResourceIfRequired({bool notify = true}) {
    if (_industrySettings?.requireResourceOnSale != true) return true;
    final hasResource = (_tab.serviceResourceId ?? '').isNotEmpty;
    if (hasResource) return true;
    if (notify) {
      NotificationOverlayManager().showError(
        title: 'Chưa chọn bàn/phòng',
        message: tr('Hồ sơ ngành yêu cầu chọn bàn/phòng trước khi giữ đơn hoặc thanh toán'),
      );
    }
    return false;
  }

  void _refreshTimedLineQtys() {
    if (_industrySettings?.enableHourlyBilling != true) return;
    final started = _tab.serviceStartedAt;
    if (started == null) return;
    var changed = false;
    for (final line in _tab.cart) {
      if (!line.product.isTimedService) continue;
      final mode = PosServiceBillingMode.parse(line.product.serviceBillingMode);
      final elapsed = PosServiceBillingCalc.elapsedMinutes(
        started,
        null,
        accumulatedPauseMinutes: _tab.accumulatedPauseMinutes,
        pausedAt: _tab.sessionIsPaused ? _tab.sessionPausedAt : null,
      );
      final billable = PosServiceBillingCalc.billableMinutes(
        elapsed: elapsed,
        mode: mode,
        minBillMinutes: line.product.minBillMinutes,
        billRoundMinutes: line.product.billRoundMinutes,
        graceMinutes: line.product.graceMinutes,
        roundAfterMinutes: line.product.roundAfterMinutes,
      );
      final qty = PosServiceBillingCalc.billableQty(
        mode: mode,
        billableMinutes: billable,
        fallbackQty: line.qty,
      );
      if ((line.qty - qty).abs() > 0.0001) {
        line.qty = qty;
        changed = true;
      }
    }
    if (changed && mounted) {
      setState(() => _syncPaidAmount());
    }
    _ensureTimedBillingTimer();
  }

  Timer? _timedBillingTimer;

  void _ensureTimedBillingTimer() {
    final need = _industrySettings?.enableHourlyBilling == true &&
        _tab.serviceStartedAt != null &&
        _tab.cart.any((l) => l.product.isTimedService) &&
        !_tab.sessionIsPaused;
    if (!need) {
      _timedBillingTimer?.cancel();
      _timedBillingTimer = null;
      return;
    }
    _timedBillingTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      _refreshTimedLineQtys();
    });
  }

  Future<void> _openSessionRedeem() async {
    final customer = _tab.customer;
    if (customer == null) {
      NotificationOverlayManager().showError(
        title: 'Thiếu khách hàng',
        message: tr('Chọn khách để trừ buổi trong gói'),
      );
      return;
    }
    final redeemed = await showPosSessionRedeemSheet(
      context,
      customerId: customer.id,
      customerName: customer.name,
      saleOrderId: _tab.draftOrderId,
    );
    if (!mounted || redeemed != true) return;
    NotificationOverlayManager().showSuccess(
      title: 'Đã trừ buổi',
      message: tr('Gói buổi của ${customer.name} đã cập nhật'),
    );
  }

  void _newTab() {
    // Đồng bộ máy khác: luôn lưu Draft trước khi mở tab mới.
    // (Giữ đơn gọi _newTab(parkCurrentIfNeeded: false) sau khi đã lưu.)
    _newTabAsync();
  }

  Future<void> _newTabAsync({bool parkCurrentIfNeeded = true}) async {
    if (parkCurrentIfNeeded &&
        !_checkingOut &&
        !_parking &&
        (_tab.cart.isNotEmpty || _tab.localDirty) &&
        !_tab.draftReadOnly) {
      await _persistDraftAutosave(forTab: _tab);
    }
    if (!mounted) return;

    await _ensureDeviceReady();
    final res = await _api.addPosInvoiceSlot(
      deviceId: _posDeviceId,
      deviceName: _posDeviceName,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(
        title: 'Không thêm được hóa đơn',
        message: res['message']?.toString() ?? 'Thử lại',
      );
      return;
    }
    await _applyInvoiceSlotsPayload(
      res['data'] as Map,
      selectSlot: (res['data'] as Map)['addedSlot'] is num
          ? ((res['data'] as Map)['addedSlot'] as num).toInt()
          : null,
    );
  }

  /// Áp danh sách slot từ server vào tab UI.
  Future<void> _applyInvoiceSlotsPayload(
    Map data, {
    int? selectSlot,
    bool hydrateAll = true,
  }) async {
    final rawItems = (data['items'] as List?) ?? [];
    if (rawItems.isEmpty) return;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
    _recentlyClosedSlots.removeWhere((_, t) => t.isBefore(cutoff));
    final built = <_SellInvoiceTab>[];
    final existingBySlot = {for (final t in _tabs) t.id: t};

    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final slot = (m['invoiceSlot'] is num)
          ? (m['invoiceSlot'] as num).toInt()
          : int.tryParse('${m['invoiceSlot']}') ?? 0;
      if (slot < 1) continue;
      // Bỏ slot vừa đóng — tránh GET/sync stale hiện lại HĐ đã xóa.
      if (_recentlyClosedSlots.containsKey(slot)) continue;
      final prev = existingBySlot[slot];
      final tab = prev ?? _SellInvoiceTab(id: slot);
      if (prev == null) {
        tab.vatRate = _storeSettings.defaultVatRate;
        tab.paymentLines
            .add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
        tab.sellerEmployeeId = _defaultSellerEmployeeId;
      }
      final newDraftId = m['id']?.toString();
      final draftIdChanged = prev != null &&
          newDraftId != null &&
          newDraftId.isNotEmpty &&
          prev.draftOrderId != null &&
          prev.draftOrderId != newDraftId;
      // Đơn bàn / đang sửa local: giữ nguyên — không đổi sang TMP slot trống.
      if (draftIdChanged && (prev.isTableBound || prev.localDirty)) {
        built.add(prev);
        continue;
      }
      // Máy khác đã thanh toán → draft id mới: bỏ dirty + xóa giỏ cũ để hydrate lại.
      if (draftIdChanged) {
        tab.localDirty = false;
        tab.lockVersion = 0;
        for (final line in List<_SellCartLine>.from(tab.cart)) {
          line.dispose();
        }
        tab.cart.clear();
        tab.serverLineCount = 0;
        tab.serverTotal = 0;
        tab.draftReadOnly = false;
        tab.lockedByLabel = null;
      }
      tab.draftOrderId = newDraftId;
      // Không đẩy lockVersion lên bằng meta khi chưa hydrate — nếu không máy khác
      // sẽ bỏ qua pull (ver đã khớp nhưng qty/note vẫn cũ).
      if (!tab.localDirty && tab.cart.isEmpty) {
        tab.lockVersion = m['lockVersion'] is num
            ? (m['lockVersion'] as num).toInt()
            : int.tryParse('${m['lockVersion']}') ?? tab.lockVersion;
      }
      final lc = m['lineCount'] is num
          ? (m['lineCount'] as num).toInt()
          : int.tryParse('${m['lineCount']}') ?? 0;
      final total = m['total'] is num
          ? (m['total'] as num).toDouble()
          : double.tryParse('${m['total']}') ?? 0;
      if (!tab.localDirty) {
        tab.serverLineCount = lc;
        tab.serverTotal = total;
      }
      final locked = m['isLocked'] == true;
      final byMeFlag = m['isLockedByMe'] == true;
      // HĐ trống: không khóa — luôn cho bán. Đang sửa local: không lật readOnly.
      if (!tab.localDirty) {
        tab.draftReadOnly = _isEffectivelyLockedByOther(
          lineCount: lc,
          isLocked: locked,
          isLockedByMeFlag: byMeFlag,
          lockedByDeviceId: m['lockedByDeviceId']?.toString(),
        );
        tab.lockedByLabel = tab.draftReadOnly ? _lockHolderLabel(m) : null;
      }
      built.add(tab);
    }
    if (built.isEmpty) return;
    built.sort((a, b) => a.id.compareTo(b.id));

    // Dispose tabs removed from server.
    final keepIds = built.map((t) => t.id).toSet();
    for (final t in List<_SellInvoiceTab>.from(_tabs)) {
      if (!keepIds.contains(t.id)) t.dispose();
    }

    // Giữ đúng slot đang mở (không nhảy theo index khi danh sách đổi).
    final preferredSlot = selectSlot ??
        (_tabs.isNotEmpty
            ? _tabs[_activeTab.clamp(0, _tabs.length - 1)].id
            : null);
    var active = 0;
    if (preferredSlot != null) {
      final idx = built.indexWhere((t) => t.id == preferredSlot);
      if (idx >= 0) {
        active = idx;
      } else if (_activeTab < built.length) {
        active = _activeTab.clamp(0, built.length - 1);
      }
    } else if (_activeTab < built.length) {
      active = _activeTab;
    } else {
      active = built.length - 1;
    }

    setState(() {
      _tabs
        ..clear()
        ..addAll(built);
      _activeTab = active.clamp(0, _tabs.length - 1);
      _nextTabSeq =
          built.map((t) => t.id).fold<int>(1, (a, b) => a > b ? a : b) + 1;
    });

    if (hydrateAll) {
      // Tab đang mở trước — các tab khác hydrate nền để không chặn UI.
      final activeIdx = _activeTab.clamp(0, _tabs.length - 1);
      if (_tabs.isNotEmpty) {
        final active = _tabs[activeIdx];
        if (!active.localDirty) {
          await _pullServerOrderIntoTab(active, quiet: true);
        }
      }
      unawaited(() async {
        for (var i = 0; i < _tabs.length; i++) {
          if (!mounted) return;
          if (i == activeIdx) continue;
          final tab = _tabs[i];
          if (tab.localDirty) continue;
          await _pullServerOrderIntoTab(tab, quiet: true);
        }
      }());
    }
    if (!mounted) return;
    _restartDraftLockHeartbeat();
  }

  Future<void> _ensureSlotEditable(_SellInvoiceTab tab) async {
    final orderId = tab.draftOrderId;
    if (orderId == null || orderId.isEmpty) return;
    if (!tab.draftReadOnly) {
      // thử renew/claim nhẹ
      final access = await _claimOrViewDraft(orderId);
      if (!mounted || access == null) return;
      setState(() {
        tab.draftReadOnly = access.readOnly;
        if (access.lock != null) _applyLockMetaFromMap(access.lock, tab: tab);
      });
      return;
    }
    await _ensureCanEditActiveDraft();
  }

  Future<void> _bootstrapInvoiceSlots() async {
    await _ensureDeviceReady();
    if (!mounted) return;
    final res = await _api.getPosInvoiceSlots(
      count: 3,
      pruneEmpty: true,
      deviceId: _posDeviceId,
      deviceName: _posDeviceName,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      return;
    }
    await _applyInvoiceSlotsPayload(res['data'] as Map, hydrateAll: true);

    // Ưu tiên hóa đơn trống để bán ngay
    final emptyIdx = _tabs.indexWhere(
        (t) => t.cart.isEmpty && t.serverLineCount == 0 && !t.draftReadOnly);
    if (emptyIdx >= 0) {
      _selectTab(emptyIdx);
    } else {
      unawaited(_onSelectedTabActivated());
    }
  }

  Future<void> _reloadInvoiceSlot(int slot) async {
    await _ensureDeviceReady();
    final res = await _api.getPosInvoiceSlots(
      count: 3,
      deviceId: _posDeviceId,
      deviceName: _posDeviceName,
    );
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    await _applyInvoiceSlotsPayload(
      res['data'] as Map,
      selectSlot: slot,
      hydrateAll: false,
    );
    final idx = _tabs.indexWhere((t) => t.id == slot);
    if (idx >= 0) {
      await _pullServerOrderIntoTab(_tabs[idx], quiet: true);
    }
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    if (_tabs.length <= 1) {
      NotificationOverlayManager().showWarning(
        title: 'Không đóng được',
        message: tr('Phải giữ ít nhất 1 hóa đơn'),
      );
      return;
    }

    final tab = _tabs[index];
    final hasItems = tab.cart.isNotEmpty || tab.serverLineCount > 0;
    if (hasItems) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Đóng hóa đơn')),
          content: Text(
            tr('${tab.label} đang có hàng.\n'
            'Xóa hết hàng và đóng hóa đơn này?'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Huỷ'))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
              child: Text(tr('Đóng')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    // Không autosave trước khi xóa — tránh tạo lại draft / đua với DELETE.
    _draftAutosaveTimer?.cancel();
    tab.localDirty = false;
    final closedSlot = tab.id;
    _recentlyClosedSlots[closedSlot] = DateTime.now();

    await _ensureDeviceReady();
    final res = await _api.removePosInvoiceSlot(
      closedSlot,
      force: true, // luôn force: trống hoặc đã xác nhận xóa hàng
      deviceId: _posDeviceId,
      deviceName: _posDeviceName,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      _recentlyClosedSlots.remove(closedSlot);
      NotificationOverlayManager().showError(
        title: 'Không đóng được hóa đơn',
        message: res['message']?.toString() ?? 'Thử lại',
      );
      return;
    }
    if (res['data'] is Map) {
      await _applyInvoiceSlotsPayload(res['data'] as Map, hydrateAll: false);
    } else {
      setState(() {
        tab.dispose();
        _tabs.removeAt(index);
        if (_activeTab >= _tabs.length) {
          _activeTab = _tabs.length - 1;
        } else if (_activeTab > index) {
          _activeTab--;
        }
      });
    }
    _restartDraftLockHeartbeat();
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (index == _activeTab) return;
    final prev = _tab;
    // Flush autosave tab cũ trước khi đổi — tránh mất hàng / mất lần xóa.
    if (prev.localDirty && !prev.draftReadOnly) {
      unawaited(_persistDraftAutosave(forTab: prev));
    } else if (!prev.draftReadOnly &&
        prev.cart.isEmpty &&
        prev.serverLineCount == 0 &&
        prev.draftOrderId != null) {
      // Rời HĐ trống → nhả chỗ ngồi để máy khác dùng được.
      unawaited(_unlockDraftQuietly(prev.draftOrderId));
    }
    setState(() {
      _activeTab = index;
      _customerSuggestions = [];
      _syncPaidAmount();
    });
    _restartDraftLockHeartbeat();
    unawaited(_onSelectedTabActivated());
  }

  Future<void> _onSelectedTabActivated() async {
    final tab = _tab;
    if (tab.draftOrderId == null) return;
    if (!tab.localDirty) {
      await _pullServerOrderIntoTab(tab, quiet: true);
    }
    if (!mounted) return;

    // HĐ trống: không chiếm chỗ / không lấy quyền.
    if (tab.cart.isEmpty && tab.serverLineCount == 0) {
      if (tab.draftReadOnly) {
        setState(() {
          tab.draftReadOnly = false;
          tab.lockedByLabel = null;
        });
      }
      return;
    }
    if (tab.draftReadOnly) return;

    await _ensureDeviceReady();
    final deviceId = _posDeviceId;
    final deviceName = _posDeviceName;
    final orderId = tab.draftOrderId;
    if (deviceId == null || deviceName == null || orderId == null) return;

    final lockRes = await _api.lockPosSaleDraft(
      orderId,
      deviceId: deviceId,
      deviceName: deviceName,
      force: false,
    );
    if (!mounted) return;
    if (lockRes['isSuccess'] == true && lockRes['data'] is Map<String, dynamic>) {
      setState(() {
        tab.draftReadOnly = false;
        _applyLockMetaFromMap(lockRes['data'] as Map<String, dynamic>, tab: tab);
      });
      return;
    }
    if (lockRes['statusCode'] == 409) {
      setState(() {
        tab.draftReadOnly = true;
        tab.localDirty = false;
        tab.lockedByLabel = _lockHolderLabel(
          lockRes['data'] is Map<String, dynamic>
              ? lockRes['data'] as Map<String, dynamic>
              : null,
          fallbackMessage: lockRes['message']?.toString(),
        );
      });
    }
  }

  double get _subTotal =>
      _tab.cart.fold(0.0, (a, c) => a + c.lineGross);

  double get _lineDiscountTotal =>
      _tab.cart.fold(0.0, (a, c) => a + c.discountAmount);

  double get _afterLineDiscount => (_subTotal - _lineDiscountTotal).clamp(0, double.infinity);

  void _recalcTotals() {
    _tab.applyDiscount(_afterLineDiscount);
    _scheduleCustomerDisplayPublish();
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

  double get _effectivePaidAmount => _effectivePaidAmountFor(_tab);

  double _effectivePaidAmountFor(_SellInvoiceTab tab) {
    if (tab.paymentLines.isNotEmpty) {
      return tab.paymentLines.fold(0.0, (a, p) => a + p.amount);
    }
    final fromCtrl = _parseMoneyInput(tab._paidCtrl.text);
    if (tab._paidCtrl.text.trim().isNotEmpty) return fromCtrl;
    return tab.paidAmount;
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

  Map<String, double> _comboOnlyReservation() {
    final lines = <CartLineForStock>[];
    for (final l in _tab.cart) {
      lines.add(
        CartLineForStock(
          productId: l.product.id,
          productType: l.product.productType,
          qty: l.qty,
          comboLines: l.product.comboLines ?? const [],
        ),
      );
    }
    return buildComboOnlyReservation(lines);
  }

  bool get _allowNegativeStock =>
      _industrySettings?.allowNegativeStock == true;

  bool _validateStockQty(
    PosProduct p,
    PosProductUnitView view,
    double requiredQty, {
    bool warnLow = true,
  }) {
    if (_allowNegativeStock) return true;
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
    final comboReserved = _comboOnlyReservation()[p.id] ?? 0;
    final needTotal = requiredQty + comboReserved;
    final available = resolvePosSellAvailableQty(p, view);
    if (available < needTotal) {
      NotificationOverlayManager().showError(
        title: available <= 0 ? 'Hết hàng' : 'Không đủ tồn',
        message: comboReserved > 0
            ? '${p.name} (${view.label}): còn ${_qtyFmt.format(available)}, '
                'cần ${_qtyFmt.format(requiredQty)}'
                ' (+${_qtyFmt.format(comboReserved)} trong combo)'
            : '${p.name} (${view.label}): còn ${_qtyFmt.format(available)}, '
                'cần ${_qtyFmt.format(requiredQty)}',
      );
      return false;
    }
    if (warnLow &&
        p.minStockQty > 0 &&
        available - needTotal < p.minStockQty &&
        available > 0) {
      NotificationOverlayManager().showWarning(
        title: 'Sắp hết hàng',
        message: tr(
            '${p.name} sẽ còn ${_qtyFmt.format(available - needTotal)} sau khi bán'),
      );
    }
    return true;
  }

  /// Làm mới OnHand/Reserved từ server trước khi thanh toán.
  Future<bool> _refreshCartStockBeforeCheckout() async {
    final ids = _tab.cart.map((l) => l.product.id).toSet().toList();
    if (ids.isEmpty) return true;
    final responses = await Future.wait(ids.map((id) => _api.getPosProduct(id)));
    if (!mounted) return false;
    final byId = <String, PosProduct>{};
    for (var i = 0; i < ids.length; i++) {
      final res = responses[i];
      if (res['isSuccess'] == true && res['data'] is Map) {
        byId[ids[i]] =
            PosProduct.fromJson(Map<String, dynamic>.from(res['data'] as Map));
      }
    }
    final overrides = _currentPriceOverrides;
    for (final line in _tab.cart) {
      final freshProduct = byId[line.product.id];
      if (freshProduct == null) continue;
      line.product = freshProduct;
      var views = posProductHasEmbeddedSellViews(freshProduct)
          ? buildPosSellUnitViewsFromProduct(freshProduct)
          : await loadPosSellUnitViews(_api, freshProduct);
      if (!mounted) return false;
      views = applyPosPriceListToViews(views, freshProduct, overrides);
      final match = views
              .where((v) =>
                  v.viewKey == line.activeViewKey ||
                  (v.variantId == line.variantId && v.unitId == line.unitId))
              .firstOrNull ??
          (views.isNotEmpty ? views.first : null);
      if (match == null) continue;
      line.unitViews = views;
      line.activeViewKey = match.viewKey;
    }
    if (mounted) setState(() {});
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
                tr(isExpired
                    ? 'Có $_expiredLotCount lô đã hết HSD'
                        '${_expiringLotCount > 0 ? ', $_expiringLotCount lô sắp hết' : ''}'
                    : 'Có $_expiringLotCount lô sắp hết HSD trong 30 ngày'),
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
              child: Text(tr('Xem'), style: TextStyle(fontSize: 12)),
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

  /// Cache đơn vị SP trên màn bán — tránh N+1 API mỗi lần chạm cùng món.
  final Map<String, List<PosProductUnitView>> _sellUnitViewsCache = {};

  Future<void> _addPick(
    PosPurchaseLookupPick pick, {
    bool mergeIfSame = false,
    bool autosave = true,
    double addQty = 1,
  }) async {
    if (addQty <= 0) return;
    if (!await _ensureCanEditActiveDraft()) return;
    // Đánh dirty sớm — chặn sync/pull đè giỏ về 0 trong lúc load đơn vị.
    _markTabDirty(_tab);
    final p = pick.product;
    List<PosProductUnitView> views =
        _sellUnitViewsCache[p.id] ?? await loadPosSellUnitViews(_api, p);
    if (views.isNotEmpty) _sellUnitViewsCache[p.id] = views;
    views = applyPosPriceListToViews(views, p, _currentPriceOverrides);
    if (!mounted || views.isEmpty) return;

    final view = pickUnitView(
          views,
          variantId: pick.variantId,
          unitId: pick.unitId,
          unitLabel: pick.unitLabel,
        ) ??
        views.first;

    if (!_validateStockForAdd(p, view, addQty: addQty)) return;

    PosProductVariant? variant;
    if (view.variantId != null) {
      variant = await _resolveVariant(p.id, view.variantId!);
    }

    _SellCartLine? focusLine;
    setState(() {
      if (mergeIfSame) {
        final idx = _tab.cart.indexWhere((l) =>
            l.product.id == p.id &&
            l.variantId == view.variantId &&
            l.unitId == view.unitId &&
            l.toppings.isEmpty);
        if (idx >= 0) {
          if (!_validateStockForAdd(p, view, addQty: addQty)) return;
          _tab.cart[idx].qty += addQty;
          focusLine = _tab.cart[idx];
          _syncPaidAmount();
          return;
        }
      }
      var qty = addQty;
      if (_industrySettings?.enableHourlyBilling == true &&
          p.isTimedService &&
          _tab.serviceStartedAt != null &&
          addQty == 1) {
        final mode = PosServiceBillingMode.parse(p.serviceBillingMode);
        final elapsed = PosServiceBillingCalc.elapsedMinutes(
          _tab.serviceStartedAt!,
          null,
          accumulatedPauseMinutes: _tab.accumulatedPauseMinutes,
          pausedAt: _tab.sessionIsPaused ? _tab.sessionPausedAt : null,
        );
        final billable = PosServiceBillingCalc.billableMinutes(
          elapsed: elapsed,
          mode: mode,
          minBillMinutes: p.minBillMinutes,
          billRoundMinutes: p.billRoundMinutes,
          graceMinutes: p.graceMinutes,
          roundAfterMinutes: p.roundAfterMinutes,
        );
        qty = PosServiceBillingCalc.billableQty(
          mode: mode,
          billableMinutes: billable,
          fallbackQty: 1,
        );
      }
      var unitPrice = view.basePrice;
      if (p.isTimedService &&
          PosServiceBillingMode.parse(p.serviceBillingMode) ==
              PosServiceBillingMode.perHour &&
          unitPrice <= 0 &&
          (_tab.serviceDefaultHourlyRate ?? 0) > 0) {
        unitPrice = _tab.serviceDefaultHourlyRate!;
      }
      final line = _SellCartLine(
        rowId: _nextCartRowId++,
        product: p,
        variantId: view.variantId,
        unitId: view.unitId,
        variant: variant,
        activeViewKey: view.viewKey,
        unitLabel: view.label,
        displayCode: view.displayCode,
        unitPrice: unitPrice,
        unitViews: views,
        qty: qty,
        vatRate: p.vatExempt ? 0 : p.vatRate,
        vatExempt: p.vatExempt,
      );
      _tab.cart.add(line);
      focusLine = line;
      _syncPaidAmount();
    });
    HapticFeedback.lightImpact();
    if (autosave) _scheduleDraftAutosave();
    _ensureTimedBillingTimer();
    await _maybeWarnProductExpiry(p, variantId: view.variantId);
    final line = focusLine;
    if (line != null &&
        mounted &&
        line.product.autoOpenToppingPopup &&
        line.product.hasToppingGroups) {
      await _openCartLineToppings(line);
    }
  }

  Future<void> _resumeDraftFromList() async {
    await _openWaitingOrdersSheet();
  }

  /// Panel đơn chờ: tab local + Draft trên server (poll khi đang mở).
  Future<void> _openWaitingOrdersSheet() async {
    // Đảm bảo giỏ hiện tại đã lên server trước khi xem danh sách (đồng bộ máy khác).
    if (_tab.cart.isNotEmpty && !_parking && !_checkingOut) {
      final ok = await _parkCurrentOrder(openNewTabAfter: false);
      if (!ok) return;
    }

    var fetched = await _fetchServerDrafts();
    if (!mounted) return;
    await _reconcileHeldDraftsMissingFrom(fetched.drafts);
    if (!mounted) return;

    var drafts = fetched.drafts;
    String? loadError = fetched.loadError;
    Timer? pollTimer;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            pollTimer ??= Timer.periodic(const Duration(seconds: 12), (_) async {
              final next = await _fetchServerDrafts();
              if (!ctx.mounted) return;
              await _reconcileHeldDraftsMissingFrom(next.drafts);
              if (!ctx.mounted) return;
              setModal(() {
                drafts = next.drafts;
                loadError = next.loadError;
              });
              if (mounted) setState(() {});
            });

            final draftIds = drafts.map((d) => d.id).toSet();
            final localBusy = _tabs.where((t) {
              if (t.cart.isEmpty) return false;
              final id = t.draftOrderId;
              // Ẩn tab local nếu draft đã không còn trên server (đã TT).
              if (id != null && id.isNotEmpty && !draftIds.contains(id)) {
                return false;
              }
              return true;
            }).toList();

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(tr('Đơn chờ thanh toán'),
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(tr('Tự làm mới ~12s — đơn đã thanh toán sẽ biến mất'),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                    if (loadError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        tr(loadError!),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFDC2626)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (localBusy.isNotEmpty) ...[
                            Text(tr('Trên máy này'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final tab in localBusy)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: PosTheme.kiotBlueLight,
                                  child: Text(
                                    tr('${tab.id}'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: PosTheme.kiotBlue,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  tr(tab.label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  tr(tab.draftOrderId != null
                                      ? 'Đã lưu server · ${tab.draftOrderNo ?? ''}'
                                      : 'Chưa lưu server'),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: tab.id == _tab.id
                                    ? Text(tr('Đang mở'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: PosTheme.kiotBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    : const Icon(Icons.chevron_right, size: 20),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  final i =
                                      _tabs.indexWhere((t) => t.id == tab.id);
                                  if (i >= 0) _selectTab(i);
                                },
                              ),
                            const Divider(height: 20),
                          ],
                          Text(tr('Đơn tạm trên server'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (drafts.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                tr(loadError != null
                                    ? 'Không tải được danh sách đơn tạm.'
                                    : 'Chưa có đơn tạm. Thêm hàng rồi bấm «Giữ đơn» hoặc «+» tab mới để lưu lên server.'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            )
                          else
                            for (final d in drafts)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.receipt_long_outlined,
                                  color: PosTheme.kiotBlue,
                                ),
                                title: Text(
                                  tr(d.orderNo.isEmpty ? 'Đơn tạm' : d.orderNo),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  tr([
                                    d.customerName ?? 'Khách lẻ',
                                    if (d.lineCount > 0) '${d.lineCount} món',
                                    _moneyFmt.format(d.total),
                                    if (d.lockBadgeLabel != null)
                                      d.lockBadgeLabel!,
                                  ].join(' · ')),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: d.isLocked && !d.isLockedByMe
                                        ? const Color(0xFFB45309)
                                        : null,
                                  ),
                                ),
                                trailing: d.isLocked && !d.isLockedByMe
                                    ? const Icon(
                                        Icons.lock_outline,
                                        size: 18,
                                        color: Color(0xFFB45309),
                                      )
                                    : const Icon(Icons.chevron_right, size: 20),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _openDraftOrder(
                                    d.id,
                                    viewOnlyOnConflict: true,
                                  );
                                },
                              ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final picked = await showPosPickSaleOrderDialog(
                                context,
                                purpose: PosPickSaleOrderPurpose.resumeDraft,
                              );
                              if (!mounted || picked == null) return;
                              await _openDraftOrder(picked.id);
                            },
                            icon: const Icon(Icons.search, size: 18),
                            label: Text(tr('Tìm thêm đơn tạm…')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      pollTimer?.cancel();
      pollTimer = null;
    });
  }

  Future<void> _openDraftOrder(
    String orderId, {
    bool silent = false,
    bool viewOnlyOnConflict = false,
    bool forceClaim = false,
  }) async {
    final existing = _tabs.indexWhere((t) => t.draftOrderId == orderId);
    if (existing >= 0) {
      _suspendDraftAutosave = true;
      setState(() => _tabs[existing].localDirty = false);
      final cleared = await _reconcileDraftTabAgainstServer(_tabs[existing]);
      if (!mounted) return;
      if (cleared) {
        _suspendDraftAutosave = false;
        return;
      }
      _selectTab(existing);
      Map<String, dynamic>? fresh;
      if (forceClaim) {
        fresh = await _fetchDraftOrderJson(orderId);
        if (fresh != null && mounted) {
          final pre = PosSaleOrder.fromJson(fresh);
          setState(() {
            _tab.serverLineCount = pre.lines.length;
            _tab.serverTotal = pre.total;
            _tab.localDirty = false;
          });
        }
        final ok = await _forceClaimActiveDraft(
          quiet: true,
          forceTake: true,
          restartSync: false,
        );
        if (!mounted || !ok) {
          _suspendDraftAutosave = false;
          return;
        }
        setState(() {
          _tab.draftReadOnly = false;
          _tab.lockedByLabel = null;
        });
        fresh = await _fetchDraftOrderJson(orderId);
        if (fresh != null && mounted) {
          final order = PosSaleOrder.fromJson(fresh);
          await _hydrateTabCartFromOrder(
            _tab,
            order,
            orderJson: fresh,
            readOnly: false,
            notify: false,
            force: true,
          );
        }
      } else {
        final access = await _claimOrViewDraft(
          orderId,
          silentViewOnConflict: viewOnlyOnConflict || silent,
        );
        if (!mounted || access == null) {
          _suspendDraftAutosave = false;
          return;
        }
        setState(() {
          var ro = access.readOnly;
          if (access.lock != null) {
            _applyLockMetaFromMap(access.lock, tab: _tabs[existing]);
            if (ro || _isLockedByAnotherDevice(access.lock)) ro = true;
          }
          _tabs[existing].draftReadOnly = ro;
          if (!ro) {
            _tabs[existing].lockedByLabel = null;
            _ignoreReadOnlyUntil =
                DateTime.now().add(const Duration(seconds: 45));
          }
        });
        fresh = await _fetchDraftOrderJson(orderId);
        if (fresh != null && mounted) {
          final order = PosSaleOrder.fromJson(fresh);
          setState(() {
            _tab.serverLineCount = order.lines.length;
            _tab.serverTotal = order.total;
            _tab.localDirty = false;
          });
          await _hydrateTabCartFromOrder(
            _tabs[existing],
            order,
            orderJson: fresh,
            readOnly: _tab.draftReadOnly,
            notify: false,
            force: true,
          );
        }
      }
      if (mounted) {
        setState(() => _tab.localDirty = false);
        _restartDraftLockHeartbeat();
        if (!silent) {
          _suspendDraftAutosave = false;
        }
      }
      if (silent && mounted) {
        await _verifyTableCartHydrated(orderId);
      }
      // Silent chuyển tab / mở đơn tạm — không toast che sơ đồ/POS.
      return;
    }
    if (_tab.cart.isNotEmpty) {
      _newTab();
    }
    await _loadDraftIntoActiveTab(
      orderId,
      silent: silent,
      viewOnlyOnConflict: viewOnlyOnConflict || silent,
      forceClaim: forceClaim,
    );
  }

  Future<void> _ensureDeviceReady() async {
    if (_posDeviceId != null &&
        _posDeviceId!.isNotEmpty &&
        _posDeviceName != null &&
        _posDeviceName!.isNotEmpty) {
      return;
    }
    await _ensurePosDeviceIdentity();
  }

  /// So khớp máy đang giữ khóa. Có device trên đơn → chỉ tin device (không tin isLockedByMe cùng account).
  bool _isLockHeldByThisDevice({
    required bool isLocked,
    required bool isLockedByMeFlag,
    required String? lockedByDeviceId,
  }) {
    if (!isLocked) return false;
    final remoteDev = (lockedByDeviceId ?? '').trim().toLowerCase();
    final myDev = (_posDeviceId ?? '').trim().toLowerCase();
    if (remoteDev.isNotEmpty && myDev.isNotEmpty) {
      return remoteDev == myDev;
    }
    if (remoteDev.isNotEmpty && myDev.isEmpty) return false;
    // Khóa chưa ghim device — không tin isLockedByMe (2 máy POS cùng tài khoản).
    if (remoteDev.isEmpty) return false;
    return isLockedByMeFlag;
  }

  /// Máy khác đang giữ khóa → chỉ xem / chỉ pull trạng thái từ máy giữ.
  bool _isEffectivelyLockedByOther({
    required int lineCount,
    required bool isLocked,
    required bool isLockedByMeFlag,
    required String? lockedByDeviceId,
  }) {
    if (!isLocked) return false;
    final remoteDev = (lockedByDeviceId ?? '').trim().toLowerCase();
    final myDev = (_posDeviceId ?? '').trim().toLowerCase();
    if (remoteDev.isNotEmpty && myDev.isNotEmpty) {
      return remoteDev != myDev;
    }
    if (remoteDev.isNotEmpty && myDev.isEmpty) return true;
    return !_isLockHeldByThisDevice(
      isLocked: isLocked,
      isLockedByMeFlag: isLockedByMeFlag,
      lockedByDeviceId: lockedByDeviceId,
    );
  }

  bool _isLockLive(Map<String, dynamic>? data) {
    if (data == null) return false;
    final isLocked = data['isLocked'] == true || data['IsLocked'] == true;
    if (!isLocked) return false;
    final expRaw = data['lockExpiresAt'] ?? data['LockExpiresAt'];
    if (expRaw != null) {
      final exp = DateTime.tryParse(expRaw.toString())?.toUtc();
      if (exp != null && exp.isBefore(DateTime.now().toUtc())) return false;
    }
    return true;
  }

  bool _isLockedByAnotherDevice(Map<String, dynamic>? data) {
    if (!_isLockLive(data)) return false;
    final isLockedByMe =
        data!['isLockedByMe'] == true || data['IsLockedByMe'] == true;
    final lockedByDeviceId =
        (data['lockedByDeviceId'] ?? data['LockedByDeviceId'])?.toString();
    return !_isLockHeldByThisDevice(
      isLocked: true,
      isLockedByMeFlag: isLockedByMe,
      lockedByDeviceId: lockedByDeviceId,
    );
  }

  /// Máy khác vẫn đang trong đơn (khóa live + heartbeat gần đây).
  bool _isLockActivelyHeldByOther(Map<String, dynamic>? data) {
    if (!_isLockLive(data) || !_isLockedByAnotherDevice(data)) return false;
    final atRaw = data!['lockedAt'] ?? data['LockedAt'];
    if (atRaw != null) {
      final at = DateTime.tryParse(atRaw.toString())?.toUtc();
      if (at != null) {
        return DateTime.now().toUtc().difference(at).inSeconds < 45;
      }
    }
    return true;
  }

  void _applyLockMetaFromMap(Map<String, dynamic>? data, {_SellInvoiceTab? tab}) {
    if (data == null) return;
    final t = tab ?? _tab;
    final orderId = t.draftOrderId;
    final inGrace = identical(t, _tab) &&
        _ignoreReadOnlyUntil != null &&
        DateTime.now().isBefore(_ignoreReadOnlyUntil!);
    if (orderId != null &&
        orderId.isNotEmpty &&
        _floorReleasedOrderIds.contains(orderId) &&
        !inGrace) {
      t.draftReadOnly = true;
      t.lockedByLabel = null;
      return;
    }
    final v = data['lockVersion'] ?? data['LockVersion'];
    if (v is num) {
      final incoming = v.toInt();
      if (incoming >= t.lockVersion) t.lockVersion = incoming;
    } else if (v != null) {
      final incoming = int.tryParse('$v');
      if (incoming != null && incoming >= t.lockVersion) {
        t.lockVersion = incoming;
      }
    }
    final isLocked = data['isLocked'] == true || data['IsLocked'] == true;
    final isLockedByMe =
        data['isLockedByMe'] == true || data['IsLockedByMe'] == true;
    final lockedByDeviceId =
        (data['lockedByDeviceId'] ?? data['LockedByDeviceId'])?.toString();
    if (isLocked &&
        _isLockHeldByThisDevice(
          isLocked: true,
          isLockedByMeFlag: isLockedByMe,
          lockedByDeviceId: lockedByDeviceId,
        )) {
      t.draftReadOnly = false;
      t.lockedByLabel = null;
      return;
    }
    final lineCount = t.cart.length;
    final byOther = _isEffectivelyLockedByOther(
      lineCount: lineCount,
      isLocked: isLocked,
      isLockedByMeFlag: isLockedByMe,
      lockedByDeviceId: lockedByDeviceId,
    );
    if (inGrace && byOther) {
      t.draftReadOnly = false;
      t.lockedByLabel = null;
      return;
    }
    t.draftReadOnly = byOther;
    t.lockedByLabel = byOther ? _lockHolderLabel(data) : null;
  }

  /// GET đơn tạm kèm deviceId — isLockedByMe / lockedByDevice khớp máy này.
  Future<Map<String, dynamic>?> _fetchDraftOrderJson(String orderId) async {
    await _ensureDeviceReady();
    final res = await _api.getPosSale(
      orderId,
      deviceId: _posDeviceId,
      deviceName: _posDeviceName,
    );
    if (res['isSuccess'] == true && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return null;
  }

  /// Chặn sửa ghi chú/CK/SL khi chỉ xem — không hỏi «Lấy quyền».
  bool _guardReadOnlyEdit({String? message}) {
    if (!_tab.draftReadOnly) return true;
    NotificationOverlayManager().showWarning(
      title: 'Chỉ xem',
      message: message ??
          (_tab.lockedByLabel != null
              ? 'Bàn đang mở trên ${_tab.lockedByLabel} — không thể sửa'
              : 'Về sơ đồ bàn bấm «Lấy quyền» để sửa'),
    );
    return false;
  }

  String _lockHolderLabel(Map<String, dynamic>? data, {String? fallbackMessage}) {
    if (data != null) {
      final who = (data['lockedByDisplayName'] ?? data['LockedByDisplayName'] ?? '')
          .toString()
          .trim();
      final device =
          (data['lockedByDeviceName'] ?? data['LockedByDeviceName'] ?? '')
              .toString()
              .trim();
      if (who.isNotEmpty || device.isNotEmpty) {
        if (who.isEmpty) return device;
        if (device.isEmpty) return who;
        return '$who · $device';
      }
    }
    final msg = (fallbackMessage ?? '').trim();
    return msg.isNotEmpty ? msg : 'thu ngân khác';
  }

  /// Claim khóa, hoặc mở chỉ xem. null = user hủy.
  Future<({Map<String, dynamic>? lock, bool readOnly})?> _claimOrViewDraft(
    String orderId, {
    bool silentViewOnConflict = false,
  }) async {
    await _ensureDeviceReady();
    final deviceId = _posDeviceId;
    final deviceName = _posDeviceName;
    if (deviceId == null || deviceName == null) {
      return (lock: null, readOnly: false);
    }

    var res = await _api.lockPosSaleDraft(
      orderId,
      deviceId: deviceId,
      deviceName: deviceName,
      force: false,
    );
    if (res['isSuccess'] == true) {
      final data = res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      if (_isLockedByAnotherDevice(data)) {
        return (lock: data, readOnly: true);
      }
      return (lock: data, readOnly: false);
    }

    if (res['statusCode'] == 409) {
      final data = res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      if (silentViewOnConflict) {
        return (lock: data, readOnly: true);
      }
      final activelyHeld = _isLockActivelyHeldByOther(data);
      // Máy khác đang sửa → chỉ xem (không hỏi dialog).
      if (activelyHeld) {
        return (lock: data, readOnly: true);
      }
      // Bàn chờ / tạm rời — tự lấy quyền, không bảng xác nhận.
      res = await _api.lockPosSaleDraft(
        orderId,
        deviceId: deviceId,
        deviceName: deviceName,
        force: true,
      );
      if (res['isSuccess'] == true) {
        final forced = res['data'] is Map
            ? Map<String, dynamic>.from(res['data'] as Map)
            : null;
        _ignoreReadOnlyUntil = DateTime.now().add(const Duration(seconds: 20));
        return (lock: forced, readOnly: false);
      }
      NotificationOverlayManager().showError(
        title: 'Không lấy được quyền',
        message: res['message']?.toString() ??
            'Máy kia vẫn đang trong đơn — nhờ thoát về sơ đồ rồi thử lại',
      );
      return null;
    }

    NotificationOverlayManager().showError(
      title: 'Không khóa được đơn',
      message: res['message']?.toString() ?? 'Thử lại',
    );
    return null;
  }

  /// @deprecated path — giữ cho chỗ gọi cũ nếu còn.
  Future<Map<String, dynamic>?> _claimDraftLock(
    String orderId, {
    bool allowForcePrompt = true,
  }) async {
    final r = await _claimOrViewDraft(orderId);
    if (r == null || r.readOnly) return null;
    return r.lock;
  }

  Future<bool> _ensureCanEditActiveDraft() async {
    final orderId = _tab.draftOrderId;
    if (orderId == null || orderId.isEmpty) return true;
    // Vừa lấy quyền / mở bàn — tránh lock lại ngay gây 409 race.
    if (_ignoreReadOnlyUntil != null &&
        DateTime.now().isBefore(_ignoreReadOnlyUntil!) &&
        !_tab.draftReadOnly) {
      return true;
    }
    // Đã có quyền sửa (kể cả bàn) — heartbeat gia hạn TTL; không lock RPC mỗi lần add.
    if (!_tab.draftReadOnly) return true;

    await _ensureDeviceReady();
    final deviceId = _posDeviceId;
    final deviceName = _posDeviceName;
    if (deviceId == null || deviceName == null) return false;

    Future<Map<String, dynamic>> tryLock({required bool force}) =>
        _api.lockPosSaleDraft(
          orderId,
          deviceId: deviceId,
          deviceName: deviceName,
          force: force,
        );

    var res = await tryLock(force: false);
    if (!mounted) return false;
    if (res['isSuccess'] == true) {
      final data = res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      if (_isLockedByAnotherDevice(data)) {
        // Khóa stale (tạm rời) — tự lấy quyền, không bắt về sơ đồ.
        if (!_isLockActivelyHeldByOther(data)) {
          res = await tryLock(force: true);
          if (!mounted) return false;
          if (res['isSuccess'] == true) {
            final forced = res['data'] is Map
                ? Map<String, dynamic>.from(res['data'] as Map)
                : null;
            if (!_isLockedByAnotherDevice(forced)) {
              _floorReleasedOrderIds.remove(orderId);
              setState(() {
                if (forced != null) _applyLockMetaFromMap(forced);
                _tab.draftReadOnly = false;
                _tab.lockedByLabel = null;
                _ignoreReadOnlyUntil =
                    DateTime.now().add(const Duration(seconds: 45));
              });
              return true;
            }
          }
        }
        setState(() {
          _applyLockMetaFromMap(data);
          _tab.draftReadOnly = true;
        });
        NotificationOverlayManager().showWarning(
          title: 'Chỉ xem',
          message: tr('Bàn đang mở trên ${_lockHolderLabel(data)} — không thể sửa'),
        );
        return false;
      }
      _floorReleasedOrderIds.remove(orderId);
      setState(() {
        _applyLockMetaFromMap(data);
        _tab.draftReadOnly = false;
        _tab.lockedByLabel = null;
        _ignoreReadOnlyUntil = DateTime.now().add(const Duration(seconds: 45));
      });
      return true;
    }

    if (res['statusCode'] != 409) {
      NotificationOverlayManager().showError(
        title: 'Không sửa được',
        message: res['message']?.toString() ?? 'Thử lại',
      );
      return false;
    }

    final data = res['data'] is Map
        ? Map<String, dynamic>.from(res['data'] as Map)
        : null;
    final holder = _tab.lockedByLabel ?? _lockHolderLabel(data);
    final activelyHeld = _isLockActivelyHeldByOther(data);

    // Bàn tạm rời / khóa cũ — tự force claim khi đã trong đơn bàn.
    if (_tab.isTableBound && !activelyHeld) {
      res = await tryLock(force: true);
      if (!mounted) return false;
      if (res['isSuccess'] == true) {
        final forced = res['data'] is Map
            ? Map<String, dynamic>.from(res['data'] as Map)
            : null;
        if (!_isLockedByAnotherDevice(forced)) {
          _floorReleasedOrderIds.remove(orderId);
          setState(() {
            if (forced != null) _applyLockMetaFromMap(forced);
            _tab.draftReadOnly = false;
            _tab.lockedByLabel = null;
            _ignoreReadOnlyUntil =
                DateTime.now().add(const Duration(seconds: 45));
          });
          return true;
        }
      }
    }

    setState(() {
      _tab.draftReadOnly = true;
      if (data != null) _applyLockMetaFromMap(data);
    });

    NotificationOverlayManager().showWarning(
      title: 'Chỉ xem',
      message: activelyHeld
          ? 'Bàn đang mở trên $holder — chờ máy đó về sơ đồ bàn rồi thử lại'
          : 'Không lấy được quyền sửa — thử lại sau vài giây',
    );
    return false;
  }

  /// Gia hạn / lấy khóa trước khi ghi đơn bàn — tránh 409 «không giữ được bàn».
  Future<bool> _ensureLockHeldForTableEdit(_SellInvoiceTab tab) async {
    if (!tab.isTableBound || tab.draftReadOnly) return !tab.draftReadOnly;
    final orderId = tab.draftOrderId;
    if (orderId == null || orderId.isEmpty) return true;
    if (_floorReleasedOrderIds.contains(orderId)) return false;
    if (identical(tab, _tab) &&
        _ignoreReadOnlyUntil != null &&
        DateTime.now().isBefore(_ignoreReadOnlyUntil!)) {
      return true;
    }

    await _ensureDeviceReady();
    final deviceId = _posDeviceId;
    final deviceName = _posDeviceName;
    if (deviceId == null || deviceName == null) return false;

    Future<Map<String, dynamic>> tryLock({required bool force}) =>
        _api.lockPosSaleDraft(
          orderId,
          deviceId: deviceId,
          deviceName: deviceName,
          force: force,
        );

    var res = await tryLock(force: false);
    if (!mounted) return false;
    if (res['isSuccess'] == true) {
      final data = res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      if (_isLockedByAnotherDevice(data)) {
        if (!_isLockActivelyHeldByOther(data)) {
          res = await tryLock(force: true);
          if (!mounted || res['isSuccess'] != true) return false;
          final forced = res['data'] is Map
              ? Map<String, dynamic>.from(res['data'] as Map)
              : null;
          if (_isLockedByAnotherDevice(forced)) return false;
          if (identical(tab, _tab)) {
            _floorReleasedOrderIds.remove(orderId);
            setState(() {
              if (forced != null) _applyLockMetaFromMap(forced, tab: tab);
              tab.draftReadOnly = false;
              tab.lockedByLabel = null;
              _ignoreReadOnlyUntil =
                  DateTime.now().add(const Duration(seconds: 45));
            });
          } else {
            if (forced != null) _applyLockMetaFromMap(forced, tab: tab);
            tab.draftReadOnly = false;
            tab.lockedByLabel = null;
          }
          return true;
        }
        return false;
      }
      if (identical(tab, _tab)) {
        _floorReleasedOrderIds.remove(orderId);
        setState(() {
          _applyLockMetaFromMap(data, tab: tab);
          tab.draftReadOnly = false;
          tab.lockedByLabel = null;
          _ignoreReadOnlyUntil =
              DateTime.now().add(const Duration(seconds: 45));
        });
      } else {
        _applyLockMetaFromMap(data, tab: tab);
        tab.draftReadOnly = false;
        tab.lockedByLabel = null;
      }
      return true;
    }

    if (res['statusCode'] == 409 && !_isLockActivelyHeldByOther(
          res['data'] is Map
              ? Map<String, dynamic>.from(res['data'] as Map)
              : null,
        )) {
      res = await tryLock(force: true);
      if (!mounted || res['isSuccess'] != true) return false;
      final forced = res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      if (_isLockedByAnotherDevice(forced)) return false;
      if (identical(tab, _tab)) {
        _floorReleasedOrderIds.remove(orderId);
        setState(() {
          if (forced != null) _applyLockMetaFromMap(forced, tab: tab);
          tab.draftReadOnly = false;
          tab.lockedByLabel = null;
          _ignoreReadOnlyUntil =
              DateTime.now().add(const Duration(seconds: 45));
        });
      } else {
        if (forced != null) _applyLockMetaFromMap(forced, tab: tab);
        tab.draftReadOnly = false;
        tab.lockedByLabel = null;
      }
      return true;
    }
    return false;
  }

  /// [forceTake]: true = cướp khóa (Lấy quyền). false = chỉ gia hạn nếu đang giữ.
  /// [quiet]: true = không toast lỗi (autosave retry dùng forceTake: false).
  Future<bool> _forceClaimActiveDraft({
    bool quiet = false,
    bool forceTake = true,
    bool restartSync = true,
  }) async {
    final orderId = _tab.draftOrderId;
    if (orderId == null || orderId.isEmpty) {
      setState(() {
        _tab.draftReadOnly = false;
        _tab.lockedByLabel = null;
      });
      return true;
    }
    await _ensureDeviceReady();
    final deviceId = _posDeviceId;
    final deviceName = _posDeviceName;
    if (deviceId == null || deviceName == null) return false;

    // Không hiện bảng «Lấy quyền» — claim thẳng; lỗi thì toast.

    final res = await _api.lockPosSaleDraft(
      orderId,
      deviceId: deviceId,
      deviceName: deviceName,
      force: forceTake,
    );
    if (!mounted) return false;
    if (res['isSuccess'] != true) {
      if (res['data'] is Map) {
        _applyLockMetaFromMap(
          Map<String, dynamic>.from(res['data'] as Map),
        );
      }
      if (!quiet) {
        final activelyHeld = res['statusCode'] == 409 &&
            _isLockActivelyHeldByOther(
              res['data'] is Map
                  ? Map<String, dynamic>.from(res['data'] as Map)
                  : null,
            );
        NotificationOverlayManager().showError(
          title: 'Không lấy được quyền',
          message: res['message']?.toString() ??
              (activelyHeld
                  ? 'Máy kia vẫn đang trong đơn — chờ về sơ đồ bàn'
                  : 'Thử lại sau vài giây'),
        );
      }
      return false;
    }
    _floorReleasedOrderIds.remove(orderId);
    setState(() {
      _applyLockMetaFromMap(
        res['data'] is Map
            ? Map<String, dynamic>.from(res['data'] as Map)
            : null,
      );
      _tab.draftReadOnly = false;
      _tab.lockedByLabel = null;
      _ignoreReadOnlyUntil = DateTime.now().add(const Duration(seconds: 45));
    });
    if (restartSync) {
      _restartDraftLockHeartbeat();
    }
    if (_tab.localDirty &&
        _tab.cart.isNotEmpty &&
        restartSync) {
      unawaited(_persistDraftAutosave(forTab: _tab, showLockError: true));
    }
    return true;
  }

  Future<bool> _unlockDraftQuietly(String? orderId) async {
    if (orderId == null || orderId.isEmpty) return true;
    await _ensureDeviceReady();
    final deviceId = _posDeviceId;
    final deviceName = _posDeviceName;
    if (deviceId == null || deviceName == null) return false;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final res = await _api.unlockPosSaleDraft(
          orderId,
          deviceId: deviceId,
          deviceName: deviceName,
        );
        if (res['isSuccess'] == true) return true;
      } catch (_) {}
      if (attempt < 4) {
        await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
      }
    }
    return false;
  }

  void _stopDraftLockHeartbeat() {
    _draftLockHeartbeat?.cancel();
    _draftLockHeartbeat = null;
  }

  /// Bắt đầu vòng sync nếu chưa chạy. Không restart (tránh bão request mỗi lần autosave).
  void _ensureDraftSyncLoop() {
    final hasDraft = _tabs.any(
        (t) => t.draftOrderId != null && t.draftOrderId!.isNotEmpty);
    if (!hasDraft) {
      _stopDraftLockHeartbeat();
      return;
    }
    if (_draftLockHeartbeat != null) return;
    // SignalR connected → poll 10s; mất WS → 4s fallback. PosFloorChanged sync sớm hơn.
    final connected = SignalRService().isConnected;
    final poll =
        connected ? const Duration(seconds: 10) : const Duration(seconds: 4);
    _draftLockHeartbeat = Timer.periodic(poll, (_) {
      if (SignalRService().isConnected != connected) {
        _stopDraftLockHeartbeat();
        _ensureDraftSyncLoop();
      }
      unawaited(_syncHeldDraftTabs());
    });
  }

  /// Restart có chủ đích (đổi tab / mở draft) — kèm 1 lần sync ngay.
  void _restartDraftLockHeartbeat() {
    _stopDraftLockHeartbeat();
    _ensureDraftSyncLoop();
    unawaited(_syncHeldDraftTabs());
  }

  void _markTabDirty(_SellInvoiceTab tab) {
    tab.localDirty = true;
  }

  /// Hủy timer autosave và đợi lần đang chạy xong — dùng trước thanh toán / giữ đơn /
  /// thao tác ghi đè draft để tránh PUT chồng → 500 serialization.
  Future<bool> _awaitDraftAutosaveIdle({
    int maxTicks = 150,
    Duration tick = const Duration(milliseconds: 80),
    String busyTitle = 'Đang lưu đơn',
    String? busyMessage,
  }) async {
    _draftAutosaveTimer?.cancel();
    for (var i = 0; i < maxTicks && _autosavingDraft; i++) {
      await Future<void>.delayed(tick);
    }
    if (_autosavingDraft) {
      if (mounted) {
        NotificationOverlayManager().showWarning(
          title: busyTitle,
          message: tr(busyMessage ?? 'Đợi lưu xong rồi thử lại'),
        );
      }
      return false;
    }
    return true;
  }

  /// [delay]: ghi chú / text dài hơn; SL / thêm hàng ngắn hơn.
  void _scheduleDraftAutosave({Duration delay = const Duration(milliseconds: 450)}) {
    if (_checkingOut || _parking) return;
    final tab = _tab;
    // Máy khác giữ khóa — không tự bỏ readOnly để ghi đè.
    if (tab.draftReadOnly) return;
    _markTabDirty(tab);
    // Giỏ trống + có draftId: vẫn lưu để xóa dòng trên server.
    if (tab.cart.isEmpty &&
        (tab.draftOrderId == null || tab.draftOrderId!.isEmpty)) {
      tab.localDirty = false;
      return;
    }
    // Đang autosave: vẫn xếp lịch lần sau — tránh mất dirty (vd. sau báo bếp).
    _draftAutosaveTimer?.cancel();
    _draftAutosaveTimer = Timer(delay, () {
      // Đơn bàn: phải retry-on-conflict + báo lỗi, không thì lưu thất bại âm thầm
      // sau khi vừa Lấy quyền (409) → món mới add vào coi như "tự động mất".
      unawaited(_persistDraftAutosave(
        forTab: tab,
        showLockError: tab.isTableBound,
        retryOnConflict: tab.isTableBound,
      ));
    });
  }

  bool _autosaveLockRetrying = false;

  Future<bool> _persistDraftAutosave({
    _SellInvoiceTab? forTab,
    bool showLockError = false,
    bool retryOnConflict = false,
  }) async {
    final tab = forTab ?? _tab;
    if (!mounted) return false;
    // Máy khác đang giữ khóa → không ghi đè; giữ dirty để không mất SL vừa tăng.
    if (tab.draftReadOnly) {
      return false;
    }
    final oid = tab.draftOrderId;
    if (oid != null && _floorReleasedOrderIds.contains(oid)) {
      return false;
    }
    if (_suspendDraftAutosave) return false;
    if (_checkingOut || _parking || _autosavingDraft) return false;
    // Slot vừa đóng — không tạo/ghi draft lại.
    if (_recentlyClosedSlots.containsKey(tab.id)) return false;
    // Giỏ local trống nhưng server còn món — không ghi đè (đang mở/claim bàn).
    if (tab.cart.isEmpty &&
        tab.draftOrderId != null &&
        tab.draftOrderId!.isNotEmpty &&
        tab.serverLineCount > 0 &&
        !tab.localDirty) {
      return false;
    }
    // Giỏ trống nhưng đã có draftId → vẫn lưu để xóa dòng trên server (đồng bộ máy khác).
    if (tab.cart.isEmpty &&
        (tab.draftOrderId == null || tab.draftOrderId!.isEmpty)) {
      tab.localDirty = false;
      return true;
    }
    // Resource bắt buộc chỉ khi đang sửa tab active và còn hàng.
    // Autosave: không toast (tránh spam khi chọn món trước khi chọn bàn).
    if (identical(tab, _tab) &&
        tab.cart.isNotEmpty &&
        !_ensureResourceIfRequired(notify: false)) {
      return false;
    }

    if (tab.isTableBound && !tab.draftReadOnly) {
      final locked = await _ensureLockHeldForTableEdit(tab);
      if (!locked) {
        if (showLockError && mounted) {
          NotificationOverlayManager().showError(
            title: 'Không giữ được bàn',
            message: tab.lockedByLabel != null
                ? 'Bàn vẫn mở trên ${tab.lockedByLabel}'
                : 'Thử lại sau vài giây hoặc về sơ đồ bấm «Lấy quyền»',
          );
        }
        return false;
      }
    }

    final snapshotLineCount = tab.cart.length;
    final snapshotFp = _cartSyncFingerprint(tab);
    _autosavingDraft = true;
    try {
      await _ensureDeviceReady();
      if (identical(tab, _tab)) {
        _refreshTimedLineQtys();
        _recalcTotals();
      }
      final body = _buildSaleBodyFor(tab, complete: false);
      var res = tab.draftOrderId != null
          ? await _api.updatePosSale(tab.draftOrderId!, body)
          : await _api.createPosSale(body);
      if (!mounted) return false;

      if (res['isSuccess'] != true &&
          retryOnConflict &&
          _isLockConflict(res) &&
          tab.draftOrderId != null) {
        // Đồng bộ lockVersion rồi gia hạn nếu đang giữ — không cướp máy khác.
        final conflictData = res['data'];
        if (conflictData is Map) {
          final v = conflictData['lockVersion'] ?? conflictData['LockVersion'];
          if (v is num) {
            tab.lockVersion = v.toInt();
          } else if (v != null) {
            tab.lockVersion = int.tryParse('$v') ?? tab.lockVersion;
          }
        }
        // KHÔNG force — nếu máy khác đang giữ hợp lệ thì phải thua, không cướp
        // ngược lại (trước đây forceTake: tab.isTableBound luôn = true cho đơn
        // bàn → tự cướp khóa ngược của máy vừa «Lấy quyền», gây lỗi "đơn đang mở
        // bởi..." ngay sau khi máy kia claim thành công).
        final held = await _forceClaimActiveDraft(
          quiet: true,
          forceTake: false,
          restartSync: false,
        );
        if (!mounted) return false;
        if (!held) {
          if (showLockError) {
            await _handleMutationLockConflict(
              res,
              title: 'Không lưu được đơn tạm',
            );
          }
          return false;
        }
        tab.draftReadOnly = false;
        final body2 = _buildSaleBodyFor(tab, complete: false);
        res = await _api.updatePosSale(tab.draftOrderId!, body2);
        if (!mounted) return false;
      }

      if (res['isSuccess'] != true) {
        // Giữ dirty để lần sau thử lại — không kéo đè giỏ local.
        if (_isLockConflict(res) && showLockError) {
          await _handleMutationLockConflict(res, title: 'Không lưu được đơn tạm');
        }
        return false;
      }
      final data = res['data'] as Map<String, dynamic>?;
      final orderId = data?['id']?.toString();
      final orderNo = data?['orderNo']?.toString() ?? '';
      setState(() {
        if (orderId != null && orderId.isNotEmpty) {
          tab.draftOrderId = orderId;
          tab.draftOrderNo =
              orderNo.isNotEmpty ? orderNo : tab.draftOrderNo;
        }
        tab.serverLineCount = snapshotLineCount;
        tab.serverTotal = data?['total'] is num
            ? (data!['total'] as num).toDouble()
            : tab.serverTotal;
        // Chỉ clear dirty khi nội dung giỏ không đổi trong lúc lưu.
        if (_cartSyncFingerprint(tab) == snapshotFp) {
          tab.localDirty = false;
        }
        _applyLockMetaFromMap(data, tab: tab);
      });
      _ensureDraftSyncLoop();
      return true;
    } catch (_) {
      // im lặng — lần sau autosave/heartbeat sẽ thử lại
      return false;
    } finally {
      _autosavingDraft = false;
      if (mounted && tab.localDirty && !_suspendDraftAutosave) {
        _draftAutosaveTimer?.cancel();
        _draftAutosaveTimer = Timer(const Duration(milliseconds: 280), () {
          unawaited(_persistDraftAutosave(forTab: tab));
        });
      } else if (_syncPending && mounted) {
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          if (mounted) unawaited(_syncHeldDraftTabs());
        });
      }
    }
  }

  Future<void> _pullServerOrderIntoTab(
    _SellInvoiceTab tab, {
    bool quiet = false,
  }) async {
    final orderId = tab.draftOrderId;
    if (orderId == null || orderId.isEmpty) return;
    if (_pullingDraft || _autosavingDraft || _parking || _checkingOut) return;
    // Đang có sửa local (kể cả khi readOnly sau 409) — không đè giỏ.
    if (tab.localDirty) return;

    _pullingDraft = true;
    try {
      await _ensureDeviceReady();
      final res = await _api.getPosSale(
        orderId,
        deviceId: _posDeviceId,
        deviceName: _posDeviceName,
      );
      if (!mounted) return;
      if (res['isSuccess'] != true || res['data'] is! Map<String, dynamic>) {
        return;
      }
      final order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      if (order.status != 'Draft') {
        // Slot đã TT / hủy → nạp lại Draft trống cùng số HĐ.
        await _reloadInvoiceSlot(tab.id);
        return;
      }

      // Nội dung đã khớp server — chỉ sync meta, không rebuild (tránh flicker).
      if (_cartSyncFingerprint(tab) == _orderSyncFingerprint(order)) {
        tab.lockVersion = order.lockVersion;
        tab.serverLineCount = order.lines.length;
        tab.serverTotal = order.total;
        _applyLockMetaFromMap(res['data'] as Map<String, dynamic>, tab: tab);
        tab.draftReadOnly = false;
        return;
      }

      await _hydrateTabCartFromOrder(
        tab,
        order,
        orderJson: res['data'] as Map<String, dynamic>,
        readOnly: false,
        notify: false,
      );
    } finally {
      _pullingDraft = false;
    }
  }

  Future<void> _hydrateTabCartFromOrder(
    _SellInvoiceTab tab,
    PosSaleOrder order, {
    Map<String, dynamic>? orderJson,
    required bool readOnly,
    bool notify = false,
    bool force = false,
  }) async {
    // User đang sửa (dirty) — KHÔNG rebuild giỏ để tránh mất món/số lượng vừa nhập.
    // Chỉ cập nhật meta (lockVersion / serverLineCount) qua caller.
    if (!force && tab.localDirty && tab.cart.isNotEmpty) {
      if (orderJson != null) {
        _applyLockMetaFromMap(orderJson, tab: tab);
      }
      tab.serverLineCount = order.lines.length;
      tab.serverTotal = order.total;
      if (order.lockVersion > tab.lockVersion) {
        tab.lockVersion = order.lockVersion;
      }
      return;
    }
    // Khôi phục bảng giá trước khi build view/giá dòng.
    final plId = order.priceListId;
    if (plId != null && plId.isNotEmpty) {
      tab.priceListId = plId;
      tab.priceListLabel = order.priceListName ?? tab.priceListLabel;
      await _ensurePriceOverrides(plId);
    } else if (order.priceListName != null && order.priceListName!.isNotEmpty) {
      tab.priceListLabel = order.priceListName ?? tab.priceListLabel;
      final match =
          _priceLists.where((p) => p.name == order.priceListName).firstOrNull;
      if (match != null) {
        tab.priceListId = match.id;
        await _ensurePriceOverrides(match.id);
      }
    }
    if (!mounted) return;

    final products = await _resolveDraftProducts(order.lines);
    if (!mounted) return;
    final variants = await _resolveDraftVariants(products, order.lines);
    if (!mounted) return;

    final overrides = tab.priceListId != null
        ? (_priceOverrideCache[tab.priceListId!] ?? const <String, double>{})
        : const <String, double>{};

    final cartLines = <_SellCartLine>[];
    for (final line in order.lines) {
      if (line.productId.isEmpty) continue;
      final p = products[line.productId];
      if (p == null) continue;

      var views = posProductHasEmbeddedSellViews(p)
          ? buildPosSellUnitViewsFromProduct(p)
          : await loadPosSellUnitViews(_api, p);
      views = applyPosPriceListToViews(views, p, overrides);
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
        discountIsPercent: false,
        vatRate: p.vatExempt ? 0 : p.vatRate,
        vatExempt: p.vatExempt,
      );
      cartLine.kitchenSentQty =
          line.kitchenSentQty.clamp(0.0, line.qty).toDouble();
      // Báo kho: dùng cùng mốc đã gửi bếp nếu chưa có tracking riêng.
      cartLine.warehouseSlipPrintedQty = cartLine.kitchenSentQty;
      cartLine.toppings = line.toppings
          .map((t) => _CartTopping(id: t.id, name: t.name, price: t.price))
          .toList();
      final split = splitPosLineNote(line.lineNote, p.saleQuickNotes);
      cartLine.selectedQuickNotes
        ..clear()
        ..addAll(split.selected);
      cartLine.noteCtrl.text = split.extra;
      cartLines.add(cartLine);
    }

    if (!mounted) return;
    setState(() {
      for (final c in tab.cart) {
        c.dispose();
      }
      tab.cart.clear();
      tab.cart.addAll(cartLines);
      tab.draftOrderId = order.id;
      tab.draftOrderNo = order.orderNo;
      if (order.lockVersion > tab.lockVersion) {
        tab.lockVersion = order.lockVersion;
      }
      tab.serverLineCount = order.lines.length;
      tab.serverTotal = order.total;
      tab.localDirty = false;
      tab.draftReadOnly = readOnly;
      if (order.priceListId != null && order.priceListId!.isNotEmpty) {
        tab.priceListId = order.priceListId;
        tab.priceListLabel = order.priceListName ?? tab.priceListLabel;
      } else if (order.priceListName != null) {
        tab.priceListLabel = order.priceListName ?? tab.priceListLabel;
      }
      if (orderJson != null) {
        _applyLockMetaFromMap(orderJson, tab: tab);
        tab.draftReadOnly = readOnly;
      } else if (order.lockedByDisplayName != null) {
        tab.lockedByLabel = order.lockBadgeLabel;
      }
      tab.discount = order.discount;
      tab.discountInput = order.discount;
      tab.discountIsPercent = false;
      tab._discountCtrl.text = order.discount == order.discount.roundToDouble()
          ? order.discount.toStringAsFixed(0)
          : order.discount.toStringAsFixed(2);
      tab.note = order.note;
      tab._noteCtrl.text = order.note ?? '';
      tab.serviceResourceId =
          order.serviceResourceId ?? tab.serviceResourceId;
      // Không ghi đè session đang sống bằng null từ đơn (tránh mất tạm tính).
      if ((order.resourceSessionId ?? '').isNotEmpty) {
        tab.resourceSessionId = order.resourceSessionId;
      }
      tab.serviceStartedAt = order.serviceStartedAt;
      tab.serviceResourceName =
          order.serviceResourceName ?? order.serviceResourceCode;
      tab.serviceAreaName = order.serviceAreaName ?? tab.serviceAreaName;
      if (order.customerId != null && order.customerId!.isNotEmpty) {
        tab.customer = PosCustomer(
          id: order.customerId!,
          customerCode: order.customerCode ?? '',
          name: order.customerName ?? 'Khách hàng',
          phone: order.customerPhone,
        );
        tab._customerSearchCtrl.text = order.customerName ?? '';
      } else {
        tab.customer = null;
        tab._customerSearchCtrl.clear();
      }
      if (identical(tab, _tab)) {
        _syncPaidAmount();
      }
    });

    // Không toast khi đồng bộ nền — tránh spam che màn hình.
  }

  /// Đảm bảo giỏ khớp server sau mở bàn (tránh Oppo/V2S lệch số món).
  Future<void> _verifyTableCartHydrated(String orderId) async {
    // User đang sửa — bỏ verify để không đè giỏ.
    if (_tab.localDirty) return;
    await _ensureDeviceReady();
    final orderJson = await _fetchDraftOrderJson(orderId);
    if (!mounted || orderJson == null) return;
    // Race: user vừa sửa trong lúc fetch — bỏ verify.
    if (_tab.localDirty) return;
    final order = PosSaleOrder.fromJson(orderJson);
    final remoteLines = order.lines.length;
    final remoteTotal = order.total;
    final cartMismatch = _tab.cart.length != remoteLines;
    final totalMismatch = (_tab.serverTotal - remoteTotal).abs() > 0.009 ||
        (_total - remoteTotal).abs() > 0.009;
    if (!cartMismatch && !totalMismatch) {
      setState(() {
        _tab.serverLineCount = remoteLines;
        _tab.serverTotal = remoteTotal;
        _tab.localDirty = false;
      });
      return;
    }
    if (_tab.localDirty) return;
    await _hydrateTabCartFromOrder(
      _tab,
      order,
      orderJson: orderJson,
      readOnly: _tab.draftReadOnly,
      notify: false,
    );
    if (!mounted) return;
    setState(() {
      _tab.serverLineCount = remoteLines;
      _tab.serverTotal = remoteTotal;
      _tab.localDirty = false;
    });
    if (_tab.cart.length < remoteLines) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu món trên giỏ',
        message: tr('Server có $remoteLines món · giỏ hiển thị ${_tab.cart.length} — thử tải lại danh mục'),
      );
    }
  }

  String _cartSyncFingerprint(_SellInvoiceTab tab) {
    final parts = <String>[
      'note=${tab.note ?? ''}',
      'disc=${tab.discount.toStringAsFixed(2)}',
    ];
    for (final c in tab.cart) {
      parts.add([
        c.product.id,
        c.variantId ?? '',
        c.unitLabel,
        c.qty.toStringAsFixed(4),
        c.unitPrice.toStringAsFixed(2),
        c.discountAmount.toStringAsFixed(2),
        c.lineNote ?? '',
        c.kitchenSentQty.toStringAsFixed(4),
        c.toppings.map((t) => '${t.id}:${t.price}').join(','),
      ].join(':'));
    }
    return parts.join('|');
  }

  String _orderSyncFingerprint(PosSaleOrder order) {
    final parts = <String>[
      'note=${order.note ?? ''}',
      'disc=${order.discount.toStringAsFixed(2)}',
    ];
    for (final l in order.lines) {
      parts.add([
        l.productId,
        l.variantId ?? '',
        l.unitName ?? '',
        l.qty.toStringAsFixed(4),
        l.unitPrice.toStringAsFixed(2),
        l.discountAmount.toStringAsFixed(2),
        l.lineNote ?? '',
        l.kitchenSentQty.toStringAsFixed(4),
        l.toppings.map((t) => '${t.id}:${t.price}').join(','),
      ].join(':'));
    }
    return parts.join('|');
  }

  Future<void> _syncHeldDraftTabs() async {
    // Tránh race: đang in tạm tính / báo bếp / checkout / autosave → bỏ qua vòng sync.
    if (_syncInFlight ||
        _parking ||
        _checkingOut ||
        _provisionalPrinting ||
        _kitchenSending ||
        _autosavingDraft ||
        _suspendDraftAutosave) {
      _syncPending = true;
      return;
    }
    _syncInFlight = true;
    _syncPending = false;
    try {
      await _ensureDeviceReady();
      if (!mounted) return;
      final deviceId = _posDeviceId;
      final deviceName = _posDeviceName;

      // 1) Metadata nhanh từ invoice-slots (lineCount / lock / version).
      // Không truyền số tab làm count — tránh server Ensure tạo lại slot vừa xóa.
      final slotsRes = await _api.getPosInvoiceSlots(
        count: 3,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      if (!mounted) return;

      final needDetail = <_SellInvoiceTab>[];
      var metaChanged = false;
      if (slotsRes['isSuccess'] == true && slotsRes['data'] is Map) {
        final slotData = slotsRes['data'] as Map;
        final items = (slotData['items'] as List?) ?? [];
        final bySlot = <int, Map<String, dynamic>>{};
        for (final raw in items) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final slot = (m['invoiceSlot'] is num)
              ? (m['invoiceSlot'] as num).toInt()
              : int.tryParse('${m['invoiceSlot']}') ?? 0;
          if (slot > 0) bySlot[slot] = m;
        }

        // Server thêm/xóa slot (máy khác hoặc prune) → đồng bộ lại tab UI.
        // Đang trong đơn bàn: không rebuild slot (tránh đè BAN* bằng TMP trống).
        final serverIds = bySlot.keys.toSet();
        final localIds = _tabs.map((t) => t.id).toSet();
        final inTableOrder = _tabs.any((t) => t.isTableBound);
        if (!inTableOrder &&
            serverIds.isNotEmpty &&
            (serverIds.length != localIds.length ||
                !serverIds.containsAll(localIds) ||
                !localIds.containsAll(serverIds))) {
          await _applyInvoiceSlotsPayload(slotData, hydrateAll: false);
          if (!mounted) return;
        }

        for (final tab in _tabs) {
          // Đơn bàn ngoài hệ thống slot TMP — không reconcile bằng invoice-slots.
          if (tab.isTableBound) continue;

          final m = bySlot[tab.id];
          if (m == null) continue;
          final newId = m['id']?.toString();
          final lc = m['lineCount'] is num
              ? (m['lineCount'] as num).toInt()
              : int.tryParse('${m['lineCount']}') ?? 0;
          final total = m['total'] is num
              ? (m['total'] as num).toDouble()
              : double.tryParse('${m['total']}') ?? 0;
          final ver = m['lockVersion'] is num
              ? (m['lockVersion'] as num).toInt()
              : int.tryParse('${m['lockVersion']}') ?? tab.lockVersion;
          final locked = m['isLocked'] == true;
          final byMeFlag = m['isLockedByMe'] == true;
          final effectivelyLockedRaw = _isEffectivelyLockedByOther(
            lineCount: lc,
            isLocked: locked,
            isLockedByMeFlag: byMeFlag,
            lockedByDeviceId: m['lockedByDeviceId']?.toString(),
          );
          final inGrace = _ignoreReadOnlyUntil != null &&
              DateTime.now().isBefore(_ignoreReadOnlyUntil!) &&
              identical(tab, _tab);
          final effectivelyLocked =
              effectivelyLockedRaw && !inGrace;

          // Snapshot trước khi đè meta — dùng để quyết định mustPull (qty/note/size).
          final prevLc = tab.serverLineCount;
          final prevTotal = tab.serverTotal;
          final prevVer = tab.lockVersion;
          final prevDraftId = tab.draftOrderId;
          var forceHydrate = false;

          if (newId != null &&
              newId.isNotEmpty &&
              tab.draftOrderId != null &&
              tab.draftOrderId != newId) {
            // Máy khác đã thanh toán / tạo draft mới cùng slot → đồng bộ ngược.
            // Không đè khi đang sửa local.
            if (tab.localDirty) continue;
            tab.draftOrderId = newId;
            tab.lockVersion = ver;
            tab.localDirty = false;
            tab.serverLineCount = lc;
            tab.serverTotal = total;
            if (tab.cart.isNotEmpty) {
              for (final line in List<_SellCartLine>.from(tab.cart)) {
                line.dispose();
              }
              tab.cart.clear();
            }
            forceHydrate = true;
            metaChanged = true;
          } else if (newId != null && tab.draftOrderId == null) {
            tab.draftOrderId = newId;
            forceHydrate = true;
            metaChanged = true;
          }

          // Server báo HĐ trống nhưng máy này còn dòng → bắt buộc pull (sau TT).
          // Không áp khi dirty — tránh xóa món vừa thêm vào bàn/giỏ.
          if (lc == 0 && tab.cart.isNotEmpty && !tab.localDirty) {
            forceHydrate = true;
            metaChanged = true;
          }

          // Đang sửa local: không lấy lineCount/total server đè, không cướp quyền.
          if (!tab.localDirty) {
            if (prevLc != lc ||
                (prevTotal - total).abs() > 0.009 ||
                prevVer != ver ||
                tab.draftReadOnly != effectivelyLocked) {
              tab.draftReadOnly = effectivelyLocked;
              if (effectivelyLocked) {
                tab.lockedByLabel = _lockHolderLabel(m);
              } else {
                tab.lockedByLabel = null;
              }
              if (!forceHydrate) {
                tab.serverLineCount = lc;
                tab.serverTotal = total;
              }
              metaChanged = true;
            }
          } else if (effectivelyLocked && !inGrace) {
            // Đang sửa — giữ localDirty, chỉ đánh dấu cần claim lúc lưu (không xóa giỏ).
            metaChanged = true;
          }

          final orderId = tab.draftOrderId;
          if (orderId == null || orderId.isEmpty) continue;

          final remoteAhead = ver > prevVer ||
              lc != prevLc ||
              (total - prevTotal).abs() > 0.009 ||
              prevDraftId != tab.draftOrderId ||
              (!tab.localDirty && lc != tab.cart.length);
          // Force hydrate sau TT / đổi draft id; còn lại chỉ pull khi không dirty.
          if (forceHydrate || (!tab.localDirty && remoteAhead)) {
            needDetail.add(tab);
          }
        }
      } else {
        // Fallback: không có slots → chỉ sync tab đang mở nếu không dirty.
        for (final tab in _tabs) {
          if (tab.draftOrderId != null &&
              !tab.localDirty &&
              (tab.draftReadOnly || identical(tab, _tab))) {
            needDetail.add(tab);
          }
        }
      }

      // Đơn bàn: không có trong invoice-slots — chỉ GET khi lệch dòng / remote ahead
      // (trước đây GET mọi tab bàn mỗi 4s → chậm khi mở bàn).
      for (final tab in _tabs) {
        if (!tab.isTableBound) continue;
        final oid = tab.draftOrderId;
        if (oid == null || oid.isEmpty) continue;
        if (tab.localDirty || needDetail.contains(tab)) continue;
        final lineMismatch =
            tab.serverLineCount > 0 && tab.cart.length != tab.serverLineCount;
        final activeNeedsRefresh =
            identical(tab, _tab) && tab.draftReadOnly;
        if (lineMismatch || activeNeedsRefresh) {
          needDetail.add(tab);
        }
      }

      // 2) GET chi tiết khi metadata báo remoteAhead.
      final toFetch = needDetail.where((t) => !_autosavingDraft).toList();
      var hydratedAny = false;
      if (toFetch.isNotEmpty) {
        final results = await Future.wait(toFetch.map((tab) async {
          final id = tab.draftOrderId;
          if (id == null) return null;
          final res = await _api.getPosSale(
            id,
            deviceId: deviceId,
            deviceName: deviceName,
          );
          return (tab: tab, res: res);
        }));
        if (!mounted) return;

        for (final item in results) {
          if (item == null) continue;
          final tab = item.tab;
          final res = item.res;

          if (res['isSuccess'] != true || res['data'] is! Map<String, dynamic>) {
            if (res['statusCode'] == 404) {
              await _reloadInvoiceSlot(tab.id);
            }
            continue;
          }

          final order =
              PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
          if (order.status != 'Draft') {
            await _reloadInvoiceSlot(tab.id);
            continue;
          }

          final remoteVer = order.lockVersion;
          final remoteLines = order.lines.length;
          final remoteTotal = order.total;
          final prevVer = tab.lockVersion;

          // Áp khóa theo device trước — máy giữ = nguồn; máy khác chỉ pull.
          _applyLockMetaFromMap(
              res['data'] as Map<String, dynamic>,
              tab: tab);
          final inGrace = _ignoreReadOnlyUntil != null &&
              DateTime.now().isBefore(_ignoreReadOnlyUntil!) &&
              identical(tab, _tab);
          if (inGrace && tab.draftReadOnly) {
            // Vừa Lấy quyền — đừng kéo lại readOnly/hydrate trong grace.
            tab.draftReadOnly = false;
            tab.lockedByLabel = null;
          }
          final heldByOther = tab.draftReadOnly;

          // Đang sửa trên máy giữ khóa: không đè giỏ (kể cả readOnly tạm thời).
          if (tab.localDirty) {
            continue;
          }

          final remoteFp = _orderSyncFingerprint(order);
          final localFp = _cartSyncFingerprint(tab);
          final contentChanged = remoteFp != localFp ||
              remoteVer != prevVer ||
              remoteLines != tab.cart.length ||
              (remoteTotal - tab.serverTotal).abs() > 0.009;

          tab.serverLineCount = remoteLines;
          tab.serverTotal = remoteTotal;

          if (!contentChanged || remoteFp == localFp) {
            // Chỉ cập nhật meta — tránh rebuild giỏ / toast khi ghi chú-SL đã khớp.
            tab.lockVersion = remoteVer;
            continue;
          }

          await _hydrateTabCartFromOrder(
            tab,
            order,
            orderJson: res['data'] as Map<String, dynamic>,
            readOnly: heldByOther,
            notify: false,
          );
          tab.localDirty = false;
          hydratedAny = true;
        }
      }

      // 3) Gia hạn khóa thật cho tab đang giữ (tránh TTL hết → 2 máy cùng sửa).
      await _renewHeldDraftLocks(
        deviceId: deviceId,
        deviceName: deviceName,
      );

      if (mounted && (metaChanged || hydratedAny)) setState(() {});
    } finally {
      _syncInFlight = false;
      if (_syncPending && mounted) {
        _syncPending = false;
        // Chạy lại sau thao tác in/lưu — tránh mất cập nhật từ máy khác.
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          if (mounted) unawaited(_syncHeldDraftTabs());
        });
      }
    }
  }

  Future<void> _heartbeatHeldDraftLocks() => _syncHeldDraftTabs();

  /// Gia hạn TTL khóa cho tab đang giữ — bỏ qua khi đang xem sơ đồ / đã nhả khóa.
  Future<void> _renewHeldDraftLocks({
    String? deviceId,
    String? deviceName,
  }) async {
    if (_floorMapVisible) return;
    if (deviceId == null ||
        deviceId.isEmpty ||
        deviceName == null ||
        deviceName.isEmpty) {
      return;
    }
    final held = _tabs
        .where((t) {
          final id = t.draftOrderId;
          if (id == null || id.isEmpty) return false;
          if (t.draftReadOnly) return false;
          if (_floorReleasedOrderIds.contains(id)) return false;
          return true;
        })
        .toList();
    if (held.isEmpty) return;
    await Future.wait(held.map((tab) async {
      final id = tab.draftOrderId;
      if (id == null || id.isEmpty) return;
      try {
        final res = await _api.heartbeatPosSaleDraftLock(
          id,
          deviceId: deviceId,
          deviceName: deviceName,
        );
        if (!mounted) return;
        if (res['isSuccess'] == true && res['data'] is Map) {
          _applyLockMetaFromMap(
            Map<String, dynamic>.from(res['data'] as Map),
            tab: tab,
          );
          tab.draftReadOnly = false;
          tab.lockedByLabel = null;
        } else if (res['statusCode'] == 409) {
          if (res['data'] is Map) {
            _applyLockMetaFromMap(
              Map<String, dynamic>.from(res['data'] as Map),
              tab: tab,
            );
          } else {
            tab.draftReadOnly = true;
          }
        }
      } catch (_) {}
    }));
  }

  /// Xóa giỏ/draft local khi đơn trên server không còn là Draft (đã TT / hủy…).
  void _invalidateStaleDraftTab(
    _SellInvoiceTab tab, {
    required String title,
    required String message,
    bool asInfo = false,
  }) {
    if (!mounted) return;
    final index = _tabs.indexOf(tab);
    if (index < 0) return;

    if (asInfo) {
      NotificationOverlayManager().showInfo(title: title, message: message);
    } else {
      NotificationOverlayManager().showError(title: title, message: message);
    }

    setState(() {
      tab.reset(defaultVatRate: _storeSettings.defaultVatRate);
      tab.sellerEmployeeId = _defaultSellerEmployeeId;
      if (index == _activeTab) {
        _customerSuggestions = [];
        _syncPaidAmount();
      }
    });
    _restartDraftLockHeartbeat();
  }

  /// Đối chiếu 1 tab với server. Trả về true nếu đã xóa tab (không còn Draft).
  Future<bool> _reconcileDraftTabAgainstServer(_SellInvoiceTab tab) async {
    final orderId = tab.draftOrderId;
    if (orderId == null || orderId.isEmpty) return false;

    final res = await _api.getPosSale(orderId);
    if (!mounted) return false;

    if (res['isSuccess'] != true || res['data'] is! Map<String, dynamic>) {
      final code = res['statusCode'];
      if (code == 404 || code == 403) {
        _invalidateStaleDraftTab(
          tab,
          title: 'Đơn không còn',
          message:
              '${tab.draftOrderNo ?? 'Đơn tạm'} không còn trên server — đã xóa khỏi tab',
        );
        return true;
      }
      return false;
    }

    final order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
    if (order.status == 'Draft') {
      _applyLockMetaFromMap(res['data'] as Map<String, dynamic>, tab: tab);
      return false;
    }

    final paid = order.status == 'Completed';
    final no = order.orderNo.isNotEmpty ? order.orderNo : (tab.draftOrderNo ?? '');
    _invalidateStaleDraftTab(
      tab,
      title: paid ? 'Đơn đã thanh toán' : 'Đơn không còn tạm',
      message: paid
          ? 'Mã $no đã thanh toán trên máy khác — đã xóa khỏi tab này'
          : 'Mã $no (${order.status}) — đã xóa khỏi tab này',
      asInfo: paid,
    );
    return true;
  }

  Future<void> _reconcileAllHeldDraftTabs() async {
    final held = _tabs
        .where((t) => t.draftOrderId != null && t.draftOrderId!.isNotEmpty)
        .toList();
    for (final tab in held) {
      if (!mounted) return;
      await _reconcileDraftTabAgainstServer(tab);
    }
  }

  /// Tab local có draftId nhưng không còn trong danh sách Draft server → đối chiếu.
  Future<void> _reconcileHeldDraftsMissingFrom(List<PosSaleOrder> drafts) async {
    final ids = drafts.map((d) => d.id).toSet();
    final stale = _tabs
        .where((t) {
          final id = t.draftOrderId;
          return id != null && id.isNotEmpty && !ids.contains(id);
        })
        .toList();
    for (final tab in stale) {
      if (!mounted) return;
      await _reconcileDraftTabAgainstServer(tab);
    }
  }

  Future<({List<PosSaleOrder> drafts, String? loadError})> _fetchServerDrafts() async {
    try {
      final res = await _api.getPosSales(
        statuses: const ['Draft'],
        page: 1,
        pageSize: 40,
      );
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        final drafts = ((data['items'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => PosSaleOrder.fromJson(Map<String, dynamic>.from(e)))
            .where((o) => o.status == 'Draft')
            .toList();
        return (drafts: drafts, loadError: null);
      }
      return (
        drafts: <PosSaleOrder>[],
        loadError: res['message']?.toString() ?? 'Không tải được đơn tạm',
      );
    } catch (_) {
      return (
        drafts: <PosSaleOrder>[],
        loadError: 'Không tải được đơn tạm',
      );
    }
  }

  bool _isLockConflict(Map<String, dynamic> res) =>
      res['isSuccess'] != true && res['statusCode'] == 409;

  /// 409 do serialization / trùng mã HD–phiếu thu — khác khóa máy (được phép retry 1 lần).
  bool _isRetryableCheckoutConflict(Map<String, dynamic> res) {
    if (res['isSuccess'] == true || res['statusCode'] != 409) return false;
    final msg = (res['message'] ?? res['errors'] ?? '').toString().toLowerCase();
    return msg.contains('xung đột') ||
        msg.contains('trùng mã') ||
        msg.contains('đồng thời') ||
        msg.contains('serialization');
  }

  void _notifyLockConflict(Map<String, dynamic> res, {required String title}) {
    NotificationOverlayManager().showError(
      title: title,
      message: res['message']?.toString() ??
          'Đơn đang được máy khác giữ.',
    );
  }

  Future<void> _handleMutationLockConflict(
    Map<String, dynamic> res, {
    required String title,
  }) async {
    _notifyLockConflict(res, title: title);
    await _reconcileDraftTabAgainstServer(_tab);
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

  Future<void> _loadDraftIntoActiveTab(
    String orderId, {
    bool silent = false,
    bool viewOnlyOnConflict = false,
    bool forceClaim = false,
  }) async {
    await _ensureDeviceReady();
    _suspendDraftAutosave = true;
    var orderJson = await _fetchDraftOrderJson(orderId);
    if (!mounted) return;
    if (orderJson == null) {
      _suspendDraftAutosave = false;
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: tr('Không tải được đơn tạm'),
      );
      return;
    }
    final order = PosSaleOrder.fromJson(orderJson);
    if (order.status != 'Draft') {
      _suspendDraftAutosave = false;
      NotificationOverlayManager().showError(
        title: 'Không phải đơn tạm',
        message: tr('Chỉ tiếp tục được đơn ở trạng thái tạm'),
      );
      return;
    }

    final switchingOrder = (_tab.draftOrderId ?? '') != orderId;
    var readOnly = false;
    Map<String, dynamic>? lockData;
    setState(() {
      if (switchingOrder) {
        _tab.reset(defaultVatRate: _storeSettings.defaultVatRate);
      }
      _tab.draftOrderId = order.id;
      _tab.draftOrderNo = order.orderNo;
      _tab.sellerEmployeeId = _defaultSellerEmployeeId;
      _tab.lockVersion = order.lockVersion;
      _tab.serverLineCount = order.lines.length;
      _tab.serverTotal = order.total;
      _tab.localDirty = false;
    });
    if (forceClaim) {
      final ok = await _forceClaimActiveDraft(
        quiet: true,
        forceTake: true,
        restartSync: false,
      );
      if (!mounted || !ok) {
        if (mounted) {
          setState(() {
            if (switchingOrder) {
              _tab.reset(defaultVatRate: _storeSettings.defaultVatRate);
              _tab.sellerEmployeeId = _defaultSellerEmployeeId;
            }
          });
          _suspendDraftAutosave = false;
          NotificationOverlayManager().showError(
            title: 'Không lấy được quyền',
            message: _tab.lockedByLabel != null
                ? 'Bàn vẫn đang mở trên ${_tab.lockedByLabel}'
                : 'Thử lại sau vài giây',
          );
        }
        return;
      }
      readOnly = false;
      // GET lại sau claim — tránh lockVersion cũ + meta khóa máy kia.
      orderJson = await _fetchDraftOrderJson(orderId);
      if (!mounted) return;
      if (orderJson == null) {
        _suspendDraftAutosave = false;
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: tr('Đã lấy quyền nhưng chưa tải lại được đơn — thử mở lại bàn'),
        );
        return;
      }
    } else {
      final access = await _claimOrViewDraft(
        orderId,
        silentViewOnConflict: viewOnlyOnConflict || silent,
      );
      if (!mounted || access == null) {
        _suspendDraftAutosave = false;
        return;
      }
      readOnly = access.readOnly;
      lockData = access.lock;
    }

    final freshOrder = PosSaleOrder.fromJson(orderJson);
    setState(() {
      _tab.draftReadOnly = readOnly;
      _tab.serverLineCount = freshOrder.lines.length;
      _tab.serverTotal = freshOrder.total;
      _tab.localDirty = false;
      if (lockData != null) {
        _applyLockMetaFromMap(lockData);
        if (readOnly || _isLockedByAnotherDevice(lockData)) {
          _tab.draftReadOnly = true;
          _tab.lockedByLabel ??= _lockHolderLabel(lockData);
        }
      } else if (!readOnly) {
        _applyLockMetaFromMap(orderJson);
        _tab.draftReadOnly = false;
        _tab.lockedByLabel = null;
      } else {
        _applyLockMetaFromMap(orderJson);
        _tab.lockedByLabel = freshOrder.lockBadgeLabel;
      }
    });

    await _hydrateTabCartFromOrder(
      _tab,
      freshOrder,
      orderJson: orderJson,
      readOnly: _tab.draftReadOnly,
      notify: false,
      force: true,
    );

    if (!mounted) return;
    setState(() => _tab.localDirty = false);
    _restartDraftLockHeartbeat();
    await _verifyTableCartHydrated(orderId);
    if (!mounted) return;
    if (!silent) {
      _suspendDraftAutosave = false;
    }
    // Không toast tải đơn tạm — tránh che màn bán hàng mỗi lần mở bàn.
  }

  Future<void> _onBarcodeScanned(String code, {bool mergeIfSame = true}) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    final pick = await lookupOrPickPosProduct(context, _api, trimmed);
    if (!mounted) return;
    if (pick == null) {
      NotificationOverlayManager().showWarning(
        title: 'Không tìm thấy sản phẩm',
        message: tr('Mã vạch "$trimmed" không có trong danh mục hàng hóa'),
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
    _ensureDefaultPaymentLines();
    // Đổi bảng giá / tổng: luôn chỉnh dòng TT để tổng = số tiền khách cần trả.
    _distributePaymentsToDue();
  }

  /// Mặc định: Tiền mặt + Chuyển khoản (nguồn thứ 2 nếu có).
  void _ensureDefaultPaymentLines([_SellInvoiceTab? forTab]) {
    final tab = forTab ?? _tab;
    if (tab.paymentLines.isEmpty) {
      tab.paymentLines
          .add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
    }
    if (!tab.paymentsManuallyEdited &&
        tab.paymentLines.length == 1 &&
        _paymentSources.length > 1) {
      final bank = _paymentSources[1];
      if (bank.key != _PosPaymentSource.cashKey) {
        tab.paymentLines.add(_SellPaymentLine(sourceKey: bank.key));
      }
    }
  }

  /// Phân bổ / chỉnh số tiền các nguồn = [_grandTotal].
  void _distributePaymentsToDue() {
    if (_tab.paymentLines.isEmpty) {
      _tab.paymentLines
          .add(_SellPaymentLine(sourceKey: _PosPaymentSource.cashKey));
    }
    final due = _grandTotal;
    if (_tab.paymentLines.length == 1 || !_tab.paymentsManuallyEdited) {
      // Chưa chỉnh tay: toàn bộ vào dòng đầu, các dòng còn lại = 0.
      for (var i = 0; i < _tab.paymentLines.length; i++) {
        final pay = _tab.paymentLines[i];
        final amt = i == 0 ? due : 0.0;
        pay.amount = amt;
        pay.amountCtrl.text = amt > 0 ? _moneyFmt.format(amt) : '';
      }
    } else {
      // Đã tách nguồn: giữ các dòng sau, chỉnh dòng đầu cho khớp tổng cần trả.
      var rest = 0.0;
      for (var i = 1; i < _tab.paymentLines.length; i++) {
        rest += _tab.paymentLines[i].amount;
      }
      if (rest > due) {
        for (var i = 1; i < _tab.paymentLines.length; i++) {
          _tab.paymentLines[i].amount = 0;
          _tab.paymentLines[i].amountCtrl.text = '';
        }
        rest = 0;
      }
      final firstAmt = (due - rest).clamp(0.0, due);
      final first = _tab.paymentLines.first;
      first.amount = firstAmt;
      first.amountCtrl.text = firstAmt > 0 ? _moneyFmt.format(firstAmt) : '';
    }
    _tab.paidAmount = _effectivePaidAmount;
    _tab.paidManuallyEdited = false;
    _tab._paidCtrl.text = _moneyFmt.format(_tab.paidAmount);
  }

  void _onDiscountInputChanged(String raw, {VoidCallback? onMutate}) {
    if (!_guardReadOnlyEdit()) return;
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
    // Chưa đồng bộ — chỉ khi chọn preset / áp dụng.
  }

  void _setDiscountMode(bool isPercent, {VoidCallback? onMutate}) {
    if (!_guardReadOnlyEdit()) return;
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
    _scheduleDraftAutosave();
  }

  Future<bool> _confirmKitchenVoidPrintNow({
    required String productName,
    required double qty,
  }) async {
    // In phiếu hủy thẳng — không hỏi xác nhận (ít thao tác trên sàn cảm ứng).
    return true;
  }

  Future<void> _showReturnGoodsDialog(_SellCartLine line) async {
    if (!await _ensureCanEditActiveDraft()) return;
    if (!mounted) return;
    final current = line.qty;
    final returnCtrl = TextEditingController(text: tr('1'));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final raw = returnCtrl.text.trim().replaceAll(',', '.');
            final returnQty = double.tryParse(raw) ?? 0;
            final usedQty = (current - returnQty).clamp(0.0, current);
            final valid = returnQty > 0 && returnQty <= current;
            String fmt(double v) =>
                v % 1 == 0 ? v.toInt().toString() : _qtyFmt.format(v);
            return AlertDialog(
              title: Text(tr('Trả hàng')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('«${line.product.name}»'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Text(tr('Số lượng hiện tại: ${fmt(current)}')),
                  const SizedBox(height: 10),
                  PosNoSoftKeyboardField(
                    controller: returnCtrl,
                    allowDecimal: true,
                    autofocus: true,
                    keypadTitle: 'Số lượng trả',
                    decoration: InputDecoration(
                      labelText: tr('Số lượng khách trả lại'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 10),
                  Text(tr('Số lượng khách dùng: ${fmt(usedQty)}'),
                    style: TextStyle(
                      color: valid ? const Color(0xFF166534) : Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_isTableOrderMode && line.kitchenSentQty > 0) ...[
                    const SizedBox(height: 8),
                    Text(tr('${tr('Đã báo bếp: ')}${fmt(line.kitchenSentQty)} — sẽ in phiếu hủy '
                      'cho phần trả đã gửi bếp.'),
                      style: const TextStyle(
                          fontSize: 12, color: PosTheme.textSecondary),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Hủy')),
                ),
                FilledButton(
                  onPressed: valid ? () => Navigator.pop(ctx, returnQty) : null,
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700),
                  child: Text(tr('Xác nhận in phiếu')),
                ),
              ],
            );
          },
        );
      },
    );
    returnCtrl.dispose();
    if (result == null || result <= 0 || !mounted) return;

    final returnQty = result > current ? current : result;
    final productName = line.product.name;
    final kitchenVoid =
        _isTableOrderMode ? returnQty.clamp(0.0, line.kitchenSentQty) : 0.0;
    final nextQty = current - returnQty;
    final ticket = kitchenVoid > 0
        ? KitchenTicketLine(
            productName: productName,
            qty: kitchenVoid,
            unitName: line.unitLabel,
            note: line.noteWithToppings,
            productId: line.product.id,
          )
        : null;

    CancelReturnReasonResult? voidReason;
    if (ticket != null) {
      voidReason = await _promptKitchenVoidReason();
      if (voidReason == null || !mounted) return;
    }

    setState(() {
      if (kitchenVoid > 0) {
        line.kitchenSentQty =
            (line.kitchenSentQty - kitchenVoid).clamp(0.0, double.infinity);
      }
      if (nextQty <= 0) {
        line.dispose();
        if (_expandedCartRowId == line.rowId) {
          _expandedCartRowId = null;
          _expandedCartMode = null;
        }
        _tab.cart.remove(line);
      } else {
        line.qty = nextQty;
        if (line.kitchenSentQty > nextQty) line.kitchenSentQty = nextQty;
        if (line.warehouseSlipPrintedQty > nextQty) {
          line.warehouseSlipPrintedQty = nextQty;
        }
        if (line.cupLabelPrintedQty > nextQty) {
          line.cupLabelPrintedQty = nextQty;
        }
      }
      _syncPaidAmount();
    });
    _scheduleDraftAutosave();
    if (ticket != null) {
      await _voidKitchenSentLines([ticket], reasonResult: voidReason);
    } else {
      NotificationOverlayManager().showSuccess(
        title: 'Đã trả hàng',
        message: '«$productName» × ${_qtyFmt.format(returnQty)}',
      );
    }
  }

  Future<void> _removeLine(int index) async {
    if (!await _ensureCanEditActiveDraft()) return;
    final line = _tab.cart[index];
    final cancelQty = line.kitchenSentQty;
    if (cancelQty > 0 && _isTableOrderMode) {
      if (line.qty > 2) {
        await _showReturnGoodsDialog(line);
        return;
      }
      if (!await _confirmKitchenVoidPrintNow(
          productName: line.product.name, qty: cancelQty)) {
        return;
      }
      final voidReason = await _promptKitchenVoidReason();
      if (voidReason == null || !mounted) return;
      final ticket = KitchenTicketLine(
        productName: line.product.name,
        qty: cancelQty,
        unitName: line.unitLabel,
        note: line.noteWithToppings,
        productId: line.product.id,
      );
      setState(() {
        if (_expandedCartRowId == line.rowId) {
          _expandedCartRowId = null;
          _expandedCartMode = null;
        }
        line.dispose();
        _tab.cart.remove(line);
        _syncPaidAmount();
      });
      _scheduleDraftAutosave();
      await _voidKitchenSentLines([ticket], reasonResult: voidReason);
      return;
    }
    setState(() {
      if (_expandedCartRowId == line.rowId) {
        _expandedCartRowId = null;
        _expandedCartMode = null;
      }
      line.dispose();
      _tab.cart.removeAt(index);
      _syncPaidAmount();
    });
    _scheduleDraftAutosave();
  }

  Future<void> _adjustQty(_SellCartLine line, double delta) async {
    if (!await _ensureCanEditActiveDraft()) return;
    final next = line.qty + delta;
    if (next <= 0) {
      final cancelQty = line.kitchenSentQty;
      if (cancelQty > 0 && _isTableOrderMode) {
        if (line.qty > 2) {
          await _showReturnGoodsDialog(line);
          return;
        }
        if (!await _confirmKitchenVoidPrintNow(
            productName: line.product.name, qty: cancelQty)) {
          return;
        }
        final voidReason = await _promptKitchenVoidReason();
        if (voidReason == null || !mounted) return;
        final ticket = KitchenTicketLine(
          productName: line.product.name,
          qty: cancelQty,
          unitName: line.unitLabel,
          note: line.noteWithToppings,
          productId: line.product.id,
        );
        setState(() {
          line.dispose();
          if (_expandedCartRowId == line.rowId) {
            _expandedCartRowId = null;
            _expandedCartMode = null;
          }
          _tab.cart.remove(line);
          _syncPaidAmount();
        });
        _scheduleDraftAutosave();
        await _voidKitchenSentLines([ticket], reasonResult: voidReason);
        return;
      }
      setState(() {
        line.dispose();
        if (_expandedCartRowId == line.rowId) {
          _expandedCartRowId = null;
          _expandedCartMode = null;
        }
        _tab.cart.remove(line);
        _syncPaidAmount();
      });
      _scheduleDraftAutosave();
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

    // Giảm SL vào phần đã báo bếp → xác nhận + in phiếu hủy ngay (không ghi đúp).
    if (delta < 0 && line.kitchenSentQty > next && _isTableOrderMode) {
      final cut = line.kitchenSentQty - next;
      if (cut > 0) {
        if (!await _confirmKitchenVoidPrintNow(
            productName: line.product.name, qty: cut)) {
          return;
        }
        final voidReason = await _promptKitchenVoidReason();
        if (voidReason == null || !mounted) return;
        final ticket = KitchenTicketLine(
          productName: line.product.name,
          qty: cut,
          unitName: line.unitLabel,
          note: line.noteWithToppings,
          productId: line.product.id,
        );
        setState(() {
          line.kitchenSentQty = next;
          line.qty = next;
          if (line.warehouseSlipPrintedQty > next) {
            line.warehouseSlipPrintedQty = next;
          }
          if (line.cupLabelPrintedQty > next) {
            line.cupLabelPrintedQty = next;
          }
          _syncPaidAmount();
        });
        // Đợi lưu kitchenSentQty trước — tránh báo bếp sau đó server vẫn alreadyAllSent.
        _draftAutosaveTimer?.cancel();
        await _persistDraftAutosave(
          forTab: _tab,
          showLockError: true,
          retryOnConflict: true,
        );
        if (!mounted) return;
        await _voidKitchenSentLines([ticket], reasonResult: voidReason);
        return;
      }
    }

    setState(() {
      line.qty = next;
      if (line.warehouseSlipPrintedQty > next) {
        line.warehouseSlipPrintedQty = next;
      }
      if (line.cupLabelPrintedQty > next) {
        line.cupLabelPrintedQty = next;
      }
      _syncPaidAmount();
    });
    if (_isTableOrderMode) {
      _markTabDirty(_tab);
      _draftAutosaveTimer?.cancel();
      await _persistDraftAutosave(
        forTab: _tab,
        showLockError: true,
        retryOnConflict: true,
      );
    } else {
      _scheduleDraftAutosave();
    }
  }

  Future<void> _switchUnit(_SellCartLine line, PosProductUnitView view) async {
    if (!await _ensureCanEditActiveDraft()) return;
    var views = await loadPosSellUnitViews(_api, line.product);
    if (!mounted) return;
    views = applyPosPriceListToViews(views, line.product, _currentPriceOverrides);
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
    _scheduleDraftAutosave();
  }

  Future<void> _applyLinePriceInput(_SellCartLine line, String raw) async {
    if (!await _ensureCanEditActiveDraft()) return;
    final price = _parseMoneyInput(raw);
    line.unitPrice = price.clamp(0, double.infinity);
    if (!line.discountIsPercent && line.discountInput > line.lineGross) {
      line.discountInput = 0;
      line.discountCtrl.text = '0';
    }
    _syncPaidAmount();
    // Chưa đồng bộ — xác nhận khi đóng editor / bấm Áp dụng.
  }

  void _applyOrderDiscountPreset(double percent, {VoidCallback? onMutate}) {
    if (!_guardReadOnlyEdit()) return;
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
    _scheduleDraftAutosave();
  }

  void _applyOrderDiscountAmountPreset(double amount, {VoidCallback? onMutate}) {
    if (!_guardReadOnlyEdit()) return;
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
    _scheduleDraftAutosave();
  }

  void _applyLineDiscountPreset(_SellCartLine line, double percent) {
    if (!_guardReadOnlyEdit()) return;
    setState(() {
      line.discountIsPercent = true;
      line.discountInput = percent;
      line.discountCtrl.text = percent % 1 == 0
          ? percent.toStringAsFixed(0)
          : percent.toStringAsFixed(2);
      _syncPaidAmount();
    });
    // Chưa đồng bộ — bấm Áp dụng / đóng editor mới lưu.
  }

  void _applyLineDiscountAmountPreset(_SellCartLine line, double amount) {
    if (!_guardReadOnlyEdit()) return;
    setState(() {
      line.discountIsPercent = false;
      final capped = amount.clamp(0, line.lineGross).toDouble();
      line.discountInput = capped;
      line.discountCtrl.text = _moneyFmt.format(capped);
      _syncPaidAmount();
    });
  }

  void _setLineDiscountMode(_SellCartLine line, bool isPercent) {
    if (!_guardReadOnlyEdit()) return;
    if (line.discountIsPercent == isPercent) return;
    setState(() {
      line.discountIsPercent = isPercent;
      line.discountInput = 0;
      line.discountCtrl.text = '0';
      _syncPaidAmount();
    });
  }

  void _onCustomerSearchChanged(String q) {
    _customerSearchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _customerSuggestions = []);
      return;
    }
    _customerSearchDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_searchCustomers(q));
    });
  }

  Future<void> _searchCustomers(String q) async {
    if (q.trim().length < 2) {
      if (mounted) setState(() => _customerSuggestions = []);
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
        message: tr('Giảm ${_moneyFmt.format(discount)} đ'),
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
          message: tr('Số lượng phải là số nguyên: ${line.product.name}'),
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

  Map<String, dynamic> _buildSaleBody({required bool complete}) =>
      _buildSaleBodyFor(_tab, complete: complete);

  Map<String, dynamic> _buildSaleBodyFor(
    _SellInvoiceTab tab, {
    required bool complete,
  }) {
    final paid = complete ? _effectivePaidAmountFor(tab) : 0.0;
    final paymentLines = complete
        ? tab.paymentLines.where((p) => p.amount > 0).toList()
        : <_SellPaymentLine>[];
    final started = tab.serviceStartedAt;
    return <String, dynamic>{
      'lines': tab.cart.map((c) {
        final line = <String, dynamic>{
          'productId': c.product.id,
          if (c.variantId != null) 'variantId': c.variantId,
          if (c.unitId != null) 'unitId': c.unitId,
          'qty': c.qty,
          'unitPrice': c.unitPrice,
          'discountAmount': c.discountAmount,
          'lineNote': c.lineNote,
          'kitchenSentQty': c.kitchenSentQty,
          if (c.toppings.isNotEmpty)
            'toppingsJson': jsonEncode(c.toppings
                .map((t) => {
                      'id': t.id,
                      'name': t.name,
                      'price': t.price,
                    })
                .toList()),
          if (c.serialNumbers.isNotEmpty) 'serialNumbers': c.serialNumbers,
          if (c.serialImeis.any((e) => e.trim().isNotEmpty))
            'serialImeis': c.serialImeis,
        };
        if (c.product.isTimedService && started != null) {
          final mode = PosServiceBillingMode.parse(c.product.serviceBillingMode);
          final elapsed = PosServiceBillingCalc.elapsedMinutes(
            started,
            complete ? DateTime.now().toUtc() : null,
            accumulatedPauseMinutes: tab.accumulatedPauseMinutes,
            pausedAt: tab.sessionIsPaused ? tab.sessionPausedAt : null,
          );
          final billable = PosServiceBillingCalc.billableMinutes(
            elapsed: elapsed,
            mode: mode,
            minBillMinutes: c.product.minBillMinutes,
            billRoundMinutes: c.product.billRoundMinutes,
            graceMinutes: c.product.graceMinutes,
            roundAfterMinutes: c.product.roundAfterMinutes,
          );
          line['durationMinutes'] = elapsed;
          line['billableMinutes'] = billable;
          line['serviceStartedAt'] = started.toUtc().toIso8601String();
          if (complete) {
            line['serviceEndedAt'] = DateTime.now().toUtc().toIso8601String();
          }
        }
        return line;
      }).toList(),
      'discount': tab.discount,
      'paidAmount': paid,
      if (complete) 'vatAmount': _vatAmount,
      'paymentMethod': paymentLines.isEmpty
          ? 'Tiền mặt'
          : paymentLines.length == 1
              ? _sourceByKey(paymentLines.first.sourceKey).methodLabel
              : paymentLines
                  .map((p) => _sourceByKey(p.sourceKey).methodLabel)
                  .join(' + '),
      'payments': paymentLines
          .map((p) {
            final src = _sourceByKey(p.sourceKey);
            return {
              'amount': p.amount,
              'paymentMethod': src.methodLabel,
              if (src.bankAccountId != null) 'bankAccountId': src.bankAccountId,
            };
          })
          .toList(),
      'complete': complete,
      'customerName': tab.customer?.name ?? 'Bán cho người tiêu dùng',
      if (tab.customer?.id != null) 'customerId': tab.customer!.id,
      'note': tab.note,
      // Đơn bàn (BAN*) không gắn InvoiceSlot — tránh đụng TMP01.. và sync đè giỏ.
      if (!tab.isTableBound) 'invoiceSlot': tab.invoiceSlot,
      if (_posDeviceId != null) 'deviceId': _posDeviceId,
      if (_posDeviceName != null) 'deviceName': _posDeviceName,
      if (tab.lockVersion >= 0) 'expectedLockVersion': tab.lockVersion,
      if (tab.priceListId != null) 'priceListId': tab.priceListId,
      if (tab.sellerEmployeeId != null) 'soldByEmployeeId': tab.sellerEmployeeId,
      if (tab.serviceResourceId != null)
        'serviceResourceId': tab.serviceResourceId,
      if (tab.resourceSessionId != null)
        'resourceSessionId': tab.resourceSessionId,
      if (tab.serviceStartedAt != null)
        'serviceStartedAt': tab.serviceStartedAt!.toUtc().toIso8601String(),
      if (complete && tab.serviceStartedAt != null)
        'serviceEndedAt': DateTime.now().toUtc().toIso8601String(),
      'isDelivery': identical(tab, _tab) && _sellMode == _SellMode.delivery,
      if (identical(tab, _tab) && _sellMode == _SellMode.delivery) ...{
        if (tab.deliveryAddress != null && tab.deliveryAddress!.isNotEmpty)
          'deliveryAddress': tab.deliveryAddress,
        if (tab.deliveryPhone != null && tab.deliveryPhone!.isNotEmpty)
          'deliveryPhone': tab.deliveryPhone,
        if (tab.deliveryPartner != null && tab.deliveryPartner!.isNotEmpty)
          'deliveryPartner': tab.deliveryPartner,
      },
      'salesChannel': identical(tab, _tab)
          ? (_sellMode == _SellMode.delivery
              ? 'Bán giao hàng'
              : _sellMode == _SellMode.normal
                  ? 'Bán thường'
                  : 'Bán nhanh')
          : 'Bán nhanh',
      if (tab.priceListLabel.isNotEmpty) 'priceListName': tab.priceListLabel,
      if (tab.voucherCode != null && tab.voucherCode!.isNotEmpty)
        'voucherCode': tab.voucherCode,
      if (tab.pointsToRedeem > 0) 'pointsToRedeem': tab.pointsToRedeem,
      if ((tab.sellerEmployeeId ?? _defaultSellerEmployeeId) != null)
        'soldByEmployeeId': tab.sellerEmployeeId ?? _defaultSellerEmployeeId,
    };
  }

  /// Lưu đơn tạm (Draft) để phục vụ nhiều khách chờ thanh toán.
  Future<bool> _parkCurrentOrder({bool openNewTabAfter = true}) async {
    if (_checkingOut || _parking || _tab.cart.isEmpty) return false;
    setState(() => _parking = true);
    try {
      if (!await _awaitDraftAutosaveIdle(
            busyMessage: 'Đợi lưu xong rồi giữ đơn lại')) {
        return false;
      }
      if (!await _ensureCanEditActiveDraft()) return false;
      if (!_ensureResourceIfRequired()) return false;

      await _ensureDeviceReady();
      _refreshTimedLineQtys();
      _recalcTotals();
      final body = _buildSaleBody(complete: false);
      final res = _tab.draftOrderId != null
          ? await _api.updatePosSale(_tab.draftOrderId!, body)
          : await _api.createPosSale(body);
      if (!mounted) return false;

      if (res['isSuccess'] != true) {
        if (_isLockConflict(res)) {
          await _handleMutationLockConflict(res, title: 'Không giữ được đơn');
        } else {
          NotificationOverlayManager().showError(
            title: 'Không giữ được đơn',
            message: res['message']?.toString() ?? 'Lưu đơn tạm thất bại',
          );
        }
        return false;
      }

      final data = res['data'] as Map<String, dynamic>?;
      final orderId = data?['id']?.toString();
      final orderNo = data?['orderNo']?.toString() ?? '';
      if (orderId != null && orderId.isNotEmpty) {
        _tab.draftOrderId = orderId;
        _tab.draftOrderNo = orderNo.isNotEmpty ? orderNo : _tab.draftOrderNo;
      }
      _applyLockMetaFromMap(data);
      _restartDraftLockHeartbeat();

      // Silent — giữ đơn thành công không cần toast che POS.
      debugPrint('POS hold OK: $orderNo');

      if (openNewTabAfter) {
        await _newTabAsync(parkCurrentIfNeeded: false);
      } else {
        setState(() {});
      }
      return true;
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Không giữ được đơn',
          message: tr('Kiểm tra kết nối rồi thử lại'),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _parking = false);
    }
  }

  Future<void> _checkout() async {
    if (_checkingOut || _parking || _tab.cart.isEmpty) return;
    // Khóa UI ngay — trước mọi await — tránh double-tap tạo 2 request chồng.
    setState(() => _checkingOut = true);
    final paidSessionId = _tab.resourceSessionId;
    try {
      final perm = Provider.of<PermissionProvider>(context, listen: false);
      if (!perm.canPosPay()) {
        NotificationOverlayManager().showWarning(
          title: 'Không có quyền thanh toán',
          message: tr(
              'Tài khoản Order chỉ tạm tính — cần tài khoản Thu ngân để thanh toán'),
        );
        return;
      }

      if (!await _awaitDraftAutosaveIdle(
            busyMessage: 'Đợi lưu xong rồi thanh toán lại')) {
        return;
      }

      if (!await _ensureCanEditActiveDraft()) return;
      if (!_ensureResourceIfRequired()) return;

      final paid = _effectivePaidAmount;
      final due = (_grandTotal - paid).clamp(0, double.infinity);
      if (due > 0 && _tab.customer == null) {
        NotificationOverlayManager().showError(
          title: 'Thiếu khách hàng',
          message: tr(
              'Chọn khách hàng để ghi nợ phần còn thiếu (${_moneyFmt.format(due)})'),
        );
        return;
      }

      if (!await _refreshCartStockBeforeCheckout()) return;
      if (!_validateFullCartStock()) return;

      await _ensureDeviceReady();
      if (!await _collectSerialsBeforeCheckout()) return;

      _refreshTimedLineQtys();
      final body = _buildSaleBody(complete: true);

      Future<Map<String, dynamic>> payOnce() => _tab.draftOrderId != null
          ? _api.updatePosSale(_tab.draftOrderId!, body)
          : _api.createPosSale(body);

      var res = await payOnce();
      // 409 xung đột serialization/mã phiếu — thử lại 1 lần (server cũng đã retry).
      if (res['isSuccess'] != true && _isRetryableCheckoutConflict(res)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        final retryBody = _buildSaleBody(complete: true);
        res = _tab.draftOrderId != null
            ? await _api.updatePosSale(_tab.draftOrderId!, retryBody)
            : await _api.createPosSale(retryBody);
      }
      if (!mounted) return;

      if (res['isSuccess'] != true) {
        if (_isLockConflict(res)) {
          await _handleMutationLockConflict(res, title: 'Không thanh toán được');
        } else {
          NotificationOverlayManager().showError(
            title: 'Lỗi',
            message: res['message']?.toString() ?? 'Thanh toán thất bại',
          );
        }
        return;
      }

      final data = res['data'] as Map<String, dynamic>?;
      final orderId = data?['id']?.toString();
      final orderNo = data?['orderNo']?.toString() ?? '';

      // Happy-path silent — tránh chồng toast che màn bán hàng (in/kho báo riêng khi lỗi).
      debugPrint('POS checkout OK: $orderNo');

      final soldLines = _cartStockLinesFromCart();
      final alreadySentToWarehouse = _warehouseAlreadyPrintedMap();
      // Giữ tên khu/bàn trước khi reset tab — phiếu TT cần in đúng.
      final printAreaName = _tab.serviceAreaName;
      final printTableName = _tab.serviceResourceName;
      final printResourceId = _tab.serviceResourceId;
      final cupLabelLines = _quickPrintCup
          ? List<_SellCartLine>.from(
              _tab.cart.where((l) => l.cupLabelPendingQty > 0))
          : const <_SellCartLine>[];
      final cupTableLabel = formatPosTableLabel(
        areaName: printAreaName,
        tableName: printTableName,
      );
      final cupOrderNo = orderNo.isNotEmpty ? orderNo : _tab.draftOrderNo;
      final paidSlot = _tab.invoiceSlot;
      final paidResourceId = _tab.serviceResourceId?.toLowerCase();
      final useFloor = _useFloorAsPrimary;
      final wantInvoicePrint = _quickPrintInvoice;
      final warehouseAuto =
          _printSettings.warehousePrintMode == PosWarehousePrintMode.auto;

      // Đóng phiên + in nền — không chặn UI sau khi API TT thành công.
      if (paidSessionId != null && paidSessionId.isNotEmpty) {
        unawaited(() async {
          try {
            await _api.closePosResourceSession(paidSessionId);
          } catch (_) {}
        }());
      }

      if (cupLabelLines.isNotEmpty) {
        unawaited(_printCupLabelsForLines(
          cupLabelLines,
          tableLabelOverride: cupTableLabel,
          orderNoOverride: cupOrderNo,
          showFeedback: false,
        ));
      }

      _stopDraftLockHeartbeat();
      setState(() {
        _tab.reset(defaultVatRate: _storeSettings.defaultVatRate);
        _tab.sellerEmployeeId = _defaultSellerEmployeeId;
        _syncPaidAmount();
        if (paidResourceId != null && paidResourceId.isNotEmpty) {
          _billRequestedResourceIds = {
            for (final e in _billRequestedResourceIds)
              if (e.toLowerCase() != paidResourceId) e,
          };
          _kitchenClearedResourceIds = {
            ..._kitchenClearedResourceIds,
            paidResourceId,
          };
        }
        if (useFloor) {
          _floorMapVisible = true;
          _tabletPaymentStage = false;
          // Không bump epoch — tránh remount sơ đồ chậm; poll/flags đủ cập nhật Free.
        }
      });
      _scheduleCustomerDisplayPublish();
      // Patch qua notifier + cache catalog (không chỉ GlobalKey — F&B/tablet
      // dispose lưới khi về sơ đồ / màn TT nên currentState thường null).
      ScreenRefreshNotifier.refreshPosAfterStockChange(
        sellStockLines: soldLines,
        reloadSellCatalog: false,
        storeId: _storeId,
      );

      // Slot TMP: nạp nền. F&B về sơ đồ — không chặn.
      if (!useFloor) {
        unawaited(() async {
          await _reloadInvoiceSlot(paidSlot);
          if (mounted) _restartDraftLockHeartbeat();
        }());
      } else {
        _restartDraftLockHeartbeat();
      }

      if (orderId != null && wantInvoicePrint) {
        final enriched = data == null
            ? null
            : <String, dynamic>{
                ...Map<String, dynamic>.from(data),
                if ((printAreaName ?? '').isNotEmpty)
                  'serviceAreaName': printAreaName,
                if ((printTableName ?? '').isNotEmpty)
                  'serviceResourceName': printTableName,
                if ((printResourceId ?? '').isNotEmpty)
                  'serviceResourceId': printResourceId,
              };
        unawaited(_maybePrintOrder(
          orderId,
          orderJson: enriched ?? data,
          areaNameOverride: printAreaName,
          tableNameOverride: printTableName,
        ));
      }
      if (orderId != null && warehouseAuto) {
        unawaited(_maybePrintWarehouseSlip(
          orderId,
          alreadyPrinted: alreadySentToWarehouse,
          orderJson: data,
        ));
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: tr('Thanh toán thất bại. Kiểm tra đơn hàng trước khi thử lại.'),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  /// Quy đổi SL bán → ĐVT cơ bản (khớp server QtyInBase) để patch tồn lưới đúng.
  /// Biến thể unit-only: để nguyên — `applyPosSellStockLine` tự nhân `_conversion`.
  double _cartLineQtyInBase(_SellCartLine l) {
    if (l.variantId != null && l.variantId!.isNotEmpty) {
      return l.qty;
    }
    final unitId = l.unitId;
    if (unitId != null && unitId.isNotEmpty) {
      final u = l.product.units?.where((x) => x.id == unitId).firstOrNull;
      if (u != null) {
        final rate = u.conversionRate > 0 ? u.conversionRate : 1;
        return l.qty * rate;
      }
    }
    return l.qty;
  }

  List<PosSellStockLineDelta> _cartStockLinesFromCart() {
    final raw = <PosSellStockLineDelta>[];
    for (final l in _tab.cart) {
      if (l.product.productType == PosProductType.service) continue;
      final baseQty = _cartLineQtyInBase(l);
      if (l.product.productType == PosProductType.combo) {
        for (final cl in l.product.comboLines ?? const <PosComboLine>[]) {
          raw.add(
            PosSellStockLineDelta(
              productId: cl.componentProductId,
              qty: cl.qty * baseQty,
            ),
          );
        }
        continue;
      }
      raw.add(
        PosSellStockLineDelta(
          productId: l.product.id,
          variantId: l.variantId,
          qty: baseQty,
        ),
      );
      for (final t in l.toppings) {
        raw.add(PosSellStockLineDelta(productId: t.id, qty: l.qty));
      }
    }
    return mergeStockLineDeltas(raw);
  }

  void _syncCartStockFromPatch() {
    final lines = ScreenRefreshNotifier.posSellStockPatch.value;
    if (lines == null || lines.isEmpty || !mounted) return;
    setState(() {
      for (final line in _tab.cart) {
        line.product = applyPosSellStockLines(line.product, lines);
        line.unitViews = applyPosPriceListToViews(
          buildPosSellUnitViewsFromProduct(line.product),
          line.product,
          _currentPriceOverrides,
        );
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
      while (_failedWarehousePrints.length > PosPendingPrintStore.maxJobsPerKind) {
        _failedWarehousePrints.removeLast();
      }
    });
    unawaited(_persistPendingPrintQueue());
  }

  void _removeFailedWarehouseJob(PendingWarehousePrintJob job) {
    setState(() => _failedWarehousePrints.removeWhere((j) => j.id == job.id));
    unawaited(_persistPendingPrintQueue());
  }

  void _clearFailedWarehouseJobsForTab(int tabId) {
    setState(
      () => _failedWarehousePrints.removeWhere((j) => j.tabId == tabId),
    );
    unawaited(_persistPendingPrintQueue());
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
      // Success silent — không toast "Đã gửi kho" chồng lên màn bán hàng.
      debugPrint('Warehouse print OK: $successTitle');
      return;
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
        message: tr('Kiểm tra máy in, Print Agent hoặc gán SP → máy in kho'),
      );
    }
  }

  String? get _warehouseBranchName =>
      _storeSettings.storeName.isNotEmpty ? _storeSettings.storeName : null;

  String? get _warehouseStoreAddress =>
      _storeSettings.address.isNotEmpty ? _storeSettings.address : null;

  String? get _warehouseStorePhone =>
      _storeSettings.phone.isNotEmpty ? _storeSettings.phone : null;

  void _enqueueFailedSalePrint(PosSaleOrder order, {String? errorMessage}) {
    if (order.id.isEmpty) return;
    final job = PendingSalePrintJob(order: order, errorMessage: errorMessage);
    setState(() {
      _failedSalePrints.removeWhere((j) => j.id == job.id);
      _failedSalePrints.insert(0, job);
      while (_failedSalePrints.length > PosPendingPrintStore.maxJobsPerKind) {
        _failedSalePrints.removeLast();
      }
    });
    unawaited(_persistPendingPrintQueue());
  }

  void _removeFailedSalePrint(PendingSalePrintJob job) {
    setState(() => _failedSalePrints.removeWhere((j) => j.id == job.id));
    unawaited(_persistPendingPrintQueue());
  }

  void _enqueueFailedKitchenPrint(PendingKitchenPrintJob job) {
    setState(() {
      _failedKitchenPrints.removeWhere((j) => j.id == job.id);
      _failedKitchenPrints.insert(0, job);
      while (_failedKitchenPrints.length > PosPendingPrintStore.maxJobsPerKind) {
        _failedKitchenPrints.removeLast();
      }
    });
    unawaited(_persistPendingPrintQueue());
  }

  void _removeFailedKitchenPrint(PendingKitchenPrintJob job) {
    setState(() => _failedKitchenPrints.removeWhere((j) => j.id == job.id));
    unawaited(_persistPendingPrintQueue());
  }

  void _enqueueFailedCupPrint(PendingCupLabelPrintJob job) {
    setState(() {
      _failedCupPrints.removeWhere((j) => j.id == job.id);
      _failedCupPrints.insert(0, job);
      while (_failedCupPrints.length > PosPendingPrintStore.maxJobsPerKind) {
        _failedCupPrints.removeLast();
      }
    });
    unawaited(_persistPendingPrintQueue());
  }

  void _removeFailedCupPrint(PendingCupLabelPrintJob job) {
    setState(() => _failedCupPrints.removeWhere((j) => j.id == job.id));
    unawaited(_persistPendingPrintQueue());
  }

  Future<void> _loadPendingPrintQueueFromDisk() async {
    final snap = await PosPendingPrintStore.load();
    if (!mounted || snap.isEmpty) return;
    // Phiếu bếp / HĐ trong hàng chờ thường đã in thật (Agent nhận rồi client
    // ghi fail) — mở lại app sẽ auto-retry và in trùng. Chỉ giữ job còn mới.
    final kitchenFresh = PosPendingPrintStore.filterFreshKitchenJobs(snap.kitchen);
    final salesFresh = PosPendingPrintStore.filterFreshSaleJobs(snap.sales);
    setState(() {
      _failedWarehousePrints
        ..clear()
        ..addAll(snap.warehouse);
      _failedSalePrints
        ..clear()
        ..addAll(salesFresh);
      _failedKitchenPrints
        ..clear()
        ..addAll(kitchenFresh);
      _failedCupPrints
        ..clear()
        ..addAll(snap.cups);
    });
    // Ghi lại ngay để máy cũ sau khi cập nhật không còn queue độc.
    if (kitchenFresh.length != snap.kitchen.length ||
        salesFresh.length != snap.sales.length) {
      unawaited(_persistPendingPrintQueue());
    }
  }

  Future<void> _persistPendingPrintQueue() async {
    await PosPendingPrintStore.save(PosPendingPrintSnapshot(
      warehouse: List.unmodifiable(_failedWarehousePrints),
      sales: List.unmodifiable(_failedSalePrints),
      kitchen: List.unmodifiable(_failedKitchenPrints),
      cups: List.unmodifiable(_failedCupPrints),
    ));
  }

  void _startPendingPrintAutoRetry() {
    _pendingPrintRetryTimer?.cancel();
    _pendingPrintRetryTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_autoRetryPendingPrints()),
    );
  }

  Future<void> _autoRetryPendingPrints() async {
    if (!mounted || _pendingPrintRetryBusy || _pendingPrintCount == 0) return;
    if (_checkingOut || _warehousePrinting) return;
    _pendingPrintRetryBusy = true;
    try {
      // KHÔNG auto-retry hóa đơn / phiếu bếp: false-fail (Agent đã in) + skipDedup
      // khiến in lại liên tục («Lần in thứ 5»). In lại chỉ bằng tay từ biểu tượng treo.
      if (_failedCupPrints.isNotEmpty) {
        final job = _failedCupPrints.first;
        if (job.attemptCount >= 8) {
          // Tem lỗi quá nhiều — bỏ khỏi queue để không chặn retry phiếu kho.
          _removeFailedCupPrint(job);
        } else {
          final ok = await printCupLabels(
            tickets: job.tickets,
            showFeedback: false,
          );
          if (!mounted) return;
          if (ok) {
            _removeFailedCupPrint(job);
          } else {
            setState(() {
              final i = _failedCupPrints.indexWhere((j) => j.id == job.id);
              if (i >= 0) {
                _failedCupPrints[i] =
                    job.copyWith(attemptCount: job.attemptCount + 1);
              }
            });
            unawaited(_persistPendingPrintQueue());
          }
          return;
        }
      }
      if (_failedWarehousePrints.isNotEmpty) {
        final job = _failedWarehousePrints.first;
        final method = (job.printerId != null && job.printerId!.isNotEmpty)
            ? WarehouseSlipPrintMethod.pickPrinter
            : WarehouseSlipPrintMethod.localThermal;
        final result = await printWarehouseSlipWithMethod(
          context: context,
          order: job.order,
          method: method,
          branchName: _warehouseBranchName,
          storeAddress: _warehouseStoreAddress,
          storePhone: _warehouseStorePhone,
          templateId: _printSettings.warehouseTemplateId,
          overridePrinterId: job.printerId,
        );
        if (!mounted) return;
        if (result.anySuccess) {
          _markWarehouseSlipPrintedLines(result.printedLines);
          // Luôn gỡ job cũ — phần còn lỗi enqueue lại (tránh in chồng dòng đã OK).
          _removeFailedWarehouseJob(job);
          if (result.hasFailures) {
            _enqueueFailedWarehousePrints(result, job.order);
          }
        }
      }
    } finally {
      _pendingPrintRetryBusy = false;
    }
  }

  int get _pendingPrintCount =>
      _failedWarehousePrints.length +
      _failedSalePrints.length +
      _failedKitchenPrints.length +
      _failedCupPrints.length;

  Future<void> _openPendingPrintQueue() async {
    if (_pendingPrintCount == 0) {
      NotificationOverlayManager().showInfo(
        title: 'Không có phiếu treo',
        message: tr('Tất cả phiếu in đã thành công'),
      );
      return;
    }
    await showPendingWarehousePrintSheet(
      context: context,
      jobs: List.unmodifiable(_failedWarehousePrints),
      saleJobs: List.unmodifiable(_failedSalePrints),
      kitchenJobs: List.unmodifiable(_failedKitchenPrints),
      cupJobs: List.unmodifiable(_failedCupPrints),
      printers: PosPrintOrchestrator.instance.printers,
      onDismiss: _removeFailedWarehouseJob,
      onDismissSale: _removeFailedSalePrint,
      onDismissKitchen: _removeFailedKitchenPrint,
      onDismissCup: _removeFailedCupPrint,
      onDismissAll: () {
        setState(() {
          _failedWarehousePrints.clear();
          _failedSalePrints.clear();
          _failedKitchenPrints.clear();
          _failedCupPrints.clear();
        });
        unawaited(_persistPendingPrintQueue());
      },
      onRetrySale: (job) async {
        return printPosSaleOrder(
          context: context,
          order: job.order,
          branchName: _warehouseBranchName,
          storeAddress: _warehouseStoreAddress,
          storePhone: _warehouseStorePhone,
          mergeSameItems: _printSettings.mergeSameItems,
          copies: _printSettings.copies,
          templateId: _printSettings.templateId,
          vietQrImageUrl: _buildVietQrImageUrlForOrder(job.order),
          skipDedup: true,
          preferDevicePrintOnly: true,
          showFeedback: true,
        );
      },
      onRetryKitchen: (job) async {
        return printKitchenCompactSlip(
          tableName: job.tableName,
          isCancel: job.isCancel,
          lines: job.lines,
          senderName: job.senderName,
          orderNo: job.orderNo,
          sentAt: job.sentAt,
          skipDedup: true,
        );
      },
      onRetryCup: (job) async {
        return printCupLabels(tickets: job.tickets, showFeedback: true);
      },
      onRetry: (job, method, {overridePrinterId}) async {
        // Dùng root navigator — tránh dialog/HTML gắn nhầm context sheet.
        final rootCtx = Navigator.of(context, rootNavigator: true).context;
        final result = await printWarehouseSlipWithMethod(
          context: rootCtx,
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
          // Gỡ job cũ rồi enqueue phần còn lỗi — tránh badge/sheet lệch + in chồng.
          _removeFailedWarehouseJob(job);
          if (result.hasFailures) {
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
    String? slipTitleOverride,
    Map<String, dynamic>? orderJson,
  }) async {
    if (orderId.isEmpty) return;
    Map<String, dynamic>? data = orderJson;
    if (data == null ||
        ((data['lines'] ?? data['Lines']) is! List) ||
        ((data['lines'] ?? data['Lines']) as List).isEmpty) {
      final res = await _api.getPosSale(orderId);
      if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
      data = Map<String, dynamic>.from(res['data'] as Map);
    }
    if (!mounted || data == null) return;
    var order = PosSaleOrder.fromJson(data);
    order = filterWarehouseSlipOrder(order, alreadyPrinted);
    if (order.lines.isEmpty) return;

    final result = await printWarehouseSlipForOrder(
      order: order,
      branchName: _warehouseBranchName,
      storeAddress: _warehouseStoreAddress,
      storePhone: _warehouseStorePhone,
      templateId: _printSettings.warehouseTemplateId,
      slipTitleOverride: slipTitleOverride,
    );
    if (!mounted) return;
    _applyWarehousePrintResult(
      result: result,
      order: order,
      lineCount: order.lines.length,
      successTitle: slipTitleOverride ?? 'Đã gửi kho',
    );
  }

  Future<void> _maybePrintOrder(
    String orderId, {
    Map<String, dynamic>? orderJson,
    String? areaNameOverride,
    String? tableNameOverride,
  }) async {
    if (orderId.isEmpty || _checkoutPrintGuard.contains(orderId)) return;
    _checkoutPrintGuard.add(orderId);
    PosSaleOrder? order;
    try {
      Map<String, dynamic>? data = orderJson;
      if (data == null ||
          ((data['lines'] ?? data['Lines']) is! List) ||
          ((data['lines'] ?? data['Lines']) as List).isEmpty) {
        final res = await _api.getPosSale(orderId);
        if (res['isSuccess'] == true && res['data'] is Map) {
          data = Map<String, dynamic>.from(res['data'] as Map);
        }
      }
      if (!mounted || data == null) {
        if (mounted) {
          NotificationOverlayManager().showError(
            title: 'Không in được hóa đơn',
            message: tr('Không tải được đơn vừa bán. Thử in lại từ danh sách đơn.'),
          );
        }
        return;
      }
      final merged = Map<String, dynamic>.from(data);
      final apiArea =
          (merged['serviceAreaName'] ?? merged['ServiceAreaName'])?.toString();
      final apiTable = (merged['serviceResourceName'] ??
              merged['ServiceResourceName'] ??
              merged['serviceResourceCode'] ??
              merged['ServiceResourceCode'])
          ?.toString();
      if ((areaNameOverride ?? '').isNotEmpty &&
          (apiArea == null || apiArea.isEmpty)) {
        merged['serviceAreaName'] = areaNameOverride;
      }
      if ((tableNameOverride ?? '').isNotEmpty &&
          (apiTable == null || apiTable.isEmpty)) {
        merged['serviceResourceName'] = tableNameOverride;
      }
      // Fallback tab (nếu chưa reset) khi API thiếu tên.
      if ((merged['serviceAreaName'] ?? '').toString().isEmpty &&
          (_tab.serviceAreaName ?? '').isNotEmpty) {
        merged['serviceAreaName'] = _tab.serviceAreaName;
      }
      if ((merged['serviceResourceName'] ?? '').toString().isEmpty &&
          (_tab.serviceResourceName ?? '').isNotEmpty) {
        merged['serviceResourceName'] = _tab.serviceResourceName;
      }
      order = PosSaleOrder.fromJson(merged);
      final ok = await printPosSaleOrder(
        context: context,
        order: order,
        branchName: _storeSettings.storeName.isNotEmpty ? _storeSettings.storeName : null,
        storeAddress: _storeSettings.address.isNotEmpty ? _storeSettings.address : null,
        storePhone: _storeSettings.phone.isNotEmpty ? _storeSettings.phone : null,
        mergeSameItems: _printSettings.mergeSameItems,
        copies: _printSettings.copies,
        templateId: _printSettings.templateId,
        vietQrImageUrl: _buildVietQrImageUrlForOrder(order),
        skipDedup: true,
        preferDevicePrintOnly: true,
        showFeedback: false,
      );
      if (!ok && mounted) {
        _enqueueFailedSalePrint(
          order,
          errorMessage: 'In sau thanh toán thất bại',
        );
        NotificationOverlayManager().showWarning(
          title: 'Hóa đơn chưa in',
          message: tr('Đã lưu vào hàng đợi — bấm biểu tượng máy in để in lại'),
        );
      }
    } catch (e) {
      debugPrint('Auto-print after checkout failed: $e');
      if (mounted) {
        if (order != null) {
          _enqueueFailedSalePrint(
            order!,
            errorMessage: 'Lỗi in sau thanh toán',
          );
        }
        NotificationOverlayManager().showError(
          title: 'Không in được hóa đơn',
          message: order != null
              ? 'Đã lưu vào hàng đợi — bấm biểu tượng máy in để in lại'
              : 'Lỗi in sau thanh toán. Thử in lại từ đơn hàng.',
        );
      }
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
          _applyPrintSettings(result.$1);
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
      setState(() => _applyPrintSettings(updated));
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
            label: Text(tr('Phóng to mã QR')),
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
    final canReturn = PermissionNavigation.canNavigate(perm, 'PosSaleReturns');
    final canEod = PermissionNavigation.canNavigate(perm, 'PosSalesReport');
    final canPosSettings = PermissionNavigation.canNavigate(perm, 'PosSell') ||
        PermissionNavigation.canNavigate(perm, 'PosProducts') ||
        PermissionNavigation.canNavigate(perm, 'SettingsHub');
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
      position: RelativeRect.fromLTRB(
          topRight.dx - 240, topRight.dy, topRight.dx, topRight.dy + 8),
      items: [
        PopupMenuItem(
          value: 'add_product',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.add_box_outlined, size: 20),
            title: Text(tr('Thêm hàng hóa mới')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (_useFloorAsPrimary) ...[
          PopupMenuItem(
            value: 'fullscreen',
            child: ListTile(
              dense: true,
              leading: Icon(
                _isPosFullscreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen,
                size: 20,
              ),
              title: Text(tr(_isPosFullscreen
                  ? 'Thoát toàn màn hình'
                  : 'Phóng toàn màn hình')),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (_printSettings.showCupLabelManualButton)
            PopupMenuItem(
              value: 'cup_label',
              enabled: _cupLabelPendingCount > 0,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.sticky_note_2_outlined, size: 20),
                title: Text(tr(_cupLabelPendingCount > 0
                    ? 'In tem ly ($_cupLabelPendingCount)'
                    : 'In tem ly')),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          const PopupMenuDivider(),
        ],
        if (isMobile)
          PopupMenuItem(
            value: 'toggle_merge',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.merge_type_outlined, size: 20),
              title: Text(tr('Tự động gộp cùng sản phẩm')),
              trailing: Icon(
                _mobileMergeSameOnAdd
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                size: 20,
                color: _mobileMergeSameOnAdd
                    ? _kiotBlue
                    : PosTheme.textSecondary,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canPosSettings)
          PopupMenuItem(
            value: 'pos_settings_hub',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.settings_outlined, size: 20),
              title: Text(tr('Thiết lập POS')),
              subtitle: Text(tr('Cửa hàng, máy in, ngành hàng…'),
                  style: TextStyle(fontSize: 11)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: 'print_settings',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.print_outlined, size: 20),
            title: Text(tr('Thiết lập in')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (_hasSecondaryCustomerDisplay || kIsWeb)
          PopupMenuItem(
            value: 'customer_display',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.tv_outlined, size: 20),
              title: Text(tr('Mở màn hình phụ (khách)')),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: 'sale_orders',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.receipt_long_outlined, size: 20),
            title: Text(tr('Đơn hàng')),
            subtitle: Text(tr('Danh sách hóa đơn bán'),
                style: TextStyle(fontSize: 11)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (_showFloorPlan)
          PopupMenuItem(
            value: 'floor_plan',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.table_restaurant_outlined, size: 20),
              title: Text(tr('Sơ đồ bàn / phòng')),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (_industrySettings?.enableSessionPacks == true)
          PopupMenuItem(
            value: 'session_redeem',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.confirmation_number_outlined, size: 20),
              title: Text(tr('Trừ buổi gói')),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canEod)
          PopupMenuItem(
            value: 'eod',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.summarize_outlined, size: 20),
              title: Text(tr('Cuối ngày')),
              subtitle: Text(tr('Kết ca / cuối ngày'),
                  style: TextStyle(fontSize: 11)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canReturn)
          PopupMenuItem(
            value: 'return',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.keyboard_return, size: 20),
              title: Text(tr('Trả hàng')),
              subtitle: Text(tr('Danh sách / chọn hóa đơn'),
                  style: TextStyle(fontSize: 11)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canCash)
          PopupMenuItem(
            value: 'receipt',
            child: ListTile(
              dense: true,
              leading:
                  Icon(Icons.call_received, size: 20, color: Colors.green),
              title: Text(tr('Lập phiếu thu')),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canCash)
          PopupMenuItem(
            value: 'payment',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.call_made, size: 20, color: Colors.red),
              title: Text(tr('Lập phiếu chi')),
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
                tr(accountName.isNotEmpty ? accountName[0].toUpperCase() : 'S'),
                style: const TextStyle(
                  color: PosTheme.kiotBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              tr(accountName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: accountSubtitle != null && accountSubtitle.isNotEmpty
                ? Text(
                    tr(accountSubtitle),
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
            title: Text(tr('Đăng xuất'),
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
      case 'add_product':
        await _openNewProduct();
      case 'fullscreen':
        await _togglePosFullscreen();
      case 'cup_label':
        if (_cupLabelPendingCount > 0) {
          await _printPendingCupLabels();
        }
      case 'toggle_merge':
        setState(() => _mobileMergeSameOnAdd = !_mobileMergeSameOnAdd);
      case 'pos_settings_hub':
        SettingsHubScreen.pendingSubIndex.value = null;
        if (NavigationNotifier.mainLayoutReady.value) {
          NavigationNotifier.navigateToModule.value = 'SettingsHub';
        } else if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsHubScreen()),
          );
        }
      case 'print_settings':
        await _openPrintSettings();
      case 'customer_display':
        await _openCustomerDisplay();
      case 'sale_orders':
        await _openSaleOrdersFromFloor();
      case 'floor_plan':
        await _openResourceFloor();
      case 'session_redeem':
        await _openSessionRedeem();
      case 'eod':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PosEndOfDayScreen()),
        );
      case 'return':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PosSaleReturnListScreen()),
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
    // Chưa load quyền → spinner (không khóa màn xám «không có quyền»).
    if (!perm.isLoaded && perm.isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _kiotBlue),
              const SizedBox(height: 12),
              Text(
                tr('Đang tải quyền…'),
                style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    final canSell = perm.canView('PosSell') || perm.canView('PosProducts');
    if (!canSell) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('Bạn không có quyền truy cập màn hình bán hàng'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: PosTheme.textPrimary),
            ),
          ),
        ),
      );
    }

    if (!_sellReady) {
      return Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _kiotBlue),
              SizedBox(height: 12),
              Text(tr('Đang tải bán hàng…'),
                style: TextStyle(fontSize: 13, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    // F&B mobile: sơ đồ + thanh gọn (Home · In treo · menu).
    if (_useFloorAsPrimary &&
        _floorMapVisible &&
        Responsive.isMobile(context)) {
      return Scaffold(
        backgroundColor: PosTheme.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFloorOpsTopBar(),
              Expanded(
                child: PosResourceFloorScreen(
                  key: ValueKey('floor-$_floorMapEpoch'),
                  embedded: true,
                  showAppBar: false,
                  manageMode: false,
                  sellProfile: _industrySettings?.sellProfile,
                  promptGuestCountOnOpen:
                      _industrySettings?.promptGuestCountOnOpen == true,
                  allowProvisionalBill:
                      _industrySettings?.allowProvisionalBill != false,
                  searchQuery: _floorSearchQuery,
                  pendingOpenCode: _floorPendingOpenCode,
                  pendingOpenToken: _floorPendingOpenToken,
                  onSelect: (result) => unawaited(_attachFloorResult(result)),
                  onResourceFreed: _onFloorResourceFreed,
                  onActiveTotalsChanged: _onFloorActiveTotalsChanged,
                  zeroPendingKitchenResourceIds: _kitchenClearedResourceIds,
                  billRequestedResourceIds: _billRequestedResourceIds,
                  releasedOrderIds: Set<String>.from(_floorReleasedOrderIds),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PosBarcodeKeyboardScope(
      enabled: !_checkingOut,
      ignoreFocusNodes: [_customerSearchFocus],
      onBarcode: _onBarcodeScanned,
      child: Scaffold(
      backgroundColor: PosTheme.background,
      body: Builder(
        builder: (context) {
          final body = LayoutBuilder(
            builder: (context, constraints) {
            final w = constraints.maxWidth;
            final wide = w >= Responsive.tabletBreakpoint;
            final isTabletBand = w >= Responsive.mobileBreakpoint && !wide;
            final isMobile = Responsive.isMobile(context);
            final isNormal = _sellMode == _SellMode.normal;
            final perm = context.watch<PermissionProvider>();

            if (isMobile && !wide) {
              return _buildMobileShell(perm, isNormal);
            }

            // F&B tablet+ (≥768): sơ đồ | thực đơn + giỏ → thanh toán stage.
            if (_useFloorAsPrimary &&
                w >= Responsive.tabletLandscapeFlowBreakpoint) {
              return _buildTabletFnbFlow(perm);
            }

            // Desktop / tablet bán lẻ (không sơ đồ): 2–3 cột.
            if (wide || isTabletBand) {
              final left = _buildDesktopProductPane();
              final Widget center;
              final Widget? right;
              if (isNormal) {
                // Bán thường: tách giỏ | thanh toán khi đủ rộng.
                if (wide) {
                  center = _buildDesktopCartColumn();
                  right = _buildPaymentSidebar(
                    perm,
                    width: double.infinity,
                  );
                } else {
                  center = _buildNormalOrderPanel(perm, compact: true);
                  right = null;
                }
              } else {
                // Quick / delivery: giỏ | pay.
                center = _buildCartPanel(showFooterTotal: false);
                right = wide
                    ? _buildPaymentSidebar(perm, width: double.infinity)
                    : null;
                if (!wide) {
                  return Column(
                    children: [
                      _buildTopBar(desktopChrome: true),
                      _buildExpiryLotBanner(),
                      Expanded(child: left),
                      SizedBox(
                        height: 320,
                        child: _buildPaymentSidebar(
                          perm,
                          width: w,
                          compact: true,
                        ),
                      ),
                      _buildBottomBar(),
                    ],
                  );
                }
              }

              return PosSellDesktopLayout(
                topBar: _buildTopBar(desktopChrome: true),
                banner: _buildExpiryLotBanner(),
                bottomBar: _buildBottomBar(),
                leftPane: left,
                centerPane: center,
                rightPane: right,
                combineOrderAndPay: right == null,
              );
            }

            // Fallback hẹp: stacked như trước.
            return Column(
              children: [
                _buildTopBar(),
                _buildExpiryLotBanner(),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        flex: isNormal ? 5 : 3,
                        child: isNormal
                            ? _buildDesktopProductPane()
                            : _buildCartPanel(showFooterTotal: false),
                      ),
                      if (isNormal)
                        SizedBox(
                          height: 360,
                          child:
                              _buildNormalOrderPanel(perm, compact: true),
                        )
                      else
                        _buildPaymentSidebar(
                          perm,
                          width: w,
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

  /// Tab Phòng bàn | Thực đơn — kiểu KiotViet (F&B).
  Widget _buildFloorMenuModeTabs({bool compact = false}) {
    if (!_useFloorAsPrimary) return const SizedBox.shrink();
    final onFloor = _floorMapVisible;
    Widget tab({
      required bool selected,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? PosTheme.kiotBlue : Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  tr(label),
                  style: TextStyle(
                    color: selected ? PosTheme.kiotBlue : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 13 : 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab(
            selected: onFloor,
            icon: Icons.table_restaurant_outlined,
            label: 'Phòng bàn',
            onTap: () {
              if (onFloor) return;
              setState(() {
                _floorMapVisible = true;
                _tabletPaymentStage = false;
              });
            },
          ),
          const SizedBox(width: 2),
          tab(
            selected: !onFloor,
            icon: Icons.restaurant_menu_outlined,
            label: 'Thực đơn',
            onTap: () {
              if (!onFloor) return;
              setState(() {
                _floorMapVisible = false;
                _tabletPaymentStage = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductSearchField({
    double? width = 280,
    bool expand = false,
    bool dense = false,
    bool showBrowse = true,
    bool showBarcode = true,
    bool showAddProduct = true,
  }) {
    final bar = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: dense ? 34 : null,
        child: PosPurchaseProductSearchBar(
          api: _api,
          sellMode: true,
          focusNode: _productSearchFocus,
          hintText:
              tr(_useFloorAsPrimary ? 'Tìm món (F3)' : 'Tìm hàng hóa (F3)'),
          onPick: (pick) => _addPick(pick),
          onBarcodePick: (pick) => _addPick(pick, mergeIfSame: true),
          onAddProduct: showAddProduct ? _openNewProduct : null,
          showBrowseButton: showBrowse,
          showBarcodeButton: showBarcode,
          denseBar: dense,
          // Thu ngân cảm ứng: không tự mở soft keyboard khi vào màn / sau chọn món.
          autofocusOnMount: false,
          restoreFocusAfterPick: false,
        ),
      ),
    );
    if (expand) return bar;
    return SizedBox(width: width, child: bar);
  }

  /// Tìm bàn/phòng trên sơ đồ (F&B · tab Phòng bàn).
  Widget _buildFloorSearchField({double width = 280}) {
    return SizedBox(
      width: width,
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextField(
          controller: _floorSearchCtrl,
          focusNode: _floorSearchFocus,
          style: const TextStyle(fontSize: 13, height: 1.2),
          decoration: InputDecoration(
            hintText: tr('Tìm bàn / phòng'),
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 32),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kiotBlue, width: 1.5),
            ),
            suffixIcon: PosBarcodeScanIcon(
              iconSize: 20,
              onScanned: (code) => unawaited(_onFloorSearchBarcode(code)),
            ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 32),
          ),
          onChanged: (v) => setState(() => _floorSearchQuery = v),
          onSubmitted: (v) => unawaited(_onFloorSearchBarcode(v)),
        ),
      ),
    );
  }

  Future<void> _onFloorSearchBarcode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    setState(() {
      _floorSearchCtrl.text = code;
      _floorSearchQuery = code;
      _floorPendingOpenCode = code;
      _floorPendingOpenToken++;
    });
  }

  Widget _buildTopBar({bool desktopChrome = false}) {
    final fnb = _useFloorAsPrimary;

    return Material(
      color: _kiotBlue,
      child: Container(
        height: _KiotLayout.topBarHeight,
        padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
        child: Row(
          children: [
            if (desktopChrome && !PosHubScope.of(context)) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('Về trang chủ'),
                icon: const Icon(Icons.home_outlined,
                    size: 22, color: Colors.white),
                onPressed: _goMobileSellHome,
              ),
              const SizedBox(width: 2),
            ],
            if (fnb) ...[
              // Tab chế độ luôn compact — tên bàn / tổng nằm ở giỏ bên phải.
              _buildFloorMenuModeTabs(compact: true),
              const SizedBox(width: 6),
              if (_floorMapVisible) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    tr('${_moneyFmt.format(_floorActiveSubtotal)}đ · $_floorActiveOpenCount bàn'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              // Ô tìm gọn + quét mã: Phòng bàn → tìm bàn; Thực đơn → tìm món.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: _floorMapVisible
                    ? _buildFloorSearchField()
                    : _buildProductSearchField(
                        width: 300,
                        dense: true,
                        showBrowse: false,
                        showBarcode: true,
                        showAddProduct: false,
                      ),
              ),
              const Spacer(),
            ] else
              // Bán lẻ: tìm + tab HĐ
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (_isTableOrderMode) ...[
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr('Đổi bàn / sơ đồ'),
                          icon: const Icon(Icons.table_restaurant_outlined,
                              size: 22, color: Colors.white),
                          onPressed: () => unawaited(_returnToFloorMap()),
                        ),
                      ],
                      if (_printSettings.showCupLabelManualButton) ...[
                        TextButton.icon(
                          onPressed: _cupLabelPendingCount == 0
                              ? null
                              : () => unawaited(_printPendingCupLabels()),
                          icon: const Icon(Icons.sticky_note_2_outlined,
                              size: 18, color: Colors.white),
                          label: Text(
                            tr(_cupLabelPendingCount > 0
                                ? 'Tem ($_cupLabelPendingCount)'
                                : 'Tem'),
                            style: TextStyle(
                              color: Colors.white.withOpacity(_cupLabelPendingCount > 0 ? 1 : 0.5),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      _buildProductSearchField(
                        width: desktopChrome ? 280 : 320,
                      ),
                      const SizedBox(width: 10),
                      if (_isTableOrderMode)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            tr('${tr('Đơn ')}${_tab.serviceResourceName ?? 'bàn'}'
                                '${(_tab.draftOrderNo ?? '').isNotEmpty ? ' · ${_tab.draftOrderNo}' : ''}'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 36,
                          width: 360,
                          child: Scrollbar(
                            controller: _tabScrollCtrl,
                            thumbVisibility: true,
                            interactive: true,
                            child: ListView(
                              controller: _tabScrollCtrl,
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              children: [
                                for (var i = 0; i < _tabs.length; i++) ...[
                                  _invoiceTabChip(i),
                                  const SizedBox(width: 4),
                                ],
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: tr('Thêm hóa đơn'),
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
                    ],
                  ),
                ),
              ),
            // Phải: khách · thông báo · in treo (icon) · [bán lẻ: fullscreen/cast] · menu
            if (_isTableOrderMode) _buildTableGuestIconButton(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr(_systemUnreadNotifications > 0
                  ? 'Thông báo ($_systemUnreadNotifications)'
                  : 'Thông báo hệ thống'),
              onPressed: () {
                unawaited(_refreshSystemUnreadNotifications());
                _openSystemNotifications();
              },
              icon: Badge(
                isLabelVisible: _systemUnreadNotifications > 0,
                label: Text(tr(_systemUnreadNotifications > 99
                    ? '99+'
                    : '$_systemUnreadNotifications')),
                child: const Icon(
                  Icons.notifications_outlined,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
            if (!fnb && _pendingPrintCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 2),
                child: TextButton.icon(
                  onPressed: _openPendingPrintQueue,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                  ),
                  icon: const Icon(Icons.print_disabled_outlined, size: 18),
                  label: Text(
                    tr('In treo ($_pendingPrintCount)'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              )
            else
              PosPendingPrintIconButton(
                pendingCount: _pendingPrintCount,
                onTap: _openPendingPrintQueue,
              ),
            if (!fnb) ..._buildTopBarScreenActions(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr('Menu'),
              icon: const Icon(Icons.menu, size: 24, color: Colors.white),
              onPressed: _openPosMenu,
            ),
          ],
        ),
      ),
    );
  }

  /// Phóng toàn màn hình + truyền màn hình phụ (khách).
  List<Widget> _buildTopBarScreenActions({Color iconColor = Colors.white}) {
    return [
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: tr(_isPosFullscreen
            ? 'Thoát toàn màn hình'
            : 'Phóng toàn màn hình'),
        onPressed: () => unawaited(_togglePosFullscreen()),
        icon: Icon(
          _isPosFullscreen
              ? Icons.fullscreen_exit
              : Icons.fullscreen,
          size: 24,
          color: iconColor,
        ),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: tr('Truyền màn hình thứ 2 (khách)'),
        onPressed: () => unawaited(_openCustomerDisplay()),
        icon: Icon(
          Icons.cast_connected_outlined,
          size: 22,
          color: iconColor,
        ),
      ),
    ];
  }

  Widget _invoiceTabChip(int index, {bool onBlue = true}) {
    final active = index == _activeTab;
    final tab = _tabs[index];
    final hasItems = tab.localDirty
        ? tab.cart.isNotEmpty
        : (tab.cart.isNotEmpty || tab.serverLineCount > 0);
    // Chiếm chỗ (kể cả trống) hoặc đang giữ có hàng → cam + khóa.
    final lockedByOther = tab.draftReadOnly;

    Color bg;
    Color borderColor;
    Color textColor;
    if (onBlue) {
      if (active) {
        bg = Colors.white;
        borderColor = Colors.white;
        textColor = _kiotBlue;
      } else if (lockedByOther) {
        bg = const Color(0xFFFDBA74); // cam — máy khác đang giữ + có hàng
        borderColor = const Color(0xFFEA580C);
        textColor = const Color(0xFF7C2D12);
      } else if (hasItems) {
        bg = const Color(0xFFFEF08A); // vàng — có hàng
        borderColor = const Color(0xFFFACC15);
        textColor = const Color(0xFF713F12);
      } else {
        bg = Colors.white.withOpacity(0.2);
        borderColor = Colors.white.withOpacity(0.35);
        textColor = Colors.white;
      }
    } else {
      if (active) {
        bg = PosTheme.kiotBlueLight;
        borderColor = PosTheme.kiotBlue;
        textColor = PosTheme.kiotBlue;
      } else if (lockedByOther) {
        bg = const Color(0xFFFFEDD5);
        borderColor = const Color(0xFFEA580C);
        textColor = const Color(0xFFC2410C);
      } else if (hasItems) {
        bg = const Color(0xFFFEF9C3);
        borderColor = const Color(0xFFEAB308);
        textColor = const Color(0xFFA16207);
      } else {
        bg = const Color(0xFFF1F5F9);
        borderColor = PosTheme.border;
        textColor = PosTheme.textSecondary;
      }
    }
    final closeColor = onBlue
        ? (active ? Colors.grey.shade600 : (hasItems ? const Color(0xFF7C2D12) : Colors.white70))
        : PosTheme.textSecondary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 2, top: 2, bottom: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: hasItems ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _selectTab(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (lockedByOther) ...[
                      const Icon(Icons.lock_outline,
                          size: 12, color: Color(0xFF9A3412)),
                      const SizedBox(width: 4),
                    ] else if (hasItems) ...[
                      Icon(Icons.shopping_bag_outlined,
                          size: 12,
                          color: onBlue
                              ? const Color(0xFF854D0E)
                              : const Color(0xFFA16207)),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      tr(tab.label),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: (active || hasItems)
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_tabs.length > 1)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: tr('Đóng hóa đơn'),
                onPressed: () {
                  // Gọi ngay — không qua InkWell cha (tránh nuốt tap).
                  unawaited(_closeTab(index));
                },
                icon: Icon(Icons.close, size: 16, color: closeColor),
              ),
          ],
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
          if (_tab.draftOrderId != null) _buildDraftSyncStatusBar(),
          _buildMissingTimedServiceBanner(),
          Expanded(child: _buildKiotCartList()),
          if (showFooterTotal) _buildCartFooter(),
        ],
      ),
    );
  }

  bool get _missingTimedServiceWarning {
    if (_industrySettings?.enableHourlyBilling != true) return false;
    if (!_tab.isTableBound && (_tab.serviceResourceId ?? '').isEmpty) {
      return false;
    }
    return !_tab.cart.any((l) => l.product.isTimedService);
  }

  Widget _buildMissingTimedServiceBanner() {
    if (!_missingTimedServiceWarning) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFF7ED),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.timer_off_outlined,
                size: 18, color: Color(0xFFC2410C)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Chưa có dịch vụ tính giờ trên đơn — thêm SP theo giờ hoặc cấu hình SP mặc định khi mở bàn.'),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9A3412),
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftReadOnlyBanner() {
    // Giữ stub — không còn UI «lấy quyền».
    return const SizedBox.shrink();
  }

  Widget _buildDraftSyncStatusBar() {
    final no = _tab.draftOrderNo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: const Color(0xFFEFF6FF),
      child: Text(
        tr(no != null && no.isNotEmpty
            ? 'Đồng bộ server · $no · tự lưu khi sửa hàng'
            : 'Đồng bộ server · tự lưu khi sửa hàng'),
        style: const TextStyle(fontSize: 11, color: Color(0xFF1D4ED8)),
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
              readOnly: _tab.draftReadOnly,
              decoration: InputDecoration(
                hintText: tr('Ghi chú đơn hàng'),
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) {
                if (_tab.draftReadOnly) return;
                _tab.note = v.trim().isEmpty ? null : v;
              },
              onEditingComplete: () {
                if (_guardReadOnlyEdit()) _scheduleDraftAutosave();
              },
              onSubmitted: (_) {
                if (_guardReadOnlyEdit()) _scheduleDraftAutosave();
              },
            ),
          ),
          Text(tr('Tổng tiền hàng (${_tab.cart.length})'),
            style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary),
          ),
          const SizedBox(width: 10),
          Text(
            tr(_moneyFmt.format(_total)),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kiotBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildCartHeader() {
    const hdr = TextStyle(
      fontSize: 11,
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
          SizedBox(width: _KiotLayout.wDel),
          Expanded(child: Text(tr('Sản phẩm'), style: hdr)),
          SizedBox(
            width: _KiotLayout.wQty,
            child: Text(tr('SL'), style: hdr, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _KiotLayout.wUnit,
            child: Text(tr('ĐVT'), style: hdr, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _KiotLayout.wPrice,
            child: Text(tr('Đơn giá'), style: hdr, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _KiotLayout.wTotal,
            child: Text(tr('Thành tiền'), style: hdr, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildKiotCartList() {
    if (_tab.cart.isEmpty) {
      return Center(
        child: Text(tr('Tìm và thêm hàng hóa vào hóa đơn'),
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
                    return _buildKiotCartRow(line, _tab.cart.length - 1 - i);
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

  Widget _buildKiotCartRow(_SellCartLine line, int cartIndex) {
    final isExpanded = _expandedCartRowId == line.rowId;
    final noteExpanded = isExpanded && _expandedCartMode == _CartRowExpand.note;
    final priceExpanded = isExpanded && _expandedCartMode == _CartRowExpand.priceDiscount;
    final canEditPrice = context.read<PermissionProvider>().canPosPay();
    void openPriceEditor() {
      if (!canEditPrice) {
        NotificationOverlayManager().showError(
          title: tr('Không đủ quyền'),
          message: tr('Cần quyền thu ngân (duyệt) để đổi giá / chiết khấu'),
        );
        return;
      }
      _toggleCartRowExpand(line.rowId, _CartRowExpand.priceDiscount);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _KiotLayout.sidePadding,
            vertical: 6,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: _KiotLayout.wDel,
                child: Center(
                  child: Material(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: () => _removeLine(cartIndex),
                      borderRadius: BorderRadius.circular(6),
                      child: const SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          Icons.delete_rounded,
                          size: 16,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: () =>
                      _toggleCartRowExpand(line.rowId, _CartRowExpand.note),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tr(line.product.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          color: noteExpanded ? _kiotBlue : null,
                          decoration: noteExpanded
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          decorationColor: _kiotBlue,
                        ),
                      ),
                      if (!noteExpanded &&
                          line.lineNote != null &&
                          line.lineNote!.isNotEmpty)
                        Text(
                          tr('↳ ${line.lineNote}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: _kiotBlue),
                        ),
                      if (!noteExpanded && line.toppings.isNotEmpty)
                        Text(
                          tr('↳ ${line.toppings.map((t) => '${t.name} (+${_moneyFmt.format(t.price)})').join(', ')}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF7C3AED)),
                        ),
                      if (!priceExpanded && line.discountAmount > 0)
                        Text(
                          tr('CK: -${_moneyFmt.format(line.discountAmount)}'),
                          style: TextStyle(
                              fontSize: 10, color: Colors.red.shade700),
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
                  onTap: openPriceEditor,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        tr(_moneyFmt.format(line.unitPrice)),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          color: canEditPrice
                              ? _kiotBlue
                              : PosTheme.textPrimary,
                          decoration: priceExpanded
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          decorationColor: _kiotBlue,
                        ),
                      ),
                      if (line.discountAmount > 0 && !priceExpanded)
                        Text(
                          tr('-${_moneyFmt.format(line.discountAmount)}'),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 9, color: Colors.red.shade700),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: _KiotLayout.wTotal,
                child: InkWell(
                  onTap: openPriceEditor,
                  child: Text(
                    tr(_moneyFmt.format(line.lineTotal)),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: priceExpanded
                          ? _kiotBlue
                          : PosTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (noteExpanded) _buildCartLineNoteEditor(line),
        if (priceExpanded && canEditPrice) _buildCartLinePriceEditor(line),
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
          border: Border.all(color: _kiotBlue.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PosLineQuickNotesPicker(
              quickNotes: line.product.saleQuickNotes,
              selected: line.selectedQuickNotes,
              onSelectedChanged: (next) {
                if (!_guardReadOnlyEdit()) return;
                setState(() {
                  line.selectedQuickNotes
                    ..clear()
                    ..addAll(next);
                  _applyLineNoteFromPicker(line);
                });
              },
              extraController: line.noteCtrl,
              onExtraChanged: () {
                if (!_guardReadOnlyEdit()) return;
                setState(() => _applyLineNoteFromPicker(line));
              },
            ),
            if (line.product.allowToppings &&
                line.product.toppingOptions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(tr('Tùy chọn thêm'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: line.product.toppingOptions.map((o) {
                  final on = line.toppings
                      .any((t) => t.id == o.toppingProductId);
                  return FilterChip(
                    label: Text(
                      tr('${o.toppingProductName} (+${_moneyFmt.format(o.extraPrice)})'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: on,
                    showCheckmark: true,
                    selectedColor: PosTheme.kiotBlueLight,
                    checkmarkColor: _kiotBlue,
                    side: BorderSide(
                      color: on ? _kiotBlue : PosTheme.border,
                    ),
                    onSelected: (v) => setState(() {
                      if (v) {
                        if (!line.toppings
                            .any((t) => t.id == o.toppingProductId)) {
                          line.toppings.add(_CartTopping(
                            id: o.toppingProductId,
                            name: o.toppingProductName,
                            price: o.extraPrice,
                          ));
                        }
                      } else {
                        line.toppings.removeWhere(
                            (t) => t.id == o.toppingProductId);
                      }
                      _syncPaidAmount();
                      _scheduleDraftAutosave();
                      _scheduleCustomerDisplayPublish();
                    }),
                  );
                }).toList(),
              ),
            ],
            if (line.product.hasToppingGroups) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Topping'),
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openCartLineToppings(line),
                    child: Text(
                      tr(line.toppings.isEmpty
                          ? 'Chọn topping'
                          : 'Sửa (${line.toppings.length})'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (line.toppings.isNotEmpty)
                Text(
                  tr(line.toppings
                      .map((t) =>
                          '↳ ${t.name} (+${_moneyFmt.format(t.price)})')
                      .join('\n')),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7C3AED),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  setState(() {
                    _commitLineNote(line, scheduleSave: true);
                    _expandedCartRowId = null;
                    _expandedCartMode = null;
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
          border: Border.all(color: _kiotBlue.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(tr('Đơn giá'), style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: PosNoSoftKeyboardField(
                    controller: line.priceCtrl,
                    allowDecimal: true,
                    textAlign: TextAlign.right,
                    keypadTitle: 'Đơn giá',
                    enabled: !_tab.draftReadOnly,
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: tr('đ'),
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
                Text(tr('Chiết khấu'), style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                _lineDiscountChip(line, true),
                const SizedBox(width: 4),
                _lineDiscountChip(line, false),
                const SizedBox(width: 8),
                Expanded(
                  child: PosNoSoftKeyboardField(
                    controller: line.discountCtrl,
                    enabled: !_tab.draftReadOnly,
                    allowDecimal: true,
                    textAlign: TextAlign.right,
                    keypadTitle: 'Chiết khấu dòng',
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      suffixText: tr(line.discountIsPercent ? '%' : 'đ'),
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) {
                      if (!_guardReadOnlyEdit()) return;
                      setState(() {
                        line.discountInput = _parseMoneyInput(v);
                        _syncPaidAmount();
                      });
                    },
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
              Text(tr('Chiết khấu dòng: -${_moneyFmt.format(line.discountAmount)}'),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  setState(() {
                    _commitLinePriceDiscount(line, scheduleSave: true);
                    _expandedCartRowId = null;
                    _expandedCartMode = null;
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
            tr(isPercent ? '%' : 'đ'),
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
    final canPay = perm.canPosPay();

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_tab.draftOrderId != null) _buildDraftSyncStatusBar(),
                Expanded(child: _buildKiotCartList()),
              ],
            ),
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
                    readOnly: _tab.draftReadOnly,
                    decoration: InputDecoration(
                      hintText: tr('Ghi chú đơn hàng'),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) {
                      if (_tab.draftReadOnly) return;
                      _tab.note = v.trim().isEmpty ? null : v;
                    },
                    onEditingComplete: () {
                      if (_guardReadOnlyEdit()) _scheduleDraftAutosave();
                    },
                    onSubmitted: (_) {
                      if (_guardReadOnlyEdit()) _scheduleDraftAutosave();
                    },
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
              canOrder: perm.canPosOrder(),
              busy: _checkingOut || _parking || _provisionalPrinting || _kitchenSending,
              onComplete: _checkout,
              height: compact ? 44 : 48,
              radius: 6,
              completeLabel: 'Thanh toán',
              completeFontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitDropdown(_SellCartLine line) {
    if (line.unitViews.length <= 1) {
      return Text(
        tr(line.unitLabel),
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
                    tr(v.label),
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
                  child: Text(tr(v.label), textAlign: TextAlign.center),
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
                    hintText: tr('Tìm khách hàng (F4)'),
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
                  onChanged: _onCustomerSearchChanged,
                ),
              ),
              IconButton(
                tooltip: tr('Thêm khách hàng'),
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
                          title: Text(tr(c.name), style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            tr([c.phone, c.customerCode]
                                .where((e) => e != null && e.isNotEmpty)
                                .join(' · ')),
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
                    labelText: tr('Người bán'),
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
                              tr(s['displayName']?.toString() ?? '—'),
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
            SizedBox(
              width: 82,
              child: Text(tr('Giảm giá'), style: TextStyle(fontSize: 12)),
            ),
            _discountModeChip('%', true, onMutate: onMutate),
            const SizedBox(width: 4),
            _discountModeChip('đ', false, onMutate: onMutate),
            const SizedBox(width: 8),
            Expanded(
              child: PosNoSoftKeyboardField(
                controller: _tab._discountCtrl,
                enabled: !_tab.draftReadOnly,
                allowDecimal: true,
                textAlign: TextAlign.right,
                keypadTitle: 'Giảm giá đơn',
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  suffixText: tr(_tab.discountIsPercent ? '%' : 'đ'),
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (v) => _onDiscountInputChanged(v, onMutate: onMutate),
                onSubmitted: (_) => _scheduleDraftAutosave(),
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
            child: Text(tr('Chiết khấu đơn: -${_moneyFmt.format(_tab.discount)}'),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
        if (_sellMode == _SellMode.delivery) ...[
          const SizedBox(height: 12),
          Text(tr('Giao hàng'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _tab._deliveryPhoneCtrl,
            decoration: InputDecoration(
              hintText: tr('SĐT người nhận'),
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: (v) => _tab.deliveryPhone = v.trim().isEmpty ? null : v.trim(),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _tab._deliveryAddressCtrl,
            decoration: InputDecoration(
              hintText: tr('Địa chỉ giao hàng'),
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
            decoration: InputDecoration(
              hintText: tr('Đối tác giao (GHN, GHTK...)'),
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: (v) => _tab.deliveryPartner = v.trim().isEmpty ? null : v.trim(),
          ),
        ],
        const SizedBox(height: 8),
        // Giá đã gồm thuế → không hiện hàng thuế trên thanh toán.
        if (_storeSettings.taxMode == PosSellTaxMode.orderTotal) ...[
          Text(tr('Thuế VAT'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
          if (_tab.vatExempt)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('Không chịu thuế GTGT'),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            )
          else if (_vatAmount > 0) ...[
            const SizedBox(height: 4),
            _summaryRow('Tiền hàng', _moneyFmt.format(_total)),
            _summaryRow(
              'VAT (${_tab.vatRate.toStringAsFixed(_tab.vatRate % 1 == 0 ? 0 : 1)}%)',
              _moneyFmt.format(_vatAmount),
            ),
          ],
        ] else if (_storeSettings.taxMode == PosSellTaxMode.perItem) ...[
          Text(tr('Thuế VAT theo từng mặt hàng (thiết lập trên hàng hóa)'),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          if (_vatAmount > 0) ...[
            const SizedBox(height: 4),
            _summaryRow('VAT', _moneyFmt.format(_vatAmount)),
          ],
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tab._voucherCtrl,
                decoration: InputDecoration(
                  hintText: tr('Mã voucher'),
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
                  : Text(tr('Áp dụng'), style: TextStyle(fontSize: 12)),
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
                child: PosNoSoftKeyboardField(
                  controller: _tab._pointsCtrl,
                  allowDecimal: false,
                  keypadTitle: 'Đổi điểm',
                  decoration: InputDecoration(
                    hintText: tr('Đổi điểm (có ${_moneyFmt.format(_tab.customer!.pointBalance)})'),
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
            tr(label),
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
            Expanded(
              child: Text(tr('Thanh toán (nhiều nguồn)'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: () => _addPaymentLine(onMutate: onMutate),
              icon: const Icon(Icons.add, size: 16),
              label: Text(tr('Thêm'), style: TextStyle(fontSize: 13)),
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
                          style: const TextStyle(fontSize: 14, color: PosTheme.textPrimary),
                          items: _paymentSources
                              .map((s) => DropdownMenuItem(
                                    value: s.key,
                                    child: Text(
                                      tr(s.label),
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
                            child: PosNoSoftKeyboardField(
                              controller: pay.amountCtrl,
                              allowDecimal: true,
                              textAlign: TextAlign.right,
                              keypadTitle: 'Số tiền thanh toán',
                              decoration: InputDecoration(
                                labelText: tr('Số tiền'),
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                              style: const TextStyle(fontSize: 14),
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
                                        tr(s.label),
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
                        child: PosNoSoftKeyboardField(
                          controller: pay.amountCtrl,
                          allowDecimal: true,
                          textAlign: TextAlign.right,
                          keypadTitle: 'Số tiền thanh toán',
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
    final showReturn = line.qty > 2;
    // Giữ nút gọn trong wQty — IconButton 48px trên cảm ứng làm + tràn sang ĐVT
    // và bị dropdown đơn vị “cướp” tap.
    const hit = 36.0;
    const qtyW = 36.0;
    const iconSize = 18.0;
    Widget qtyBtn({
      required IconData icon,
      required VoidCallback onPressed,
      Color? color,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: hit,
            height: hit,
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            qtyBtn(
              icon: Icons.remove,
              onPressed: () => unawaited(_adjustQty(line, -1)),
            ),
            SizedBox(
              width: qtyW,
              child: Text(
                tr(line.qty == line.qty.roundToDouble()
                    ? line.qty.toStringAsFixed(0)
                    : line.qty.toStringAsFixed(2)),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            qtyBtn(
              icon: Icons.add,
              color: _kiotBlue,
              onPressed: () => unawaited(_adjustQty(line, 1)),
            ),
          ],
        ),
        if (showReturn)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_showReturnGoodsDialog(line)),
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                tr('Trả'),
                style: TextStyle(fontSize: 10, color: Colors.red.shade700),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCheckoutActions({
    required bool canPay,
    required bool busy,
    required VoidCallback? onComplete,
    VoidCallback? onPark,
    double height = 50,
    double radius = 10,
    String completeLabel = 'HOÀN TẤT',
    double completeFontSize = 12,
    bool showQuickPrintChips = true,
    VoidCallback? onPrintChipChanged,
    bool? canOrder,
  }) {
    final orderOk = canOrder ?? canPay;
    final showProvisional = (_industrySettings?.allowProvisionalBill ?? false) &&
        _tab.cart.isNotEmpty &&
        orderOk;
    final canPark = onPark != null && _tab.cart.isNotEmpty && !busy && orderOk;

    Widget completeBtn({required bool expanded}) {
      return FilledButton(
        onPressed: _tab.cart.isEmpty || busy || !canPay
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onComplete?.call();
              },
        style: FilledButton.styleFrom(
          backgroundColor: PosTheme.payGreen,
          foregroundColor: Colors.white,
          // Giỏ trống / không quyền: xám rõ — tránh nhìn như nút đang bấm được.
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          minimumSize: Size(expanded ? double.infinity : 0, height),
          elevation: busy || _tab.cart.isEmpty || !canPay ? 0 : 2,
          shadowColor: PosTheme.payGreen.withOpacity(0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withOpacity(0.28);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withOpacity(0.12);
            }
            return null;
          }),
        ),
        child: busy && (_checkingOut || _parking)
            ? SizedBox(
                height: height * 0.44,
                width: height * 0.44,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    tr(completeLabel),
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: completeFontSize,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
      );
    }

    Widget parkBtn() {
      return OutlinedButton(
        onPressed: canPark
            ? () {
                HapticFeedback.selectionClick();
                onPark!();
              }
            : null,
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, height),
          foregroundColor: _kiotBlue,
          side: const BorderSide(color: PosTheme.kiotBlue, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return _kiotBlue.withOpacity(0.18);
            }
            return null;
          }),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(tr('Giữ đơn'),
            maxLines: 1,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
      );
    }

    Widget provisionalBtn() {
      final provisionalBusy = _provisionalPrinting;
      return OutlinedButton(
        onPressed: busy
            ? null
            : () {
                HapticFeedback.mediumImpact();
                unawaited(_printProvisionalBill());
              },
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, height),
          foregroundColor: const Color(0xFFB45309),
          backgroundColor: provisionalBusy
              ? const Color(0xFFFEF3C7)
              : const Color(0xFFFFFBEB),
          side: BorderSide(
            color: provisionalBusy
                ? const Color(0xFFD97706)
                : const Color(0xFFCA8A04),
            width: provisionalBusy ? 2 : 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return const Color(0xFFF59E0B).withOpacity(0.35);
            }
            return null;
          }),
        ),
        child: provisionalBusy
            ? SizedBox(
                height: height * 0.44,
                width: height * 0.44,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFFB45309),
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(tr('Tạm tính'),
                  maxLines: 1,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
      );
    }

    if (!showProvisional) {
      if (onPark == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showQuickPrintChips)
              _buildCheckoutQuickPrintChips(onChanged: onPrintChipChanged),
            completeBtn(expanded: true),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showQuickPrintChips)
            _buildCheckoutQuickPrintChips(onChanged: onPrintChipChanged),
          Row(
            children: [
              Expanded(child: parkBtn()),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: completeBtn(expanded: false)),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showQuickPrintChips)
          _buildCheckoutQuickPrintChips(onChanged: onPrintChipChanged),
        Row(
          children: [
            if (onPark != null) ...[
              Expanded(child: parkBtn()),
              const SizedBox(width: 6),
            ],
            Expanded(child: provisionalBtn()),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: completeBtn(expanded: false)),
          ],
        ),
      ],
    );
  }

  /// Chip bật/tắt in bill & in tem khi thanh toán (chỉ lần TT này).
  Widget _buildCheckoutQuickPrintChips({VoidCallback? onChanged}) {
    Widget chip({
      required String label,
      required IconData icon,
      required bool selected,
      required ValueChanged<bool> onSelected,
    }) {
      return FilterChip(
        selected: selected,
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 16,
          color: selected ? Colors.white : _kiotBlue,
        ),
        label: Text(
          tr(label),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : PosTheme.textPrimary,
          ),
        ),
        selectedColor: _kiotBlue,
        backgroundColor: const Color(0xFFF1F5F9),
        side: BorderSide(
          color: selected ? _kiotBlue : PosTheme.border,
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: onSelected,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          chip(
            label: 'In bill',
            icon: Icons.receipt_long_outlined,
            selected: _quickPrintInvoice,
            onSelected: (v) {
              setState(() => _quickPrintInvoice = v);
              onChanged?.call();
            },
          ),
          chip(
            label: 'In tem',
            icon: Icons.local_cafe_outlined,
            selected: _quickPrintCup,
            onSelected: (v) {
              setState(() => _quickPrintCup = v);
              onChanged?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSidebar(PermissionProvider perm, {required double width, bool compact = false}) {
    _recalcTotals();
    final canPay = perm.canPosPay();

    final summary = _buildPaymentSummaryContent();

    final payButton = _buildCheckoutActions(
      canPay: canPay,
      canOrder: perm.canPosOrder(),
      busy: _checkingOut || _parking || _provisionalPrinting || _kitchenSending,
      onComplete: _checkout,
      height: compact ? 44 : 48,
      radius: 6,
      completeLabel: 'Thanh toán',
      completeFontSize: 14,
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
            tr(label),
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

  Widget _summaryRow(String label, String value, {bool bold = false, bool blue = false, double? labelSize}) {
    final ls = labelSize ?? 14;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            tr(label),
            style: TextStyle(fontSize: ls, fontWeight: bold ? FontWeight.w600 : null),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            tr(value),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: bold ? (ls + 3) : ls,
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
    final canPay = perm.canPosPay();
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
    final draftCount = _pickerDraftQty.values.fold<double>(0, (a, b) => a + b);
    final draftLines = _pickerDraftQty.length;
    return Material(
      color: const Color(0xFFF3F4F6),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: Text(tr(_isTableOrderMode ? 'Chọn món' : 'Chọn hàng hóa')),
              backgroundColor: Colors.white,
              foregroundColor: PosTheme.textPrimary,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _closeMobileProductPicker,
              ),
              actions: [
                IconButton(
                  tooltip: tr('Thêm hàng mới'),
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
                allowNegativeStock: _allowNegativeStock,
                // Chỉ hiện SL đang chọn nháp — không lấy từ đơn (không sync list).
                cartQtyByProductId: Map<String, double>.from(_pickerDraftQty),
                onPick: (pick) async {
                  await _pickerDraftIncrement(pick);
                },
                onDecrement: (product) {
                  _pickerDraftDecrement(product);
                },
              ),
            ),
            Material(
              color: Colors.white,
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(draftLines == 0
                              ? 'Chưa chọn hàng'
                              : 'Đã chọn $draftLines SP · ${_qtyFmtInt(draftCount)}'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PosTheme.textPrimary,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: draftLines == 0
                            ? null
                            : () => unawaited(_confirmPickerDraftToCart()),
                        style: FilledButton.styleFrom(
                          backgroundColor: _kiotBlue,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          tr(_isTableOrderMode ? 'Thêm vào bàn' : 'Chọn hàng hóa'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _qtyFmtInt(double q) {
    if (q == q.roundToDouble()) return q.toStringAsFixed(0);
    return q.toStringAsFixed(1);
  }

  void _openMobileProductPicker() {
    _pickerDraftQty.clear();
    _pickerDraftPicks.clear();
    setState(() => _mobileProductPickerOpen = true);
  }

  void _closeMobileProductPicker() {
    _pickerDraftQty.clear();
    _pickerDraftPicks.clear();
    setState(() => _mobileProductPickerOpen = false);
  }

  Future<void> _pickerDraftIncrement(PosPurchaseLookupPick pick) async {
    final id = pick.product.id;
    var views = await loadPosSellUnitViews(_api, pick.product);
    views = applyPosPriceListToViews(views, pick.product, _currentPriceOverrides);
    if (!mounted || views.isEmpty) return;
    final view = pickUnitView(
          views,
          variantId: pick.variantId,
          unitId: pick.unitId,
          unitLabel: pick.unitLabel,
        ) ??
        views.first;
    final draftNext = (_pickerDraftQty[id] ?? 0) + 1;
    // Tồn = giỏ hiện tại + bản nháp (chưa vào đơn).
    if (!_validateStockForAdd(pick.product, view, addQty: draftNext)) return;
    setState(() {
      _pickerDraftQty[id] = draftNext;
      _pickerDraftPicks[id] = pick;
    });
    HapticFeedback.lightImpact();
  }

  void _pickerDraftDecrement(PosProduct product) {
    final id = product.id;
    final cur = _pickerDraftQty[id] ?? 0;
    if (cur <= 0) return;
    setState(() {
      final next = cur - 1;
      if (next <= 0) {
        _pickerDraftQty.remove(id);
        _pickerDraftPicks.remove(id);
      } else {
        _pickerDraftQty[id] = next;
      }
    });
  }

  /// Đưa bản nháp vào đơn → mới autosave/đồng bộ.
  Future<void> _confirmPickerDraftToCart() async {
    if (_pickerDraftQty.isEmpty) {
      _closeMobileProductPicker();
      return;
    }
    if (!await _ensureCanEditActiveDraft()) return;
    final entries = _pickerDraftQty.entries.toList();
    for (final e in entries) {
      final pick = _pickerDraftPicks[e.key];
      if (pick == null || e.value <= 0) continue;
      await _addPick(
        pick,
        mergeIfSame: true,
        autosave: false,
        addQty: e.value,
      );
      if (!mounted) return;
    }
    _pickerDraftQty.clear();
    _pickerDraftPicks.clear();
    if (!mounted) return;
    // Giữ chế độ bàn + đánh dấu dirty trước khi đóng picker / autosave.
    _markTabDirty(_tab);
    setState(() => _mobileProductPickerOpen = false);
    _scheduleDraftAutosave(delay: const Duration(milliseconds: 200));
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
      // Desktop/tablet POS fullscreen → về trang chủ MainLayout.
      NavigationNotifier.goTo(NavigationNotifier.home);
    }
  }

  /// Cột giỏ (desktop 3 vùng) — tách khỏi panel thanh toán.
  Widget _buildDesktopCartColumn() {
    return RepaintBoundary(
      child: ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_tab.draftOrderId != null) _buildDraftSyncStatusBar(),
          Expanded(child: _buildKiotCartList()),
          Container(
            height: 36,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: PosTheme.border)),
              color: Color(0xFFFAFBFC),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: _KiotLayout.sidePadding),
            child: Row(
              children: [
                const Icon(Icons.edit_outlined,
                    size: 15, color: PosTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _tab._noteCtrl,
                    readOnly: _tab.draftReadOnly,
                    decoration: InputDecoration(
                      hintText: tr('Ghi chú đơn hàng'),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) {
                      if (_tab.draftReadOnly) return;
                      _tab.note = v.trim().isEmpty ? null : v;
                    },
                    onEditingComplete: () {
                      if (_guardReadOnlyEdit()) _scheduleDraftAutosave();
                    },
                    onSubmitted: (_) {
                      if (_guardReadOnlyEdit()) _scheduleDraftAutosave();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildDesktopProductPane() {
    return RepaintBoundary(
      child: PosSellProductGrid(
        key: _productGridKey,
        api: _api,
        storeId: _storeId,
        priceOverrides: _currentPriceOverrides,
        allowNegativeStock: _allowNegativeStock,
        onPick: (pick) => _addPick(pick),
      ),
    );
  }

  Widget _buildDesktopFloorPane() {
    return PosResourceFloorScreen(
      key: ValueKey('floor-desk-$_floorMapEpoch'),
      embedded: true,
      showAppBar: false,
      manageMode: false,
      sellProfile: _industrySettings?.sellProfile,
      promptGuestCountOnOpen:
          _industrySettings?.promptGuestCountOnOpen == true,
      allowProvisionalBill:
          _industrySettings?.allowProvisionalBill != false,
      searchQuery: _floorSearchQuery,
      pendingOpenCode: _floorPendingOpenCode,
      pendingOpenToken: _floorPendingOpenToken,
      onSelect: (result) => unawaited(_attachFloorResult(result)),
      onResourceFreed: _onFloorResourceFreed,
      onActiveTotalsChanged: _onFloorActiveTotalsChanged,
      zeroPendingKitchenResourceIds: _kitchenClearedResourceIds,
      billRequestedResourceIds: _billRequestedResourceIds,
      releasedOrderIds: Set<String>.from(_floorReleasedOrderIds),
    );
  }

  // ─── Tablet lớn / màn ngang F&B: trái = Phòng bàn|Thực đơn, phải = giỏ ───

  Widget _buildTabletFnbFlow(PermissionProvider perm) {
    if (_tabletPaymentStage) return _buildTabletPaymentStage(perm);
    // Phòng bàn và Thực đơn cùng layout 2 cột — không chuyển full-page.
    return _buildTabletSplitStage(perm);
  }

  /// F&B: nửa trái sơ đồ hoặc thực đơn; nửa phải giỏ hàng (luôn giữ).
  Widget _buildTabletSplitStage(PermissionProvider perm) {
    _recalcTotals();
    final canPay = perm.canPosPay();
    final left = _floorMapVisible
        ? _buildDesktopFloorPane()
        : _buildDesktopProductPane();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(desktopChrome: true),
        _buildExpiryLotBanner(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Phòng bàn & Thực đơn cùng tỉ lệ 6:4 (trái rộng hơn giỏ).
              Expanded(flex: 6, child: left),
              const VerticalDivider(
                  width: 1, thickness: 1, color: PosTheme.border),
              Expanded(
                flex: 4,
                child: ColoredBox(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTabletOrderCartHeader(),
                      Expanded(child: _buildDesktopCartColumn()),
                      _buildTabletOrderFooter(
                        canPay: canPay,
                        canOrder: perm.canPosOrder(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Mobile F&B: sơ đồ full-width (giữ luồng cũ trên điện thoại).
  Widget _buildTabletFloorStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFloorOpsTopBar(),
        _buildExpiryLotBanner(),
        Expanded(child: _buildDesktopFloorPane()),
      ],
    );
  }

  /// Thanh sơ đồ bàn.
  /// Mobile dọc: Home · tổng tiền bàn mở · thông báo · in treo · menu ☰
  /// Ngang / màn lớn: đầy đủ tab Phòng bàn|Thực đơn + tìm món.
  Widget _buildFloorOpsTopBar() {
    final size = MediaQuery.sizeOf(context);
    final isPortrait = size.height >= size.width;
    final compact = Responsive.isMobile(context) && isPortrait;
    final totalLabel =
        'Tổng ${_moneyFmt.format(_floorActiveSubtotal)}đ';
    final openLabel = _floorActiveOpenCount > 0
        ? '${_floorActiveOpenCount} bàn'
        : '0 bàn';

    return Material(
      color: _kiotBlue,
      child: SizedBox(
        height: _KiotLayout.topBarHeight + (compact ? 4 : 8),
        child: Row(
          children: [
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr('Về trang chủ'),
              icon: const Icon(Icons.home_outlined,
                  size: 22, color: Colors.white),
              onPressed: _goMobileSellHome,
            ),
            if (!compact) ...[
              _buildFloorMenuModeTabs(compact: true),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: _floorMapVisible
                    ? _buildFloorSearchField(width: 260)
                    : _buildProductSearchField(
                        width: 280,
                        dense: true,
                        showBrowse: false,
                        showBarcode: true,
                        showAddProduct: false,
                      ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: compact ? 4 : 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: compact
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.end,
                  children: [
                    Text(
                      tr(totalLabel),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 16 : 14,
                      ),
                    ),
                    Text(
                      tr(openLabel),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.88),
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 12 : 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr(_systemUnreadNotifications > 0
                  ? 'Thông báo ($_systemUnreadNotifications)'
                  : 'Thông báo hệ thống'),
              onPressed: () {
                unawaited(_refreshSystemUnreadNotifications());
                _openSystemNotifications();
              },
              icon: Badge(
                isLabelVisible: _systemUnreadNotifications > 0,
                label: Text(tr(_systemUnreadNotifications > 99
                    ? '99+'
                    : '$_systemUnreadNotifications')),
                child: const Icon(
                  Icons.notifications_outlined,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
            PosPendingPrintIconButton(
              pendingCount: _pendingPrintCount,
              onTap: _openPendingPrintQueue,
              iconColor: Colors.white,
              compact: true,
            ),
            if (!compact) ..._buildTopBarScreenActions(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr('Menu'),
              icon: const Icon(Icons.menu, size: 26, color: Colors.white),
              onPressed: _openPosMenu,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  void _onFloorActiveTotalsChanged(double subtotal, int openCount) {
    if (!mounted) return;
    if ((subtotal - _floorActiveSubtotal).abs() < 0.009 &&
        openCount == _floorActiveOpenCount) {
      return;
    }
    setState(() {
      _floorActiveSubtotal = subtotal;
      _floorActiveOpenCount = openCount;
    });
  }

  Future<void> _openSaleOrdersFromFloor() async {
    if (NavigationNotifier.mainLayoutReady.value) {
      NavigationNotifier.navigateToModule.value = 'PosSaleOrders';
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PosSaleOrderListScreen()),
    );
  }

  /// Legacy alias — F&B dùng [_buildTabletSplitStage].
  Widget _buildTabletOrderStage(PermissionProvider perm) =>
      _buildTabletSplitStage(perm);

  /// Đầu cột giỏ hàng: tên bàn/khu + số món — phân biệt rõ với vùng chọn món.
  Widget _buildTabletOrderCartHeader() {
    final tableLabel = [
      if ((_tab.serviceAreaName ?? '').isNotEmpty) _tab.serviceAreaName,
      if ((_tab.serviceResourceName ?? '').isNotEmpty) _tab.serviceResourceName,
    ].whereType<String>().join(' · ');
    final title = tableLabel.isNotEmpty
        ? tableLabel
        : (_floorMapVisible && _useFloorAsPrimary
            ? 'Chọn bàn để bán'
            : 'Giỏ hàng');
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          Icon(
            _isTableOrderMode
                ? Icons.table_restaurant_outlined
                : Icons.receipt_long_outlined,
            size: 17,
            color: PosTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr(title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: PosTheme.textPrimary,
              ),
            ),
          ),
          if (_useFloorAsPrimary &&
              !_floorMapVisible &&
              (_isTableOrderMode || _tab.cart.isNotEmpty))
            TextButton.icon(
              onPressed: () => unawaited(_returnToFloorMap()),
              icon: const Icon(Icons.table_restaurant_outlined, size: 16),
              label: Text(tr('Đổi bàn'), style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: PosTheme.kiotBlue,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (_tab.cart.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: PosTheme.kiotBlueLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tr('${_tab.cart.length} món'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: PosTheme.kiotBlue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Chân màn chọn món: tổng tiền + Thanh toán (xanh lá) + Thông báo bếp (xanh dương).
  Widget _buildTabletOrderFooter({required bool canPay, required bool canOrder}) {
    final notifyBusy = _kitchenSending || _checkingOut || _parking;
    final canNotify = _isTableOrderMode &&
        _kitchenActionCount > 0 &&
        !notifyBusy &&
        canOrder;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: PosTheme.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryRow(
            'Tổng tiền (${_tab.cart.length} món)',
            _moneyFmt.format(_grandTotal),
            bold: true,
            blue: true,
            labelSize: 15,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: _tab.cart.isEmpty || !canPay
                      ? null
                      : () => setState(() => _tabletPaymentStage = true),
                  style: PosTheme.payButtonStyle(height: 56, radius: 10),
                  child: Text(
                    tr('Thanh toán (F9)'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              if (_isTableOrderMode &&
                  _industrySettings?.sellProfile ==
                      PosSellProfile.restaurant) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: canNotify
                        ? () => unawaited(_kitchenSendCurrentTable())
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: PosTheme.kiotBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade600,
                      minimumSize: const Size(0, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      tr(_kitchenSending
                          ? 'Đang gửi…'
                          : _kitchenActionCount > 0
                              ? 'Thông báo (F10)'
                              : 'Thông báo'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Bước 3: thanh toán — giữ giỏ bên trái để đối chiếu món.
  Widget _buildTabletPaymentStage(PermissionProvider perm) {
    _recalcTotals();
    final canPay = perm.canPosPay();
    final widePay = MediaQuery.sizeOf(context).width >= 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: _kiotBlue,
          child: SizedBox(
            height: _KiotLayout.topBarHeight,
            child: Row(
              children: [
                IconButton(
                  tooltip: tr('Quay lại giỏ hàng'),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => setState(() => _tabletPaymentStage = false),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tr('${tr('Thanh toán · ')}${_tab.serviceResourceName ?? 'Đơn hàng'}'
                        '${(_tab.draftOrderNo ?? '').isNotEmpty ? ' · ${_tab.draftOrderNo}' : ''}'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
        _buildExpiryLotBanner(),
        Expanded(
          child: widePay
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 4,
                      child: ColoredBox(
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: 40,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.centerLeft,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF8FAFC),
                                border: Border(
                                    bottom:
                                        BorderSide(color: PosTheme.border)),
                              ),
                              child: Text(
                                tr('Giỏ · ${_tab.cart.length} món · ${_moneyFmt.format(_grandTotal)}đ'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: PosTheme.textPrimary,
                                ),
                              ),
                            ),
                            Expanded(child: _buildDesktopCartColumn()),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(
                        width: 1, thickness: 1, color: PosTheme.border),
                    Expanded(
                      flex: 6,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        children: [_buildPaymentSummaryContent()],
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [_buildPaymentSummaryContent()],
                ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: PosTheme.border)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: _buildCheckoutActions(
            canPay: canPay,
            canOrder: perm.canPosOrder(),
            busy: _checkingOut ||
                _parking ||
                _provisionalPrinting ||
                _kitchenSending,
            onComplete: _checkout,
            height: 56,
            radius: 10,
            completeLabel: 'HOÀN TẤT THANH TOÁN',
            completeFontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileTopBar() {
    final inHub = PosHubScope.of(context);
    final tableMode = _isTableOrderMode;
    final bar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(tableMode || inHub ? 4 : 12, 4, 4, 0),
          child: Row(
            children: [
              if (tableMode)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Về sơ đồ bàn'),
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: PosTheme.kiotBlue, size: 18),
                  onPressed: () => unawaited(_returnToFloorMap()),
                )
              else if (inHub)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Về trang chủ'),
                  icon: const Icon(Icons.home_outlined,
                      color: PosTheme.textPrimary),
                  onPressed: _goMobileSellHome,
                ),
              Expanded(
                child: Text(
                  tr(tableMode && (_tab.serviceResourceName ?? '').isNotEmpty
                      ? _tab.serviceResourceName!
                      : 'Bán hàng'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: PosTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!tableMode &&
                  (_tab.resourceSessionId ?? '').isNotEmpty &&
                  _industrySettings?.sellProfile == PosSellProfile.restaurant)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Báo chế biến'),
                  icon: const Icon(Icons.soup_kitchen_outlined,
                      color: Color(0xFFB45309)),
                  onPressed: (_kitchenSending || _checkingOut || _parking)
                      ? null
                      : () => unawaited(_kitchenSendCurrentTable()),
                ),
              if (_printSettings.showCupLabelManualButton)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr(_cupLabelPendingCount > 0
                      ? 'In tem ly ($_cupLabelPendingCount)'
                      : 'In tem ly'),
                  icon: Badge(
                    isLabelVisible: _cupLabelPendingCount > 0,
                    label: Text(tr('$_cupLabelPendingCount')),
                    child: Icon(
                      Icons.sticky_note_2_outlined,
                      color: _cupLabelPendingCount > 0
                          ? const Color(0xFF0D9488)
                          : PosTheme.textSecondary,
                    ),
                  ),
                  onPressed: _cupLabelPendingCount == 0
                      ? null
                      : () => unawaited(_printPendingCupLabels()),
                ),
              if (!tableMode)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Chọn bảng giá'),
                  icon:
                      const Icon(Icons.sell_outlined, color: PosTheme.kiotBlue),
                  onPressed: _openMobilePriceListPicker,
                ),
              if (!tableMode)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Quét liên tục'),
                  icon: const Icon(Icons.qr_code_scanner,
                      color: PosTheme.kiotBlue),
                  onPressed: _openMobileContinuousScan,
                ),
              if (tableMode)
                _buildTableGuestIconButton(
                  iconColor: PosTheme.textPrimary,
                  compact: true,
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr(_systemUnreadNotifications > 0
                    ? 'Thông báo ($_systemUnreadNotifications)'
                    : 'Thông báo hệ thống'),
                onPressed: () {
                  unawaited(_refreshSystemUnreadNotifications());
                  _openSystemNotifications();
                },
                icon: Badge(
                  isLabelVisible: _systemUnreadNotifications > 0,
                  label: Text(tr(_systemUnreadNotifications > 99
                      ? '99+'
                      : '$_systemUnreadNotifications')),
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: PosTheme.textPrimary,
                  ),
                ),
              ),
              PosPendingPrintIconButton(
                pendingCount: _pendingPrintCount,
                onTap: _openPendingPrintQueue,
                iconColor: PosTheme.textPrimary,
                compact: true,
              ),
              ..._buildTopBarScreenActions(iconColor: PosTheme.textPrimary),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.menu, color: PosTheme.textPrimary),
                tooltip: tr('Menu'),
                onPressed: _openPosMenu,
              ),
            ],
          ),
        ),
        if (!tableMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: SizedBox(
              height: 34,
              child: ListView(
                controller: _tabScrollCtrl,
                scrollDirection: Axis.horizontal,
                children: [
                  if (_showFloorPlan) ...[
                    Material(
                      color: PosTheme.kiotBlueLight,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _openResourceFloor,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.table_restaurant_outlined,
                                  color: PosTheme.kiotBlue, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                tr((_tab.serviceResourceName ?? '').isNotEmpty
                                    ? _tab.serviceResourceName!
                                    : 'Bàn'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: PosTheme.kiotBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_industrySettings?.enableSessionPacks == true) ...[
                    if (_showFloorPlan) const SizedBox(width: 6),
                    Material(
                      color: PosTheme.kiotBlueLight,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _openSessionRedeem,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.confirmation_number_outlined,
                                  color: PosTheme.kiotBlue, size: 18),
                              SizedBox(width: 4),
                              Text(tr('Trừ buổi'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: PosTheme.kiotBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
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
    final tableMode = _isTableOrderMode;
    return Material(
      color: const Color(0xFFFAFBFC),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Row(
          children: [
            Expanded(
              flex: tableMode ? 2 : 1,
              child: FilledButton.icon(
                onPressed: _openMobileProductPicker,
                icon: Icon(
                  tableMode
                      ? Icons.restaurant_menu_rounded
                      : Icons.inventory_2_outlined,
                  size: 18,
                ),
                label: Text(
                  tr(tableMode ? 'Chọn món' : 'Hàng hóa'),
                  style: const TextStyle(fontSize: 14),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: PosTheme.kiotBlue,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            if (tableMode) ...[
              if (_industrySettings?.sellProfile ==
                  PosSellProfile.restaurant) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _kitchenActionCount == 0 ||
                            _kitchenSending ||
                            _checkingOut ||
                            _parking
                        ? null
                        : () => unawaited(_kitchenSendCurrentTable()),
                    icon: const Icon(Icons.soup_kitchen_outlined, size: 18),
                    label: Text(
                      tr(_kitchenActionCount == 0
                          ? 'Đã báo bếp'
                          : _kitchenCancelPendingCount > 0 &&
                                  _kitchenPendingLineCount == 0
                              ? 'Gửi hủy (${_kitchenCancelPendingCount})'
                              : _kitchenCancelPendingCount > 0
                                  ? 'Báo/hủy ($_kitchenActionCount)'
                                  : 'Báo bếp ($_kitchenPendingLineCount)'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      side: BorderSide(
                        color: _kitchenActionCount == 0
                            ? PosTheme.border
                            : const Color(0xFFB45309),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
              if (_printSettings.showCupLabelManualButton) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cupLabelPendingCount == 0
                        ? null
                        : () => unawaited(_printPendingCupLabels()),
                    icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                    label: Text(
                      tr(_cupLabelPendingCount > 0
                          ? 'Tem ($_cupLabelPendingCount)'
                          : 'Tem'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D9488),
                      side: BorderSide(
                        color: _cupLabelPendingCount == 0
                            ? PosTheme.border
                            : const Color(0xFF0D9488),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openMobileCameraScan,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(tr('Quét mã'), style: TextStyle(fontSize: 14)),
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
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSellCartBody() {
    if (_tab.cart.isEmpty) {
      if (_isTableOrderMode) {
        final table = (_tab.serviceResourceName ?? '').trim();
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restaurant_menu_rounded,
                    size: 56, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  tr(table.isEmpty ? 'Chưa có món' : '$table · chưa có món'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: PosTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(tr('Bấm «Chọn món» để thêm từ thực đơn.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _openMobileProductPicker,
                  icon: const Icon(Icons.restaurant_menu_rounded),
                  label: Text(tr('Chọn món')),
                  style: FilledButton.styleFrom(
                    backgroundColor: PosTheme.kiotBlue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_scanner_rounded,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(tr('Quét mã vạch để bán'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: PosTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(tr('Dùng nút Quét mã, máy quét cứng Sunmi, hoặc USB.\nChọn Hàng hóa để thêm thủ công.'),
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
    const payLabel = 'Thanh toán';
    return Material(
      elevation: 6,
      color: Colors.white,
      child: SafeArea(
        top: false,
        bottom: !inHub,
          child: Container(
          padding: EdgeInsets.fromLTRB(12, 6, 12, inHub ? 4 : 8),
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
                      tr(_tab.cart.isEmpty
                          ? 'Chưa có hàng'
                          : 'Tổng (${_tab.cart.length} món)'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                    Text(tr('${_moneyFmt.format(_grandTotal)} đ'),
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
                  tooltip: tr('Mã VietQR'),
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
                  height: 56,
                  child: FilledButton(
                    onPressed: _tab.cart.isEmpty || _checkingOut || _parking || !canPay
                        ? null
                        : () => _openMobilePaymentScreen(perm),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kiotBlue,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        tr(payLabel),
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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
    if (!_guardReadOnlyEdit()) return;
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
    _scheduleDraftAutosave();
  }

  Future<void> _openMobileLineNote(_SellCartLine line) async {
    if (!_guardReadOnlyEdit()) return;
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
                Text(tr('Ghi chú sản phẩm'),
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
                  onPressed: () {
                    _commitLineNote(line, scheduleSave: true);
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('OK')),
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
      cloned.toppings = [
        for (final t in line.toppings)
          _CartTopping(id: t.id, name: t.name, price: t.price),
      ];
      cloned.selectedQuickNotes
        ..clear()
        ..addAll(line.selectedQuickNotes);
      cloned.noteCtrl.text = line.noteCtrl.text;
      _tab.cart.insert(cartIndex + 1, cloned);
      _syncPaidAmount();
    });
    _scheduleDraftAutosave();
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
      final sameToppings = other.toppings.map((t) => '${t.id}:${t.price}').join('|') ==
          line.toppings.map((t) => '${t.id}:${t.price}').join('|');
      if (sameIdentity && sameNoteDiscount && sameToppings) {
        matches.add(i);
      }
    }
    if (matches.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không thể gộp',
        message: tr('Chỉ gộp được dòng cùng sản phẩm, ghi chú, topping và chiết khấu.'),
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
    _scheduleDraftAutosave();
  }

  Future<void> _openMobileCustomerPicker() async {
    final qCtrl = TextEditingController(text: tr(_tab._customerSearchCtrl.text));
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
                          Expanded(
                            child: Text(tr('Chọn khách hàng'),
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
                          hintText: tr('Tên, SĐT, mã khách...'),
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
                      title: Text(tr('Bán cho người tiêu dùng')),
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
                            title: Text(tr(c.name)),
                            subtitle: Text(
                              tr([c.phone, c.customerCode]
                                  .where((e) => e != null && e.isNotEmpty)
                                  .join(' · ')),
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

  Future<void> _openMobilePriceListPicker({VoidCallback? onMutate}) async {
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
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(tr('Chọn bảng giá'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            ...options.map(
              (pl) {
                final bits = <String>[
                  if (pl.isDefault) 'Mặc định',
                  if (pl.validFrom != null || pl.validTo != null)
                    '${pl.validFrom != null ? DateFormat('dd/MM').format(pl.validFrom!) : '…'}'
                        '→${pl.validTo != null ? DateFormat('dd/MM').format(pl.validTo!) : '…'}',
                ];
                return ListTile(
                  title: Text(tr(pl.name)),
                  subtitle: bits.isEmpty ? null : Text(tr(bits.join(' · '))),
                  trailing: _tab.priceListId == pl.id ||
                          (_tab.priceListId == null &&
                              _tab.priceListLabel == pl.name)
                      ? const Icon(Icons.check, color: _kiotBlue)
                      : null,
                  onTap: () async {
                    // Áp bảng giá XONG rồi mới đóng sheet — tránh race
                    // setPay rebuild khi giá/tổng chưa đổi.
                    if (pl.id.isNotEmpty) {
                      await _selectPriceList(pl, onMutate: onMutate);
                    } else {
                      await _clearPriceListSelection(
                          label: pl.name, onMutate: onMutate);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                );
              },
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
                      tr(title),
                      style: const TextStyle(
                        fontSize: 13,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                    Text(
                      tr(value),
                      style: const TextStyle(
                        fontSize: 15,
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
    final canPay = perm.canPosPay();
    var paying = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: Text(tr('Thanh toán')),
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
                          value: _tab.customer?.name ?? 'Bán cho người tiêu dùng',
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
                                  await _openMobilePriceListPicker(
                                      onMutate: () => setPay(() {}));
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
                        canOrder: perm.canPosOrder(),
                        busy: busy ||
                            _parking ||
                            _provisionalPrinting ||
                            _kitchenSending,
                        completeLabel: 'Hoàn thành',
                        completeFontSize: 17,
                        onPrintChipChanged: () => setPay(() {}),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showMobileCartLineActions(line, cartIndex),
        child: Container(
          decoration: PosTheme.mobileCardDecoration(),
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PosProductImage(
                    productId: line.product.id,
                    imageUrl: line.product.imageUrl,
                    updatedAt: line.product.updatedAt,
                    size: 42,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(line.product.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(tr('${_moneyFmt.format(line.unitPrice)} đ/${line.unitLabel}'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kiotBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Thêm chức năng'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _showMobileCartLineActions(line, cartIndex),
                    icon: const Icon(Icons.more_horiz, size: 22),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 2),
                    child: Material(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => _removeLine(cartIndex),
                        borderRadius: BorderRadius.circular(10),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.delete_rounded,
                            size: 22,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (hasDiscount ||
                  hasNote ||
                  line.toppings.isNotEmpty ||
                  _isTableOrderMode) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    if (hasDiscount)
                      Text(
                        tr('CK -${_moneyFmt.format(line.discountAmount)}'),
                        style:
                            TextStyle(fontSize: 12, color: Colors.red.shade700),
                      ),
                    if (hasNote)
                      Text(
                        tr('↳ ${line.lineNote}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: _kiotBlue),
                      ),
                    if (line.toppings.isNotEmpty)
                      Text(
                        tr('↳ ${line.toppings.map((t) => '${t.name} (+${_moneyFmt.format(t.price)})').join(', ')}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    if (_isTableOrderMode && line.kitchenFullySent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(tr('Đã báo bếp'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF047857),
                          ),
                        ),
                      )
                    else if (_isTableOrderMode && line.kitchenPendingQty > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tr(line.kitchenSentQty > 0
                              ? 'Mới +${_qtyFmt.format(line.kitchenPendingQty)}'
                              : 'Chưa báo bếp'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
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
                      tr(_qtyFmt.format(line.qty)),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
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
                  Text(tr('${_moneyFmt.format(line.lineTotal)} đ'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: PosTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMobileCartLineActions(
      _SellCartLine line, int cartIndex) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  tr(line.product.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _mobileLineActionTile(
                  icon: Icons.notes_outlined,
                  label: 'Ghi chú',
                  onTap: () => Navigator.pop(ctx, 'note'),
                ),
                if (line.product.allowToppings || line.product.hasToppingGroups)
                  _mobileLineActionTile(
                    icon: Icons.add_circle_outline,
                    label: line.product.hasToppingGroups
                        ? (line.toppings.isEmpty
                            ? 'Chọn topping'
                            : 'Topping (${line.toppings.length})')
                        : (line.toppings.isEmpty
                            ? 'Tùy chọn thêm'
                            : 'Tùy chọn (${line.toppings.length})'),
                    onTap: () => Navigator.pop(ctx, 'topping'),
                  ),
                _mobileLineActionTile(
                  icon: Icons.discount_outlined,
                  label: 'Chiết khấu',
                  onTap: () => Navigator.pop(ctx, 'discount'),
                ),
                _mobileLineActionTile(
                  icon: Icons.call_split_outlined,
                  label: 'Tách dòng',
                  enabled: line.qty > 1,
                  onTap: () => Navigator.pop(ctx, 'split'),
                ),
                _mobileLineActionTile(
                  icon: Icons.merge_type_outlined,
                  label: 'Gộp dòng',
                  onTap: () => Navigator.pop(ctx, 'merge'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'delete'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.delete_rounded, size: 22),
                    label: Text(tr('Xóa khỏi hóa đơn'),
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'note':
        await _openMobileLineNote(line);
      case 'topping':
        await _openCartLineToppings(line);
      case 'discount':
        await _openMobileLineDiscount(line);
      case 'split':
        if (line.qty > 1) _splitMobileCartLine(cartIndex);
      case 'merge':
        _mergeMobileCartLine(cartIndex);
      case 'delete':
        await _removeLine(cartIndex);
    }
  }

  Future<void> _openCartLineToppings(_SellCartLine line) async {
    var options = line.product.toppingGroupItems;
    if (options.isEmpty) {
      options = line.product.toppingOptions;
    }
    if (options.isEmpty &&
        (line.product.allowToppings || line.product.toppingGroupIds.isNotEmpty)) {
      final res = await _api.getPosProduct(line.product.id);
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
        final fresh =
            PosProduct.fromJson(res['data'] as Map<String, dynamic>);
        line.product = fresh;
        options = fresh.toppingGroupItems.isNotEmpty
            ? fresh.toppingGroupItems
            : fresh.toppingOptions;
      }
    }
    if (options.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa có topping',
        message: tr('Gắn nhóm topping hoặc tùy chọn thêm trong hàng hóa'),
      );
      return;
    }
    final selected = <String>{for (final t in line.toppings) t.id};
    final confirmed = await showModalBottomSheet<List<_CartTopping>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('Topping — ${line.product.name}'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: options.map((o) {
                          final on = selected.contains(o.toppingProductId);
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: on,
                            title: Text(tr(o.toppingProductName)),
                            subtitle: Text(tr('+${_moneyFmt.format(o.extraPrice)} đ'),
                              style: const TextStyle(color: _kiotBlue),
                            ),
                            onChanged: (v) {
                              setModal(() {
                                if (v == true) {
                                  selected.add(o.toppingProductId);
                                } else {
                                  selected.remove(o.toppingProductId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () {
                        final picks = options
                            .where((o) => selected.contains(o.toppingProductId))
                            .map((o) => _CartTopping(
                                  id: o.toppingProductId,
                                  name: o.toppingProductName,
                                  price: o.extraPrice,
                                ))
                            .toList();
                        Navigator.pop(ctx, picks);
                      },
                      child: Text(tr('Xong')),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted || confirmed == null) return;
    setState(() {
      final extraIds = {
        for (final o in line.product.toppingOptions) o.toppingProductId
      };
      final keptExtras = [
        for (final t in line.toppings)
          if (extraIds.contains(t.id) && !confirmed.any((c) => c.id == t.id)) t,
      ];
      line.toppings = [...keptExtras, ...confirmed];
      _syncPaidAmount();
    });
    _scheduleDraftAutosave();
    _scheduleCustomerDisplayPublish();
  }

  Widget _mobileLineActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return ListTile(
      enabled: enabled,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: enabled ? PosTheme.textPrimary : Colors.grey),
      title: Text(
        tr(label),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: enabled ? PosTheme.textPrimary : Colors.grey,
        ),
      ),
      onTap: enabled ? onTap : null,
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
          ? _kiotBlue.withOpacity(0.1)
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
                        decoration: InputDecoration(
                          hintText: tr('Ghi chú đơn hàng'),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (v) {
                          _tab.note = v.trim().isEmpty ? null : v;
                        },
                        onEditingComplete: () => _scheduleDraftAutosave(),
                        onSubmitted: (_) => _scheduleDraftAutosave(),
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
              tr(label),
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
