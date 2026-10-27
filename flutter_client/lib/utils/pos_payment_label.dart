/// Mã phương thức tiếng Anh (đơn tạo qua API / import / dữ liệu cũ) → nhãn tiếng Việt.
/// Nhãn đã là tiếng Việt hoặc tên tài khoản nhận tiền thì giữ nguyên.
String posPaymentMethodVi(String? method) {
  final m = (method ?? '').trim();
  switch (m.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '')) {
    case 'cash':
      return 'Tiền mặt';
    case 'transfer':
    case 'banktransfer':
    case 'bank':
      return 'Chuyển khoản';
    case 'card':
    case 'creditcard':
      return 'Thẻ';
    case 'debt':
    case 'credit':
      return 'Công nợ';
    case 'mixed':
      return 'Tiền mặt + CK';
  }
  return m;
}

/// Hình thức thanh toán hiển thị của đơn bán: đơn thu chưa đủ ghi thêm «Công nợ»
/// (khách chưa trả gì → «Công nợ»; trả một phần → «Tiền mặt + Công nợ»).
/// Đơn lưu phương thức của tiền đã thu — «Công nợ» chỉ là nhãn, không lưu.
String posPaymentLabel(String? method, {required double paid, required double due}) {
  final m = posPaymentMethodVi(method);
  if (due <= 0.5) return m.isEmpty ? 'Tiền mặt' : m;
  if (paid <= 0.5) return 'Công nợ';
  return '${m.isEmpty ? 'Tiền mặt' : m} + Công nợ';
}

/// Như [posPaymentLabel] cho bản ghi JSON (danh sách đơn, lịch sử mua, báo cáo).
String posPaymentLabelOf(Map<String, dynamic> o) {
  double n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  final paid = n(o['paidAmount'] ?? o['PaidAmount']);
  final hasDue = o.containsKey('balanceDue') || o.containsKey('BalanceDue');
  final total = n(o['payableTotal'] ?? o['PayableTotal'] ?? o['total'] ?? o['Total']);
  final due = hasDue ? n(o['balanceDue'] ?? o['BalanceDue']) : total - paid;
  final status = '${o['status'] ?? o['Status'] ?? ''}'.toLowerCase();
  // Đơn tạm / đã hủy: không phải công nợ.
  if (status == '0' || status == 'draft' || status == '2' || status == 'cancelled') {
    return posPaymentMethodVi('${o['paymentMethod'] ?? o['PaymentMethod'] ?? ''}');
  }
  return posPaymentLabel('${o['paymentMethod'] ?? o['PaymentMethod'] ?? ''}', paid: paid, due: due);
}
