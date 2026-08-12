import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import 'pos_device_identity.dart';
import 'pos_label_printer_settings.dart';
import 'pos_thermal_printer_settings.dart';

/// Loại máy in nội bộ trên thiết bị.
enum PosLocalPrinterKind {
  receipt('receipt'),
  label('label');

  const PosLocalPrinterKind(this.key);
  final String key;

  static PosLocalPrinterKind fromKey(String? key) =>
      key == 'label' ? PosLocalPrinterKind.label : PosLocalPrinterKind.receipt;

  String get labelVi =>
      this == PosLocalPrinterKind.label ? 'Máy in tem' : 'Máy in nhiệt';
}

/// Vai trò chứng từ của máy in nội bộ (khớp PosPrintDocumentType API).
class PosLocalPrinterRoles {
  static const saleInvoice = 'SaleInvoice';
  static const kitchenSlip = 'KitchenSlip';
  static const kitchenVoid = 'KitchenVoid';
  static const kitchenLabel = 'KitchenLabel';
  static const stockIssue = 'StockIssue';
  static const endOfDay = 'EndOfDayReport';
  static const barcodeLabel = 'BarcodeLabel';

  static const all = <String>[
    saleInvoice,
    kitchenSlip,
    kitchenVoid,
    kitchenLabel,
    stockIssue,
    endOfDay,
    barcodeLabel,
  ];

  static const receiptRoles = <String>[
    saleInvoice,
    kitchenSlip,
    kitchenVoid,
    stockIssue,
    endOfDay,
  ];

  static const labelRoles = <String>[
    kitchenLabel,
    barcodeLabel,
  ];

  static String label(String role) => switch (role) {
        saleInvoice => 'Hóa đơn',
        kitchenSlip => 'Báo bếp',
        kitchenVoid => 'Hủy bếp',
        kitchenLabel => 'Tem bếp',
        stockIssue => 'Báo kho / xuất kho',
        endOfDay => 'Tổng kết cuối ngày',
        barcodeLabel => 'Tem mã vạch',
        _ => role,
      };

  static List<String> forKind(PosLocalPrinterKind kind) =>
      kind == PosLocalPrinterKind.label ? labelRoles : receiptRoles;

  /// Vai trò cần gán sản phẩm (bếp / hủy bếp / kho / tem ly).
  static bool needsProductAssignment(Set<String> roles) =>
      roles.contains(kitchenSlip) ||
      roles.contains(kitchenVoid) ||
      roles.contains(stockIssue) ||
      roles.contains(kitchenLabel);
}

/// Một máy in nội bộ trên thiết bị POS (BT/LAN/USB/Sunmi) — nhiệt hoặc tem.
class PosLocalPrinterProfile {
  const PosLocalPrinterProfile({
    required this.id,
    required this.name,
    this.storePrinterId,
    this.enabled = true,
    this.kind = PosLocalPrinterKind.receipt,
    this.roles = const {PosLocalPrinterRoles.saleInvoice},
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
    this.openCashDrawer = false,
    this.openDrawerCashOnly = true,
    this.beepOnPrint = false,
    this.labelProtocol = PosLabelPrinterProtocol.tspl,
    this.labelTemplateId = 'roll_1_50x30',
    this.labelDpi = 203,
    this.labelGapMm = 2.0,
    this.labelShiftRightMm = 3.0,
    this.labelMarginRightMm = 2.0,
    this.labelMarginTopMm = 2.0,
    this.labelMarginBottomMm = 2.0,
    this.labelFontScale = 1.2,
    this.labelShowHeader = true,
    this.labelShowTable = true,
    this.labelShowOrderNo = true,
    this.labelShowToppings = true,
    this.labelShowNote = true,
    this.labelShowQty = true,
  });

  final String id;
  /// Id máy trên server (PosStorePrinter) sau khi sync — dùng gán món.
  final String? storePrinterId;
  final String name;
  final bool enabled;
  final PosLocalPrinterKind kind;
  final Set<String> roles;
  final PosThermalConnectionType connectionType;
  final PosThermalPrinterBrand printerBrand;
  final PosThermalTextMode textMode;
  final String paperSize;
  final String? bluetoothAddress;
  final String? bluetoothName;
  final String? lanHost;
  final int lanPort;
  final String? usbDeviceName;
  final int escPosCodePage;
  final int feedBeforeCut;
  final bool partialCut;
  final bool openCashDrawer;
  final bool openDrawerCashOnly;
  final bool beepOnPrint;
  final PosLabelPrinterProtocol labelProtocol;
  final String labelTemplateId;
  final int labelDpi;
  final double labelGapMm;
  /// Lề trái (mm) — giữ tên cũ để tương thích JSON.
  final double labelShiftRightMm;
  final double labelMarginRightMm;
  final double labelMarginTopMm;
  final double labelMarginBottomMm;
  final double labelFontScale;
  final bool labelShowHeader;
  final bool labelShowTable;
  final bool labelShowOrderNo;
  final bool labelShowToppings;
  final bool labelShowNote;
  final bool labelShowQty;

  double get labelMarginLeftMm => labelShiftRightMm;

  bool get isLabel => kind == PosLocalPrinterKind.label;

  bool hasRole(String role) => roles.contains(role);

  PosThermalPrinterSettings toThermalSettings() => PosThermalPrinterSettings(
        enabled: enabled,
        connectionType: connectionType,
        printerBrand: printerBrand,
        textMode: textMode,
        paperSize: paperSize,
        bluetoothAddress: bluetoothAddress,
        bluetoothName: bluetoothName,
        lanHost: lanHost,
        lanPort: lanPort,
        usbDeviceName: usbDeviceName,
        escPosCodePage: escPosCodePage,
        feedBeforeCut: feedBeforeCut,
        partialCut: partialCut,
        openCashDrawer: openCashDrawer,
        openDrawerCashOnly: openDrawerCashOnly,
        beepOnPrint: beepOnPrint,
      );

  PosLabelPrinterSettings toLabelSettings() => PosLabelPrinterSettings(
        enabled: enabled,
        connectionType: connectionType,
        protocol: labelProtocol,
        templateId: labelTemplateId,
        dpi: labelDpi,
        gapMm: labelGapMm,
        marginLeftMm: labelShiftRightMm,
        marginRightMm: labelMarginRightMm,
        marginTopMm: labelMarginTopMm,
        marginBottomMm: labelMarginBottomMm,
        fontScale: labelFontScale,
        showHeader: labelShowHeader,
        showTable: labelShowTable,
        showOrderNo: labelShowOrderNo,
        showToppings: labelShowToppings,
        showNote: labelShowNote,
        showQty: labelShowQty,
        bluetoothAddress: bluetoothAddress,
        bluetoothName: bluetoothName,
        lanHost: lanHost,
        lanPort: lanPort,
        usbDeviceName: usbDeviceName,
      );

  PosLocalPrinterProfile copyWith({
    String? id,
    String? storePrinterId,
    String? name,
    bool? enabled,
    PosLocalPrinterKind? kind,
    Set<String>? roles,
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
    bool? openCashDrawer,
    bool? openDrawerCashOnly,
    bool? beepOnPrint,
    PosLabelPrinterProtocol? labelProtocol,
    String? labelTemplateId,
    int? labelDpi,
    double? labelGapMm,
    double? labelShiftRightMm,
    double? labelMarginRightMm,
    double? labelMarginTopMm,
    double? labelMarginBottomMm,
    double? labelFontScale,
    bool? labelShowHeader,
    bool? labelShowTable,
    bool? labelShowOrderNo,
    bool? labelShowToppings,
    bool? labelShowNote,
    bool? labelShowQty,
    bool clearStorePrinterId = false,
  }) =>
      PosLocalPrinterProfile(
        id: id ?? this.id,
        storePrinterId:
            clearStorePrinterId ? null : (storePrinterId ?? this.storePrinterId),
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        kind: kind ?? this.kind,
        roles: roles ?? this.roles,
        connectionType: connectionType ?? this.connectionType,
        printerBrand: printerBrand ?? this.printerBrand,
        textMode: textMode ?? this.textMode,
        paperSize: paperSize ?? this.paperSize,
        bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
        bluetoothName: bluetoothName ?? this.bluetoothName,
        lanHost: lanHost ?? this.lanHost,
        lanPort: lanPort ?? this.lanPort,
        usbDeviceName: usbDeviceName ?? this.usbDeviceName,
        escPosCodePage: escPosCodePage ?? this.escPosCodePage,
        feedBeforeCut: feedBeforeCut ?? this.feedBeforeCut,
        partialCut: partialCut ?? this.partialCut,
        openCashDrawer: openCashDrawer ?? this.openCashDrawer,
        openDrawerCashOnly: openDrawerCashOnly ?? this.openDrawerCashOnly,
        beepOnPrint: beepOnPrint ?? this.beepOnPrint,
        labelProtocol: labelProtocol ?? this.labelProtocol,
        labelTemplateId: labelTemplateId ?? this.labelTemplateId,
        labelDpi: labelDpi ?? this.labelDpi,
        labelGapMm: labelGapMm ?? this.labelGapMm,
        labelShiftRightMm: labelShiftRightMm ?? this.labelShiftRightMm,
        labelMarginRightMm: labelMarginRightMm ?? this.labelMarginRightMm,
        labelMarginTopMm: labelMarginTopMm ?? this.labelMarginTopMm,
        labelMarginBottomMm: labelMarginBottomMm ?? this.labelMarginBottomMm,
        labelFontScale: labelFontScale ?? this.labelFontScale,
        labelShowHeader: labelShowHeader ?? this.labelShowHeader,
        labelShowTable: labelShowTable ?? this.labelShowTable,
        labelShowOrderNo: labelShowOrderNo ?? this.labelShowOrderNo,
        labelShowToppings: labelShowToppings ?? this.labelShowToppings,
        labelShowNote: labelShowNote ?? this.labelShowNote,
        labelShowQty: labelShowQty ?? this.labelShowQty,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'storePrinterId': storePrinterId,
        'name': name,
        'enabled': enabled,
        'kind': kind.key,
        'roles': roles.toList(),
        'connectionType': connectionType.key,
        'printerBrand': printerBrand.key,
        'textMode': textMode.key,
        'paperSize': paperSize,
        'bluetoothAddress': bluetoothAddress,
        'bluetoothName': bluetoothName,
        'lanHost': lanHost,
        'lanPort': lanPort,
        'usbDeviceName': usbDeviceName,
        'escPosCodePage': escPosCodePage,
        'feedBeforeCut': feedBeforeCut,
        'partialCut': partialCut,
        'openCashDrawer': openCashDrawer,
        'openDrawerCashOnly': openDrawerCashOnly,
        'beepOnPrint': beepOnPrint,
        'labelProtocol': labelProtocol.key,
        'labelTemplateId': labelTemplateId,
        'labelDpi': labelDpi,
        'labelGapMm': labelGapMm,
        'labelShiftRightMm': labelShiftRightMm,
        'labelMarginRightMm': labelMarginRightMm,
        'labelMarginTopMm': labelMarginTopMm,
        'labelMarginBottomMm': labelMarginBottomMm,
        'labelFontScale': labelFontScale,
        'labelShowHeader': labelShowHeader,
        'labelShowTable': labelShowTable,
        'labelShowOrderNo': labelShowOrderNo,
        'labelShowToppings': labelShowToppings,
        'labelShowNote': labelShowNote,
        'labelShowQty': labelShowQty,
      };

  factory PosLocalPrinterProfile.fromJson(Map<String, dynamic> json) {
    final rolesRaw = json['roles'];
    final roles = <String>{};
    if (rolesRaw is List) {
      for (final r in rolesRaw) {
        final s = r?.toString() ?? '';
        if (s.isNotEmpty) roles.add(s);
      }
    }
    final kindRaw = json['kind']?.toString();
    final kind = kindRaw != null && kindRaw.isNotEmpty
        ? PosLocalPrinterKind.fromKey(kindRaw)
        : (roles.isNotEmpty &&
                roles.every(PosLocalPrinterRoles.labelRoles.contains)
            ? PosLocalPrinterKind.label
            : PosLocalPrinterKind.receipt);
    if (roles.isEmpty) {
      roles.addAll(
        kind == PosLocalPrinterKind.label
            ? {PosLocalPrinterRoles.barcodeLabel}
            : {PosLocalPrinterRoles.saleInvoice},
      );
    }
    return PosLocalPrinterProfile(
      id: json['id']?.toString() ?? _newId(),
      storePrinterId: json['storePrinterId']?.toString(),
      name: json['name']?.toString() ??
          (kind == PosLocalPrinterKind.label
              ? 'Máy in tem nội bộ'
              : 'Máy in nhiệt nội bộ'),
      enabled: json['enabled'] != false,
      kind: kind,
      roles: roles,
      connectionType:
          PosThermalConnectionType.fromKey(json['connectionType']?.toString()),
      printerBrand:
          PosThermalPrinterBrand.fromKey(json['printerBrand']?.toString()),
      textMode: PosThermalTextMode.fromKey(json['textMode']?.toString()),
      paperSize: json['paperSize']?.toString() ?? 'K80',
      bluetoothAddress: json['bluetoothAddress']?.toString(),
      bluetoothName: json['bluetoothName']?.toString(),
      lanHost: json['lanHost']?.toString(),
      lanPort: (json['lanPort'] as num?)?.toInt() ?? 9100,
      usbDeviceName: json['usbDeviceName']?.toString(),
      escPosCodePage: (json['escPosCodePage'] as num?)?.toInt() ?? 27,
      feedBeforeCut: (json['feedBeforeCut'] as num?)?.toInt() ?? 5,
      partialCut: json['partialCut'] != false,
      openCashDrawer: json['openCashDrawer'] == true,
      openDrawerCashOnly: json['openDrawerCashOnly'] != false,
      beepOnPrint: json['beepOnPrint'] == true,
      labelProtocol:
          PosLabelPrinterProtocol.fromKey(json['labelProtocol']?.toString()),
      labelTemplateId: json['labelTemplateId']?.toString() ??
          (kind == PosLocalPrinterKind.label
              ? (json['paperSize']?.toString() ?? 'roll_1_50x30')
              : 'roll_1_50x30'),
      labelDpi: (json['labelDpi'] as num?)?.toInt() ?? 203,
      labelGapMm: (json['labelGapMm'] as num?)?.toDouble() ??
          (kind == PosLocalPrinterKind.label
              ? ((json['feedBeforeCut'] as num?)?.toDouble() ?? 2.0)
              : 2.0),
      labelShiftRightMm: (json['labelMarginLeftMm'] as num?)?.toDouble() ??
          (json['labelShiftRightMm'] as num?)?.toDouble() ??
          3.0,
      labelMarginRightMm:
          (json['labelMarginRightMm'] as num?)?.toDouble() ?? 2.0,
      labelMarginTopMm: (json['labelMarginTopMm'] as num?)?.toDouble() ?? 2.0,
      labelMarginBottomMm:
          (json['labelMarginBottomMm'] as num?)?.toDouble() ?? 2.0,
      labelFontScale: (json['labelFontScale'] as num?)?.toDouble() ?? 1.2,
      labelShowHeader: json['labelShowHeader'] != false,
      labelShowTable: json['labelShowTable'] != false,
      labelShowOrderNo: json['labelShowOrderNo'] != false,
      labelShowToppings: json['labelShowToppings'] != false,
      labelShowNote: json['labelShowNote'] != false,
      labelShowQty: json['labelShowQty'] != false,
    );
  }

  factory PosLocalPrinterProfile.fromLegacy(PosThermalPrinterSettings s) =>
      PosLocalPrinterProfile(
        id: _newId(),
        name: 'Máy in nhiệt nội bộ',
        enabled: s.enabled,
        kind: PosLocalPrinterKind.receipt,
        // Chỉ hóa đơn / cuối ngày — không tự gắn bếp/kho (tránh báo bếp in nhầm).
        roles: {
          PosLocalPrinterRoles.saleInvoice,
          PosLocalPrinterRoles.endOfDay,
        },
        connectionType: s.connectionType,
        printerBrand: s.printerBrand,
        textMode: s.textMode,
        paperSize: s.paperSize,
        bluetoothAddress: s.bluetoothAddress,
        bluetoothName: s.bluetoothName,
        lanHost: s.lanHost,
        lanPort: s.lanPort,
        usbDeviceName: s.usbDeviceName,
        escPosCodePage: s.escPosCodePage,
        feedBeforeCut: s.feedBeforeCut <= 0 ? 5 : s.feedBeforeCut,
        partialCut: s.partialCut,
        openCashDrawer: s.openCashDrawer,
        openDrawerCashOnly: s.openDrawerCashOnly,
        beepOnPrint: s.beepOnPrint,
      );

  factory PosLocalPrinterProfile.fromLabelLegacy(PosLabelPrinterSettings s) =>
      PosLocalPrinterProfile(
        id: _newId(),
        name: 'Máy in tem nội bộ',
        enabled: s.enabled,
        kind: PosLocalPrinterKind.label,
        roles: {
          PosLocalPrinterRoles.barcodeLabel,
          PosLocalPrinterRoles.kitchenLabel,
        },
        connectionType: s.connectionType,
        bluetoothAddress: s.bluetoothAddress,
        bluetoothName: s.bluetoothName,
        lanHost: s.lanHost,
        lanPort: s.lanPort,
        usbDeviceName: s.usbDeviceName,
        labelProtocol: s.protocol,
        labelTemplateId: s.templateId,
        labelDpi: s.dpi,
        labelGapMm: s.gapMm,
        labelShiftRightMm: s.marginLeftMm,
        labelMarginRightMm: s.marginRightMm,
        labelMarginTopMm: s.marginTopMm,
        labelMarginBottomMm: s.marginBottomMm,
        labelFontScale: s.fontScale,
        labelShowHeader: s.showHeader,
        labelShowTable: s.showTable,
        labelShowOrderNo: s.showOrderNo,
        labelShowToppings: s.showToppings,
        labelShowNote: s.showNote,
        labelShowQty: s.showQty,
      );
}

String _newId() {
  final r = Random();
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final n = List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  return 'loc-$t-$n';
}

/// Kho máy in nội bộ (nhiều máy / thiết bị) + đồng bộ server để gán món.
class PosLocalPrintersStore {
  PosLocalPrintersStore._();
  static final PosLocalPrintersStore instance = PosLocalPrintersStore._();

  static const _kList = 'pos_local_printers_v1';
  final _api = ApiService();

  Future<List<PosLocalPrinterProfile>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kList);

    // Đã từng lưu (kể cả list rỗng `[]`) → không migrate lại (tránh máy cuối bị «mọc» lại).
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) =>
                  PosLocalPrinterProfile.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {
        // fall through → migrate
      }
    }

    // Lần đầu: migrate singleton cũ.
    List<PosLocalPrinterProfile> list = [];
    final legacy = await PosThermalPrinterSettings.loadLegacyRaw();
    if (legacy != null &&
        (legacy.enabled ||
            legacy.bluetoothAddress?.trim().isNotEmpty == true ||
            legacy.lanHost?.trim().isNotEmpty == true ||
            legacy.connectionType == PosThermalConnectionType.sunmi)) {
      list = [PosLocalPrinterProfile.fromLegacy(legacy)];
    }

    final labelLegacy = await PosLabelPrinterSettings.load();
    final labelConfigured = labelLegacy.enabled ||
        (labelLegacy.bluetoothAddress?.trim().isNotEmpty == true) ||
        (labelLegacy.lanHost?.trim().isNotEmpty == true);
    if (labelConfigured && !list.any((p) => p.isLabel)) {
      list = [...list, PosLocalPrinterProfile.fromLabelLegacy(labelLegacy)];
    }

    // Ghi `[]` nếu không có gì — khóa migrate lần sau.
    await saveAll(list);
    return list;
  }

  Future<void> saveAll(List<PosLocalPrinterProfile> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kList,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );

    // Giữ singleton legacy đồng bộ (tương thích code cũ).
    final invoice = list
            .where((p) =>
                p.enabled &&
                !p.isLabel &&
                p.hasRole(PosLocalPrinterRoles.saleInvoice))
            .firstOrNull ??
        list.where((p) => p.enabled && !p.isLabel).firstOrNull;
    if (invoice != null) {
      await invoice.toThermalSettings().save();
    } else {
      await const PosThermalPrinterSettings(enabled: false).save();
    }

    final label = list.where((p) => p.enabled && p.isLabel).firstOrNull;
    if (label != null) {
      await label.toLabelSettings().save();
    } else {
      await const PosLabelPrinterSettings(enabled: false).save();
    }
  }

  Future<List<PosLocalPrinterProfile>> forRole(String role) async {
    final all = await loadAll();
    return all.where((p) => p.enabled && p.hasRole(role)).toList();
  }

  Future<PosLocalPrinterProfile?> byStorePrinterId(String storePrinterId) async {
    if (storePrinterId.isEmpty) return null;
    final all = await loadAll();
    return all
        .where((p) => p.storePrinterId == storePrinterId && p.enabled)
        .firstOrNull;
  }

  /// Cổng được in thẳng khi đã cài trên máy nội bộ của thiết bị này
  /// (USB / BT / Sunmi / LAN). Địa chỉ LAN chỉ lấy từ profile nội bộ —
  /// không dùng lanHost đọc từ máy cloud/Agent.
  static bool isOnDeviceDirectPort(PosThermalConnectionType t) =>
      t == PosThermalConnectionType.usb ||
      t == PosThermalConnectionType.bluetooth ||
      t == PosThermalConnectionType.sunmi ||
      t == PosThermalConnectionType.lan;

  static bool profileAllowsDirectLocal(PosLocalPrinterProfile p) =>
      p.enabled && isOnDeviceDirectPort(p.connectionType);

  /// Vai trò chứng từ khớp máy nội bộ (bếp/hủy, tem/barcode).
  static bool roleMatchesDocument(Set<String> roles, String documentRole) {
    if (roles.contains(documentRole)) return true;
    if (documentRole == PosLocalPrinterRoles.kitchenVoid &&
        roles.contains(PosLocalPrinterRoles.kitchenSlip)) {
      return true;
    }
    if (documentRole == PosLocalPrinterRoles.kitchenSlip &&
        roles.contains(PosLocalPrinterRoles.kitchenVoid)) {
      return true;
    }
    if (documentRole == PosLocalPrinterRoles.barcodeLabel &&
        roles.contains(PosLocalPrinterRoles.kitchenLabel)) {
      return true;
    }
    if (documentRole == PosLocalPrinterRoles.kitchenLabel &&
        roles.contains(PosLocalPrinterRoles.barcodeLabel)) {
      return true;
    }
    return false;
  }

  /// Máy nội bộ trên máy này, trùng máy cloud + chức năng.
  /// Có profile LAN nội bộ → in LAN local; chỉ thấy lanHost từ Agent/cloud → null (cloud).
  Future<PosLocalPrinterProfile?> resolveOnDeviceForStorePrinter(
    PosStorePrinter printer, {
    required String documentRole,
  }) async {
    final local = await resolveForStorePrinter(printer);
    if (local == null || !profileAllowsDirectLocal(local)) return null;
    if (!roleMatchesDocument(local.roles, documentRole)) return null;
    return local;
  }

  /// Máy nội bộ theo vai trò đã cài trên thiết bị (gồm LAN nội bộ).
  Future<List<PosLocalPrinterProfile>> forRoleOnDevice(String role) async {
    final all = await forRole(role);
    return all.where(profileAllowsDirectLocal).toList();
  }

  /// Map máy cloud → máy nội bộ: ưu tiên storePrinterId, rồi khớp cổng USB/BT/LAN/Sunmi.
  /// (Chip Agent trước đây hay không ghi storePrinterId → cloud test Zywell thiếu usbDeviceName.)
  ///
  /// Quan trọng: không dùng chip USB khi job là máy LAN/WiFi (storePrinterId gắn nhầm) —
  /// nếu không, báo bếp gán WiFi sẽ in ra USB rồi treo/ báo lỗi máy WiFi.
  Future<PosLocalPrinterProfile?> resolveForStorePrinter(
    PosStorePrinter printer,
  ) async {
    if (printer.id.isEmpty) return null;
    final byId = await byStorePrinterId(printer.id);
    if (byId != null) {
      if (matchesStorePrinter(byId, printer) ||
          _compatibleConnection(byId.connectionType, printer.connectionType)) {
        return byId;
      }
      debugPrint(
        'LocalPrinters: bỏ link storePrinterId lệch cổng '
        'local=${byId.name}/${byId.connectionType} ↔ '
        'store=${printer.name}/${printer.connectionType}',
      );
    }

    final all = await loadAll();
    for (final p in all.where((x) => x.enabled)) {
      if (matchesStorePrinter(p, printer)) return p;
    }
    return null;
  }

  /// Cùng loại cổng (Lan/Usb/BT/Sunmi) — không cho USB thay LAN dù cùng storePrinterId.
  static bool _compatibleConnection(
    PosThermalConnectionType local,
    String storeConnectionType,
  ) {
    final conn = switch (local) {
      PosThermalConnectionType.lan => 'Lan',
      PosThermalConnectionType.bluetooth => 'Bluetooth',
      PosThermalConnectionType.usb => 'Usb',
      PosThermalConnectionType.sunmi => 'Sunmi',
    };
    return storeConnectionType.trim().toLowerCase() == conn.toLowerCase();
  }

  static bool matchesStorePrinter(
    PosLocalPrinterProfile local,
    PosStorePrinter store,
  ) {
    final conn = switch (local.connectionType) {
      PosThermalConnectionType.lan => 'Lan',
      PosThermalConnectionType.bluetooth => 'Bluetooth',
      PosThermalConnectionType.usb => 'Usb',
      PosThermalConnectionType.sunmi => 'Sunmi',
    };
    if (store.connectionType != conn) return false;
    switch (local.connectionType) {
      case PosThermalConnectionType.lan:
        return (store.lanHost ?? '').trim() == (local.lanHost ?? '').trim();
      case PosThermalConnectionType.bluetooth:
        return (store.bluetoothAddress ?? '').toLowerCase() ==
            (local.bluetoothAddress ?? '').toLowerCase();
      case PosThermalConnectionType.usb:
        final a = (store.usbDeviceName ?? '').trim();
        final b = (local.usbDeviceName ?? '').trim();
        if (a.isNotEmpty && b.isNotEmpty) return a == b;
        // Cùng USB + tên gần giống (chip «zywel usb» vs máy cloud trùng).
        return local.name.trim().toLowerCase() ==
            store.name.trim().toLowerCase();
      case PosThermalConnectionType.sunmi:
        return true;
    }
  }

  Future<PosLocalPrinterProfile> upsert(PosLocalPrinterProfile profile,
      {bool syncServer = true}) async {
    final list = await loadAll();
    final idx = list.indexWhere((p) => p.id == profile.id);
    var next = profile;
    if (idx >= 0) {
      list[idx] = next;
    } else {
      list.add(next);
    }
    if (syncServer) {
      next = await syncOne(next) ?? next;
      final i2 = list.indexWhere((p) => p.id == next.id);
      if (i2 >= 0) list[i2] = next;
    }
    await saveAll(list);
    return next;
  }

  Future<void> remove(String id, {bool syncServer = true}) async {
    final list = await loadAll();
    final victim = list.where((p) => p.id == id).firstOrNull;
    list.removeWhere((p) => p.id == id);
    await saveAll(list);
    if (syncServer &&
        victim?.storePrinterId != null &&
        victim!.storePrinterId!.isNotEmpty) {
      try {
        await _api.deletePosStorePrinter(victim.storePrinterId!);
      } catch (_) {}
    }
  }

  /// Đẩy máy nội bộ lên server (IsDeviceLocal) để hiện trong gán món toàn hệ thống.
  /// Trả về profile đã cập nhật [storePrinterId]; `null` nếu sync thất bại.
  Future<PosLocalPrinterProfile?> syncOne(
    PosLocalPrinterProfile p, {
    bool forceNew = false,
  }) async {
    try {
      final device = await PosDeviceIdentity.get();
      final sendId = !forceNew &&
          p.storePrinterId != null &&
          p.storePrinterId!.trim().isNotEmpty;
      final res = await _api.upsertPosDeviceLocalPrinter({
        if (sendId) 'id': p.storePrinterId!.trim(),
        'ownerDeviceId': device.id,
        'name': p.name,
        'connectionType': _apiConnection(p.connectionType),
        'printerBrand': p.isLabel ? 'label' : p.printerBrand.key,
        'paperSize': p.isLabel ? p.labelTemplateId : p.paperSize,
        'textMode': p.isLabel ? p.labelProtocol.key : p.textMode.key,
        'bluetoothAddress': p.bluetoothAddress,
        'bluetoothName': p.bluetoothName,
        'lanHost': p.lanHost,
        'lanPort': p.lanPort,
        'usbDeviceName': p.usbDeviceName,
        'feedBeforeCut':
            p.isLabel ? p.labelGapMm.round().clamp(1, 10) : p.feedBeforeCut,
        'partialCut': !p.isLabel && p.partialCut,
        'openCashDrawer': !p.isLabel && p.openCashDrawer,
        'openDrawerCashOnly': p.openDrawerCashOnly,
        'beepOnPrint': !p.isLabel && p.beepOnPrint,
        'isActive': p.enabled,
        'documentTypes': p.roles.toList(),
      });
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        final id = (data['id'] ?? data['Id'])?.toString().trim();
        if (id != null && id.isNotEmpty && id != 'null') {
          final next = p.copyWith(storePrinterId: id);
          // Persist ngay để gán SP không dùng ID stale.
          final list = await loadAll();
          final i = list.indexWhere((x) => x.id == next.id);
          if (i >= 0) {
            list[i] = next;
            await saveAll(list);
          }
          return next;
        }
      }
      debugPrint(
        'LocalPrinters.syncOne fail forceNew=$forceNew '
        'oldId=${p.storePrinterId} msg=${res['message']}',
      );
      // ID cũ có thể là máy Agent / đã xóa / sai cửa hàng → tạo máy device-local mới.
      if (!forceNew && sendId) {
        return syncOne(p.copyWith(clearStorePrinterId: true), forceNew: true);
      }
    } catch (e) {
      debugPrint('LocalPrinters.syncOne error: $e');
      if (!forceNew && (p.storePrinterId ?? '').trim().isNotEmpty) {
        try {
          return syncOne(p.copyWith(clearStorePrinterId: true), forceNew: true);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Bảo đảm có [storePrinterId] hợp lệ trên server (luôn gọi trước khi gán SP).
  Future<PosLocalPrinterProfile?> ensureServerPrinter(
    PosLocalPrinterProfile p,
  ) async {
    final synced = await syncOne(p);
    if (synced != null && (synced.storePrinterId ?? '').trim().isNotEmpty) {
      return synced;
    }
    return syncOne(p.copyWith(clearStorePrinterId: true), forceNew: true);
  }

  Future<void> syncAll() async {
    final list = await loadAll();
    final out = <PosLocalPrinterProfile>[];
    for (final p in list) {
      out.add(await syncOne(p) ?? p);
    }
    await saveAll(out);
  }

  static String _apiConnection(PosThermalConnectionType t) => switch (t) {
        PosThermalConnectionType.bluetooth => 'Bluetooth',
        PosThermalConnectionType.lan => 'Lan',
        PosThermalConnectionType.usb => 'Usb',
        PosThermalConnectionType.sunmi => 'Sunmi',
      };
}
