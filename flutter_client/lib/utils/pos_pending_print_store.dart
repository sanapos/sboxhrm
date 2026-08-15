import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_sale_order.dart';
import 'pos_cup_label_print.dart';
import 'pos_kitchen_print.dart';
import 'pos_sale_order_print.dart';

/// Snapshot hàng chờ in — sống qua kill app (SharedPreferences).
class PosPendingPrintSnapshot {
  const PosPendingPrintSnapshot({
    this.warehouse = const [],
    this.sales = const [],
    this.kitchen = const [],
    this.cups = const [],
  });

  final List<PendingWarehousePrintJob> warehouse;
  final List<PendingSalePrintJob> sales;
  final List<PendingKitchenPrintJob> kitchen;
  final List<PendingCupLabelPrintJob> cups;

  int get totalCount =>
      warehouse.length + sales.length + kitchen.length + cups.length;

  bool get isEmpty => totalCount == 0;

  PosPendingPrintSnapshot copyWith({
    List<PendingWarehousePrintJob>? warehouse,
    List<PendingSalePrintJob>? sales,
    List<PendingKitchenPrintJob>? kitchen,
    List<PendingCupLabelPrintJob>? cups,
  }) =>
      PosPendingPrintSnapshot(
        warehouse: warehouse ?? this.warehouse,
        sales: sales ?? this.sales,
        kitchen: kitchen ?? this.kitchen,
        cups: cups ?? this.cups,
      );
}

/// Phiếu bếp/hủy chưa in được (đã báo hệ thống / đã ghi hủy).
class PendingKitchenPrintJob {
  PendingKitchenPrintJob({
    required this.id,
    required this.isCancel,
    required this.tableName,
    required this.senderName,
    required this.lines,
    this.orderNo,
    this.errorMessage,
    this.attemptCount = 0,
    this.printerId,
    this.printerName,
    DateTime? createdAt,
    DateTime? sentAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        sentAt = sentAt ?? DateTime.now();

  final String id;
  final bool isCancel;
  final String tableName;
  final String senderName;
  final String? orderNo;
  final List<KitchenTicketLine> lines;
  final String? errorMessage;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime sentAt;

  /// Máy in đích khi lỗi một phần (fan-out nhiều máy). Null = chưa biết / cả bill.
  final String? printerId;
  final String? printerName;

  String get title => isCancel ? 'Phiếu hủy bếp' : 'Phiếu báo bếp';

  String get lineSummary {
    final names = lines.map((l) => l.productName).take(3).join(', ');
    if (lines.length > 3) return '$names…';
    return names.isEmpty ? '${lines.length} món' : names;
  }

  PendingKitchenPrintJob copyWith({
    String? errorMessage,
    int? attemptCount,
    String? printerId,
    String? printerName,
  }) =>
      PendingKitchenPrintJob(
        id: id,
        isCancel: isCancel,
        tableName: tableName,
        senderName: senderName,
        orderNo: orderNo,
        lines: lines,
        errorMessage: errorMessage ?? this.errorMessage,
        attemptCount: attemptCount ?? this.attemptCount,
        printerId: printerId ?? this.printerId,
        printerName: printerName ?? this.printerName,
        createdAt: createdAt,
        sentAt: sentAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'isCancel': isCancel,
        'tableName': tableName,
        'senderName': senderName,
        'orderNo': orderNo,
        'errorMessage': errorMessage,
        'attemptCount': attemptCount,
        'printerId': printerId,
        'printerName': printerName,
        'createdAt': createdAt.toIso8601String(),
        'sentAt': sentAt.toIso8601String(),
        'lines': lines
            .map((l) => {
                  'productName': l.productName,
                  'qty': l.qty,
                  'unitName': l.unitName,
                  'note': l.note,
                  'productId': l.productId,
                  'sentBefore': l.sentBefore,
                  'lineKey': l.lineKey,
                })
            .toList(),
      };

  factory PendingKitchenPrintJob.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final lines = <KitchenTicketLine>[];
    if (rawLines is List) {
      for (final e in rawLines) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        lines.add(KitchenTicketLine(
          productName: (m['productName'] ?? '').toString(),
          qty: (m['qty'] is num)
              ? (m['qty'] as num).toDouble()
              : double.tryParse('${m['qty']}') ?? 0,
          unitName: m['unitName']?.toString(),
          note: m['note']?.toString(),
          productId: m['productId']?.toString(),
          sentBefore: (m['sentBefore'] is num)
              ? (m['sentBefore'] as num).toDouble()
              : double.tryParse('${m['sentBefore']}'),
          lineKey: m['lineKey']?.toString(),
        ));
      }
    }
    return PendingKitchenPrintJob(
      id: (json['id'] ?? '').toString(),
      isCancel: json['isCancel'] == true,
      tableName: (json['tableName'] ?? '').toString(),
      senderName: (json['senderName'] ?? '').toString(),
      orderNo: json['orderNo']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      attemptCount: json['attemptCount'] is num
          ? (json['attemptCount'] as num).toInt()
          : int.tryParse('${json['attemptCount']}') ?? 0,
      printerId: json['printerId']?.toString(),
      printerName: json['printerName']?.toString(),
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      sentAt: DateTime.tryParse('${json['sentAt']}') ?? DateTime.now(),
      lines: lines,
    );
  }
}

/// Tem ly chưa in được.
class PendingCupLabelPrintJob {
  PendingCupLabelPrintJob({
    required this.id,
    required this.tickets,
    this.tableLabel,
    this.orderNo,
    this.errorMessage,
    this.attemptCount = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final List<CupLabelTicket> tickets;
  final String? tableLabel;
  final String? orderNo;
  final String? errorMessage;
  final int attemptCount;
  final DateTime createdAt;

  String get lineSummary {
    final names = tickets.map((t) => t.productName).take(3).join(', ');
    if (tickets.length > 3) return '$names…';
    return names.isEmpty ? '${tickets.length} tem' : names;
  }

  PendingCupLabelPrintJob copyWith({
    String? errorMessage,
    int? attemptCount,
  }) =>
      PendingCupLabelPrintJob(
        id: id,
        tickets: tickets,
        tableLabel: tableLabel,
        orderNo: orderNo,
        errorMessage: errorMessage ?? this.errorMessage,
        attemptCount: attemptCount ?? this.attemptCount,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tableLabel': tableLabel,
        'orderNo': orderNo,
        'errorMessage': errorMessage,
        'attemptCount': attemptCount,
        'createdAt': createdAt.toIso8601String(),
        'tickets': tickets
            .map((t) => {
                  'productName': t.productName,
                  'toppings': t.toppings,
                  'note': t.note,
                  'qtyLabel': t.qtyLabel,
                  'tableLabel': t.tableLabel,
                  'orderNo': t.orderNo,
                })
            .toList(),
      };

  factory PendingCupLabelPrintJob.fromJson(Map<String, dynamic> json) {
    final raw = json['tickets'];
    final tickets = <CupLabelTicket>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        tickets.add(CupLabelTicket(
          productName: (m['productName'] ?? '').toString(),
          toppings: m['toppings']?.toString(),
          note: m['note']?.toString(),
          qtyLabel: m['qtyLabel']?.toString(),
          tableLabel: m['tableLabel']?.toString(),
          orderNo: m['orderNo']?.toString(),
        ));
      }
    }
    return PendingCupLabelPrintJob(
      id: (json['id'] ?? '').toString(),
      tableLabel: json['tableLabel']?.toString(),
      orderNo: json['orderNo']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      attemptCount: json['attemptCount'] is num
          ? (json['attemptCount'] as num).toInt()
          : int.tryParse('${json['attemptCount']}') ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      tickets: tickets,
    );
  }
}

/// Lưu / tải hàng chờ in cục bộ.
class PosPendingPrintStore {
  static const _kKey = 'pos_pending_print_queue_v1';
  static const maxJobsPerKind = 40;

  static Future<PosPendingPrintSnapshot> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) return const PosPendingPrintSnapshot();
      final map = jsonDecode(raw);
      if (map is! Map) return const PosPendingPrintSnapshot();
      // Giữ nguyên mọi phiếu treo — chỉ thu ngân Bỏ qua / In lại mới xóa.
      return _fromMap(Map<String, dynamic>.from(map));
    } catch (e) {
      debugPrint('PosPendingPrintStore.load: $e');
      return const PosPendingPrintSnapshot();
    }
  }

  static Future<void> save(PosPendingPrintSnapshot snap) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(_toMap(snap));
      await prefs.setString(_kKey, payload);
    } catch (e) {
      debugPrint('PosPendingPrintStore.save: $e');
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }

  static Map<String, dynamic> _toMap(PosPendingPrintSnapshot snap) => {
        'warehouse': snap.warehouse.map(_warehouseToJson).toList(),
        'sales': snap.sales.map(_saleToJson).toList(),
        'kitchen': snap.kitchen.map((j) => j.toJson()).toList(),
        'cups': snap.cups.map((j) => j.toJson()).toList(),
      };

  static PosPendingPrintSnapshot _fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> listOf(String key) {
      final raw = map[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return PosPendingPrintSnapshot(
      warehouse: listOf('warehouse')
          .map(_warehouseFromJson)
          .whereType<PendingWarehousePrintJob>()
          .toList(),
      sales: listOf('sales')
          .map(_saleFromJson)
          .whereType<PendingSalePrintJob>()
          .toList(),
      kitchen: listOf('kitchen').map(PendingKitchenPrintJob.fromJson).toList(),
      cups: listOf('cups').map(PendingCupLabelPrintJob.fromJson).toList(),
    );
  }

  static Map<String, dynamic> _saleToJson(PendingSalePrintJob job) => {
        'errorMessage': job.errorMessage,
        'createdAt': job.createdAt.toIso8601String(),
        'order': _orderToJson(job.order),
      };

  static PendingSalePrintJob? _saleFromJson(Map<String, dynamic> json) {
    final orderMap = json['order'];
    if (orderMap is! Map) return null;
    try {
      return PendingSalePrintJob(
        order: PosSaleOrder.fromJson(Map<String, dynamic>.from(orderMap)),
        errorMessage: json['errorMessage']?.toString(),
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      );
    } catch (e) {
      debugPrint('PendingSalePrintJob decode: $e');
      return null;
    }
  }

  static Map<String, dynamic> _warehouseToJson(PendingWarehousePrintJob job) => {
        'id': job.id,
        'tabId': job.tabId,
        'printerId': job.printerId,
        'printerName': job.printerName,
        'errorMessage': job.errorMessage,
        'reason': job.reason.name,
        'createdAt': job.createdAt.toIso8601String(),
        'order': _orderToJson(job.order),
      };

  static PendingWarehousePrintJob? _warehouseFromJson(Map<String, dynamic> json) {
    final orderMap = json['order'];
    if (orderMap is! Map) return null;
    try {
      final reasonName = (json['reason'] ?? 'dispatchFailed').toString();
      final reason = PendingWarehousePrintReason.values.firstWhere(
        (e) => e.name == reasonName,
        orElse: () => PendingWarehousePrintReason.dispatchFailed,
      );
      return PendingWarehousePrintJob(
        id: (json['id'] ?? '').toString(),
        tabId: json['tabId'] is num ? (json['tabId'] as num).toInt() : null,
        printerId: json['printerId']?.toString(),
        printerName: (json['printerName'] ?? '').toString(),
        errorMessage: json['errorMessage']?.toString(),
        reason: reason,
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
        order: PosSaleOrder.fromJson(Map<String, dynamic>.from(orderMap)),
      );
    } catch (e) {
      debugPrint('PendingWarehousePrintJob decode: $e');
      return null;
    }
  }

  static Map<String, dynamic> _orderToJson(PosSaleOrder o) => {
        'id': o.id,
        'orderNo': o.orderNo,
        'status': o.status,
        'subTotal': o.subTotal,
        'discount': o.discount,
        'total': o.total,
        'paidAmount': o.paidAmount,
        'balanceDue': o.balanceDue,
        'returnedAmount': o.returnedAmount,
        'paymentMethod': o.paymentMethod,
        'customerName': o.customerName,
        'note': o.note,
        'saleDate': o.saleDate?.toIso8601String(),
        'soldBy': o.soldBy,
        'createdAt': o.createdAt?.toIso8601String(),
        'createdBy': o.createdBy,
        'printCount': o.printCount,
        'dailyOrderIndex': o.dailyOrderIndex,
        'dailySalesTotal': o.dailySalesTotal,
        'serviceResourceName': o.serviceResourceName,
        'serviceAreaName': o.serviceAreaName,
        'lines': o.lines
            .map((l) => {
                  'id': l.id,
                  'productId': l.productId,
                  'variantId': l.variantId,
                  'productName': l.productName,
                  'unitName': l.unitName,
                  'qty': l.qty,
                  'unitPrice': l.unitPrice,
                  'discountAmount': l.discountAmount,
                  'lineTotal': l.lineTotal,
                  'lineNote': l.lineNote,
                  'toppingsJson': l.toppings.isEmpty
                      ? null
                      : jsonEncode(l.toppings.map((t) => t.toJson()).toList()),
                })
            .toList(),
      };

  static List<T> capList<T>(List<T> list) {
    if (list.length <= maxJobsPerKind) return list;
    return list.sublist(0, maxJobsPerKind);
  }
}
