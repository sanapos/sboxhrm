import 'package:flutter/material.dart';

import '../../widgets/warehouse/wh_doc_type.dart';
import '../pos_purchase_receipt_list_screen.dart';
import '../pos_purchase_return_list_screen.dart';
import '../pos_stock_count_list_screen.dart';
import '../pos_stock_issue_list_screen.dart';
import '../pos_damage_issue_list_screen.dart';
import '../pos_internal_use_list_screen.dart';

class WhMobileHubScreen extends StatelessWidget {
  const WhMobileHubScreen({super.key});

  static Future<void> open(BuildContext context, {WhDocType? type}) async {
    final screen = switch (type) {
      WhDocType.purchaseReceipt => const PosPurchaseReceiptListScreen(),
      WhDocType.purchaseReturn => const PosPurchaseReturnListScreen(),
      WhDocType.stockCount => const PosStockCountListScreen(),
      WhDocType.damageIssue => const PosDamageIssueListScreen(),
      WhDocType.internalUseIssue => const PosInternalUseListScreen(),
      null => const PosPurchaseReceiptListScreen(),
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kho')),
      body: ListView(
        children: [
          for (final t in WhDocType.values)
            ListTile(
              title: Text(t.title),
              onTap: () => open(context, type: t),
            ),
        ],
      ),
    );
  }
}

class WhMobileDocListScreen extends StatelessWidget {
  const WhMobileDocListScreen({super.key, required this.type});
  final WhDocType type;

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      WhDocType.purchaseReceipt => const PosPurchaseReceiptListScreen(),
      WhDocType.purchaseReturn => const PosPurchaseReturnListScreen(),
      WhDocType.stockCount => const PosStockCountListScreen(),
      WhDocType.damageIssue => const PosDamageIssueListScreen(),
      WhDocType.internalUseIssue => const PosInternalUseListScreen(),
    };
  }
}

class WhAdaptivePurchaseReceiptList extends StatelessWidget {
  const WhAdaptivePurchaseReceiptList({super.key});
  @override
  Widget build(BuildContext context) => const PosPurchaseReceiptListScreen();
}

class WhAdaptivePurchaseReturnList extends StatelessWidget {
  const WhAdaptivePurchaseReturnList({super.key});
  @override
  Widget build(BuildContext context) => const PosPurchaseReturnListScreen();
}

class WhAdaptiveStockCountList extends StatelessWidget {
  const WhAdaptiveStockCountList({super.key});
  @override
  Widget build(BuildContext context) => const PosStockCountListScreen();
}

class WhAdaptiveDamageIssueList extends StatelessWidget {
  const WhAdaptiveDamageIssueList({super.key});
  @override
  Widget build(BuildContext context) => const PosDamageIssueListScreen();
}

class WhAdaptiveInternalUseList extends StatelessWidget {
  const WhAdaptiveInternalUseList({super.key});
  @override
  Widget build(BuildContext context) => const PosInternalUseListScreen();
}
