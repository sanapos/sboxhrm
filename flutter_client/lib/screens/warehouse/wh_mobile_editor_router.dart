import 'package:flutter/material.dart';

import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/warehouse/wh_doc_type.dart';
import 'editors/wh_mobile_purchase_receipt_editor.dart';
import 'editors/wh_mobile_purchase_return_editor.dart';
import 'editors/wh_mobile_stock_count_editor.dart';
import 'editors/wh_mobile_stock_issue_editor.dart';

/// Điều hướng tới editor mobile mới theo loại phiếu.
abstract final class WhMobileEditorRouter {
  static Future<bool?> openCreate(BuildContext context, WhDocType type) =>
      _push(context, type, docId: null);

  static Future<bool?> openEdit(
    BuildContext context,
    WhDocType type,
    String docId,
  ) =>
      _push(context, type, docId: docId);

  static Future<bool?> _push(
    BuildContext context,
    WhDocType type, {
    required String? docId,
  }) {
    final widget = switch (type) {
      WhDocType.purchaseReceipt => WhMobilePurchaseReceiptEditor(docId: docId),
      WhDocType.purchaseReturn => WhMobilePurchaseReturnEditor(docId: docId),
      WhDocType.stockCount => WhMobileStockCountEditor(countId: docId),
      WhDocType.damageIssue => WhMobileStockIssueEditor(
          docType: WhDocType.damageIssue,
          issueId: docId,
        ),
      WhDocType.internalUseIssue => WhMobileStockIssueEditor(
          docType: WhDocType.internalUseIssue,
          issueId: docId,
        ),
    };
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PosHubScope(
          embeddedInHub: false,
          pushedSubPage: true,
          child: widget,
        ),
      ),
    );
  }
}
