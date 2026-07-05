import 'package:shared_preferences/shared_preferences.dart';

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

@Deprecated('Use PosWarehousePrintMode')
typedef PosKitchenPrintMode = PosWarehousePrintMode;

/// Thiết lập in hóa đơn trên màn bán hàng (lưu local).
class PosSellPrintSettings {
  const PosSellPrintSettings({
    this.autoPrint = false,
    this.mergeSameItems = true,
    this.copies = 1,
    this.templateId,
    this.warehouseTemplateId,
    this.printVietQrOnReceipt = false,
    this.warehousePrintMode = PosWarehousePrintMode.off,
  });

  final bool autoPrint;
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

  bool get showWarehouseManualButton =>
      warehousePrintMode == PosWarehousePrintMode.manual;

  @Deprecated('Use warehousePrintMode')
  PosWarehousePrintMode get kitchenPrintMode => warehousePrintMode;

  @Deprecated('Use showWarehouseManualButton')
  bool get showKitchenManualButton => showWarehouseManualButton;

  static const _kAuto = 'pos_sell_print_auto';
  static const _kMerge = 'pos_sell_print_merge';
  static const _kCopies = 'pos_sell_print_copies';
  static const _kTemplate = 'pos_sell_print_template_id';
  static const _kWarehouseTemplate = 'pos_sell_warehouse_print_template_id';
  static const _kPrintVietQr = 'pos_sell_print_vietqr';
  static const _kWarehouseMode = 'pos_sell_kitchen_print_mode';

  PosSellPrintSettings copyWith({
    bool? autoPrint,
    bool? mergeSameItems,
    int? copies,
    String? templateId,
    String? warehouseTemplateId,
    bool clearTemplateId = false,
    bool clearWarehouseTemplateId = false,
    bool? printVietQrOnReceipt,
    PosWarehousePrintMode? warehousePrintMode,
    PosWarehousePrintMode? kitchenPrintMode,
  }) =>
      PosSellPrintSettings(
        autoPrint: autoPrint ?? this.autoPrint,
        mergeSameItems: mergeSameItems ?? this.mergeSameItems,
        copies: copies ?? this.copies,
        templateId: clearTemplateId ? null : (templateId ?? this.templateId),
        warehouseTemplateId: clearWarehouseTemplateId
            ? null
            : (warehouseTemplateId ?? this.warehouseTemplateId),
        printVietQrOnReceipt: printVietQrOnReceipt ?? this.printVietQrOnReceipt,
        warehousePrintMode:
            warehousePrintMode ?? kitchenPrintMode ?? this.warehousePrintMode,
      );

  static Future<PosSellPrintSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = prefs.getString(_kTemplate);
    final wtid = prefs.getString(_kWarehouseTemplate);
    return PosSellPrintSettings(
      autoPrint: prefs.getBool(_kAuto) ?? false,
      mergeSameItems: prefs.getBool(_kMerge) ?? true,
      copies: (prefs.getInt(_kCopies) ?? 1).clamp(1, 10),
      templateId: tid != null && tid.isNotEmpty ? tid : null,
      warehouseTemplateId: wtid != null && wtid.isNotEmpty ? wtid : null,
      printVietQrOnReceipt: prefs.getBool(_kPrintVietQr) ?? false,
      warehousePrintMode:
          PosWarehousePrintMode.fromStored(prefs.getString(_kWarehouseMode)),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuto, autoPrint);
    await prefs.setBool(_kMerge, mergeSameItems);
    await prefs.setInt(_kCopies, copies.clamp(1, 10));
    await prefs.setBool(_kPrintVietQr, printVietQrOnReceipt);
    await prefs.setString(_kWarehouseMode, warehousePrintMode.storageValue);
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
