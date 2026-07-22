import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';
import '../../widgets/warehouse/wh_doc_type.dart';
import '../pos_damage_issue_list_screen.dart';
import '../pos_internal_use_list_screen.dart';
import '../pos_purchase_receipt_list_screen.dart';
import '../pos_purchase_return_list_screen.dart';
import '../pos_stock_count_list_screen.dart';
import 'wh_mobile_hub_screen.dart';
import 'wh_mobile_list_screen.dart';

/// Chuyển mobile → UI Kho mới; desktop giữ màn hình cũ.
abstract final class WhMobileNav {
  static bool useNewMobileUi(BuildContext context) =>
      Responsive.isMobile(context) || Responsive.isCompactViewport(context);

  static void openHub(BuildContext context) {
    if (useNewMobileUi(context)) {
      WhMobileHubScreen.open(context);
    } else {
      // Desktop: mở phiếu nhập làm entry mặc định
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PosPurchaseReceiptListScreen()),
      );
    }
  }

  static void openList(BuildContext context, WhDocType type) {
    if (useNewMobileUi(context)) {
      WhMobileDocListScreen.open(context, type);
    } else {
      final screen = switch (type) {
        WhDocType.purchaseReceipt => const PosPurchaseReceiptListScreen(),
        WhDocType.purchaseReturn => const PosPurchaseReturnListScreen(),
        WhDocType.stockCount => const PosStockCountListScreen(),
        WhDocType.damageIssue => const PosDamageIssueListScreen(),
        WhDocType.internalUseIssue => const PosInternalUseListScreen(),
      };
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }
  }
}

/// Wrapper cho sidebar / hub — tự chọn UI theo viewport.
class WhAdaptivePurchaseReceiptList extends StatelessWidget {
  const WhAdaptivePurchaseReceiptList({super.key});

  @override
  Widget build(BuildContext context) =>
      WhMobileNav.useNewMobileUi(context)
          ? const WhMobileDocListScreen(docType: WhDocType.purchaseReceipt)
          : const PosPurchaseReceiptListScreen();
}

class WhAdaptivePurchaseReturnList extends StatelessWidget {
  const WhAdaptivePurchaseReturnList({super.key});

  @override
  Widget build(BuildContext context) =>
      WhMobileNav.useNewMobileUi(context)
          ? const WhMobileDocListScreen(docType: WhDocType.purchaseReturn)
          : const PosPurchaseReturnListScreen();
}

class WhAdaptiveStockCountList extends StatelessWidget {
  const WhAdaptiveStockCountList({super.key});

  @override
  Widget build(BuildContext context) =>
      WhMobileNav.useNewMobileUi(context)
          ? const WhMobileDocListScreen(docType: WhDocType.stockCount)
          : const PosStockCountListScreen();
}

class WhAdaptiveDamageIssueList extends StatelessWidget {
  const WhAdaptiveDamageIssueList({super.key});

  @override
  Widget build(BuildContext context) =>
      WhMobileNav.useNewMobileUi(context)
          ? const WhMobileDocListScreen(docType: WhDocType.damageIssue)
          : const PosDamageIssueListScreen();
}

class WhAdaptiveInternalUseList extends StatelessWidget {
  const WhAdaptiveInternalUseList({super.key});

  @override
  Widget build(BuildContext context) =>
      WhMobileNav.useNewMobileUi(context)
          ? const WhMobileDocListScreen(docType: WhDocType.internalUseIssue)
          : const PosInternalUseListScreen();
}
