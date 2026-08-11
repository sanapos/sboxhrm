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

  /// Tên hiển thị rõ loại + khổ (đổi tên cũ «Khổ K80 - Mẫu 1»).
  String get displayTitle {
    final n = name.trim();
    final doc = PosPrintDocumentTypes.all[documentType] ?? documentType;
    final paper = PosPrintPaperSizes.displayLabel(paperSize);
    final looksGeneric = n.isEmpty ||
        RegExp(r'^Khổ\s', caseSensitive: false).hasMatch(n) ||
        RegExp(r'^Tem\s+\d', caseSensitive: false).hasMatch(n) ||
        n == paperSize;
    if (looksGeneric) {
      final m = RegExp(r'Mẫu\s*(\d+)', caseSensitive: false).firstMatch(n);
      final variant = m?.group(1) ?? '1';
      final shortPaper = switch (paperSize) {
        PosPrintPaperSizes.k58 => 'K58',
        PosPrintPaperSizes.k80 => 'K80',
        PosPrintPaperSizes.a5 => 'A5',
        PosPrintPaperSizes.a4 => 'A4',
        PosPrintPaperSizes.label50x30 || 'roll_1_50x30' => '50×30',
        PosPrintPaperSizes.label40x30 || 'roll_1_40x30' => '40×30',
        _ => paperSize,
      };
      return '$doc $variant ($shortPaper)';
    }
    if (!n.contains(doc) && !n.toLowerCase().contains('hóa đơn')) {
      return '$n · $doc · $paper';
    }
    return n;
  }

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
  /// Tem dán sản phẩm (mã hàng / mã vạch / giá).
  static const barcodeLabel = 'BarcodeLabel';
  /// Tem báo bếp / tem ly / tem báo sản phẩm khi chế biến.
  static const kitchenLabel = 'KitchenLabel';

  static const all = <String, String>{
    saleInvoice: 'Hóa đơn bán hàng',
    stockIssue: 'Xuất kho',
    kitchenSlip: 'Báo chế biến',
    kitchenVoid: 'Hủy bếp',
    kitchenLabel: 'Tem báo bếp',
    barcodeLabel: 'Tem sản phẩm',
    saleOrder: 'Đặt hàng',
    delivery: 'Giao hàng',
    saleReturn: 'Trả hàng',
    saleExchange: 'Đổi trả hàng',
    purchaseOrder: 'Đặt hàng nhập',
    purchaseReceipt: 'Nhập hàng',
    purchaseReturn: 'Trả hàng nhập',
    stockTransfer: 'Chuyển hàng',
    cashReceipt: 'Phiếu thu',
    cashPayment: 'Phiếu chi',
  };

  /// Gợi ý ngắn khi chọn loại mẫu — tránh nhầm Hóa đơn ↔ Xuất kho ↔ Tem.
  static const usageHints = <String, String>{
    saleInvoice: 'In khi thanh toán (hóa đơn bán hàng).',
    stockIssue: 'Phiếu xuất kho / báo kho — sau thanh toán hoặc nút Báo kho.',
    kitchenSlip: 'Phiếu báo chế biến (bếp). Chế độ: không in / thủ công (Báo bếp) / tự in sau thanh toán. Máy nhiệt + gán SP.',
    kitchenVoid: 'Phiếu hủy món đã báo bếp (in kèm khi hủy trên báo bếp).',
    kitchenLabel: 'Tem ly / tem báo bếp (1 tem mỗi món, khổ 50×30 hoặc 40×30). Không dùng khổ K58/K80.',
    barcodeLabel: 'Tem dán sản phẩm (mã hàng / barcode / giá). Khổ tem — không phải phiếu nhiệt.',
    saleOrder: 'Phiếu đặt hàng (không phải hóa đơn thanh toán).',
    delivery: 'Phiếu giao hàng.',
    saleReturn: 'Phiếu trả hàng bán.',
    saleExchange: 'Phiếu đổi trả hàng.',
    purchaseOrder: 'Đơn đặt hàng nhập.',
    purchaseReceipt: 'Phiếu nhập hàng.',
    purchaseReturn: 'Phiếu trả hàng nhập.',
    stockTransfer: 'Phiếu chuyển kho.',
    cashReceipt: 'Phiếu thu tiền.',
    cashPayment: 'Phiếu chi tiền.',
  };

  static String usageHint(String documentType) =>
      usageHints[documentType] ?? 'Chọn đúng loại mẫu khớp chức năng in cần dùng.';
}

abstract final class PosPrintPaperSizes {
  static const k58 = 'K58';
  static const k80 = 'K80';
  static const a5 = 'A5';
  static const a4 = 'A4';
  /// Tem nhãn 50×30 mm.
  static const label50x30 = 'Label50x30';
  /// Tem nhãn 40×30 mm.
  static const label40x30 = 'Label40x30';
  static const label60x40 = 'Label60x40';
  static const label58x40 = 'Label58x40';
  static const label75x100 = 'Label75x100';
  static const label100x150 = 'Label100x150';
  /// 35×22 × 2 tem (cuộn đôi).
  static const label35x22x2 = 'roll_2_72x22';
  /// 35×22 × 3 tem (cuộn ba).
  static const label35x22x3 = 'roll_3_104x22';

  static const labels = <String, String>{
    k58: 'Khổ K58 (58mm) — phiếu nhiệt',
    k80: 'Khổ K80 (80mm) — phiếu nhiệt',
    a5: 'Khổ A5 — phiếu / PDF',
    a4: 'Khổ A4 — phiếu / PDF',
    label50x30: 'Tem 50×30 mm',
    label40x30: 'Tem 40×30 mm',
    label60x40: 'Tem 60×40 mm',
    label58x40: 'Tem 58×40 mm',
    label75x100: 'Tem 75×100 mm (A7)',
    label100x150: 'Tem 100×150 mm (A6)',
    label35x22x2: 'Tem 35×22 × 2',
    label35x22x3: 'Tem 35×22 × 3',
    'roll_1_50x30': 'Tem 50×30 mm',
    'roll_1_40x30': 'Tem 40×30 mm',
    'roll_1_60x40': 'Tem 60×40 mm',
    'roll_1_58x40': 'Tem 58×40 mm',
    'roll_1_75x100': 'Tem 75×100 mm (A7)',
    'roll_1_100x150': 'Tem 100×150 mm (A6)',
  };

  /// Nhãn hiển thị (gồm id tem roll_* từ mẫu barcode).
  static String displayLabel(String paperSize) {
    final known = labels[paperSize];
    if (known != null) return known;
    if (paperSize.startsWith('roll_') ||
        paperSize.startsWith('sheet_') ||
        paperSize.startsWith('jewelry_')) {
      return 'Tem · $paperSize';
    }
    return paperSize;
  }

  /// Khổ nhiệt phiếu (không gồm tem).
  static const receiptSizes = [k58, k80, a5, a4];

  /// Khổ tem báo bếp / tem ly — không dùng K58/K80/A4/A5.
  static const kitchenLabelSizes = [
    label50x30,
    label40x30,
    label35x22x2,
    label35x22x3,
    label60x40,
    label58x40,
    label75x100,
    label100x150,
  ];

  /// Khổ tem hàng hóa (dropdown mẫu in tem).
  static List<String> get productLabelSizes => [
        for (final t in const [
          'roll_1_50x30',
          'roll_1_40x30',
          'roll_2_72x22',
          'roll_3_104x22',
          'roll_1_60x40',
          'roll_1_58x40',
          'roll_1_75x100',
          'roll_1_100x150',
        ])
          t,
      ];

  /// Nhóm UI: phiếu nhiệt vs tem.
  static String categoryLabel(String documentType) {
    if (isLabelDoc(documentType)) return 'Tem nhãn';
    return 'Phiếu nhiệt / PDF';
  }

  static bool isLabelDoc(String documentType) =>
      documentType == PosPrintDocumentTypes.barcodeLabel ||
      documentType == PosPrintDocumentTypes.kitchenLabel;

  static bool isLabelSize(String size) =>
      size == label50x30 ||
      size == label40x30 ||
      size == label60x40 ||
      size == label58x40 ||
      size == label75x100 ||
      size == label100x150 ||
      size.startsWith('roll_') ||
      size.startsWith('sheet_') ||
      size.startsWith('jewelry_');

  static double widthMm(String size) {
    final fromRoll = _dimsFromRollId(size);
    if (fromRoll != null) return fromRoll.$1;
    return switch (size) {
      label50x30 => 50,
      label40x30 => 40,
      label60x40 => 60,
      label58x40 => 58,
      label75x100 => 75,
      label100x150 => 100,
      k58 => 58,
      k80 => 80,
      a5 => 148,
      a4 => 210,
      _ => 50,
    };
  }

  static double heightMm(String size) {
    final fromRoll = _dimsFromRollId(size);
    if (fromRoll != null) return fromRoll.$2;
    return switch (size) {
      label50x30 => 30,
      label40x30 => 30,
      label60x40 => 40,
      label58x40 => 40,
      label75x100 => 100,
      label100x150 => 150,
      k58 || k80 => 0,
      a5 => 210,
      a4 => 297,
      _ => 30,
    };
  }

  static (double, double)? _dimsFromRollId(String size) {
    switch (size) {
      case 'roll_1_50x30':
      case label50x30:
        return (50, 30);
      case 'roll_1_40x30':
      case label40x30:
        return (40, 30);
      case 'roll_1_60x40':
      case label60x40:
        return (60, 40);
      case 'roll_1_58x40':
      case label58x40:
        return (58, 40);
      case 'roll_1_75x100':
      case label75x100:
        return (75, 100);
      case 'roll_1_100x150':
      case label100x150:
        return (100, 150);
      case label35x22x2: // == roll_2_72x22
        return (36, 22);
      case label35x22x3: // == roll_3_104x22
        return (34.67, 22);
      case 'roll_1_100x50':
        return (100, 50);
    }
    return null;
  }

  /// Phiếu nhiệt cuộn (không gồm tem nhãn).
  static bool isThermal(String size) => size == k58 || size == k80;

  /// Map khổ V2 (có thể là id tem barcode) → enum API (chỉ 50×30 / 40×30).
  static String toApiPaperSize(String documentType, String v2PaperSize) {
    if (documentType == PosPrintDocumentTypes.kitchenLabel ||
        documentType == PosPrintDocumentTypes.barcodeLabel) {
      if (v2PaperSize == label40x30 ||
          v2PaperSize == 'roll_1_40x30' ||
          v2PaperSize == label35x22x2 ||
          v2PaperSize == label35x22x3) {
        return label40x30;
      }
      return label50x30;
    }
    if (labels.containsKey(v2PaperSize) && !isLabelSize(v2PaperSize)) {
      return v2PaperSize;
    }
    return k80;
  }

  /// Id khổ máy in tem (roll_*) từ paperSize mẫu.
  static String toLabelTemplateId(String paperSize) {
    switch (paperSize) {
      case label50x30:
        return 'roll_1_50x30';
      case label40x30:
        return 'roll_1_40x30';
      case label60x40:
        return 'roll_1_60x40';
      case label58x40:
        return 'roll_1_58x40';
      case label75x100:
        return 'roll_1_75x100';
      case label100x150:
        return 'roll_1_100x150';
      case label35x22x2:
        return 'roll_2_72x22';
      case label35x22x3:
        return 'roll_3_104x22';
      default:
        if (paperSize.startsWith('roll_') ||
            paperSize.startsWith('sheet_') ||
            paperSize.startsWith('jewelry_')) {
          return paperSize;
        }
        return 'roll_1_50x30';
    }
  }
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
    ('Ma_Vach', 'Mã vạch'),
    ('Ten_Hang_Hoa', 'Tên hàng'),
    ('Don_Gia', 'Đơn giá'),
    ('So_Luong', 'Số lượng'),
    ('Don_Vi_Tinh', 'ĐVT'),
    ('Chiet_Khau', 'Chiết khấu dòng'),
    ('Thanh_Tien', 'Thành tiền dòng'),
    ('Ten_Ban', 'Tên bàn'),
  ];

  /// Token chuyên dùng tem sản phẩm / tem bếp.
  static const label = [
    ('Ma_Hang', 'Mã hàng'),
    ('Ma_Vach', 'Mã vạch'),
    ('Ten_Hang_Hoa', 'Tên hàng'),
    ('Don_Gia', 'Đơn giá'),
    ('Don_Vi_Tinh', 'ĐVT'),
    ('So_Luong', 'Số lượng'),
    ('Ten_Ban', 'Tên bàn'),
    ('Ma_Don_Hang', 'Mã đơn'),
    ('Ngay', 'Ngày'),
    ('Gio', 'Giờ'),
    ('Ghi_Chu', 'Ghi chú / topping'),
    ('Ten_Cua_Hang', 'Tên cửa hàng'),
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
