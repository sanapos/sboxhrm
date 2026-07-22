class PosPrintTemplate {
  const PosPrintTemplate({
    required this.id,
    required this.name,
    required this.documentType,
    required this.paperSize,
    required this.htmlContent,
    this.isDefault = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String documentType;
  final String paperSize;
  final String htmlContent;
  final bool isDefault;
  final bool isActive;
  final int sortOrder;

  factory PosPrintTemplate.fromJson(Map<String, dynamic> json) => PosPrintTemplate(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        documentType: json['documentType']?.toString() ?? 'SaleInvoice',
        paperSize: json['paperSize']?.toString() ?? 'K80',
        htmlContent: json['htmlContent']?.toString() ?? '',
        isDefault: json['isDefault'] == true,
        isActive: json['isActive'] != false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toSaveJson() => {
        'name': name,
        'documentType': documentType,
        'paperSize': paperSize,
        'htmlContent': htmlContent,
        'isDefault': isDefault,
        'isActive': isActive,
        'sortOrder': sortOrder,
      };

  PosPrintTemplate copyWith({
    String? name,
    String? documentType,
    String? paperSize,
    String? htmlContent,
    bool? isDefault,
    bool? isActive,
    int? sortOrder,
  }) =>
      PosPrintTemplate(
        id: id,
        name: name ?? this.name,
        documentType: documentType ?? this.documentType,
        paperSize: paperSize ?? this.paperSize,
        htmlContent: htmlContent ?? this.htmlContent,
        isDefault: isDefault ?? this.isDefault,
        isActive: isActive ?? this.isActive,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

class PosPrintTemplatePreset {
  const PosPrintTemplatePreset({
    required this.paperSize,
    required this.name,
    required this.htmlContent,
  });

  final String paperSize;
  final String name;
  final String htmlContent;

  factory PosPrintTemplatePreset.fromJson(Map<String, dynamic> json) =>
      PosPrintTemplatePreset(
        paperSize: json['paperSize']?.toString() ?? 'K80',
        name: json['name']?.toString() ?? '',
        htmlContent: json['htmlContent']?.toString() ?? '',
      );
}

/// Loại chứng từ mẫu in.
abstract final class PosPrintDocumentTypes {
  static const saleOrder = 'SaleOrder';
  static const saleInvoice = 'SaleInvoice';
  static const delivery = 'Delivery';
  static const saleReturn = 'SaleReturn';
  static const saleExchange = 'SaleExchange';
  static const purchaseOrder = 'PurchaseOrder';
  static const purchaseReceipt = 'PurchaseReceipt';
  static const purchaseReturn = 'PurchaseReturn';
  static const stockTransfer = 'StockTransfer';
  static const stockIssue = 'StockIssue';
  static const cashReceipt = 'CashReceipt';
  static const cashPayment = 'CashPayment';
  static const kitchenSlip = 'KitchenSlip';
  static const kitchenVoid = 'KitchenVoid';

  static const all = <String, String>{
    saleOrder: 'Đặt hàng',
    saleInvoice: 'Hóa đơn',
    delivery: 'Giao hàng',
    saleReturn: 'Trả hàng',
    saleExchange: 'Đổi trả hàng',
    purchaseOrder: 'Đặt hàng nhập',
    purchaseReceipt: 'Nhập hàng',
    purchaseReturn: 'Trả hàng nhập',
    stockTransfer: 'Chuyển hàng',
    stockIssue: 'Phiếu xuất kho',
    cashReceipt: 'Phiếu thu',
    cashPayment: 'Phiếu chi',
    kitchenSlip: 'Phiếu chế biến',
    kitchenVoid: 'Phiếu hủy bếp',
  };
}

abstract final class PosPrintPaperSizes {
  static const k58 = 'K58';
  static const k80 = 'K80';
  static const a5 = 'A5';
  static const a4 = 'A4';

  static const labels = <String, String>{
    k58: 'Khổ K58 (58mm)',
    k80: 'Khổ K80 (80mm)',
    a5: 'Khổ A5',
    a4: 'Khổ A4',
  };

  static double widthMm(String size) => switch (size) {
        k58 => 58,
        k80 => 80,
        a5 => 148,
        a4 => 210,
        _ => 80,
      };

  static bool isThermal(String size) => size == k58 || size == k80;
}

/// Placeholder có thể chèn vào mẫu in.
abstract final class PosPrintTokens {
  static const store = [
    ('Ten_Cua_Hang', 'Tên cửa hàng'),
    ('Dia_Chi_Chi_Nhanh', 'Địa chỉ chi nhánh'),
    ('Dien_Thoai_Chi_Nhanh', 'Điện thoại'),
  ];

  static const order = [
    ('Ma_Don_Hang', 'Mã đơn / hóa đơn'),
    ('Ngay', 'Ngày'),
    ('Gio', 'Giờ'),
    ('Tieu_De_In', 'Tiêu đề in'),
  ];

  static const customer = [
    ('Khach_Hang', 'Tên khách hàng'),
    ('SDT', 'Số điện thoại'),
    ('Dia_Chi_Khach_Hang', 'Địa chỉ khách'),
  ];

  static const line = [
    ('STT', 'STT dòng'),
    ('Ma_Hang', 'Mã hàng'),
    ('Ten_Hang_Hoa', 'Tên hàng'),
    ('Don_Gia', 'Đơn giá'),
    ('So_Luong', 'Số lượng'),
    ('Don_Vi_Tinh', 'ĐVT'),
    ('Chiet_Khau', 'Chiết khấu dòng'),
    ('Thanh_Tien', 'Thành tiền dòng'),
  ];

  static const totals = [
    ('Tong_Tien_Hang', 'Tổng tiền hàng'),
    ('Chiet_Khau_Hoa_Don', 'Chiết khấu đơn'),
    ('Tong_Cong', 'Tổng cộng'),
    ('Khach_Can_Tra', 'Khách cần trả'),
    ('Khach_Thanh_Toan', 'Khách thanh toán'),
    ('Tien_Thua', 'Tiền thừa'),
    ('Con_Lai', 'Còn lại'),
    ('Tong_Cong_Bang_Chu', 'Tổng bằng chữ'),
    ('Hinh_Thuc_Thanh_Toan', 'Hình thức thanh toán'),
    ('Nguoi_Ban', 'Người bán'),
    ('Ghi_Chu', 'Ghi chú'),
  ];

  static const blockHint =
      '<!--BEGIN_ITEMS--> ... <!--END_ITEMS--> — lặp cho từng dòng hàng';
}
