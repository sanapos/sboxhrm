import 'package:flutter/material.dart';

import '../config/sbox_app_variant.dart';
import '../models/settings_hub_sidebar_config.dart';
import '../theme/sbox_tokens.dart';

/// Định nghĩa một mục trong Thiết lập SBOX.
class SettingsHubItemDef {
  const SettingsHubItemDef({
    required this.index,
    required this.code,
    required this.icon,
    required this.label,
    required this.desc,
    required this.accent,
    required this.groupTitle,
    this.moduleCode,
    this.healthKey,
    this.keywords = const [],
    this.packageModule,
    this.altModuleCodes = const [],
  });

  /// Mã số cố định (lưu thứ tự / ẩn hiện / mở gần đây trên máy). Không đổi khi sắp xếp lại.
  final int index;

  /// Mã chữ cố định để mở thẳng một mục từ chỗ khác: `SettingsHubScreen.openCode('printers')`.
  final String code;

  /// Mã quyền thay thế: có quyền một trong các mã này cũng thấy mục (vd Máy in = thiết bị hoặc cloud).
  final List<String> altModuleCodes;
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

/// Danh mục Thiết lập SBOX — mọi cấu hình của cửa hàng, tối đa 2 tầng (nhóm → mục).
/// Cài đặt cá nhân (hồ sơ, mật khẩu, giao diện, ngôn ngữ, phiên bản) nằm ở «Cài đặt», không ở đây.
/// «Khách hàng POS» (menu Bán hàng), «Thiết lập lương» (menu Hồ sơ nhân sự), «Lịch sử hủy / trả» và
/// «Màn hình bếp» (POS › Giao dịch) là màn vận hành, không thuộc Thiết lập.
class SettingsHubCatalog {
  SettingsHubCatalog._();

  static const gStore = 'Cửa hàng';
  static const gHr = 'Nhân sự & chấm công';
  static const gPay = 'Lương & chính sách';
  static const gSell = 'Bán hàng';
  static const gMoney = 'Thanh toán & hóa đơn';
  static const gPrint = 'In ấn';
  static const gAccount = 'Người dùng & bảo mật';
  static const gIntegr = 'Tích hợp & thông báo';

  static const groups = <SettingsHubGroup>[
    SettingsHubGroup(gStore, Icons.storefront_rounded, SboxColors.brand600),
    SettingsHubGroup(gSell, Icons.point_of_sale_rounded, SboxColors.success),
    SettingsHubGroup(gMoney, Icons.account_balance_rounded, SboxColors.warning),
    SettingsHubGroup(gPrint, Icons.print_rounded, SboxColors.slate600),
    SettingsHubGroup(gHr, Icons.schedule_rounded, SboxColors.brand700, hrm: true),
    SettingsHubGroup(gPay, Icons.payments_rounded, SboxColors.violet, hrm: true),
    SettingsHubGroup(gAccount, Icons.admin_panel_settings_rounded, SboxColors.danger),
    SettingsHubGroup(gIntegr, Icons.hub_rounded, SboxColors.brand500),
  ];

  static SettingsHubGroup groupOf(String title) =>
      groups.firstWhere((g) => g.title == title, orElse: () => const SettingsHubGroup('Khác', Icons.folder_outlined, SboxColors.slate500));

  static const List<SettingsHubItemDef> allItems = [
    // ── Cửa hàng & chi nhánh
    SettingsHubItemDef(
      index: 17, code: 'store', icon: Icons.store_outlined, label: 'Thông tin cửa hàng', groupTitle: gStore, accent: SboxColors.brand600,
      desc: 'Tên, địa chỉ, logo, VAT, phụ thu, phí giao hàng', moduleCode: 'SettingsHub',
      keywords: ['vat', 'thuế giá trị gia tăng', 'phụ thu', 'logo', 'địa chỉ', 'cửa hàng'],
    ),
    SettingsHubItemDef(
      index: 13, code: 'branch', icon: Icons.account_tree_outlined, label: 'Chi nhánh', groupTitle: gStore, accent: SboxColors.brand600,
      desc: 'Danh sách, cây chi nhánh, trụ sở, quản lý chi nhánh', moduleCode: 'Branch', healthKey: 'branch',
      keywords: ['trụ sở', 'cơ sở', 'kho'],
    ),
    SettingsHubItemDef(
      index: 9, code: 'system', icon: Icons.settings_suggest_outlined, label: 'Tham số hệ thống', groupTitle: gStore, accent: SboxColors.brand600,
      desc: 'Giờ kết thúc ngày, tham số vận hành chung', moduleCode: 'SystemSettings',
      keywords: ['giờ chốt ngày', 'ngày làm việc', 'hệ thống'],
    ),
    // ── Nhân sự & chấm công
    SettingsHubItemDef(
      index: 0, code: 'shift', icon: Icons.schedule_rounded, label: 'Ca làm việc', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Ca mẫu, giờ vào ra, đi trễ, về sớm, tăng ca, lương ca', moduleCode: 'ShiftSetup', healthKey: 'shift',
      keywords: ['ca mẫu', 'tăng ca', 'đi trễ', 'về sớm', 'nghỉ trưa', 'ca đêm'],
    ),
    SettingsHubItemDef(
      index: 14, code: 'staffing', icon: Icons.groups_outlined, label: 'Định mức nhân sự', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Số người tối thiểu / tối đa mỗi ca theo bộ phận, thứ trong tuần', moduleCode: 'WorkSchedule',
      keywords: ['min max', 'xếp ca', 'thiếu người'],
    ),
    SettingsHubItemDef(
      index: 2, code: 'holiday', icon: Icons.celebration_outlined, label: 'Ngày lễ', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Ngày nghỉ lễ, hệ số lương ngày lễ', moduleCode: 'Holiday', healthKey: 'holiday',
      keywords: ['tết', 'nghỉ lễ', 'hệ số', 'lịch nghỉ'],
    ),
    SettingsHubItemDef(
      index: 1, code: 'mobileAttendance', icon: Icons.phone_android_outlined, label: 'Chấm công Mobile', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Vị trí chấm công, GPS, khuôn mặt, ảnh hiện trường, tự duyệt', moduleCode: 'MobileAttendance', healthKey: 'mobile',
      keywords: ['gps', 'face id', 'khuôn mặt', 'vị trí', 'wifi', 'điện thoại'],
    ),
    SettingsHubItemDef(
      index: 12, code: 'device', icon: Icons.fingerprint_rounded, label: 'Máy chấm công', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Kết nối, đồng bộ, điều khiển máy chấm công vân tay / khuôn mặt', moduleCode: 'Device', healthKey: 'device',
      keywords: ['zkteco', 'vân tay', 'adms', 'máy cc'],
    ),
    SettingsHubItemDef(
      index: 25, code: 'gateway', icon: Icons.wifi_tethering_rounded, label: 'Gateway WiFi', groupTitle: gHr, accent: SboxColors.brand700,
      desc: 'Mạch ESP32 nối máy chấm công đời cũ lên máy chủ', moduleCode: 'Device',
      keywords: ['esp32', 'máy cũ'],
    ),
    // ── Lương & chính sách
    SettingsHubItemDef(
      index: 31, code: 'annualLeave', icon: Icons.beach_access_outlined, label: 'Phép năm', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Số ngày phép, thâm niên, chuyển phép, tiền phép còn lại', moduleCode: 'Leave',
      keywords: ['nghỉ phép', 'phép tồn', 'thâm niên', 'trả tiền phép'],
    ),
    SettingsHubItemDef(
      index: 3, code: 'allowance', icon: Icons.card_giftcard_outlined, label: 'Phụ cấp', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Phụ cấp cố định, theo ngày công, theo ca', moduleCode: 'Allowance', healthKey: 'allowance',
      keywords: ['ăn trưa', 'xăng xe', 'điện thoại', 'chuyên cần'],
    ),
    SettingsHubItemDef(
      index: 4, code: 'penalty', icon: Icons.gavel_outlined, label: 'Mức phạt', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Đi trễ, về sớm, quên chấm, tái phạm', moduleCode: 'PenaltySetup', healthKey: 'penalty',
      keywords: ['phạt', 'đi muộn', 'kỷ luật', 'quên chấm công'],
    ),
    SettingsHubItemDef(
      index: 5, code: 'insurance', icon: Icons.health_and_safety_outlined, label: 'Bảo hiểm', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'BHXH, BHYT, BHTN, lương cơ sở, vùng', moduleCode: 'Insurance', healthKey: 'insurance',
      keywords: ['bhxh', 'bhyt', 'bhtn', 'lương tối thiểu vùng', 'lương cơ sở'],
    ),
    SettingsHubItemDef(
      index: 6, code: 'tax', icon: Icons.receipt_long_outlined, label: 'Thuế TNCN', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Biểu thuế lũy tiến, giảm trừ gia cảnh', moduleCode: 'Tax', healthKey: 'tax',
      keywords: ['thuế thu nhập', 'giảm trừ', 'người phụ thuộc', 'tncn'],
    ),
    SettingsHubItemDef(
      index: 10, code: 'productSalary', icon: Icons.precision_manufacturing_outlined, label: 'Lương sản phẩm', groupTitle: gPay, accent: SboxColors.violet,
      desc: 'Nhóm sản phẩm, đơn giá theo bậc', moduleCode: 'ProductSalary',
      keywords: ['khoán', 'sản lượng', 'đơn giá'],
    ),
    // ── Bán hàng
    SettingsHubItemDef(
      index: 16, code: 'industry', icon: Icons.storefront_rounded, label: 'Ngành hàng & cách bán', groupTitle: gSell, accent: SboxColors.success,
      desc: 'Ngành, chế độ bán, ca thu ngân, khóa đơn tạm, tạm tính, bán khi hết hàng', moduleCode: 'SettingsHub', packageModule: 'PosSell',
      keywords: ['ngành', 'cafe', 'nhà hàng', 'bán lẻ', 'ca thu ngân', 'tạm tính', 'tồn kho', 'ngày kinh doanh'],
    ),
    SettingsHubItemDef(
      index: 19, code: 'floor', icon: Icons.table_restaurant_outlined, label: 'Bàn / phòng', groupTitle: gSell, accent: SboxColors.success,
      desc: 'Sơ đồ mặt bằng, khu vực, bàn ghế, phòng', moduleCode: 'SettingsHub', packageModule: 'PosSell',
      keywords: ['sơ đồ bàn', 'khu vực', 'phòng hát', 'karaoke'],
    ),
    SettingsHubItemDef(
      index: 23, code: 'customerDisplay', icon: Icons.tv_outlined, label: 'Màn hình phụ', groupTitle: gSell, accent: SboxColors.success,
      desc: 'Màn hình khách hàng, ảnh / video quảng cáo khi bán', moduleCode: 'PosCustomerDisplay',
      keywords: ['customer display', 'màn hình khách'],
    ),
    SettingsHubItemDef(
      index: 32, code: 'qrOrder', icon: Icons.qr_code_2_rounded, label: 'QR order tại bàn', groupTitle: gSell, accent: SboxColors.success,
      desc: 'Bật / tắt, in QR dán bàn, khách tự gọi món', moduleCode: 'PosQrOrder',
      keywords: ['qr', 'gọi món', 'menu online', 'order tại bàn'],
    ),
    SettingsHubItemDef(
      index: 33, code: 'loyalty', icon: Icons.stars_outlined, label: 'Tích điểm & đổi điểm', groupTitle: gSell, accent: SboxColors.success,
      desc: 'Tỷ lệ tích điểm, giá trị điểm, trần % đổi điểm', moduleCode: 'SettingsHub', packageModule: 'PosSell',
      keywords: ['điểm', 'khách thân thiết', 'loyalty', 'thành viên'],
    ),
    SettingsHubItemDef(
      index: 34, code: 'cancelControl', icon: Icons.rule_folder_outlined, label: 'Kiểm soát hủy / trả', groupTitle: gSell, accent: SboxColors.success,
      desc: 'Bắt buộc lý do, lý do mẫu, chống gian lận khi hủy món / trả hàng', moduleCode: 'SettingsHub', packageModule: 'PosSell',
      keywords: ['hủy món', 'trả hàng', 'lý do hủy', 'gian lận'],
    ),
    // ── Thanh toán & hóa đơn
    SettingsHubItemDef(
      index: 28, code: 'payment', icon: Icons.account_balance_outlined, label: 'Tài khoản nhận tiền', groupTitle: gMoney, accent: SboxColors.warning,
      desc: 'Tài khoản ngân hàng, VietQR, Tingee báo có tự động', moduleCode: 'BankAccount', healthKey: 'payment',
      keywords: ['ngân hàng', 'vietqr', 'tingee', 'chuyển khoản', 'qr', 'cổng thanh toán'],
    ),
    SettingsHubItemDef(
      index: 26, code: 'einvoice', icon: Icons.request_quote_outlined, label: 'Hóa đơn điện tử', groupTitle: gMoney, accent: SboxColors.warning,
      desc: 'Viettel, Easy, MISA, VNPT — xuất, hủy, thay thế, gửi email', moduleCode: 'PosEInvoice', healthKey: 'einvoice',
      keywords: ['hđđt', 'viettel', 'misa', 'vnpt', 'easyinvoice'],
    ),
    SettingsHubItemDef(
      index: 27, code: 'shipping', icon: Icons.local_shipping_outlined, label: 'Đơn vị giao hàng', groupTitle: gMoney, accent: SboxColors.warning,
      desc: 'GHN, GHTK, SPX, Viettel Post, AhaMove — kết nối, tạo vận đơn', moduleCode: 'PosShipping', healthKey: 'shipping',
      keywords: ['ghn', 'ghtk', 'vận chuyển', 'ship', 'vận đơn'],
    ),
    // ── In ấn & thiết bị
    SettingsHubItemDef(
      index: 18, code: 'printers', icon: Icons.print_outlined, label: 'Máy in', groupTitle: gPrint, accent: SboxColors.slate600,
      desc: 'Máy in trên máy này (Bluetooth, LAN, USB) và máy in cloud qua Print Agent', moduleCode: 'PosPrinters',
      altModuleCodes: ['PosStorePrinters'], healthKey: 'cloudPrinter',
      keywords: ['bluetooth', 'lan', 'k80', 'k58', 'in bếp', 'tem', 'print agent', 'in từ xa', 'máy in cloud'],
    ),
    SettingsHubItemDef(
      index: 15, code: 'printTemplates', icon: Icons.design_services_outlined, label: 'Mẫu in', groupTitle: gPrint, accent: SboxColors.slate600,
      desc: 'Thiết kế hóa đơn K58 / K80, tem 50×30, phiếu bếp', moduleCode: 'PosPrintTemplates',
      keywords: ['hóa đơn', 'tem', 'phiếu', 'mẫu hóa đơn'],
    ),
    // ── Tài khoản & bảo mật
    SettingsHubItemDef(
      index: 7, code: 'accounts', icon: Icons.manage_accounts_outlined, label: 'Tài khoản nhân viên', groupTitle: gAccount, accent: SboxColors.danger,
      desc: 'Tạo tài khoản đăng nhập cho nhân viên, khóa, đặt lại mật khẩu, vai trò', moduleCode: 'UserManagement',
      keywords: ['người dùng', 'mật khẩu', 'đăng nhập', 'user', 'tài khoản'],
    ),
    SettingsHubItemDef(
      index: 8, code: 'roles', icon: Icons.security_outlined, label: 'Phân quyền', groupTitle: gAccount, accent: SboxColors.danger,
      desc: 'Vai trò, ma trận quyền theo chức năng', moduleCode: 'Role',
      keywords: ['quyền', 'vai trò', 'role'],
    ),
    SettingsHubItemDef(
      index: 30, code: 'accessDevices', icon: Icons.devices_other_outlined, label: 'Thiết bị truy cập', groupTitle: gAccount, accent: SboxColors.danger,
      desc: 'Điện thoại / máy tính / POS đang dùng suất của gói dịch vụ', moduleCode: 'UserManagement',
      keywords: ['slot', 'đăng xuất thiết bị', 'gói dịch vụ'],
    ),
    // ── Tích hợp & thông báo
    SettingsHubItemDef(
      index: 11, code: 'ai', icon: Icons.auto_awesome_outlined, label: 'Trợ lý AI', groupTitle: gIntegr, accent: SboxColors.brand500,
      desc: 'Gemini, bật / tắt trợ lý AI', moduleCode: 'AIGemini',
      keywords: ['gemini', 'ai', 'trí tuệ nhân tạo'],
    ),
    SettingsHubItemDef(
      index: 21, code: 'notifications', icon: Icons.notifications_active_outlined, label: 'Thông báo', groupTitle: gIntegr, accent: SboxColors.brand500,
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

  /// Mã số cũ đã gộp vào mục khác (lối tắt / «mở gần đây» cũ vẫn mở đúng chỗ).
  static const legacyIndex = {29: 18};

  static int canonicalIndex(int index) => legacyIndex[index] ?? index;

  static SettingsHubItemDef? byIndex(int index) {
    final i = canonicalIndex(index);
    for (final item in allItems) {
      if (item.index == i) return item;
    }
    return null;
  }

  static SettingsHubItemDef? byCode(String code) {
    for (final item in allItems) {
      if (item.code == code) return item;
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
