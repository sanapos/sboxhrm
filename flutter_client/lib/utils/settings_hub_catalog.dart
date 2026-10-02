import 'package:flutter/material.dart';

import '../config/sbox_app_variant.dart';
import '../models/settings_hub_sidebar_config.dart';
import '../theme/sbox_tokens.dart';

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
    this.healthKey,
    this.keywords = const [],
    this.packageModule,
  });

  /// Mã cố định của mục (dùng cho lối tắt, lưu thứ tự / ẩn hiện). Không đổi khi sắp xếp lại.
  final int index;
  final IconData icon;
  final String label;
  final String desc;
  final Color accent;
  final String groupTitle;
  final String? moduleCode;

  /// Khóa tình trạng từ /api/settings-health (null = không theo dõi).
  final String? healthKey;

  /// Từ khóa tìm kiếm thêm (viết thường, có dấu).
  final List<String> keywords;

  /// Gói dịch vụ phải có chức năng này mục mới hiện (vd mục chỉ dành cho bán hàng → PosSell).
  final String? packageModule;

  /// Chuỗi tìm kiếm: tên + mô tả + nhóm + từ khóa.
  String get searchText => '$label $desc $groupTitle ${keywords.join(' ')}'.toLowerCase();
}

/// Nhóm thiết lập theo nghiệp vụ.
class SettingsHubGroup {
  const SettingsHubGroup(this.title, this.icon, this.color, {this.hrm = false});
  final String title;
  final IconData icon;
  final Color color;

  /// Nhóm chỉ dành cho nhân sự (ẩn ở app POS độc lập).
  final bool hrm;
}

/// Danh mục Thiết lập SBOX.
/// «Khách hàng POS» (menu Bán hàng) và «Thiết lập lương» (menu Hồ sơ nhân sự) đã chuyển ra khỏi Thiết lập.
class SettingsHubCatalog {
  SettingsHubCatalog._();

  static const gStore = 'Cửa hàng & chi nhánh';
  static const gHr = 'Nhân sự & chấm công';
  static const gPay = 'Lương & chính sách';
  static const gSell = 'Bán hàng';
  static const gMoney = 'Thanh toán & hóa đơn';
  static const gPrint = 'In ấn & thiết bị';
  static const gAccount = 'Tài khoản & bảo mật';
  static const gIntegr = 'Tích hợp & thông báo';

  static const groups = <SettingsHubGroup>[
    SettingsHubGroup(gStore, Icons.storefront_rounded, SboxColors.brand600),
    SettingsHubGroup(gHr, Icons.schedule_rounded, SboxColors.brand700, hrm: true),
    SettingsHubGroup(gPay, Icons.payments_rounded, SboxColors.violet, hrm: true),
    SettingsHubGroup(gSell, Icons.point_of_sale_rounded, SboxColors.success),
    SettingsHubGroup(gMoney, Icons.account_balance_rounded, SboxColors.warning),
    SettingsHubGroup(gPrint, Icons.print_rounded, SboxColors.slate600),
    SettingsHubGroup(gAccount, Icons.admin_panel_settings_rounded, SboxColors.danger),
    SettingsHubGroup(gIntegr, Icons.hub_rounded, SboxColors.brand500),
  ];

  static SettingsHubGroup groupOf(String title) =>
      groups.firstWhere((g) => g.title == title, orElse: () => const SettingsHubGroup('Khác', Icons.folder_outlined, SboxColors.slate500));

  static const List<SettingsHubItemDef> allItems = [
    // ── Cửa hàng & chi nhánh
    SettingsHubItemDef(
      index: 17, icon: Icons.store_outlined, label: 'Thông tin cửa hàng', groupTitle: gStore, accent: SboxColors.brand600,
      desc: 'Tên, địa chỉ, logo, VAT, phụ thu, phí giao hàng', moduleCode: 'SettingsHub',
      keywords: ['vat', 'thuế giá trị gia tăng', 'phụ thu', 'logo', 'địa chỉ', 'cửa hàng'],
    ),
    SettingsHubItemDef(
      index: 13, icon: Icons.account_tree_outlined, label: 'Chi nhánh', groupTitle: gStore, accent: SboxColors.brand600,
      desc: 'Danh sách, cây chi nhánh, trụ sở, quản lý chi nhánh', moduleCode: 'Branch', healthKey: 'branch',
      keywords: ['trụ sở', 'cơ sở', 'kho'],
    ),
    SettingsHubItemDef(
      index: 9, icon: Icons.settings_suggest_outlined, label: 'Tham số hệ thống', groupTitle: gStore, accent: SboxColors.brand600,
      desc: 'Giờ kết thúc ngày, tham số vận hành chung', moduleCode: 'SystemSettings',
      keywords: ['giờ chốt ngày', 'ngày làm việc', 'hệ thống'],
    ),
    // ── Nhân sự & chấm công
    SettingsHubItemDef(
      index: 0, icon: Icons.schedule_rounded, label: 'Ca làm việc', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Ca mẫu, giờ vào ra, đi trễ, về sớm, tăng ca, lương ca', moduleCode: 'ShiftSetup', healthKey: 'shift',
      keywords: ['ca mẫu', 'tăng ca', 'đi trễ', 'về sớm', 'nghỉ trưa', 'ca đêm'],
    ),
    SettingsHubItemDef(
      index: 14, icon: Icons.groups_outlined, label: 'Định mức nhân sự', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Số người tối thiểu / tối đa mỗi ca theo bộ phận, thứ trong tuần', moduleCode: 'WorkSchedule',
      keywords: ['min max', 'xếp ca', 'thiếu người'],
    ),
    SettingsHubItemDef(
      index: 2, icon: Icons.celebration_outlined, label: 'Ngày lễ', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Ngày nghỉ lễ, hệ số lương ngày lễ', moduleCode: 'Holiday', healthKey: 'holiday',
      keywords: ['tết', 'nghỉ lễ', 'hệ số', 'lịch nghỉ'],
    ),
    SettingsHubItemDef(
      index: 1, icon: Icons.phone_android_outlined, label: 'Chấm công Mobile', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Vị trí chấm công, GPS, khuôn mặt, ảnh hiện trường, tự duyệt', moduleCode: 'MobileAttendance', healthKey: 'mobile',
      keywords: ['gps', 'face id', 'khuôn mặt', 'vị trí', 'wifi', 'điện thoại'],
    ),
    SettingsHubItemDef(
      index: 12, icon: Icons.fingerprint_rounded, label: 'Máy chấm công', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Kết nối, đồng bộ, điều khiển máy chấm công vân tay / khuôn mặt', moduleCode: 'Device', healthKey: 'device',
      keywords: ['zkteco', 'vân tay', 'adms', 'máy cc'],
    ),
    SettingsHubItemDef(
      index: 25, icon: Icons.wifi_tethering_rounded, label: 'Gateway WiFi', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Mạch ESP32 nối máy chấm công đời cũ lên máy chủ', moduleCode: 'Device',
      keywords: ['esp32', 'máy cũ'],
    ),
    // ── Lương & chính sách
    SettingsHubItemDef(
      index: 31, icon: Icons.beach_access_outlined, label: 'Phép năm', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Số ngày phép, thâm niên, chuyển phép, tiền phép còn lại', moduleCode: 'Leave',
      keywords: ['nghỉ phép', 'phép tồn', 'thâm niên', 'trả tiền phép'],
    ),
    SettingsHubItemDef(
      index: 3, icon: Icons.card_giftcard_outlined, label: 'Phụ cấp', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Phụ cấp cố định, theo ngày công, theo ca', moduleCode: 'Allowance', healthKey: 'allowance',
      keywords: ['ăn trưa', 'xăng xe', 'điện thoại', 'chuyên cần'],
    ),
    SettingsHubItemDef(
      index: 4, icon: Icons.gavel_outlined, label: 'Mức phạt', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Đi trễ, về sớm, quên chấm, tái phạm', moduleCode: 'PenaltySetup', healthKey: 'penalty',
      keywords: ['phạt', 'đi muộn', 'kỷ luật', 'quên chấm công'],
    ),
    SettingsHubItemDef(
      index: 5, icon: Icons.health_and_safety_outlined, label: 'Bảo hiểm', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'BHXH, BHYT, BHTN, lương cơ sở, vùng', moduleCode: 'Insurance', healthKey: 'insurance',
      keywords: ['bhxh', 'bhyt', 'bhtn', 'lương tối thiểu vùng', 'lương cơ sở'],
    ),
    SettingsHubItemDef(
      index: 6, icon: Icons.receipt_long_outlined, label: 'Thuế TNCN', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Biểu thuế lũy tiến, giảm trừ gia cảnh', moduleCode: 'Tax', healthKey: 'tax',
      keywords: ['thuế thu nhập', 'giảm trừ', 'người phụ thuộc', 'tncn'],
    ),
    SettingsHubItemDef(
      index: 10, icon: Icons.precision_manufacturing_outlined, label: 'Lương sản phẩm', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Nhóm sản phẩm, đơn giá theo bậc', moduleCode: 'ProductSalary',
      keywords: ['khoán', 'sản lượng', 'đơn giá'],
    ),
    // ── Bán hàng
    SettingsHubItemDef(
      index: 16, icon: Icons.storefront_rounded, label: 'Ngành hàng & bán hàng', groupTitle: gSell, accent: SboxColors.success,
      desc: 'Hồ sơ ngành, lý do hủy / trả hàng, cách bán', moduleCode: 'SettingsHub', packageModule: 'PosSell',
      keywords: ['ngành', 'cafe', 'nhà hàng', 'bán lẻ', 'hủy đơn', 'trả hàng'],
    ),
    SettingsHubItemDef(
      index: 19, icon: Icons.table_restaurant_outlined, label: 'Bàn / phòng', groupTitle: gSell, accent: SboxColors.success,
      desc: 'Sơ đồ mặt bằng, khu vực, bàn ghế, phòng', moduleCode: 'SettingsHub', packageModule: 'PosSell',
      keywords: ['sơ đồ bàn', 'khu vực', 'phòng hát', 'karaoke'],
    ),
    SettingsHubItemDef(
      index: 23, icon: Icons.tv_outlined, label: 'Màn hình phụ', groupTitle: gSell, accent: SboxColors.success,
      desc: 'Màn hình khách hàng, ảnh / video quảng cáo khi bán', moduleCode: 'PosCustomerDisplay',
      keywords: ['customer display', 'màn hình khách'],
    ),
    // ── Thanh toán & hóa đơn
    SettingsHubItemDef(
      index: 28, icon: Icons.account_balance_outlined, label: 'Tài khoản nhận tiền', groupTitle: gMoney, accent: SboxColors.warning,
      desc: 'Tài khoản ngân hàng, VietQR, Tingee báo có tự động', moduleCode: 'BankAccount', healthKey: 'payment',
      keywords: ['ngân hàng', 'vietqr', 'tingee', 'chuyển khoản', 'qr', 'cổng thanh toán'],
    ),
    SettingsHubItemDef(
      index: 26, icon: Icons.request_quote_outlined, label: 'Hóa đơn điện tử', groupTitle: gMoney, accent: SboxColors.warning,
      desc: 'Viettel, Easy, MISA, VNPT — xuất, hủy, thay thế, gửi email', moduleCode: 'PosEInvoice', healthKey: 'einvoice',
      keywords: ['hđđt', 'viettel', 'misa', 'vnpt', 'easyinvoice'],
    ),
    SettingsHubItemDef(
      index: 27, icon: Icons.local_shipping_outlined, label: 'Đơn vị giao hàng', groupTitle: gMoney, accent: SboxColors.warning,
      desc: 'GHN, GHTK, SPX, Viettel Post, AhaMove — kết nối, tạo vận đơn', moduleCode: 'PosShipping', healthKey: 'shipping',
      keywords: ['ghn', 'ghtk', 'vận chuyển', 'ship', 'vận đơn'],
    ),
    // ── In ấn & thiết bị
    SettingsHubItemDef(
      index: 18, icon: Icons.print_outlined, label: 'Máy in', groupTitle: gPrint, accent: SboxColors.slate600,
      desc: 'Máy in hóa đơn, bếp, tem ly — Bluetooth, LAN, USB', moduleCode: 'PosPrinters',
      keywords: ['bluetooth', 'lan', 'k80', 'k58', 'in bếp', 'tem'],
    ),
    SettingsHubItemDef(
      index: 29, icon: Icons.cloud_outlined, label: 'Máy in cloud', groupTitle: gPrint, accent: SboxColors.slate600,
      desc: 'In từ xa qua Print Agent', moduleCode: 'PosStorePrinters', healthKey: 'cloudPrinter',
      keywords: ['print agent', 'in từ xa'],
    ),
    SettingsHubItemDef(
      index: 15, icon: Icons.design_services_outlined, label: 'Mẫu in', groupTitle: gPrint, accent: SboxColors.slate600,
      desc: 'Thiết kế hóa đơn K58 / K80, tem 50×30, phiếu bếp', moduleCode: 'PosPrintTemplates',
      keywords: ['hóa đơn', 'tem', 'phiếu', 'mẫu hóa đơn'],
    ),
    // ── Tài khoản & bảo mật
    SettingsHubItemDef(
      index: 7, icon: Icons.manage_accounts_outlined, label: 'Tài khoản', groupTitle: gAccount, accent: SboxColors.danger,
      desc: 'Người dùng, kích hoạt, đặt lại mật khẩu, vai trò', moduleCode: 'UserManagement',
      keywords: ['người dùng', 'mật khẩu', 'đăng nhập', 'user'],
    ),
    SettingsHubItemDef(
      index: 8, icon: Icons.security_outlined, label: 'Phân quyền', groupTitle: gAccount, accent: SboxColors.danger,
      desc: 'Vai trò, ma trận quyền theo chức năng', moduleCode: 'Role',
      keywords: ['quyền', 'vai trò', 'role'],
    ),
    SettingsHubItemDef(
      index: 30, icon: Icons.devices_other_outlined, label: 'Thiết bị truy cập', groupTitle: gAccount, accent: SboxColors.danger,
      desc: 'Điện thoại / máy tính / POS đang dùng suất của gói dịch vụ', moduleCode: 'UserManagement',
      keywords: ['slot', 'đăng xuất thiết bị', 'gói dịch vụ'],
    ),
    // ── Tích hợp & thông báo
    SettingsHubItemDef(
      index: 11, icon: Icons.auto_awesome_outlined, label: 'Trợ lý AI', groupTitle: gIntegr, accent: SboxColors.brand500,
      desc: 'Gemini, bật / tắt trợ lý AI', moduleCode: 'AIGemini',
      keywords: ['gemini', 'ai', 'trí tuệ nhân tạo'],
    ),
    SettingsHubItemDef(
      index: 21, icon: Icons.notifications_active_outlined, label: 'Thông báo', groupTitle: gIntegr, accent: SboxColors.brand500,
      desc: 'Bật / tắt thông báo chấm công, công việc, bán hàng', moduleCode: 'NotificationSettings',
      keywords: ['push', 'nhắc nhở', 'fcm'],
    ),
  ];

  static List<int> get defaultOrder => itemsForCurrentApp.map((item) => item.index).toList();

  /// HRM: toàn bộ thiết lập. POS độc lập: bỏ nhóm nhân sự / lương.
  static List<SettingsHubItemDef> get itemsForCurrentApp {
    if (!SboxAppVariant.standalonePos) return allItems;
    final hrmGroups = groups.where((g) => g.hrm).map((g) => g.title).toSet();
    return allItems.where((i) => !hrmGroups.contains(i.groupTitle)).toList();
  }

  static SettingsHubItemDef? byIndex(int index) {
    for (final item in allItems) {
      if (item.index == index) return item;
    }
    return null;
  }

  /// Tìm theo tên, mô tả, nhóm, từ khóa (không phân biệt hoa thường).
  static List<SettingsHubItemDef> search(List<SettingsHubItemDef> items, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    final words = q.split(RegExp(r'\s+'));
    return items.where((i) => words.every(i.searchText.contains)).toList();
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

  /// Gom theo nhóm (thứ tự nhóm cố định, thứ tự mục trong nhóm theo cấu hình).
  static List<({String title, List<SettingsHubItemDef> items})> groupOrderedItems(
    List<SettingsHubItemDef> ordered,
  ) {
    final result = <({String title, List<SettingsHubItemDef> items})>[];
    for (final g in groups) {
      final items = ordered.where((i) => i.groupTitle == g.title).toList();
      if (items.isNotEmpty) result.add((title: g.title, items: items));
    }
    return result;
  }
}
