import 'package:flutter/material.dart';

import '../models/settings_hub_sidebar_config.dart';
import '../widgets/hrm_page_chrome.dart';

/// Định nghĩa một mục menu trong Thiết lập HRM.
class SettingsHubItemDef {
  const SettingsHubItemDef({
    required this.index,
    required this.icon,
    required this.label,
    required this.desc,
    required this.accent,
    required this.groupTitle,
    this.moduleCode,
  });

  final int index;
  final IconData icon;
  final String label;
  final String desc;
  final Color accent;
  final String groupTitle;
  final String? moduleCode;
}

/// Danh mục cố định các module Thiết lập HRM.
class SettingsHubCatalog {
  SettingsHubCatalog._();

  static const List<SettingsHubItemDef> allItems = [
    SettingsHubItemDef(
      index: 0,
      icon: Icons.schedule_send,
      label: 'Thiết lập ca',
      desc: 'Ca làm việc, vào sớm, đi trễ, về sớm, tăng ca',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Chấm công & Ca',
      moduleCode: 'ShiftSetup',
    ),
    SettingsHubItemDef(
      index: 1,
      icon: Icons.phone_android,
      label: 'Chấm công mobile',
      desc: 'Face ID, GPS, cấp quyền thiết bị, vùng chấm công',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Chấm công & Ca',
      moduleCode: 'MobileAttendance',
    ),
    SettingsHubItemDef(
      index: 2,
      icon: Icons.celebration,
      label: 'Ngày lễ',
      desc: 'Ngày nghỉ lễ, hệ số công, cấu hình lịch nghỉ',
      accent: Color(0xFFEF4444),
      groupTitle: 'Chấm công & Ca',
      moduleCode: 'Holiday',
    ),
    SettingsHubItemDef(
      index: 12,
      icon: Icons.router,
      label: 'Máy chấm công',
      desc: 'Kết nối, quản lý, điều khiển máy chấm công',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Chấm công & Ca',
      moduleCode: 'Device',
    ),
    SettingsHubItemDef(
      index: 14,
      icon: Icons.groups,
      label: 'Định mức nhân sự',
      desc: 'Min/Max nhân sự theo ca, phòng ban, từng thứ T2–CN',
      accent: Color(0xFF7C3AED),
      groupTitle: 'Chấm công & Ca',
      moduleCode: 'WorkSchedule',
    ),
    SettingsHubItemDef(
      index: 3,
      icon: Icons.card_giftcard,
      label: 'Phụ cấp',
      desc: 'Phụ cấp cố định, phụ cấp ngày công',
      accent: Color(0xFFEC4899),
      groupTitle: 'Chính sách lương',
      moduleCode: 'Allowance',
    ),
    SettingsHubItemDef(
      index: 4,
      icon: Icons.gavel,
      label: 'Phạt',
      desc: 'Đi trễ, về sớm, tái phạm, kỷ luật',
      accent: Color(0xFFF97316),
      groupTitle: 'Chính sách lương',
      moduleCode: 'PenaltySetup',
    ),
    SettingsHubItemDef(
      index: 5,
      icon: Icons.health_and_safety,
      label: 'Bảo hiểm',
      desc: 'BHXH, BHYT, BHTN, lương cơ sở',
      accent: Color(0xFF2D5F8B),
      groupTitle: 'Chính sách lương',
      moduleCode: 'Insurance',
    ),
    SettingsHubItemDef(
      index: 6,
      icon: Icons.receipt_long,
      label: 'Thuế TNCN',
      desc: 'Bậc thuế, giảm trừ gia cảnh',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Chính sách lương',
      moduleCode: 'Tax',
    ),
    SettingsHubItemDef(
      index: 10,
      icon: Icons.precision_manufacturing,
      label: 'Lương sản phẩm',
      desc: 'Nhóm SP, sản phẩm, đơn giá theo bậc',
      accent: Color(0xFF059669),
      groupTitle: 'Chính sách lương',
      moduleCode: 'ProductSalary',
    ),
    SettingsHubItemDef(
      index: 7,
      icon: Icons.manage_accounts,
      label: 'Tài khoản',
      desc: 'Người dùng, kích hoạt, vai trò',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Quản trị hệ thống',
      moduleCode: 'UserManagement',
    ),
    SettingsHubItemDef(
      index: 8,
      icon: Icons.security,
      label: 'Phân quyền',
      desc: 'Ma trận quyền, vai trò, module',
      accent: Color(0xFFEF4444),
      groupTitle: 'Quản trị hệ thống',
      moduleCode: 'Role',
    ),
    SettingsHubItemDef(
      index: 9,
      icon: Icons.settings_suggest,
      label: 'Hệ thống',
      desc: 'Giờ kết thúc ngày, tham số vận hành',
      accent: Color(0xFF334155),
      groupTitle: 'Quản trị hệ thống',
      moduleCode: 'SystemSettings',
    ),
    SettingsHubItemDef(
      index: 13,
      icon: Icons.business,
      label: 'Chi nhánh',
      desc: 'Quản lý chi nhánh, cây chi nhánh, thống kê',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Quản trị hệ thống',
      moduleCode: 'Branch',
    ),
    SettingsHubItemDef(
      index: 15,
      icon: Icons.print_outlined,
      label: 'Mẫu in',
      desc: 'K58, K80, A5, A4 — thiết kế hóa đơn, phiếu',
      accent: Color(0xFF2563EB),
      groupTitle: 'POS / Bán hàng',
      moduleCode: 'PosProducts',
    ),
    SettingsHubItemDef(
      index: 16,
      icon: Icons.storefront_outlined,
      label: 'Ngành hàng & bán hàng',
      desc: 'Hồ sơ ngành, bàn/ghế, tính giờ, gói buổi',
      accent: Color(0xFF0D9488),
      groupTitle: 'POS / Bán hàng',
      moduleCode: 'PosSell',
    ),
    SettingsHubItemDef(
      index: 11,
      icon: Icons.auto_awesome,
      label: 'Thiết lập AI',
      desc: 'Gemini, bật/tắt AI',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Tích hợp',
      moduleCode: 'AIGemini',
    ),
  ];

  static List<int> get defaultOrder =>
      allItems.map((item) => item.index).toList();

  static SettingsHubItemDef? byIndex(int index) {
    for (final item in allItems) {
      if (item.index == index) return item;
    }
    return null;
  }

  /// Áp dụng cấu hình tùy chỉnh lên danh sách đã lọc quyền.
  static List<SettingsHubItemDef> applyConfig(
    List<SettingsHubItemDef> permitted,
    SettingsHubSidebarConfig? config,
  ) {
    if (permitted.isEmpty) return const [];
    final permittedIds = permitted.map((e) => e.index).toSet();
    if (config == null || config.order.isEmpty) return permitted;

    final byId = {for (final item in permitted) item.index: item};
    final seen = <int>{};
    final ordered = <SettingsHubItemDef>[];

    for (final id in config.order) {
      if (!permittedIds.contains(id) || config.hidden.contains(id)) continue;
      final item = byId[id];
      if (item == null || seen.contains(id)) continue;
      ordered.add(item);
      seen.add(id);
    }

    for (final item in permitted) {
      if (seen.contains(item.index) || config.hidden.contains(item.index)) {
        continue;
      }
      ordered.add(item);
    }
    return ordered;
  }

  /// Nhóm các mục đã sắp xếp để hiển thị header nhóm trên sidebar.
  static List<({String title, List<SettingsHubItemDef> items})> groupOrderedItems(
    List<SettingsHubItemDef> ordered,
  ) {
    final result = <({String title, List<SettingsHubItemDef> items})>[];
    for (final item in ordered) {
      if (result.isEmpty || result.last.title != item.groupTitle) {
        result.add((title: item.groupTitle, items: [item]));
      } else {
        final last = result.removeLast();
        result.add((
          title: last.title,
          items: [...last.items, item],
        ));
      }
    }
    return result;
  }
}
