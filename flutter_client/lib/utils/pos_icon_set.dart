import 'package:flutter/material.dart';

import '../theme/sbox_tokens.dart';

/// Bộ icon đồng nhất của app SBOX POS: toàn bộ dùng kiểu Rounded của Material (không thêm font).
/// Bản HRM, BOSS, Nhân Viên, KDS giữ icon cũ.
abstract final class PosIconSet {
  /// Theo tên chức năng: nhiều mục dùng chung moduleCode (PosProducts: Hàng hóa, Chuyển kho, Voucher…).
  static const _byLabel = <String, IconData>{
    'Trang chủ': Icons.home_rounded,
    'Thông báo': Icons.notifications_rounded,
    'Tổng quan': Icons.space_dashboard_rounded,
    'Thu chi': Icons.account_balance_wallet_rounded,
    'Hàng hóa': Icons.inventory_2_rounded,
    'In tem nhãn': Icons.sell_rounded,
    'Kho chi nhánh': Icons.warehouse_rounded,
    'Chuyển kho': Icons.move_up_rounded,
    'Bán hàng': Icons.point_of_sale_rounded,
    'Báo giá': Icons.request_quote_rounded,
    'Mẫu in báo giá': Icons.description_rounded,
    'Hợp đồng': Icons.handshake_rounded,
    'Khuyến mãi': Icons.local_offer_rounded,
    'Màn hình bếp (KDS)': Icons.soup_kitchen_rounded,
    'Đơn hàng': Icons.receipt_long_rounded,
    'Menu QR / Online': Icons.qr_code_2_rounded,
    'Đơn online': Icons.delivery_dining_rounded,
    'Trả hàng bán': Icons.assignment_return_rounded,
    'Đặt lịch': Icons.event_available_rounded,
    'Khách hàng POS': Icons.groups_rounded,
    'Bảo hành POS': Icons.verified_user_rounded,
    'Nhà cung cấp': Icons.storefront_rounded,
    'Nhập hàng NCC': Icons.add_shopping_cart_rounded,
    'Trả hàng nhập': Icons.keyboard_return_rounded,
    'Kiểm kho': Icons.fact_check_rounded,
    'Xuất hủy': Icons.delete_sweep_rounded,
    'Xuất dùng nội bộ': Icons.outbox_rounded,
    'Báo cáo POS': Icons.bar_chart_rounded,
    'Báo cáo chi nhánh': Icons.account_tree_rounded,
    'Báo cáo hủy / trả': Icons.history_rounded,
    'Công nợ khách hàng': Icons.credit_score_rounded,
    'Báo cáo thu chi': Icons.paid_rounded,
    'Cài đặt': Icons.manage_accounts_rounded,
    'Thiết lập thông báo': Icons.notifications_active_rounded,
    'Check-in hội viên': Icons.how_to_reg_rounded,
    'PT · Khách của tôi': Icons.sports_gymnastics_rounded,
    'Bảng giá': Icons.price_change_rounded,
    'Voucher': Icons.confirmation_number_rounded,
    'Lịch sử thao tác': Icons.manage_history_rounded,
    'Trung tâm Kho': Icons.warehouse_rounded,
    'Kiểm kho theo mã': Icons.qr_code_scanner_rounded,
    'Sổ seri máy': Icons.pin_rounded,
    'Đối soát kho': Icons.rule_rounded,
  };

  /// Theo moduleCode: ô Truy cập nhanh và thanh dưới.
  static const _byModule = <String, IconData>{
    'Home': Icons.home_rounded,
    'Dashboard': Icons.space_dashboard_rounded,
    'Notification': Icons.notifications_rounded,
    'PosSell': Icons.point_of_sale_rounded,
    'PosKds': Icons.soup_kitchen_rounded,
    'PosProducts': Icons.inventory_2_rounded,
    'PosSaleOrders': Icons.receipt_long_rounded,
    'PosQuotes': Icons.request_quote_rounded,
    'PosPrintTemplates': Icons.description_rounded,
    'PosContracts': Icons.handshake_rounded,
    'PosPromotions': Icons.local_offer_rounded,
    'PosQrOrder': Icons.qr_code_2_rounded,
    'PosSaleReturns': Icons.assignment_return_rounded,
    'PosBooking': Icons.event_available_rounded,
    'PosCustomers': Icons.groups_rounded,
    'PosWarranty': Icons.verified_user_rounded,
    'PosPurchaseReceipts': Icons.add_shopping_cart_rounded,
    'PosPurchaseReturns': Icons.keyboard_return_rounded,
    'PosStockCounts': Icons.fact_check_rounded,
    'PosDamageIssues': Icons.delete_sweep_rounded,
    'PosInternalUseIssues': Icons.outbox_rounded,
    'PosSalesReport': Icons.bar_chart_rounded,
    'PosReportPnl': Icons.account_tree_rounded,
    'CashTransaction': Icons.account_balance_wallet_rounded,
    'CashReport': Icons.paid_rounded,
    'SettingsHub': Icons.tune_rounded,
    'Settings': Icons.manage_accounts_rounded,
  };

  /// Biểu tượng nhóm trên Trang chủ.
  static const _byGroup = <String, IconData>{
    'Tài chính': Icons.account_balance_rounded,
    'POS': Icons.point_of_sale_rounded,
    'Bán hàng': Icons.point_of_sale_rounded,
    'Thương mại': Icons.request_quote_rounded,
    'Khách hàng & khuyến mãi': Icons.loyalty_rounded,
    'Hàng hóa & kho': Icons.inventory_2_rounded,
    'Báo cáo kinh doanh': Icons.insights_rounded,
    'Cài đặt': Icons.settings_rounded,
  };

  static IconData ofNav(String label, IconData fallback) =>
      SboxColors.posApp ? (_byLabel[label] ?? fallback) : fallback;

  static IconData ofModule(String? moduleCode, IconData fallback) =>
      SboxColors.posApp ? (_byModule[moduleCode] ?? fallback) : fallback;

  static IconData ofGroup(String group, IconData fallback) =>
      SboxColors.posApp ? (_byGroup[group] ?? fallback) : fallback;
}
