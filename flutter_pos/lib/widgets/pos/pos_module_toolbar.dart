import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';
import 'pos_hub_scope.dart';

/// Thanh tab ngang POS (SBOX POS / Hàng hóa / Bán hàng / Đơn hàng…).
/// Tab ngang đã tắt — điều hướng dùng rail hub / menu ☰.
///
/// Còn lại: khi màn kho dạng bảng được mở riêng từ «Nhiều hơn» (route mới),
/// hiện thanh tiêu đề mảnh có nút quay lại — các màn này không tự vẽ tiêu đề,
/// trước đây chỉ thấy thanh lọc, không biết đang ở màn nào.
class PosModuleToolbar extends StatelessWidget {
  const PosModuleToolbar({
    super.key,
    this.activeModule = 'PosProducts',
  });

  final String activeModule;

  /// Chỉ các màn không có tiêu đề riêng (màn khác đã có → tránh trùng).
  static const _pushedTitles = {
    'PosPurchaseReceipts': 'Phiếu nhập hàng',
    'PosPurchaseReturns': 'Trả hàng nhập',
    'PosStockCounts': 'Kiểm kho',
  };

  @override
  Widget build(BuildContext context) {
    final title = _pushedTitles[activeModule];
    if (title == null ||
        !PosHubScope.pushedSubPageOf(context) ||
        !Navigator.of(context).canPop()) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.white,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: SboxColors.border)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: tr('Quay lại'),
              icon: const Icon(Icons.arrow_back, color: SboxColors.text),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: SboxColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
