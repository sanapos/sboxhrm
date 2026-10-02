import 'package:flutter/material.dart';

import '../models/settings_hub_sidebar_config.dart';
import '../widgets/hrm_page_chrome.dart';

/// Định nghĩa một mục trong Thiết lập SBOX.
class SettingsHubItemDef {
  const SettingsHubItemDef({
    required this.index,
    required this.icon,
    required this.label,
    required this.desc,
    required this.accent,
    required this.groupTitle,
    this.moduleCode,
    this.altModuleCodes = const [],
  });

  final int index;
  final IconData icon;
  final String label;
  final String desc;
  final Color accent;
  final String groupTitle;
  final String? moduleCode;

  /// Mã quyền thay thế: có một trong các mã này cũng thấy mục (Máy in = thiết bị hoặc cloud).
  final List<String> altModuleCodes;
}

/// Danh mục Thiết lập SBOX (cấu hình cửa hàng). Cài đặt cá nhân nằm ở «Cài đặt».
class SettingsHubCatalog {
  SettingsHubCatalog._();

  static const List<SettingsHubItemDef> allItems = [
    SettingsHubItemDef(
      index: 0,
      icon: Icons.schedule_send,
      label: 'Ca làm việc',
      desc: 'Ca làm việc, vào sớm, đi trễ, về sớm, tăng ca',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Nhân sự & chấm công',
      moduleCode: 'ShiftSetup',
    ),
    SettingsHubItemDef(
      index: 1,
      icon: Icons.phone_android,
      label: 'Chấm công mobile',
      desc: 'Face ID, GPS, cấp quyền thiết bị, vùng chấm công',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Nhân sự & chấm công',
      moduleCode: 'MobileAttendance',
    ),
    SettingsHubItemDef(
      index: 2,
      icon: Icons.celebration,
      label: 'Ngày lễ',
      desc: 'Ngày nghỉ lễ, hệ số công, cấu hình lịch nghỉ',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Nhân sự & chấm công',
      moduleCode: 'Holiday',
    ),
    SettingsHubItemDef(
      index: 12,
      icon: Icons.router,
      label: 'Máy chấm công',
      desc: 'Kết nối, quản lý, điều khiển máy chấm công',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Nhân sự & chấm công',
      moduleCode: 'Device',
    ),
    SettingsHubItemDef(
      index: 25,
      icon: Icons.wifi_tethering,
      label: 'Gateway WiFi',
      desc: 'Cài đặt mạch ESP32 nối máy chấm công cũ lên máy chủ',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Nhân sự & chấm công',
      moduleCode: 'Device',
    ),
    SettingsHubItemDef(
      index: 14,
      icon: Icons.groups,
      label: 'Định mức nhân sự',
      desc: 'Min/Max nhân sự theo ca, phòng ban, từng thứ T2–CN',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Nhân sự & chấm công',
      moduleCode: 'WorkSchedule',
    ),
    SettingsHubItemDef(
      index: 3,
      icon: Icons.card_giftcard,
      label: 'Phụ cấp',
      desc: 'Phụ cấp cố định, phụ cấp ngày công',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Lương & chính sách',
      moduleCode: 'Allowance',
    ),
    SettingsHubItemDef(
      index: 4,
      icon: Icons.gavel,
      label: 'Mức phạt',
      desc: 'Đi trễ, về sớm, tái phạm, kỷ luật',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Lương & chính sách',
      moduleCode: 'PenaltySetup',
    ),
    SettingsHubItemDef(
      index: 5,
      icon: Icons.health_and_safety,
      label: 'Bảo hiểm',
      desc: 'BHXH, BHYT, BHTN, lương cơ sở',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Lương & chính sách',
      moduleCode: 'Insurance',
    ),
    SettingsHubItemDef(
      index: 6,
      icon: Icons.receipt_long,
      label: 'Thuế TNCN',
      desc: 'Bậc thuế, giảm trừ gia cảnh',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Lương & chính sách',
      moduleCode: 'Tax',
    ),
    SettingsHubItemDef(
      index: 10,
      icon: Icons.precision_manufacturing,
      label: 'Lương sản phẩm',
      desc: 'Nhóm SP, sản phẩm, đơn giá theo bậc',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Lương & chính sách',
      moduleCode: 'ProductSalary',
    ),
    SettingsHubItemDef(
      index: 20,
      icon: Icons.price_change_outlined,
      label: 'Thiết lập lương',
      desc: 'Bảng lương, tham số tính lương nhân viên',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Lương & chính sách',
      moduleCode: 'SalarySettings',
    ),
    SettingsHubItemDef(
      index: 7,
      icon: Icons.manage_accounts,
      label: 'Tài khoản nhân viên',
      desc: 'Người dùng, kích hoạt, vai trò',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Người dùng & bảo mật',
      moduleCode: 'UserManagement',
    ),
    SettingsHubItemDef(
      index: 8,
      icon: Icons.security,
      label: 'Phân quyền',
      desc: 'Ma trận quyền, vai trò, module',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Người dùng & bảo mật',
      moduleCode: 'Role',
    ),
    SettingsHubItemDef(
      index: 9,
      icon: Icons.settings_suggest,
      label: 'Tham số hệ thống',
      desc: 'Giờ kết thúc ngày, tham số vận hành',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Người dùng & bảo mật',
      moduleCode: 'SystemSettings',
    ),
    SettingsHubItemDef(
      index: 13,
      icon: Icons.business,
      label: 'Chi nhánh',
      desc: 'Quản lý chi nhánh, cây chi nhánh, thống kê',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Người dùng & bảo mật',
      moduleCode: 'Branch',
    ),
    SettingsHubItemDef(
      index: 30,
      icon: Icons.devices_other_outlined,
      label: 'Thiết bị truy cập',
      desc: 'Nhả điện thoại / web / POS chiếm slot gói dịch vụ',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Người dùng & bảo mật',
      moduleCode: 'SettingsHub',
    ),
    SettingsHubItemDef(
      index: 15,
      icon: Icons.print_outlined,
      label: 'Mẫu in',
      desc: 'Hóa đơn K58/K80, tem 50×30… — thiết kế mẫu in',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Bán hàng, thanh toán & in',
      moduleCode: 'PosPrintTemplates',
    ),
    SettingsHubItemDef(
      index: 16,
      icon: Icons.storefront_outlined,
      label: 'Ngành hàng & cách bán',
      desc: 'Hồ sơ ngành, hủy/trả hàng',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Bán hàng, thanh toán & in',
      moduleCode: 'SettingsHub',
    ),
    SettingsHubItemDef(
      index: 17,
      icon: Icons.store_outlined,
      label: 'Thông tin cửa hàng',
      desc: 'Tên, địa chỉ, VAT, phụ thu, phí giao hàng',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Bán hàng, thanh toán & in',
      moduleCode: 'SettingsHub',
    ),
    SettingsHubItemDef(
      index: 28,
      icon: Icons.account_balance_outlined,
      label: 'Tài khoản nhận tiền',
      desc: 'Bật/tắt VietQR, Tingee · tài khoản NH · token',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Bán hàng, thanh toán & in',
      moduleCode: 'SettingsHub',
    ),
    SettingsHubItemDef(
      index: 27,
      icon: Icons.local_shipping_outlined,
      label: 'Đơn vị giao hàng',
      desc: 'GHN, GHTK, SPX Express, Viettel Post, AhaMove — token, tạo vận đơn',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Bán hàng, thanh toán & in',
      moduleCode: 'PosShipping',
    ),
    SettingsHubItemDef(
      index: 26,
      icon: Icons.request_quote_outlined,
      label: 'Hóa đơn điện tử',
      desc: 'Viettel / Easy / MISA / VNPT — xuất, xem lại, hủy, thay thế, email, báo cáo',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Bán hàng, thanh toán & in',
      moduleCode: 'PosEInvoice',
    ),
    SettingsHubItemDef(
      index: 18,
      icon: Icons.print_outlined,
      label: 'Máy in',
      desc: 'Máy in trên máy này (Bluetooth, LAN, USB) và máy in cloud qua Print Agent',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Bán hàng, thanh toán & in',
      moduleCode: 'PosPrinters',
      altModuleCodes: ['PosStorePrinters'],
    ),
    SettingsHubItemDef(
      index: 19,
      icon: Icons.table_restaurant_outlined,
      label: 'Bàn / phòng',
      desc: 'Sơ đồ mặt bằng, tạo/sửa bàn ghế',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Bán hàng, thanh toán & in',
      moduleCode: 'SettingsHub',
    ),
    SettingsHubItemDef(
      index: 23,
      icon: Icons.tv_outlined,
      label: 'Màn hình phụ',
      desc: 'Customer display, media khi bán',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Bán hàng, thanh toán & in',
      moduleCode: 'PosCustomerDisplay',
    ),
    SettingsHubItemDef(
      index: 11,
      icon: Icons.auto_awesome,
      label: 'Trợ lý AI',
      desc: 'Gemini, bật/tắt AI',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Tích hợp & thông báo',
      moduleCode: 'AIGemini',
    ),
    SettingsHubItemDef(
      index: 21,
      icon: Icons.notifications_active_outlined,
      label: 'Thông báo',
      desc: 'Bật/tắt thông báo chấm công & công việc',
      accent: HrmPageChrome.primaryNavy,
      groupTitle: 'Tích hợp & thông báo',
      moduleCode: 'NotificationSettings',
    ),
  ];

  static List<int> get defaultOrder =>
      allItems.map((item) => item.index).toList();

  /// Mã số cũ đã gộp vào mục khác (lối tắt / «mở gần đây» cũ vẫn mở đúng chỗ).
  static const legacyIndex = {29: 18, 24: -1};

  static int canonicalIndex(int index) => legacyIndex[index] ?? index;

  static SettingsHubItemDef? byIndex(int index) {
    final i = canonicalIndex(index);
    for (final item in allItems) {
      if (item.index == i) return item;
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
