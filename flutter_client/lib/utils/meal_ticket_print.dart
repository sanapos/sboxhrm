import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_local_printers_store.dart';
import 'pos_pdf_fonts.dart';
import 'pos_print_orchestrator.dart';
import 'pos_thermal_printer_service.dart';

/// Một phiếu ăn (1 lượt chấm cơm tại căn tin).
class MealTicket {
  const MealTicket({
    required this.id,
    required this.ticketNo,
    required this.mealTime,
    required this.sessionName,
    required this.employeeName,
    this.employeeCode,
    this.department,
    this.price = 0,
    this.source = '',
    this.printedAt,
    this.printCount = 0,
    this.dishes = const [],
  });

  final String id;
  final int ticketNo;
  final DateTime mealTime;
  final String sessionName;
  final String employeeName;
  final String? employeeCode;
  final String? department;
  final double price;
  final String source;
  final DateTime? printedAt;
  final int printCount;
  final List<String> dishes;

  bool get printed => printedAt != null;

  factory MealTicket.fromJson(Map<String, dynamic> j) => MealTicket(
        id: j['id']?.toString() ?? '',
        ticketNo: (j['ticketNo'] as num?)?.toInt() ?? 0,
        mealTime: DateTime.tryParse(j['mealTime']?.toString() ?? '') ?? DateTime.now(),
        sessionName: j['sessionName']?.toString() ?? '',
        employeeName: j['employeeName']?.toString() ?? '',
        employeeCode: j['employeeCode']?.toString(),
        department: j['department']?.toString(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        source: j['source']?.toString() ?? '',
        printedAt: DateTime.tryParse(j['printedAt']?.toString() ?? ''),
        printCount: (j['printCount'] as num?)?.toInt() ?? 0,
        dishes: [
          for (final d in (j['dishes'] as List? ?? const []))
            if (d is Map && (d['dishName']?.toString() ?? '').isNotEmpty) d['dishName'].toString(),
        ],
      );
}

enum MealTicketPrinterMode { thermal, system }

/// Cấu hình trạm in phiếu ăn — lưu trên chính máy đặt tại căn tin.
class MealTicketPrinterConfig {
  const MealTicketPrinterConfig({
    this.mode = MealTicketPrinterMode.thermal,
    this.thermalProfileId,
    this.systemPrinterUrl,
    this.systemPrinterName,
    this.showMenu = true,
    this.showPrice = true,
    this.autoPrint = true,
    this.footer = 'Chúc bạn ngon miệng!',
  });

  final MealTicketPrinterMode mode;
  final String? thermalProfileId;
  final String? systemPrinterUrl;
  final String? systemPrinterName;
  final bool showMenu;
  final bool showPrice;
  final bool autoPrint;
  final String footer;

  static const _key = 'meal_ticket_printer_v1';

  bool get isConfigured => mode == MealTicketPrinterMode.thermal
      ? (thermalProfileId ?? '').isNotEmpty
      : true; // máy in hệ thống: không chọn thì mở hộp thoại in

  String get printerLabel => mode == MealTicketPrinterMode.thermal
      ? 'Máy in nhiệt'
      : (systemPrinterName ?? 'Hộp thoại in của hệ thống');

  MealTicketPrinterConfig copyWith({
    MealTicketPrinterMode? mode,
    String? thermalProfileId,
    String? systemPrinterUrl,
    String? systemPrinterName,
    bool? showMenu,
    bool? showPrice,
    bool? autoPrint,
    String? footer,
  }) =>
      MealTicketPrinterConfig(
        mode: mode ?? this.mode,
        thermalProfileId: thermalProfileId ?? this.thermalProfileId,
        systemPrinterUrl: systemPrinterUrl ?? this.systemPrinterUrl,
        systemPrinterName: systemPrinterName ?? this.systemPrinterName,
        showMenu: showMenu ?? this.showMenu,
        showPrice: showPrice ?? this.showPrice,
        autoPrint: autoPrint ?? this.autoPrint,
        footer: footer ?? this.footer,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'thermalProfileId': thermalProfileId,
        'systemPrinterUrl': systemPrinterUrl,
        'systemPrinterName': systemPrinterName,
        'showMenu': showMenu,
        'showPrice': showPrice,
        'autoPrint': autoPrint,
        'footer': footer,
      };

  static Future<MealTicketPrinterConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const MealTicketPrinterConfig();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return MealTicketPrinterConfig(
        mode: j['mode'] == 'system' ? MealTicketPrinterMode.system : MealTicketPrinterMode.thermal,
        thermalProfileId: j['thermalProfileId'] as String?,
        systemPrinterUrl: j['systemPrinterUrl'] as String?,
        systemPrinterName: j['systemPrinterName'] as String?,
        showMenu: j['showMenu'] as bool? ?? true,
        showPrice: j['showPrice'] as bool? ?? true,
        autoPrint: j['autoPrint'] as bool? ?? true,
        footer: j['footer'] as String? ?? 'Chúc bạn ngon miệng!',
      );
    } catch (_) {
      return const MealTicketPrinterConfig();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }
}

/// In phiếu ăn: máy in nhiệt (đã khai báo ở Cài đặt máy in POS) hoặc máy in hệ thống (PDF khổ 80mm).
class MealTicketPrinter {
  MealTicketPrinter._();

  static final _money = NumberFormat('#,##0', 'vi_VN');
  static final _time = DateFormat('HH:mm');
  static final _date = DateFormat('dd/MM/yyyy');

  static List<String> ticketLines(MealTicket t, MealTicketPrinterConfig cfg, {String? storeName}) => [
        if ((storeName ?? '').isNotEmpty) storeName!,
        '--------------------------------',
        'Số phiếu: ${t.ticketNo.toString().padLeft(3, '0')}',
        'Buổi ăn:  ${t.sessionName}',
        'Ngày:     ${_date.format(t.mealTime)}  ${_time.format(t.mealTime)}',
        'Họ tên:   ${t.employeeName}',
        if ((t.employeeCode ?? '').isNotEmpty) 'Mã NV:    ${t.employeeCode}',
        if ((t.department ?? '').isNotEmpty) 'Bộ phận:  ${t.department}',
        if (cfg.showPrice && t.price > 0) 'Giá suất: ${_money.format(t.price)}đ',
        if (cfg.showMenu && t.dishes.isNotEmpty) ...[
          '--------------------------------',
          'Thực đơn:',
          for (final d in t.dishes) ' - $d',
        ],
        '--------------------------------',
        if (t.printCount > 0) '(In lại lần ${t.printCount + 1})',
      ];

  /// Danh sách máy in nhiệt đã khai báo trên máy này (Cài đặt → Máy in).
  static Future<List<PosLocalPrinterProfile>> thermalPrinters() async {
    final all = await PosLocalPrintersStore.instance.loadAll();
    return all.where((p) => p.enabled).toList();
  }

  static Future<bool> printTicket(MealTicket t, MealTicketPrinterConfig cfg, {String? storeName}) async {
    if (cfg.mode == MealTicketPrinterMode.thermal && !kIsWeb) {
      final printers = await thermalPrinters();
      final p = printers.where((x) => x.id == cfg.thermalProfileId).firstOrNull;
      if (p == null) return false;
      final settings = p.toThermalSettings();
      final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
        settings: settings,
        title: 'PHIẾU ĂN #${t.ticketNo}',
        lines: ticketLines(t, cfg, storeName: storeName),
        footer: cfg.footer,
      );
      return PosPrintOrchestrator.instance.dispatchLocalEscPos(
        bytes: bytes,
        showFeedback: false,
        settingsOverride: settings,
        skipDedup: true,
      );
    }
    return _printPdf(t, cfg, storeName: storeName);
  }

  static Future<Uint8List> buildPdf(MealTicket t, MealTicketPrinterConfig cfg, {String? storeName}) async {
    final fonts = await loadPosPdfFonts();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold));
    pw.Widget row(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 52, child: pw.Text(k, style: const pw.TextStyle(fontSize: 9))),
            pw.Expanded(child: pw.Text(v, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          ]),
        );
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80.copyWith(marginLeft: 8, marginRight: 8, marginTop: 6, marginBottom: 6),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        if ((storeName ?? '').isNotEmpty)
          pw.Text(storeName!, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 2),
        pw.Text('PHIẾU ĂN', textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.Text(t.ticketNo.toString().padLeft(3, '0'), textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold)),
        pw.Text('${t.sessionName} · ${_date.format(t.mealTime)} ${_time.format(t.mealTime)}',
            textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
        pw.Divider(thickness: 0.5),
        row('Họ tên', t.employeeName),
        if ((t.employeeCode ?? '').isNotEmpty) row('Mã NV', t.employeeCode!),
        if ((t.department ?? '').isNotEmpty) row('Bộ phận', t.department!),
        if (cfg.showPrice && t.price > 0) row('Giá suất', '${_money.format(t.price)}đ'),
        if (cfg.showMenu && t.dishes.isNotEmpty) ...[
          pw.Divider(thickness: 0.5),
          pw.Text('Thực đơn', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          for (final d in t.dishes) pw.Text('• $d', style: const pw.TextStyle(fontSize: 9)),
        ],
        pw.Divider(thickness: 0.5),
        if (t.printCount > 0)
          pw.Text('(In lại lần ${t.printCount + 1})', textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8)),
        pw.Text(cfg.footer, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
      ]),
    ));
    return doc.save();
  }

  static Future<bool> _printPdf(MealTicket t, MealTicketPrinterConfig cfg, {String? storeName}) async {
    final bytes = await buildPdf(t, cfg, storeName: storeName);
    final url = cfg.systemPrinterUrl;
    if (!kIsWeb && url != null && url.isNotEmpty) {
      return Printing.directPrintPdf(
        printer: Printer(url: url, name: cfg.systemPrinterName),
        name: 'Phieu-an-${t.ticketNo}',
        onLayout: (_) async => bytes,
      );
    }
    return Printing.layoutPdf(name: 'Phieu-an-${t.ticketNo}', onLayout: (_) async => bytes);
  }
}
