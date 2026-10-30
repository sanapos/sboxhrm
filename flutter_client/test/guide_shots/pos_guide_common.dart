import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/user.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';

/// Phần dùng chung cho ảnh hướng dẫn POS (bổ sung cho guide_shot_kit.dart, không sửa kit).

/// Gói dịch vụ đủ module POS — màn nào lọc theo gói (hub báo cáo, menu POS) mới hiện đủ thẻ.
const posGuideModules = [
  'PosSell', 'PosProducts', 'PosSalesReport', 'PosReportRevenue', 'PosReportSoldGoods', 'PosReportStock',
  'PosReportPurchases', 'PosReportPayment', 'PosReportDebt', 'PosReportExpiry', 'PosReportProfit',
  'PosReportExpense', 'PosReportEndOfDay', 'PosReportStaffRevenue', 'PosReportStaffCommission',
  'PosReportCashbook', 'PosReportPnl', 'PosReportVoucher', 'PosBooking', 'PosEInvoice', 'HkdBooks',
  'PosPrinters', 'PosStorePrinters', 'PosPrintTemplates', 'PosCustomers', 'PosSaleOrders',
];

/// Bọc [child] bằng AuthProvider có gói module POS (provider gần hơn khung của kit).
Widget withPosPackage(Widget child) {
  // Tạo AuthProvider trước khi kit giả SharedPreferences → khôi phục phiên lỗi và xóa user.
  SharedPreferences.setMockInitialValues({});
  final auth = AuthProvider()
    ..debugSetUser(User(
      id: 'u1',
      employeeId: 'e1',
      email: 'admin@caphemoc.vn',
      fullName: 'Nguyễn Văn An',
      role: 'Admin',
      storeId: 's1',
      allowedModules: posGuideModules,
    ));
  return ChangeNotifierProvider<AuthProvider>.value(value: auth, child: child);
}

/// API giả theo cả query: [handler] trả phần `data` (null = danh sách rỗng).
MockClient posGuideApi(Object? Function(http.Request req) handler) => MockClient((req) async {
      final data = handler(req) ?? const [];
      return http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
