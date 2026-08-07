import 'package:flutter/material.dart';

import 'pos_purchase_toolbar.dart';

Widget stockCountStatusChip(String status) => purchaseStatusChip(
      status == 'InProgress' ? 'Draft' : status,
      completedLabel: 'Đã cân bằng kho',
    );

String stockCountStatusLabel(String status) => switch (status) {
      'Completed' => 'Đã cân bằng kho',
      'Cancelled' => 'Đã hủy',
      'InProgress' => 'Phiếu tạm',
      _ => status,
    };
