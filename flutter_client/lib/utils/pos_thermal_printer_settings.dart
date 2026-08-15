import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Hãng / dòng máy in nhiệt.
enum PosThermalPrinterBrand {
  generic('generic', 'ESC/POS chung'),
  zywell('zywell', 'Zywell'),
  xprinter('xprinter', 'Xprinter'),
  epson('epson', 'Epson'),
  sunmi('sunmi', 'Sunmi'),
  hprt('hprt', 'HPRT'),
  rp80('rp80', 'RP80 / Rongta');

  const PosThermalPrinterBrand(this.key, this.label);
  final String key;
  final String label;

  static PosThermalPrinterBrand fromKey(String? key) {
    return PosThermalPrinterBrand.values.firstWhere(
      (e) => e.key == key,
      orElse: () => PosThermalPrinterBrand.generic,
    );
  }
}

/// Cách gửi chữ tiếng Việt ra máy in.
enum PosThermalTextMode {
  auto('auto', 'Tự động (khuyến nghị)'),
  image('image', 'In ảnh — tiếng Việt chuẩn'),
  tcvn3('tcvn3', 'ESC/POS TCVN-3'),
  cp1258('cp1258', 'ESC/POS CP1258'),
  utf8('utf8', 'ESC/POS UTF-8'),
  ascii('ascii', 'Không dấu (ASCII)');

  const PosThermalTextMode(this.key, this.label);
  final String key;
  final String label;

  static PosThermalTextMode fromKey(String? key) {
    return PosThermalTextMode.values.firstWhere(
      (e) => e.key == key,
      orElse: () => PosThermalTextMode.auto,
    );
  }
}

/// Loại kết nối máy in nhiệt POS mobile.
///
/// iOS (A7 / HRM): chỉ Bluetooth + LAN — USB OTG / Sunmi dành cho Android POS (A6).
enum PosThermalConnectionType {
  bluetooth('bluetooth', 'Bluetooth'),
  lan('lan', 'LAN / WiFi'),
  usb('usb', 'USB'),
  sunmi('sunmi', 'Máy in Sunmi');

  const PosThermalConnectionType(this.key, this.label);
  final String key;
  final String label;

  static bool get _isIos => !kIsWeb && Platform.isIOS;

  /// Kết nối dùng được trên thiết bị hiện tại.
  bool get isAvailableOnThisDevice {
    if (kIsWeb) return this == lan;
    if (_isIos) {
      return this == bluetooth || this == lan;
    }
    return true;
  }

  /// Danh sách chọn UI — [includeSunmi] chỉ khi máy Android Sunmi.
  static List<PosThermalConnectionType> availableOnThisDevice({
    bool includeSunmi = false,
  }) {
    if (kIsWeb) return const [lan];
    if (_isIos) return const [bluetooth, lan];
    return [
      bluetooth,
      lan,
      usb,
      if (includeSunmi) sunmi,
    ];
  }

  static PosThermalConnectionType coerceForPlatform(
    PosThermalConnectionType type,
  ) {
    if (type.isAvailableOnThisDevice) return type;
    return bluetooth;
  }

  static PosThermalConnectionType fromKey(String? key) {
    return PosThermalConnectionType.values.firstWhere(
      (e) => e.key == key,
      orElse: () => PosThermalConnectionType.bluetooth,
    );
  }
}

/// Thiết lập máy in nhiệt (lưu local theo cửa hàng).
class PosThermalPrinterSettings {
  const PosThermalPrinterSettings({
    this.enabled = false,
    this.connectionType = PosThermalConnectionType.bluetooth,
    this.printerBrand = PosThermalPrinterBrand.zywell,
    this.textMode = PosThermalTextMode.auto,
    this.paperSize = 'K80',
    this.bluetoothAddress,
    this.bluetoothName,
    this.lanHost,
    this.lanPort = 9100,
    this.usbDeviceName,
    this.escPosCodePage = 27,
    this.feedBeforeCut = 5,
    this.partialCut = true,
    this.cutPerItem = false,
    this.openCashDrawer = false,
    this.openDrawerCashOnly = true,
    this.beepOnPrint = false,
  });

  final bool enabled;
  final PosThermalConnectionType connectionType;
  final PosThermalPrinterBrand printerBrand;
  final PosThermalTextMode textMode;

  /// K58 hoặc K80
  final String paperSize;
  final String? bluetoothAddress;
  final String? bluetoothName;
  final String? lanHost;
  final int lanPort;
  final String? usbDeviceName;

  /// Code page ESC t n khi dùng CP1258 (mặc định 27).
  final int escPosCodePage;

  /// Số dòng giấy trống trước khi cắt (tránh cắt mất dòng cuối).
  final int feedBeforeCut;
  final bool partialCut;
  final bool cutPerItem;

  /// Gửi lệnh mở két (ESC p / SunmiDrawer) khi in hóa đơn.
  final bool openCashDrawer;

  /// Chỉ mở két khi thanh toán tiền mặt.
  final bool openDrawerCashOnly;

  /// Gửi lệnh bip loa máy in khi in.
  final bool beepOnPrint;

  static const _kEnabled = 'pos_thermal_enabled';
  static const _kType = 'pos_thermal_type';
  static const _kBrand = 'pos_thermal_brand';
  static const _kTextMode = 'pos_thermal_text_mode';
  static const _kPaper = 'pos_thermal_paper';
  static const _kBtAddr = 'pos_thermal_bt_addr';
  static const _kBtName = 'pos_thermal_bt_name';
  static const _kLanHost = 'pos_thermal_lan_host';
  static const _kLanPort = 'pos_thermal_lan_port';
  static const _kUsbName = 'pos_thermal_usb_name';
  static const _kCodePage = 'pos_thermal_esc_code_page';
  static const _kFeedCut = 'pos_thermal_feed_before_cut';
  static const _kPartialCut = 'pos_thermal_partial_cut';
  static const _kOpenDrawer = 'pos_thermal_open_cash_drawer';
  static const _kOpenDrawerCashOnly = 'pos_thermal_open_drawer_cash_only';
  static const _kBeepOnPrint = 'pos_thermal_beep_on_print';

  int get paperWidthMm {
    final p = paperSize.trim().toUpperCase();
    if (p == 'K58' || p == '58' || p.contains('58MM') || p == '58MM') {
      return 58;
    }
    return 80;
  }

  /// Chế độ in chữ thực tế sau khi áp dụng auto + hãng máy.
  PosThermalTextMode get resolvedTextMode {
    if (textMode != PosThermalTextMode.auto) return textMode;
    switch (printerBrand) {
      case PosThermalPrinterBrand.zywell:
      case PosThermalPrinterBrand.xprinter:
      case PosThermalPrinterBrand.hprt:
      case PosThermalPrinterBrand.rp80:
      case PosThermalPrinterBrand.generic:
        return PosThermalTextMode.image;
      case PosThermalPrinterBrand.epson:
        return PosThermalTextMode.utf8;
      case PosThermalPrinterBrand.sunmi:
        return PosThermalTextMode.utf8;
    }
  }

  /// Số dòng đẩy giấy trước khi cắt.
  /// 0 = tắt feed. Giá trị thấp (kể cả default cũ = 1) được nâng sàn theo hãng
  /// vì lưỡi cắt nằm sau đầu in — thiếu feed → cắt mất phần món phía dưới.
  int get resolvedFeedBeforeCut {
    final n = feedBeforeCut.clamp(0, 40);
    if (n == 0) return 0;
    const usbFloor = 5;
    switch (printerBrand) {
      case PosThermalPrinterBrand.zywell:
      case PosThermalPrinterBrand.xprinter:
      case PosThermalPrinterBrand.hprt:
      case PosThermalPrinterBrand.rp80:
      case PosThermalPrinterBrand.generic:
        return n < usbFloor ? usbFloor : n;
      case PosThermalPrinterBrand.sunmi:
        return n < 4 ? 4 : n;
      case PosThermalPrinterBrand.epson:
        return n < 3 ? 3 : n;
    }
  }

  PosThermalPrinterSettings copyWith({
    bool? enabled,
    PosThermalConnectionType? connectionType,
    PosThermalPrinterBrand? printerBrand,
    PosThermalTextMode? textMode,
    String? paperSize,
    String? bluetoothAddress,
    String? bluetoothName,
    String? lanHost,
    int? lanPort,
    String? usbDeviceName,
    int? escPosCodePage,
    int? feedBeforeCut,
    bool? partialCut,
    bool? cutPerItem,
    bool? openCashDrawer,
    bool? openDrawerCashOnly,
    bool? beepOnPrint,
    bool clearBluetooth = false,
    bool clearLan = false,
    bool clearUsb = false,
  }) =>
      PosThermalPrinterSettings(
        enabled: enabled ?? this.enabled,
        connectionType: connectionType ?? this.connectionType,
        printerBrand: printerBrand ?? this.printerBrand,
        textMode: textMode ?? this.textMode,
        paperSize: paperSize ?? this.paperSize,
        bluetoothAddress:
            clearBluetooth ? null : (bluetoothAddress ?? this.bluetoothAddress),
        bluetoothName:
            clearBluetooth ? null : (bluetoothName ?? this.bluetoothName),
        lanHost: clearLan ? null : (lanHost ?? this.lanHost),
        lanPort: lanPort ?? this.lanPort,
        usbDeviceName: clearUsb ? null : (usbDeviceName ?? this.usbDeviceName),
        escPosCodePage: escPosCodePage ?? this.escPosCodePage,
        feedBeforeCut: feedBeforeCut ?? this.feedBeforeCut,
        partialCut: partialCut ?? this.partialCut,
        cutPerItem: cutPerItem ?? this.cutPerItem,
        openCashDrawer: openCashDrawer ?? this.openCashDrawer,
        openDrawerCashOnly: openDrawerCashOnly ?? this.openDrawerCashOnly,
        beepOnPrint: beepOnPrint ?? this.beepOnPrint,
      );

  static Future<PosThermalPrinterSettings> load() async {
    final legacy = await loadLegacyRaw();
    return legacy ?? const PosThermalPrinterSettings();
  }

  /// Đọc singleton SharedPreferences (dùng migrate → multi máy).
  static Future<PosThermalPrinterSettings?> loadLegacyRaw() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kEnabled) &&
        !prefs.containsKey(_kBtAddr) &&
        !prefs.containsKey(_kLanHost) &&
        !prefs.containsKey(_kType)) {
      return null;
    }
    return PosThermalPrinterSettings(
      enabled: prefs.getBool(_kEnabled) ?? false,
      connectionType: PosThermalConnectionType.coerceForPlatform(
        PosThermalConnectionType.fromKey(prefs.getString(_kType)),
      ),
      printerBrand: PosThermalPrinterBrand.fromKey(prefs.getString(_kBrand)),
      textMode: PosThermalTextMode.fromKey(prefs.getString(_kTextMode)),
      paperSize: prefs.getString(_kPaper) ?? 'K80',
      bluetoothAddress: prefs.getString(_kBtAddr),
      bluetoothName: prefs.getString(_kBtName),
      lanHost: prefs.getString(_kLanHost),
      lanPort: prefs.getInt(_kLanPort) ?? 9100,
      usbDeviceName: prefs.getString(_kUsbName),
      escPosCodePage: prefs.getInt(_kCodePage) ?? 27,
      feedBeforeCut: prefs.getInt(_kFeedCut) ?? 5,
      partialCut: prefs.getBool(_kPartialCut) ?? true,
      openCashDrawer: prefs.getBool(_kOpenDrawer) ?? false,
      openDrawerCashOnly: prefs.getBool(_kOpenDrawerCashOnly) ?? true,
      beepOnPrint: prefs.getBool(_kBeepOnPrint) ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    await prefs.setString(_kType, connectionType.key);
    await prefs.setString(_kBrand, printerBrand.key);
    await prefs.setString(_kTextMode, textMode.key);
    await prefs.setString(_kPaper, paperSize);
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
    await prefs.setInt(_kCodePage, escPosCodePage.clamp(0, 255));
    if (usbDeviceName != null && usbDeviceName!.isNotEmpty) {
      await prefs.setString(_kUsbName, usbDeviceName!);
    } else {
      await prefs.remove(_kUsbName);
    }
    await prefs.setInt(_kFeedCut, feedBeforeCut);
    await prefs.setBool(_kPartialCut, partialCut);
    await prefs.setBool(_kOpenDrawer, openCashDrawer);
    await prefs.setBool(_kOpenDrawerCashOnly, openDrawerCashOnly);
    await prefs.setBool(_kBeepOnPrint, beepOnPrint);
  }
}
