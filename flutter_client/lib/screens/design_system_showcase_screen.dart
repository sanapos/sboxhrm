import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../widgets/sbox/sbox_ui.dart';

/// Trang mẫu giao diện SBOX — duyệt màu, chữ, nút, bảng… trước khi áp dụng toàn app.
class DesignSystemShowcaseScreen extends StatefulWidget {
  const DesignSystemShowcaseScreen({super.key});

  @override
  State<DesignSystemShowcaseScreen> createState() => _DesignSystemShowcaseScreenState();
}

class _DemoOrder {
  const _DemoOrder(this.code, this.customer, this.table, this.staff, this.total, this.status, this.minutesAgo);
  final String code;
  final String customer;
  final String table;
  final String staff;
  final int total;
  final String status;
  final int minutesAgo;
}

class _DesignSystemShowcaseScreenState extends State<DesignSystemShowcaseScreen> {
  String _status = 'all';
  String _q = '';
  bool _switch = true;
  bool _check = true;
  String _seg = 'day';

  static final _orders = List.generate(57, (i) {
    const names = [
      'Nguyễn Thị Minh Anh', 'Trần Quốc Bảo', 'Khách lẻ', 'Lê Hoàng Phương Linh — Công ty TNHH Thương mại Dịch vụ Ánh Dương',
      'Phạm Gia Huy', 'Võ Thanh Tâm', 'Đặng Ngọc Hân',
    ];
    const staff = ['Thu ngân 1', 'Mai', 'Tuấn', 'Hạnh'];
    const st = ['done', 'open', 'done', 'debt', 'cancel', 'done'];
    return _DemoOrder(
      'HD${(24091 + i).toString()}',
      names[i % names.length],
      i % 3 == 0 ? 'Mang về' : 'Bàn ${(i % 12) + 1}',
      staff[i % staff.length],
      85000 + (i * 37500) % 1450000,
      st[i % st.length],
      i * 7,
    );
  });

  static String _money(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return '$bđ';
  }

  static (String, SboxTone) _statusOf(String s) => switch (s) {
        'done' => ('Hoàn thành', SboxTone.success),
        'open' => ('Đang phục vụ', SboxTone.brand),
        'debt' => ('Ghi nợ', SboxTone.warning),
        _ => ('Đã hủy', SboxTone.danger),
      };

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = SboxSpace.pagePadding(w);
    final rows = _orders
        .where((o) => _status == 'all' || o.status == _status)
        .where((o) => _q.isEmpty || '${o.code} ${o.customer}'.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(title: Text(tr('Mẫu giao diện SBOX'))),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(pad),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SboxPageHeader(
                title: 'Đơn hàng',
                subtitle: 'Mẫu một màn danh sách chuẩn: tiêu đề, số liệu, bộ lọc, bảng, phân trang',
                actions: [
                  SboxButton.secondary(label: 'Xuất Excel', icon: Icons.download_rounded, onPressed: () {}),
                  SboxButton(label: 'Tạo đơn', icon: Icons.add_rounded, onPressed: () {}),
                ],
              ),
              const SizedBox(height: SboxSpace.xl),
              _metrics(w),
              const SizedBox(height: SboxSpace.xl),
              SboxFilterBar(
                searchHint: 'Tìm mã đơn, khách hàng',
                onSearch: (v) => setState(() => _q = v),
                filters: [
                  SboxFilterChip<String>(
                    label: 'Trạng thái',
                    value: _status,
                    options: const {
                      'all': 'Tất cả',
                      'done': 'Hoàn thành',
                      'open': 'Đang phục vụ',
                      'debt': 'Ghi nợ',
                      'cancel': 'Đã hủy',
                    },
                    onChanged: (v) => setState(() => _status = v),
                  ),
                  SboxFilterChip<String>(
                    label: 'Thời gian',
                    value: 'today',
                    options: const {'today': 'Hôm nay', 'week': '7 ngày', 'month': 'Tháng này'},
                    onChanged: (_) {},
                  ),
                ],
                actions: [SboxIconButton(icon: Icons.tune_rounded, tooltip: 'Bộ lọc nâng cao', onPressed: () {})],
              ),
              const SizedBox(height: SboxSpace.md),
              SboxDataTable<_DemoOrder>(
                rows: rows,
                emptyTitle: 'Không tìm thấy đơn',
                emptyMessage: 'Thử đổi từ khóa hoặc bộ lọc trạng thái.',
                onRowTap: (_) {},
                rowActions: (o) => Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(visualDensity: VisualDensity.compact, tooltip: tr('In lại'), icon: const Icon(Icons.print_outlined, size: 18), onPressed: () {}),
                  IconButton(visualDensity: VisualDensity.compact, tooltip: tr('Xem'), icon: const Icon(Icons.chevron_right_rounded, size: 20), onPressed: () {}),
                ]),
                columns: [
                  SboxColumn(label: 'Mã đơn', text: (o) => o.code, width: 100, primary: true, sortValue: (o) => o.code),
                  SboxColumn(label: 'Khách hàng', text: (o) => o.customer, flex: 3, minWidth: 180, sortValue: (o) => o.customer),
                  SboxColumn(label: 'Bàn', text: (o) => o.table, width: 96, hideOnMobile: true),
                  SboxColumn(label: 'Nhân viên', text: (o) => o.staff, flex: 1, minWidth: 110),
                  SboxColumn(
                    label: 'Trạng thái',
                    width: 136,
                    cell: (o) {
                      final (l, t) = _statusOf(o.status);
                      return SboxStatusChip(label: l, tone: t, dot: true);
                    },
                  ),
                  SboxColumn(label: 'Tổng tiền', text: (o) => _money(o.total), width: 120, numeric: true, sortValue: (o) => o.total),
                ],
              ),
              const SizedBox(height: SboxSpace.xxl),
              _section('Màu sắc', 'Thương hiệu #158DC0 · nút dùng tông đậm #0F7BA8 · một họ xám Slate · màu trạng thái', _colors()),
              _section('Chữ', 'Be Vietnam Pro · 7 cỡ · 4 mức đậm', _type()),
              _section('Nút', '5 kiểu × 3 cỡ · có trạng thái đang xử lý / tắt', _buttons()),
              _section('Nhãn trạng thái', 'Nền nhạt + chữ đậm cùng tông, bo tròn', _chips()),
              _section('Ô nhập & lựa chọn', 'Cao 40, bo 10, viền xanh khi đang nhập', _inputs()),
              _section('Trạng thái rỗng', 'Lời mời hành động thay vì màn trắng', _emptyDemo()),
              const SizedBox(height: SboxSpace.xxl),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _metrics(double w) {
    final cols = w < SboxBreakpoints.mobile ? 2 : 4;
    final items = [
      const SboxMetricCard(label: 'Doanh thu hôm nay', value: '18.450.000đ', icon: Icons.payments_outlined, delta: '+12% so với hôm qua', deltaUp: true),
      const SboxMetricCard(label: 'Số đơn', value: '146', icon: Icons.receipt_long_outlined, tone: SboxTone.violet, delta: '+8 đơn', deltaUp: true),
      const SboxMetricCard(label: 'Đang phục vụ', value: '9 bàn', icon: Icons.table_restaurant_outlined, tone: SboxTone.warning),
      const SboxMetricCard(label: 'Hủy / trả', value: '3', icon: Icons.undo_rounded, tone: SboxTone.danger, delta: '-2 đơn', deltaUp: false),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = SboxSpace.md;
      final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final m in items) SizedBox(width: itemW, child: m)]);
    });
  }

  Widget _section(String title, String sub, Widget child) => Padding(
        padding: const EdgeInsets.only(top: SboxSpace.xl),
        child: SboxCard(title: title, subtitle: sub, child: child),
      );

  Widget _swatch(Color c, String name, String hex) => SizedBox(
        width: 124,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: c,
              borderRadius: SboxRadius.mdAll,
              border: Border.all(color: SboxColors.border),
            ),
          ),
          const SizedBox(height: 4),
          Text(name, style: SboxType.captionStyle(SboxColors.text).copyWith(fontWeight: SboxType.semibold)),
          Text(hex, style: SboxType.captionStyle()),
        ]),
      );

  Widget _colors() => Wrap(spacing: SboxSpace.md, runSpacing: SboxSpace.md, children: [
        _swatch(SboxColors.brand50, 'Brand 50', '#E8F5FB'),
        _swatch(SboxColors.brand100, 'Brand 100', '#BFE3F3'),
        _swatch(SboxColors.brand300, 'Brand 300', '#6FC0E3'),
        _swatch(SboxColors.brand500, 'Thương hiệu', '#158DC0'),
        _swatch(SboxColors.brand600, 'Nút chính', '#0F7BA8'),
        _swatch(SboxColors.brand700, 'Di chuột', '#0B6A91'),
        _swatch(SboxColors.brand900, 'Chữ trên nền xanh', '#084B67'),
        _swatch(SboxColors.page, 'Nền trang', '#F4F7FA'),
        _swatch(SboxColors.border, 'Viền', '#E2E8F0'),
        _swatch(SboxColors.textMuted, 'Chữ phụ', '#64748B'),
        _swatch(SboxColors.text, 'Chữ chính', '#0F172A'),
        _swatch(SboxColors.success, 'Thành công / Thanh toán', '#16A34A'),
        _swatch(SboxColors.warning, 'Cảnh báo', '#D97706'),
        _swatch(SboxColors.danger, 'Lỗi / Xóa', '#DC2626'),
        _swatch(SboxColors.violet, 'Dịch vụ / Chốt giờ', '#7C3AED'),
      ]);

  Widget _type() {
    Widget row(String name, TextStyle s, String sample) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            SizedBox(width: 150, child: Text(name, style: SboxType.captionStyle())),
            Expanded(child: Text(sample, style: s, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row('Số liệu 28 · 700', SboxType.displayStyle(), '18.450.000đ'),
      row('Tiêu đề trang 22 · 700', SboxType.headlineStyle(), 'Báo cáo doanh thu'),
      row('Tiêu đề 18 · 600', SboxType.titleStyle(), 'Thanh toán hóa đơn HD24091'),
      row('Tiêu đề nhỏ 16 · 600', SboxType.titleSmStyle(), 'Thông tin khách hàng'),
      row('Nội dung 14 · 400', SboxType.bodyStyle(), 'Tiếng Việt có dấu hiển thị rõ ràng, dễ đọc trên mọi màn hình.'),
      row('Chữ phụ 13 · 400', SboxType.smallStyle(), 'Cập nhật lúc 14:05 bởi Thu ngân 1'),
      row('Chú thích 12 · 500', SboxType.captionStyle(), 'MÃ VẠCH · ĐƠN VỊ · GHI CHÚ'),
    ]);
  }

  Widget _buttons() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SboxButton(label: 'Lưu', icon: Icons.check_rounded, onPressed: () {}),
          SboxButton.secondary(label: 'Hủy bỏ', onPressed: () {}),
          SboxButton.ghost(label: 'Xem chi tiết', onPressed: () {}),
          SboxButton.danger(label: 'Xóa đơn', icon: Icons.delete_outline_rounded, onPressed: () {
            SboxDialogs.confirm(context, title: 'Xóa đơn HD24091?', message: 'Đơn đã xóa không khôi phục được.', confirmLabel: 'Xóa', danger: true);
          }),
          const SboxButton(label: 'Đang lưu', loading: true),
          const SboxButton(label: 'Không khả dụng'),
        ]),
        const SizedBox(height: SboxSpace.md),
        Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SboxButton(label: 'Nhỏ', size: SboxButtonSize.sm, onPressed: () {}),
          SboxButton(label: 'Vừa', onPressed: () {}),
          SboxButton(label: 'Lớn', size: SboxButtonSize.lg, onPressed: () {}),
          SboxIconButton(icon: Icons.print_outlined, tooltip: 'In', onPressed: () {}),
          SboxIconButton(icon: Icons.delete_outline_rounded, tooltip: 'Xóa', tone: SboxTone.danger, onPressed: () {}),
        ]),
        const SizedBox(height: SboxSpace.md),
        SizedBox(width: 360, child: SboxButton.pay(label: 'Thanh toán 1.250.000đ (F9)', icon: Icons.payments_rounded, onPressed: () {})),
      ]);

  Widget _chips() => const Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: [
        SboxStatusChip(label: 'Hoàn thành', tone: SboxTone.success, dot: true),
        SboxStatusChip(label: 'Đang phục vụ', tone: SboxTone.brand, dot: true),
        SboxStatusChip(label: 'Ghi nợ', tone: SboxTone.warning, dot: true),
        SboxStatusChip(label: 'Đã hủy', tone: SboxTone.danger, dot: true),
        SboxStatusChip(label: 'Chốt 14:05', tone: SboxTone.violet, icon: Icons.lock_clock),
        SboxStatusChip(label: 'Nháp', tone: SboxTone.neutral),
        SboxStatusChip(label: 'VIP', tone: SboxTone.brand, icon: Icons.star_rounded),
      ]);

  Widget _inputs() => Wrap(spacing: SboxSpace.lg, runSpacing: SboxSpace.lg, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 260,
          child: TextField(decoration: InputDecoration(labelText: tr('Tên khách hàng'), hintText: tr('Nguyễn Văn A'))),
        ),
        SizedBox(
          width: 200,
          child: TextField(
            decoration: InputDecoration(
              labelText: tr('Số điện thoại'),
              errorText: tr('Số điện thoại chưa đúng'),
              prefixIcon: const Icon(Icons.phone_outlined, size: 18),
            ),
          ),
        ),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'day', label: Text(tr('Ngày'))),
            ButtonSegment(value: 'week', label: Text(tr('Tuần'))),
            ButtonSegment(value: 'month', label: Text(tr('Tháng'))),
          ],
          selected: {_seg},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _seg = v.first),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(value: _switch, onChanged: (v) => setState(() => _switch = v)),
          Text(tr('Bật tính giờ'), style: SboxType.bodyStyle()),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: _check, onChanged: (v) => setState(() => _check = v ?? false)),
          Text(tr('In hóa đơn'), style: SboxType.bodyStyle()),
        ]),
      ]);

  Widget _emptyDemo() => SboxEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Chưa có đơn hàng hôm nay',
        message: 'Đơn bán tại quầy, đặt bàn và QR order sẽ hiện ở đây.',
        action: SboxButton(label: 'Tạo đơn đầu tiên', icon: Icons.add_rounded, onPressed: () {}),
      );
}
