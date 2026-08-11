import 'package:shared_preferences/shared_preferences.dart';

import 'pos_barcode_print.dart';
import 'pos_thermal_printer_settings.dart';

/// Giao thức máy in tem nhãn.
enum PosLabelPrinterProtocol {
  tspl('tspl', 'TSPL (Xprinter, TSC, Zywell tem)'),
  escpos('escpos', 'ESC/POS raster');

  const PosLabelPrinterProtocol(this.key, this.label);
  final String key;
  final String label;

  static PosLabelPrinterProtocol fromKey(String? key) {
    return PosLabelPrinterProtocol.values.firstWhere(
      (e) => e.key == key,
      orElse: () => PosLabelPrinterProtocol.tspl,
    );
  }
}

/// Thiết lập máy in tem nhãn (lưu local).
class PosLabelPrinterSettings {
  const PosLabelPrinterSettings({
    this.enabled = false,
    this.connectionType = PosThermalConnectionType.bluetooth,
    this.protocol = PosLabelPrinterProtocol.tspl,
    this.templateId = 'roll_1_50x30',
    this.dpi = 203,
    this.gapMm = 2.0,
    /// Lề trái (mm) — bù tem lệch trái trên nhiều máy 50×30.
    this.marginLeftMm = 3.0,
    this.marginRightMm = 2.0,
    this.marginTopMm = 2.0,
    this.marginBottomMm = 2.0,
    this.fontScale = 1.2,
    this.showHeader = true,
    this.showTable = true,
    this.showOrderNo = true,
    this.showToppings = true,
    this.showNote = true,
    this.showQty = true,
    this.bluetoothAddress,
    this.bluetoothName,
    this.lanHost,
    this.lanPort = 9100,
    this.usbDeviceName,
  });

  final bool enabled;
  final PosThermalConnectionType connectionType;
  final PosLabelPrinterProtocol protocol;
  /// ID khớp [posBarcodeLabelTemplates].
  final String templateId;
  final int dpi;
  final double gapMm;
  final double marginLeftMm;
  final double marginRightMm;
  final double marginTopMm;
  final double marginBottomMm;
  final double fontScale;
  final bool showHeader;
  final bool showTable;
  final bool showOrderNo;
  final bool showToppings;
  final bool showNote;
  final bool showQty;
  final String? bluetoothAddress;
  final String? bluetoothName;
  final String? lanHost;
  final int lanPort;
  final String? usbDeviceName;

  /// Alias cũ — dùng [marginLeftMm].
  double get shiftRightMm => marginLeftMm;

  static const _kEnabled = 'pos_label_enabled';
  static const _kType = 'pos_label_conn_type';
  static const _kProtocol = 'pos_label_protocol';
  static const _kTemplate = 'pos_label_template_id';
  static const _kDpi = 'pos_label_dpi';
  static const _kGap = 'pos_label_gap_mm';
  static const _kMarginL = 'pos_label_margin_left_mm';
  static const _kMarginR = 'pos_label_margin_right_mm';
  static const _kMarginT = 'pos_label_margin_top_mm';
  static const _kMarginB = 'pos_label_margin_bottom_mm';
  static const _kFontScale = 'pos_label_font_scale';
  static const _kShowHeader = 'pos_label_show_header';
  static const _kShowTable = 'pos_label_show_table';
  static const _kShowOrder = 'pos_label_show_order';
  static const _kShowToppings = 'pos_label_show_toppings';
  static const _kShowNote = 'pos_label_show_note';
  static const _kShowQty = 'pos_label_show_qty';
  static const _kShiftRight = 'pos_label_shift_right_mm'; // legacy
  static const _kBtAddr = 'pos_label_bt_addr';
  static const _kBtName = 'pos_label_bt_name';
  static const _kLanHost = 'pos_label_lan_host';
  static const _kLanPort = 'pos_label_lan_port';
  static const _kUsbName = 'pos_label_usb_name';

  PosBarcodeLabelTemplate? get template =>
      posBarcodeLabelTemplateById(templateId);

  PosLabelPrinterSettings copyWith({
    bool? enabled,
    PosThermalConnectionType? connectionType,
    PosLabelPrinterProtocol? protocol,
    String? templateId,
    int? dpi,
    double? gapMm,
    double? marginLeftMm,
    double? marginRightMm,
    double? marginTopMm,
    double? marginBottomMm,
    double? fontScale,
    bool? showHeader,
    bool? showTable,
    bool? showOrderNo,
    bool? showToppings,
    bool? showNote,
    bool? showQty,
    double? shiftRightMm,
    String? bluetoothAddress,
    String? bluetoothName,
    String? lanHost,
    int? lanPort,
    String? usbDeviceName,
    bool clearBluetooth = false,
    bool clearLan = false,
    bool clearUsb = false,
  }) =>
      PosLabelPrinterSettings(
        enabled: enabled ?? this.enabled,
        connectionType: connectionType ?? this.connectionType,
        protocol: protocol ?? this.protocol,
        templateId: templateId ?? this.templateId,
        dpi: dpi ?? this.dpi,
        gapMm: gapMm ?? this.gapMm,
        marginLeftMm: marginLeftMm ?? shiftRightMm ?? this.marginLeftMm,
        marginRightMm: marginRightMm ?? this.marginRightMm,
        marginTopMm: marginTopMm ?? this.marginTopMm,
        marginBottomMm: marginBottomMm ?? this.marginBottomMm,
        fontScale: fontScale ?? this.fontScale,
        showHeader: showHeader ?? this.showHeader,
        showTable: showTable ?? this.showTable,
        showOrderNo: showOrderNo ?? this.showOrderNo,
        showToppings: showToppings ?? this.showToppings,
        showNote: showNote ?? this.showNote,
        showQty: showQty ?? this.showQty,
        bluetoothAddress:
            clearBluetooth ? null : (bluetoothAddress ?? this.bluetoothAddress),
        bluetoothName:
            clearBluetooth ? null : (bluetoothName ?? this.bluetoothName),
        lanHost: clearLan ? null : (lanHost ?? this.lanHost),
        lanPort: lanPort ?? this.lanPort,
        usbDeviceName: clearUsb ? null : (usbDeviceName ?? this.usbDeviceName),
      );

  static Future<PosLabelPrinterSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyShift = prefs.getDouble(_kShiftRight);
    return PosLabelPrinterSettings(
      enabled: prefs.getBool(_kEnabled) ?? false,
      connectionType: PosThermalConnectionType.coerceForPlatform(
        PosThermalConnectionType.fromKey(prefs.getString(_kType)),
      ),
      protocol: PosLabelPrinterProtocol.fromKey(prefs.getString(_kProtocol)),
      templateId: prefs.getString(_kTemplate) ?? 'roll_1_50x30',
      dpi: prefs.getInt(_kDpi) ?? 203,
      gapMm: prefs.getDouble(_kGap) ?? 2.0,
      marginLeftMm: prefs.getDouble(_kMarginL) ?? legacyShift ?? 3.0,
      marginRightMm: prefs.getDouble(_kMarginR) ?? 2.0,
      marginTopMm: prefs.getDouble(_kMarginT) ?? 2.0,
      marginBottomMm: prefs.getDouble(_kMarginB) ?? 2.0,
      fontScale: prefs.getDouble(_kFontScale) ?? 1.2,
      showHeader: prefs.getBool(_kShowHeader) ?? true,
      showTable: prefs.getBool(_kShowTable) ?? true,
      showOrderNo: prefs.getBool(_kShowOrder) ?? true,
      showToppings: prefs.getBool(_kShowToppings) ?? true,
      showNote: prefs.getBool(_kShowNote) ?? true,
      showQty: prefs.getBool(_kShowQty) ?? true,
      bluetoothAddress: prefs.getString(_kBtAddr),
      bluetoothName: prefs.getString(_kBtName),
      lanHost: prefs.getString(_kLanHost),
      lanPort: prefs.getInt(_kLanPort) ?? 9100,
      usbDeviceName: prefs.getString(_kUsbName),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    await prefs.setString(_kType, connectionType.key);
    await prefs.setString(_kProtocol, protocol.key);
    await prefs.setString(_kTemplate, templateId);
    await prefs.setInt(_kDpi, dpi);
    await prefs.setDouble(_kGap, gapMm);
    await prefs.setDouble(_kMarginL, marginLeftMm);
    await prefs.setDouble(_kMarginR, marginRightMm);
    await prefs.setDouble(_kMarginT, marginTopMm);
    await prefs.setDouble(_kMarginB, marginBottomMm);
    await prefs.setDouble(_kFontScale, fontScale);
    await prefs.setBool(_kShowHeader, showHeader);
    await prefs.setBool(_kShowTable, showTable);
    await prefs.setBool(_kShowOrder, showOrderNo);
    await prefs.setBool(_kShowToppings, showToppings);
    await prefs.setBool(_kShowNote, showNote);
    await prefs.setBool(_kShowQty, showQty);
    await prefs.setDouble(_kShiftRight, marginLeftMm);
    if (bluetoothAddress != null && bluetoothAddress!.isNotEmpty) {
      await prefs.setString(_kBtAddr, bluetoothAddress!);
    } else {
      await prefs.remove(_kBtAddr);
    }
    if (bluetoothName != null && bluetoothName!.isNotEmpty) {
      await prefs.setString(_kBtName, bluetoothName!);
    } else {
      await prefs.remove(_kBtName);
    }
    if (lanHost != null && lanHost!.isNotEmpty) {
      await prefs.setString(_kLanHost, lanHost!);
    } else {
      await prefs.remove(_kLanHost);
    }
    await prefs.setInt(_kLanPort, lanPort);
    if (usbDeviceName != null && usbDeviceName!.isNotEmpty) {
      await prefs.setString(_kUsbName, usbDeviceName!);
    } else {
      await prefs.remove(_kUsbName);
    }
  }
}
