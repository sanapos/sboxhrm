import 'package:flutter/material.dart';

import '../widgets/pos/pos_stock_issue_config.dart';
import 'pos_stock_issue_list_screen.dart';

class PosDamageIssueListScreen extends StatelessWidget {
  const PosDamageIssueListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PosStockIssueListScreen(config: PosStockIssueConfig.damage);
  }
}
