import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/pos_sell_industry.dart';
import '../../providers/permission_provider.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_cancel_return_history_screen.dart';
import 'pos_cancel_return_settings_screen.dart';
import 'pos_customer_display_settings_screen.dart';
import 'pos_qr_table_order_screen.dart';
import 'pos_kds_screen.dart';
import 'pos_resource_floor_screen.dart';
import 'pos_sell_industry_settings_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

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
    final canEdit = context.watch<PermissionProvider>().canEditPosSetup();
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        if (!canEdit)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  tr('Chỉ xem — không có quyền sửa thiết lập POS.'),
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                ),
              ),
            ),
          ),
        Text(
          tr('Chọn nhóm thiết lập'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        _tile(
          context,
          icon: Icons.storefront_outlined,
          title: 'Ngành hàng & chế độ bán',
          subtitle: _settings == null
              ? 'Bán lẻ, nhà hàng, salon… · ca thu ngân · khóa đơn tạm'
              : '${_settings!.sellProfile.label} · ca thu ngân · khóa đơn tạm · ${_settings!.sellProfile.featureHints.take(2).join(' · ')}',
          onTap: () => _open(
            context,
            const PosSellIndustrySettingsScreen(section: 'profile'),
          ),
        ),
        _tile(
          context,
          icon: Icons.table_restaurant_outlined,
          title: _settings?.sellProfile.usesFloorPlan == true
              ? '${_settings!.sellProfile.floorTabLabel} / tạm tính'
              : 'Tạm tính & tồn kho',
          subtitle: _settings?.sellProfile.usesFloorPlan == true
              ? 'Sơ đồ ${_settings!.sellProfile.resourceNoun}, tính giờ, tạm tính'
              : 'Tạm tính, bán khi hết hàng, ngày KD',
          onTap: () => _open(
            context,
            const PosSellIndustrySettingsScreen(section: 'resources'),
          ),
        ),
        if (_showFloorManage)
          _tile(
            context,
            icon: Icons.map_outlined,
            title: _settings?.sellProfile.usesFloorPlan == true
                ? 'Quản lý ${_settings!.sellProfile.resourceNounPlural}'
                : 'Quản lý bàn / phòng',
            subtitle: _settings?.sellProfile.usesFloorPlan == true
                ? 'Thêm sửa khu vực, ${_settings!.sellProfile.resourceNoun} trên sơ đồ'
                : 'Thêm sửa khu vực, bàn ghế trên sơ đồ',
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
          icon: Icons.qr_code_2,
          title: 'QR order tại bàn',
          subtitle: 'Tắt mặc định · in QR dán bàn, khách gọi món, phiếu in bếp qua Agent',
          onTap: () => _open(
            context,
            const PosQrTableOrderScreen(),
          ),
        ),
        _tile(
          context,
          icon: Icons.kitchen_outlined,
          title: 'Màn hình bếp (KDS)',
          subtitle: 'Ticket theo bàn · đang làm / sẵn sàng / XONG · lọc trạm in',
          onTap: () => _open(
            context,
            const PosKdsScreen(),
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
          title: 'Màn hình phụ (khách)',
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
          backgroundColor: PosTheme.kiotBlue.withValues(alpha: 0.12),
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
