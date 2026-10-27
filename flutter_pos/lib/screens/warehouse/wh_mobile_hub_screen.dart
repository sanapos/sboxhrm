import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/permission_provider.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/warehouse/wh_doc_type.dart';
import '../../widgets/warehouse/wh_mobile_components.dart';
import '../../widgets/warehouse/wh_mobile_theme.dart';
import 'wh_mobile_list_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Trung tâm điều hướng module Kho trên mobile.
class WhMobileHubScreen extends StatelessWidget {
  const WhMobileHubScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PosHubScope(
          embeddedInHub: false,
          pushedSubPage: true,
          child: WhMobileHubScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);

    final tiles = <({WhDocType type, String modules})>[
      (type: WhDocType.purchaseReceipt, modules: 'PosPurchaseReceipts'),
      (type: WhDocType.purchaseReturn, modules: 'PosPurchaseReturns'),
      (type: WhDocType.stockCount, modules: 'PosStockCounts'),
      (type: WhDocType.damageIssue, modules: 'PosDamageIssues'),
      (type: WhDocType.internalUseIssue, modules: 'PosInternalUseIssues'),
    ].where((t) => perm.canView(t.modules) || perm.canView('PosProducts')).toList();

    return WhMobileScaffold(
      title: 'Kho hàng',
      subtitle: 'Quản lý nhập · xuất · kiểm',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          WhMobileTheme.padH,
          WhMobileTheme.gap,
          WhMobileTheme.padH,
          WhMobileTheme.gapLg + 24,
        ),
        children: [
          Text(tr('Chọn loại phiếu'),
            style: WhMobileTheme.titleLarge.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 6),
          Text(tr('Thao tác nhanh bằng một tay — tạo, sửa và hoàn thành phiếu kho.'),
            style: WhMobileTheme.caption,
          ),
          const SizedBox(height: WhMobileTheme.gapLg),
          // Ô rộng tối đa ~300px: điện thoại vẫn 2 cột, máy POS ngang (T1 1920px) hiện đủ 5 loại
          // phiếu trên một hàng — trước đây 2 cột ô cao ~900px, Kiểm kho / Xuất hủy bị khuất.
          GridView.extent(
            maxCrossAxisExtent: 320,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: WhMobileTheme.gap,
            crossAxisSpacing: WhMobileTheme.gap,
            // Màn ngang: ô thấp hơn (1.6 → 2.4) — trước ô ~190dp chỉ có icon + chữ ở nửa trên.
            childAspectRatio: MediaQuery.sizeOf(context).width >= 700 ? 2.4 : 1.05,
            children: [
              for (final t in tiles)
                WhHubTile(
                  icon: t.type.icon,
                  label: t.type.title,
                  color: t.type.accentColor,
                  onTap: () => WhMobileDocListScreen.open(context, t.type),
                ),
            ],
          ),
          const SizedBox(height: WhMobileTheme.gapLg),
          WhGlassCard(
            child: Row(
              children: [
                Icon(Icons.tips_and_updates_outlined,
                    color: WhMobileTheme.primary.withOpacity(0.8), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr('Quét mã vạch khi thêm hàng · Lưu tạm bất cứ lúc nào · Hoàn thành khi đã kiểm tra xong.'),
                    style: WhMobileTheme.caption,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
