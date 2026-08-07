import 'package:flutter/material.dart';

import 'pos_purchase_toolbar.dart';

Widget stockIssueStatusChip(String status) =>
    purchaseStatusChip(status, completedLabel: 'Hoàn thành');

String stockIssueStatusLabel(String status) => switch (status) {
      'Completed' => 'Hoàn thành',
      'Cancelled' => 'Đã hủy',
      'Draft' => 'Phiếu tạm',
      _ => status,
    };
