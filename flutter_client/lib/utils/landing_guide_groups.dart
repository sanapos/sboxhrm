import 'package:flutter/material.dart';

import 'landing_usage_guide.dart';

/// Hướng dẫn chia 3 khu (HRM · POS · Ngành hàng), mỗi khu nhiều nhóm nhỏ, mỗi nhóm vài bước.
/// Bước vẫn khai trong landing_usage_guide.dart / landing_industry_guide.dart (mục lưu
/// basic / advanced / pos / industry giữ cho link chia sẻ cũ); ở đây chỉ xếp mã bước vào nhóm.
/// Cùng dữ liệu này đi vào guide.html và trợ lý AI («POS › Kho hàng › Kiểm kho»).
/// Bước chưa xếp nhóm vẫn hiện trong nhóm «Khác» của khu; test bắt phải xếp đủ.
class GuideGroup {
  const GuideGroup({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.stepIds,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> stepIds;
}

class GuideArea {
  const GuideArea({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.sections,
    required this.groups,
  });

  final String id;
  final String title;
  final String subtitle;

  /// Mục lưu bước (LandingGuideData) thuộc khu này.
  final List<String> sections;
  final List<GuideGroup> groups;
}

/// Một bước trong khu: kèm mục lưu (để dựng link chia sẻ) và nhóm.
class GuideEntry {
  const GuideEntry({required this.section, required this.step, required this.group});

  final String section;
  final LandingUsageGuideStep step;
  final GuideGroup group;
}

abstract final class LandingGuideGroups {
  static const areas = <GuideArea>[
    GuideArea(
      id: 'hrm',
      title: 'HRM',
      subtitle: 'Nhân sự, chấm công, ca làm việc, lương',
      sections: ['basic', 'advanced'],
      groups: [
        GuideGroup(
          id: 'hrm_setup',
          title: 'Khởi tạo ban đầu',
          subtitle: 'Đăng ký, cơ cấu, chi nhánh, nhân viên, tài khoản',
          icon: Icons.flag_rounded,
          stepIds: ['getting_started', 'register', 'org_structure', 'branches', 'employees', 'employee_account'],
        ),
        GuideGroup(
          id: 'hrm_schedule',
          title: 'Ca & lịch làm việc',
          subtitle: 'Ca, phân lịch, đổi ca, ngày lễ',
          icon: Icons.calendar_month_rounded,
          stepIds: ['shifts', 'work_schedule_basic', 'work_schedule', 'shift_swap', 'holidays'],
        ),
        GuideGroup(
          id: 'hrm_attendance',
          title: 'Chấm công',
          subtitle: 'Máy chấm công, mobile, kiểu chấm, sửa công',
          icon: Icons.fingerprint_rounded,
          stepIds: [
            'device_connect',
            'device_users',
            'gateway_wifi',
            'mobile_attendance',
            'attendance_modes',
            'attendance_correction',
            'raw_attendance',
            'field_checkin',
            'meal',
          ],
        ),
        GuideGroup(
          id: 'hrm_requests',
          title: 'Đơn từ & phê duyệt',
          subtitle: 'Nghỉ phép, tăng ca, công tác',
          icon: Icons.assignment_turned_in_rounded,
          stepIds: ['leave', 'overtime', 'business_trip'],
        ),
        GuideGroup(
          id: 'hrm_payroll',
          title: 'Lương & chính sách',
          subtitle: 'Thiết lập lương, phụ cấp, bảo hiểm, thuế, thưởng, phạt, KPI',
          icon: Icons.payments_rounded,
          stepIds: ['salary', 'allowance', 'insurance_tax', 'bonus', 'penalty', 'production', 'kpi'],
        ),
        GuideGroup(
          id: 'hrm_finance',
          title: 'Phiếu tài chính & chốt lương',
          subtitle: 'Phiếu phạt, thưởng, ứng lương, thu chi, chốt kỳ',
          icon: Icons.account_balance_wallet_rounded,
          stepIds: ['penalty_ticket', 'bonus_ticket', 'advance', 'cash', 'first_payroll'],
        ),
        GuideGroup(
          id: 'hrm_reports',
          title: 'Báo cáo & vận hành hằng ngày',
          subtitle: 'Xem báo cáo, việc mỗi ngày, tình huống thường gặp',
          icon: Icons.insert_chart_rounded,
          stepIds: ['reports', 'hr_analytics', 'daily_ops', 'common_hrm'],
        ),
        GuideGroup(
          id: 'hrm_employee',
          title: 'Dành cho nhân viên',
          subtitle: 'Nhân viên dùng app: chấm công, lịch ca, gửi đơn, phiếu lương',
          icon: Icons.phone_iphone_rounded,
          stepIds: ['employee_self_service'],
        ),
        GuideGroup(
          id: 'hrm_tools',
          title: 'Giao tiếp & công cụ',
          subtitle: 'Truyền thông, kiến nghị, thông báo, Zalo, trợ lý AI, công việc, tài sản',
          icon: Icons.forum_rounded,
          stepIds: ['communication', 'feedback', 'notifications', 'zalo_bot', 'ai_assistant', 'tasks', 'asset'],
        ),
      ],
    ),
    GuideArea(
      id: 'pos',
      title: 'POS',
      subtitle: 'Bán hàng, hàng hóa, kho, hóa đơn, báo cáo',
      sections: ['pos'],
      groups: [
        GuideGroup(
          id: 'pos_init',
          title: 'Khởi tạo ban đầu',
          subtitle: 'Chọn máy, thiết lập cửa hàng, tài khoản nhận tiền, máy in, màn hình phụ',
          icon: Icons.storefront_rounded,
          stepIds: ['pos_devices', 'pos_setup', 'pos_bank_account', 'pos_printers', 'pos_customer_display'],
        ),
        GuideGroup(
          id: 'pos_catalog',
          title: 'Hàng hóa & dịch vụ',
          subtitle: 'Hàng hóa, ĐVT, lô/HSD, dịch vụ, combo, nguyên vật liệu, topping',
          icon: Icons.inventory_2_rounded,
          stepIds: ['pos_products', 'pos_units', 'pos_lots', 'pos_services', 'pos_combo', 'pos_bom', 'pos_toppings'],
        ),
        GuideGroup(
          id: 'pos_selling',
          title: 'Bán hàng',
          subtitle: 'Chọn hàng, sửa món, thanh toán, sau bán',
          icon: Icons.point_of_sale_rounded,
          stepIds: ['pos_sales', 'pos_sale_edit', 'pos_sale_pay', 'pos_after_sale'],
        ),
        GuideGroup(
          id: 'pos_fnb',
          title: 'Bàn, bếp & đặt lịch',
          subtitle: 'Sơ đồ bàn / phòng, gửi bếp, màn hình bếp, đặt bàn / lịch hẹn',
          icon: Icons.table_restaurant_rounded,
          stepIds: ['pos_tables', 'pos_kitchen', 'pos_kds', 'pos_booking'],
        ),
        GuideGroup(
          id: 'pos_channels',
          title: 'Báo giá, giao hàng & bán online',
          subtitle: 'Báo giá / hợp đồng, vận đơn, menu QR',
          icon: Icons.local_shipping_rounded,
          stepIds: ['pos_qr_order', 'pos_quotes', 'pos_shipping'],
        ),
        GuideGroup(
          id: 'pos_customers_group',
          title: 'Khách hàng',
          subtitle: 'Điểm, công nợ, bảo hành',
          icon: Icons.people_alt_rounded,
          stepIds: ['pos_customers', 'pos_warranty'],
        ),
        GuideGroup(
          id: 'pos_stock',
          title: 'Kho hàng',
          subtitle: 'Nhà cung cấp, nhập hàng, phiếu giảm tồn, thẻ kho, kiểm kho, nguyên tắc tồn',
          icon: Icons.warehouse_rounded,
          stepIds: ['pos_inventory', 'pos_suppliers', 'pos_stock_docs', 'pos_stock_card', 'pos_stock_count', 'pos_stock_rules'],
        ),
        GuideGroup(
          id: 'pos_einvoice_group',
          title: 'Hóa đơn điện tử',
          subtitle: 'Kết nối hãng, xuất, quản lý',
          icon: Icons.receipt_long_rounded,
          stepIds: ['pos_einvoice', 'pos_einvoice_manage'],
        ),
        GuideGroup(
          id: 'pos_reports_group',
          title: 'Báo cáo & cuối ngày',
          subtitle: 'Báo cáo POS, ca thu ngân, tổng kết',
          icon: Icons.bar_chart_rounded,
          stepIds: ['pos_reports', 'pos_eod'],
        ),
        GuideGroup(
          id: 'pos_rules_group',
          title: 'Tình huống & nguyên tắc',
          subtitle: 'Lỗi thường gặp, nguyên tắc chứng từ',
          icon: Icons.rule_rounded,
          stepIds: ['pos_common', 'pos_rules'],
        ),
      ],
    ),
    GuideArea(
      id: 'industry',
      title: 'Ngành hàng',
      subtitle: 'Cách dùng riêng cho từng loại cửa hàng',
      sections: ['industry'],
      groups: [
        GuideGroup(
          id: 'ind_start',
          title: 'Chọn ngành',
          subtitle: 'Ngành quyết định màn bán và tính năng',
          icon: Icons.category_rounded,
          stepIds: ['ind_choose'],
        ),
        GuideGroup(
          id: 'ind_types',
          title: 'Theo từng ngành',
          subtitle: 'Bán lẻ, nhà hàng, karaoke, salon, gym, khách sạn',
          icon: Icons.storefront_rounded,
          stepIds: ['ind_retail', 'ind_restaurant', 'ind_room_hourly', 'ind_salon', 'ind_gym', 'ind_hotel'],
        ),
        GuideGroup(
          id: 'ind_shared',
          title: 'Dùng chung mọi ngành',
          subtitle: 'Hoa hồng, mẫu Word, lịch sử thao tác',
          icon: Icons.handyman_rounded,
          stepIds: ['ind_commission', 'ind_docs_log'],
        ),
      ],
    ),
  ];

  static GuideArea areaById(String id) => areas.firstWhere((a) => a.id == id, orElse: () => areas.first);

  /// Khu chứa mục lưu (basic / advanced → HRM…).
  static GuideArea areaForSection(String section) =>
      areas.firstWhere((a) => a.sections.contains(section), orElse: () => areas.first);

  static int areaIndexForSection(String section) => areas.indexOf(areaForSection(section));

  static GuideGroup otherGroup(GuideArea area) => GuideGroup(
        id: '${area.id}_other',
        title: 'Khác',
        subtitle: 'Bước chưa xếp nhóm',
        icon: Icons.more_horiz_rounded,
        stepIds: const [],
      );

  /// Bước của khu theo thứ tự nhóm (bước chưa xếp nhóm đứng cuối, nhóm «Khác»).
  static List<GuideEntry> entries(LandingGuideData data, GuideArea area) {
    final byId = <String, (String, LandingUsageGuideStep)>{};
    for (final section in area.sections) {
      for (final s in data.stepsAt(LandingGuideData.indexForKey(section))) {
        byId[s.id] = (section, s);
      }
    }
    final out = <GuideEntry>[];
    final used = <String>{};
    for (final g in area.groups) {
      for (final id in g.stepIds) {
        final hit = byId[id];
        if (hit == null) continue;
        out.add(GuideEntry(section: hit.$1, step: hit.$2, group: g));
        used.add(id);
      }
    }
    final other = otherGroup(area);
    for (final e in byId.entries) {
      if (!used.contains(e.key)) out.add(GuideEntry(section: e.value.$1, step: e.value.$2, group: other));
    }
    return out;
  }

  /// Nhóm của một bước (null = chưa xếp).
  static (GuideArea, GuideGroup)? locate(String stepId) {
    for (final a in areas) {
      for (final g in a.groups) {
        if (g.stepIds.contains(stepId)) return (a, g);
      }
    }
    return null;
  }
}
