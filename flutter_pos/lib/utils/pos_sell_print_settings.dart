import 'package:shared_preferences/shared_preferences.dart';

import 'pos_thermal_printer_settings.dart';

/// Chế độ in phiếu báo xuất kho trên màn bán hàng.
enum PosWarehousePrintMode {
  off,
  auto,
  manual;

  String get label => switch (this) {
        PosWarehousePrintMode.off => 'Không in',
        PosWarehousePrintMode.auto => 'Tự động sau thanh toán',
        PosWarehousePrintMode.manual => 'In thủ công (nút Báo kho)',
      };

  static PosWarehousePrintMode fromStored(String? raw) => switch (raw) {
        'auto' => PosWarehousePrintMode.auto,
        'manual' => PosWarehousePrintMode.manual,
        _ => PosWarehousePrintMode.off,
      };

  String get storageValue => switch (this) {
        PosWarehousePrintMode.off => 'off',
        PosWarehousePrintMode.auto => 'auto',
        PosWarehousePrintMode.manual => 'manual',
      };
}

/// In tem dán ly (trà sữa): tên, topping, SL, giờ, bàn — in 1 lần như báo bếp.
enum PosCupLabelPrintMode {
  off,
  manual,
  withKitchen,
  onCheckout;

  String get label => switch (this) {
        PosCupLabelPrintMode.off => 'Không in tem ly',
        PosCupLabelPrintMode.manual => 'In thủ công (nút Tem ly)',
        PosCupLabelPrintMode.withKitchen => 'Tự in khi báo bếp (+ nút Tem ly)',
        PosCupLabelPrintMode.onCheckout =>
          'Tự in khi thanh toán (+ nút Tem ly)',
      };

  static PosCupLabelPrintMode fromStored(String? raw) => switch (raw) {
        'manual' => PosCupLabelPrintMode.manual,
        'withKitchen' => PosCupLabelPrintMode.withKitchen,
        'onCheckout' => PosCupLabelPrintMode.onCheckout,
        _ => PosCupLabelPrintMode.off,
      };

  String get storageValue => switch (this) {
        PosCupLabelPrintMode.off => 'off',
        PosCupLabelPrintMode.manual => 'manual',
        PosCupLabelPrintMode.withKitchen => 'withKitchen',
        PosCupLabelPrintMode.onCheckout => 'onCheckout',
      };

  bool get enabled => this != PosCupLabelPrintMode.off;
  bool get showManualButton => enabled;
  bool get autoWithKitchen => this == PosCupLabelPrintMode.withKitchen;
  bool get autoOnCheckout => this == PosCupLabelPrintMode.onCheckout;
}

@Deprecated('Use PosWarehousePrintMode')
typedef PosKitchenPrintMode = PosWarehousePrintMode;

/// Thiết lập in hóa đơn trên màn bán hàng (lưu local).
class PosSellPrintSettings {
  const PosSellPrintSettings({
    this.autoPrint = false,
    this.printCupOnCheckout = false,
    this.mergeSameItems = true,
    this.copies = 1,
    this.templateId,
    this.warehouseTemplateId,
    this.printVietQrOnReceipt = false,
    this.warehousePrintMode = PosWarehousePrintMode.off,
    this.cupLabelPrintMode = PosCupLabelPrintMode.off,
  });

  /// In hóa đơn khi thanh toán (thiết lập cố định).
  final bool autoPrint;

  /// In tem ly khi thanh toán — độc lập với [autoPrint] và chế độ tem.
  final bool printCupOnCheckout;

  final bool mergeSameItems;
  final int copies;

  /// Id mẫu in hóa đơn từ server (null = mẫu mặc định).
  final String? templateId;

  /// Id mẫu in phiếu báo xuất kho.
  final String? warehouseTemplateId;

  /// In mã VietQR (số tiền đơn) trên hóa đơn nhiệt/PDF.
  final bool printVietQrOnReceipt;

  /// Phiếu báo xuất kho.
  final PosWarehousePrintMode warehousePrintMode;

  /// Tem dán ly (trà sữa).
  final PosCupLabelPrintMode cupLabelPrintMode;

  bool get showWarehouseManualButton =>
      warehousePrintMode == PosWarehousePrintMode.manual;

  bool get showCupLabelManualButton =>
      cupLabelPrintMode.showManualButton || printCupOnCheckout;

  /// In tem khi TT: cờ riêng hoặc chế độ onCheckout.
  bool get shouldPrintCupOnPay =>
      printCupOnCheckout || cupLabelPrintMode.autoOnCheckout;

  @Deprecated('Use warehousePrintMode')
  PosWarehousePrintMode get kitchenPrintMode => warehousePrintMode;

  @Deprecated('Use showWarehouseManualButton')
  bool get showKitchenManualButton => showWarehouseManualButton;

  static const _kAuto = 'pos_sell_print_auto';
  static const _kCupOnPay = 'pos_sell_print_cup_on_checkout';
  static const _kMerge = 'pos_sell_print_merge';
  static const _kCopies = 'pos_sell_print_copies';
  static const _kTemplate = 'pos_sell_print_template_id';
  static const _kWarehouseTemplate = 'pos_sell_warehouse_print_template_id';
  static const _kPrintVietQr = 'pos_sell_print_vietqr';
  static const _kWarehouseMode = 'pos_sell_kitchen_print_mode';
  static const _kCupLabelMode = 'pos_sell_cup_label_print_mode';

  PosSellPrintSettings copyWith({
    bool? autoPrint,
    bool? printCupOnCheckout,
    bool? mergeSameItems,
    int? copies,
    String? templateId,
    String? warehouseTemplateId,
    bool clearTemplateId = false,
    bool clearWarehouseTemplateId = false,
    bool? printVietQrOnReceipt,
    PosWarehousePrintMode? warehousePrintMode,
    PosWarehousePrintMode? kitchenPrintMode,
    PosCupLabelPrintMode? cupLabelPrintMode,
  }) =>
      PosSellPrintSettings(
        autoPrint: autoPrint ?? this.autoPrint,
        printCupOnCheckout: printCupOnCheckout ?? this.printCupOnCheckout,
        mergeSameItems: mergeSameItems ?? this.mergeSameItems,
        copies: copies ?? this.copies,
        templateId: clearTemplateId ? null : (templateId ?? this.templateId),
        warehouseTemplateId: clearWarehouseTemplateId
            ? null
            : (warehouseTemplateId ?? this.warehouseTemplateId),
        printVietQrOnReceipt: printVietQrOnReceipt ?? this.printVietQrOnReceipt,
        warehousePrintMode:
            warehousePrintMode ?? kitchenPrintMode ?? this.warehousePrintMode,
        cupLabelPrintMode: cupLabelPrintMode ?? this.cupLabelPrintMode,
      );

  static Future<PosSellPrintSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = prefs.getString(_kTemplate);
    final wtid = prefs.getString(_kWarehouseTemplate);
    // Lần đầu chưa chọn: bật tự động in nếu đã cấu hình máy in nhiệt local.
    late final bool autoPrint;
    if (prefs.containsKey(_kAuto)) {
      autoPrint = prefs.getBool(_kAuto) ?? false;
    } else {
      try {
        final thermal = await PosThermalPrinterSettings.load();
        autoPrint = thermal.enabled;
      } catch (_) {
        autoPrint = false;
      }
    }
    final cupMode =
        PosCupLabelPrintMode.fromStored(prefs.getString(_kCupLabelMode));
    // Cờ riêng; nếu prefs chưa có mà mode = onCheckout → coi như bật.
    final printCupOnCheckout = prefs.containsKey(_kCupOnPay)
        ? (prefs.getBool(_kCupOnPay) ?? false)
        : cupMode.autoOnCheckout;
    return PosSellPrintSettings(
      autoPrint: autoPrint,
      printCupOnCheckout: printCupOnCheckout,
      mergeSameItems: prefs.getBool(_kMerge) ?? true,
      copies: (prefs.getInt(_kCopies) ?? 1).clamp(1, 10),
      templateId: tid != null && tid.isNotEmpty ? tid : null,
      warehouseTemplateId: wtid != null && wtid.isNotEmpty ? wtid : null,
      printVietQrOnReceipt: prefs.getBool(_kPrintVietQr) ?? false,
      warehousePrintMode:
          PosWarehousePrintMode.fromStored(prefs.getString(_kWarehouseMode)),
      cupLabelPrintMode: cupMode,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuto, autoPrint);
    await prefs.setBool(_kCupOnPay, printCupOnCheckout);
    await prefs.setBool(_kMerge, mergeSameItems);
    await prefs.setInt(_kCopies, copies.clamp(1, 10));
    await prefs.setBool(_kPrintVietQr, printVietQrOnReceipt);
    await prefs.setString(_kWarehouseMode, warehousePrintMode.storageValue);
    await prefs.setString(_kCupLabelMode, cupLabelPrintMode.storageValue);
    if (templateId != null && templateId!.isNotEmpty) {
      await prefs.setString(_kTemplate, templateId!);
    } else {
      await prefs.remove(_kTemplate);
    }
    if (warehouseTemplateId != null && warehouseTemplateId!.isNotEmpty) {
      await prefs.setString(_kWarehouseTemplate, warehouseTemplateId!);
    } else {
      await prefs.remove(_kWarehouseTemplate);
    }
  }
}
