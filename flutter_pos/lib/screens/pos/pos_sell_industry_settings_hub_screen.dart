import 'package:flutter/material.dart';

import '../../models/pos_sell_industry.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_cancel_return_history_screen.dart';
import 'pos_cancel_return_settings_screen.dart';
import 'pos_customer_display_settings_screen.dart';
import 'pos_resource_floor_screen.dart';
import 'pos_sell_industry_settings_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Hub tách «Ngành hàng & bán hàng» thành các nhóm chức năng.
class PosSellIndustrySettingsHubScreen extends StatefulWidget {
  const PosSellIndustrySettingsHubScreen({
    super.key,
    this.embeddedInSettings = false,
  });

  final bool embeddedInSettings;

  @override
  State<PosSellIndustrySettingsHubScreen> createState() =>
      _PosSellIndustrySettingsHubScreenState();
}

class _PosSellIndustrySettingsHubScreenState
    extends State<PosSellIndustrySettingsHubScreen> {
  PosStoreSellSettingsDto? _settings;

  bool get _showFloorManage {
    final s = _settings;
    if (s == null) return false;
    return s.enableResources || s.showFloorPlan;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await PosSellSettingsHelper(ApiService()).load();
    if (!mounted) return;
    setState(() => _settings = r.settings);
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          tr('Chọn nhóm thiết lập'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        _tile(
          context,
          icon: Icons.storefront_outlined,
          title: 'Hồ sơ ngành & chế độ bán',
          subtitle: 'F&B / salon / gym · bán nhanh / thường / giao hàng',
          onTap: () => _open(
            context,
            const PosSellIndustrySettingsScreen(section: 'profile'),
          ),
        ),
        _tile(
          context,
          icon: Icons.table_restaurant_outlined,
          title: 'Bàn / tài nguyên / tạm tính',
          subtitle: 'Sơ đồ bàn, tính giờ, gói buổi, hỏi số khách',
          onTap: () => _open(
            context,
            const PosSellIndustrySettingsScreen(section: 'resources'),
          ),
        ),
        if (_showFloorManage)
          _tile(
            context,
            icon: Icons.map_outlined,
            title: 'Quản lý bàn / phòng',
            subtitle: 'Thêm sửa khu vực, bàn ghế trên sơ đồ',
            onTap: () => _open(
              context,
              PosResourceFloorScreen(
                manageMode: true,
                sellProfile: _settings?.sellProfile,
                allowProvisionalBill:
                    _settings?.allowProvisionalBill != false,
              ),
            ),
          ),
        _tile(
          context,
          icon: Icons.rule_folder_outlined,
          title: 'Kiểm soát hủy / trả',
          subtitle: 'Bắt buộc lý do · lịch sử chống gian lận',
          onTap: () => _open(
            context,
            const PosCancelReturnSettingsScreen(),
          ),
        ),
        _tile(
          context,
          icon: Icons.history,
          title: 'Lịch sử hủy / trả',
          subtitle: 'Lọc thao tác, trước/sau tạm tính, nhân viên',
          onTap: () => _open(
            context,
            const PosCancelReturnHistoryScreen(),
          ),
        ),
        _tile(
          context,
          icon: Icons.tv_outlined,
          title: 'Màn hình phụ',
          subtitle: 'Ảnh / video trình chiếu · hóa đơn phụ',
          onTap: () => _open(
            context,
            const PosCustomerDisplaySettingsScreen(),
          ),
        ),
      ],
    );

    if (widget.embeddedInSettings) {
      return ColoredBox(
        color: PosTheme.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                child: Text(
                  tr('Ngành hàng & bán hàng'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Ngành hàng & bán hàng')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: PosTheme.kiotBlue.withOpacity(0.12),
          child: Icon(icon, color: PosTheme.kiotBlue, size: 22),
        ),
        title: Text(tr(title),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(tr(subtitle),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
