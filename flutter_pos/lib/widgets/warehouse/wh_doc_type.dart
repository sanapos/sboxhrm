import 'package:flutter/material.dart';

import '../../widgets/pos/pos_stock_issue_config.dart';

/// Loại phiếu kho — dùng cho hub, list, detail, editor routing.
enum WhDocType {
  purchaseReceipt,
  purchaseReturn,
  stockCount,
  damageIssue,
  internalUseIssue,
}

extension WhDocTypeX on WhDocType {
  String get title => switch (this) {
        WhDocType.purchaseReceipt => 'Nhập hàng',
        WhDocType.purchaseReturn => 'Trả hàng nhập',
        WhDocType.stockCount => 'Kiểm kho',
        WhDocType.damageIssue => 'Xuất hủy',
        WhDocType.internalUseIssue => 'Dùng nội bộ',
      };

  String get listTitle => switch (this) {
        WhDocType.purchaseReceipt => 'Phiếu nhập hàng',
        WhDocType.purchaseReturn => 'Phiếu trả hàng',
        WhDocType.stockCount => 'Phiếu kiểm kho',
        WhDocType.damageIssue => 'Phiếu xuất hủy',
        WhDocType.internalUseIssue => 'Phiếu xuất nội bộ',
      };

  String get createLabel => switch (this) {
        WhDocType.purchaseReceipt => 'Tạo phiếu nhập',
        WhDocType.purchaseReturn => 'Tạo phiếu trả',
        WhDocType.stockCount => 'Tạo phiếu KK',
        WhDocType.damageIssue => 'Tạo phiếu XH',
        WhDocType.internalUseIssue => 'Tạo phiếu XDNB',
      };

  IconData get icon => switch (this) {
        WhDocType.purchaseReceipt => Icons.move_to_inbox_rounded,
        WhDocType.purchaseReturn => Icons.undo_rounded,
        WhDocType.stockCount => Icons.fact_check_rounded,
        WhDocType.damageIssue => Icons.delete_forever_rounded,
        WhDocType.internalUseIssue => Icons.outbox_rounded,
      };

  Color get accentColor => switch (this) {
        WhDocType.purchaseReceipt => const Color(0xFF007AFF),
        WhDocType.purchaseReturn => const Color(0xFF5856D6),
        WhDocType.stockCount => const Color(0xFF34C759),
        WhDocType.damageIssue => const Color(0xFFFF3B30),
        WhDocType.internalUseIssue => const Color(0xFFFF9500),
      };

  String get moduleCode => switch (this) {
        WhDocType.purchaseReceipt => 'PosPurchaseReceipts',
        WhDocType.purchaseReturn => 'PosPurchaseReturns',
        WhDocType.stockCount => 'PosStockCounts',
        WhDocType.damageIssue => 'PosDamageIssues',
        WhDocType.internalUseIssue => 'PosInternalUseIssues',
      };

  String get draftStatusLabel => switch (this) {
        WhDocType.stockCount => 'Đang kiểm',
        _ => 'Nháp',
      };

  String get completeLabel => switch (this) {
        WhDocType.purchaseReceipt => 'Hoàn thành nhập',
        WhDocType.purchaseReturn => 'Hoàn thành trả',
        WhDocType.stockCount => 'Cân bằng kho',
        WhDocType.damageIssue => 'Hoàn thành xuất hủy',
        WhDocType.internalUseIssue => 'Hoàn thành xuất',
      };

  PosStockIssueConfig? get stockIssueConfig => switch (this) {
        WhDocType.damageIssue => PosStockIssueConfig.damage,
        WhDocType.internalUseIssue => PosStockIssueConfig.internalUse,
        _ => null,
      };

  /// Draft status value on server.
  String get draftStatus => switch (this) {
        WhDocType.stockCount => 'InProgress',
        _ => 'Draft',
      };
}

/// Một dòng trong danh sách phiếu (view-model thống nhất).
class WhDocListItem {
  const WhDocListItem({
    required this.id,
    required this.docNo,
    required this.status,
    required this.amount,
    required this.lineCount,
    this.subtitle,
    this.meta,
    this.createdAt,
    this.createdBy,
    this.note,
  });

  final String id;
  final String docNo;
  final String status;
  final double amount;
  final int lineCount;
  final String? subtitle;
  final String? meta;
  final DateTime? createdAt;
  final String? createdBy;
  final String? note;
}
