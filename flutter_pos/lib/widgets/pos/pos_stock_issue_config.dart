import 'package:flutter/material.dart';

class PosStockIssueConfig {
  const PosStockIssueConfig({
    required this.title,
    required this.kind,
    required this.moduleCode,
    required this.activeModule,
    required this.icon,
    required this.createButtonLabel,
    required this.qtyColumnLabel,
    required this.completeActionLabel,
    required this.completeDialogTitle,
    required this.completeDialogMessage,
    required this.voidDialogTitle,
    required this.voidDialogMessage,
    this.showInternalFields = false,
    this.searchHint = 'Tìm mã phiếu, ghi chú…',
  });

  final String title;
  final String kind;
  final String moduleCode;
  final String activeModule;
  final IconData icon;
  final String createButtonLabel;
  final String qtyColumnLabel;
  final String completeActionLabel;
  final String completeDialogTitle;
  final String completeDialogMessage;
  final String voidDialogTitle;
  final String voidDialogMessage;
  final bool showInternalFields;
  final String searchHint;

  static const damage = PosStockIssueConfig(
    title: 'Xuất hủy',
    kind: 'damage',
    moduleCode: 'PosDamageIssues',
    activeModule: 'PosDamageIssues',
    icon: Icons.delete_forever_outlined,
    createButtonLabel: 'Tạo phiếu XH',
    qtyColumnLabel: 'SL hủy',
    completeActionLabel: 'Hoàn thành xuất hủy',
    completeDialogTitle: 'Xuất hủy',
    completeDialogMessage: 'Hoàn thành phiếu và trừ tồn kho?',
    voidDialogTitle: 'Hủy phiếu xuất hủy',
    voidDialogMessage: 'Hủy phiếu và hoàn tồn kho?',
    searchHint: 'Tìm mã XH, ghi chú…',
  );

  static const internalUse = PosStockIssueConfig(
    title: 'Xuất dùng nội bộ',
    kind: 'internal-use',
    moduleCode: 'PosInternalUseIssues',
    activeModule: 'PosInternalUseIssues',
    icon: Icons.outbox_outlined,
    createButtonLabel: 'Tạo phiếu XDNB',
    qtyColumnLabel: 'SL xuất',
    completeActionLabel: 'Hoàn thành xuất',
    completeDialogTitle: 'Xuất dùng nội bộ',
    completeDialogMessage: 'Hoàn thành phiếu và trừ tồn kho?',
    voidDialogTitle: 'Hủy phiếu xuất dùng',
    voidDialogMessage: 'Hủy phiếu và hoàn tồn kho?',
    showInternalFields: true,
    searchHint: 'Tìm mã XDNB, ghi chú, người nhận…',
  );
}

const kInternalUseCategories = [
  'Tiêu hao',
  'Marketing',
  'Bảo trì',
  'Khác',
];
