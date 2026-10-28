import '../utils/api_datetime.dart';
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
    this.sourceCatalogId,
    this.createdAt,
    this.updatedAt,
    this.isDocx = false,
  });

  final String id;
  final String name;
  final String documentType;
  final String paperSize;
  final String htmlContent;
  final bool isDefault;
  final bool isActive;
  final int sortOrder;
  /// Id mẫu chung đã clone (nếu có).
  final String? sourceCatalogId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  /// Mẫu Word giữ nguyên bố cục (AI gắn mã trường) — sửa qua màn «Trường mẫu Word».
  final bool isDocx;

  /// Tên ngắn trên UI thiết lập: `Hợp đồng 1 · A4 ★`.
  String get shortLabel {
    final paper = PosPrintPaperSizes.shortLabel(paperSize);
    final n = name.trim();
    final star = isDefault && !n.contains('★') && !paper.contains('★') ? ' ★' : '';
    final word = isDocx ? ' · Word' : '';
    if (n.isEmpty) return '$paper$word$star';
    return '$n · $paper$word$star';
  }

  /// Tên hiển thị rõ loại + khổ (đổi tên cũ «Khổ K80 - Mẫu 1»).
  String get displayTitle => shortLabel;

  factory PosPrintTemplate.fromJson(Map<String, dynamic> json) => PosPrintTemplate(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        documentType: json['documentType']?.toString() ?? 'SaleInvoice',
        paperSize: json['paperSize']?.toString() ?? 'K80',
        htmlContent: json['htmlContent']?.toString() ?? '',
        isDefault: json['isDefault'] == true,
        isActive: json['isActive'] != false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        sourceCatalogId: (json['sourceCatalogId'] ?? json['SourceCatalogId'])
            ?.toString(),
        createdAt: parseApiUtcDateTime(
            '${json['createdAt'] ?? json['CreatedAt'] ?? ''}'),
        updatedAt: parseApiUtcDateTime(
            '${json['updatedAt'] ?? json['UpdatedAt'] ?? ''}'),
        isDocx: json['isDocx'] == true || json['IsDocx'] == true,
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
    String? sourceCatalogId,
    DateTime? createdAt,
    DateTime? updatedAt,
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
        sourceCatalogId: sourceCatalogId ?? this.sourceCatalogId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isDocx: isDocx,
      );
}

/// Mẫu chung (soạn sẵn) — cửa hàng chọn «Dùng mẫu này» để clone.
class PosPrintTemplateCatalog {
  const PosPrintTemplateCatalog({
    required this.id,
    required this.name,
    required this.documentType,
    required this.paperSize,
    required this.htmlContent,
    this.isRecommended = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String documentType;
  final String paperSize;
  final String htmlContent;
  final bool isRecommended;
  final bool isActive;
  final int sortOrder;

  factory PosPrintTemplateCatalog.fromJson(Map<String, dynamic> json) =>
      PosPrintTemplateCatalog(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        documentType: json['documentType']?.toString() ?? 'SaleInvoice',
        paperSize: json['paperSize']?.toString() ?? 'K80',
        htmlContent: json['htmlContent']?.toString() ?? '',
        isRecommended: json['isRecommended'] == true,
        isActive: json['isActive'] != false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
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
  /// Tem cân hàng tươi (khối lượng × đơn giá, mã cân EAN-13, ngày giờ in, HSD).
  static const scaleLabel = 'ScaleLabel';

  /// Tem thông số kỹ thuật / tem tự soạn: khổ tùy chỉnh, mã vạch / QR nội dung tự soạn, trường thông số hàng.
  static const specLabel = 'SpecLabel';

  /// Tem dán hàng (tem sản phẩm / tem cân / tem thông số) — cùng khổ tem, cùng máy in tem.
  static bool isProductLabel(String t) => t == barcodeLabel || t == scaleLabel || t == specLabel;
  static const quote = 'Quote';
  static const contract = 'Contract';
  static const handover = 'Handover';
  static const acceptance = 'Acceptance';
  static const paymentRequest = 'PaymentRequest';

  static bool isCommercial(String t) =>
      t == quote ||
      t == contract ||
      t == handover ||
      t == acceptance ||
      t == paymentRequest;

  static const all = <String, String>{
    saleInvoice: 'Hóa đơn bán hàng',
    stockIssue: 'Xuất kho',
    kitchenSlip: 'Báo chế biến',
    kitchenVoid: 'Hủy bếp',
    kitchenLabel: 'Tem báo bếp',
    barcodeLabel: 'Tem sản phẩm',
    scaleLabel: 'Tem cân',
    specLabel: 'Tem thông số / tự soạn',
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
    quote: 'Báo giá',
    contract: 'Hợp đồng',
    handover: 'Biên bản bàn giao',
    acceptance: 'Biên bản nghiệm thu',
    paymentRequest: 'Đề nghị thanh toán',
  };

  /// Gợi ý ngắn khi chọn loại mẫu — tránh nhầm Hóa đơn ↔ Xuất kho ↔ Tem.
  static const usageHints = <String, String>{
    saleInvoice: 'In khi thanh toán (hóa đơn bán hàng).',
    stockIssue: 'Phiếu xuất kho / báo kho — sau thanh toán hoặc nút Báo kho.',
    kitchenSlip: 'Phiếu báo chế biến (bếp). Chế độ: không in / thủ công (Báo bếp) / tự in sau thanh toán. Máy nhiệt + gán SP.',
    kitchenVoid: 'Phiếu hủy món đã báo bếp (in kèm khi hủy trên báo bếp).',
    kitchenLabel: 'Tem ly / tem báo bếp (1 tem mỗi món, khổ 50×30 hoặc 40×30). Không dùng khổ K58/K80.',
    barcodeLabel: 'Tem dán sản phẩm (mã hàng / barcode / giá). Khổ tem — không phải phiếu nhiệt.',
    scaleLabel: 'Tem cân hàng tươi (rau, thịt, cá…): khối lượng, đơn giá/kg, thành tiền, mã cân, ngày giờ in, HSD.',
    specLabel: 'Tem thông số kỹ thuật / tem tự soạn: khổ tem tùy chỉnh (rộng × cao mm), mã vạch hoặc QR nội dung tự soạn, '
        'thương hiệu, xuất xứ, bảo hành, kích thước, khối lượng…',
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
    quote: 'Bảng báo giá A4 — soạn như Word, trường động như hóa đơn.',
    contract: 'Hợp đồng thi công A4 (Bên A / Bên B, điều khoản, bảng hạng mục).',
    handover: 'Biên bản bàn giao công trình A4.',
    acceptance: 'Biên bản nghiệm thu hoàn thành A4.',
    paymentRequest: 'Đề nghị thanh toán / tạm ứng theo hợp đồng.',
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
    k58: 'Khổ K57/K58 (57–58mm) — phiếu nhiệt',
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

  /// Nhãn ngắn cho dropdown / chip (K80, 50×30…).
  static String shortLabel(String paperSize) {
    return switch (paperSize) {
      k58 => 'K58',
      k80 => 'K80',
      a5 => 'A5',
      a4 => 'A4',
      label50x30 || 'roll_1_50x30' => '50×30',
      label40x30 || 'roll_1_40x30' => '40×30',
      label60x40 || 'roll_1_60x40' => '60×40',
      label58x40 || 'roll_1_58x40' => '58×40',
      label75x100 || 'roll_1_75x100' => '75×100',
      label100x150 || 'roll_1_100x150' => '100×150',
      _ => paperSize,
    };
  }

  /// Nhãn hiển thị (gồm id tem roll_* từ mẫu barcode).
  static String displayLabel(String paperSize) {
    final known = labels[paperSize];
    if (known != null) return known;
    final custom = customLabelDims(paperSize);
    if (custom != null &&
        !productLabelSizes.contains(paperSize) &&
        paperSize != 'roll_1_100x50') {
      return 'Tem ${_mm(custom.$1)}×${_mm(custom.$2)} mm (tùy chỉnh)';
    }
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
      PosPrintDocumentTypes.isProductLabel(documentType) ||
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

  /// Điểm in nhiệt (K58=384, K80=576) — preview phải chia cùng mẫu này.
  static int thermalDots(String size) {
    final mm = widthMm(size);
    return mm <= 58 ? 384 : 576;
  }

  /// Quy đổi mm → px in nhiệt trên khổ giấy hiện tại.
  static int mmToPrintPx(String size, double mm) {
    final w = widthMm(size);
    if (w <= 0) return 0;
    return (thermalDots(size) / w * mm).round();
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

  static String _mm(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Id khổ tem tùy chỉnh 1 tem / hàng: `roll_1_{rộng}x{cao}` (mm, cho phép 1 số lẻ).
  static String customLabelId(double widthMm, double heightMm) =>
      'roll_1_${_mm(widthMm)}x${_mm(heightMm)}';

  /// (rộng, cao) mm của id `roll_1_WxH` bất kỳ; null nếu không phải dạng đó / ngoài 10–200 mm.
  static (double, double)? customLabelDims(String size) {
    final m = RegExp(r'^roll_1_(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)$').firstMatch(size);
    if (m == null) return null;
    final w = double.parse(m.group(1)!);
    final h = double.parse(m.group(2)!);
    if (w < 10 || w > 200 || h < 8 || h > 300) return null;
    return (w, h);
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
    return customLabelDims(size);
  }

  /// Phiếu nhiệt cuộn (không gồm tem nhãn).
  static bool isThermal(String size) => size == k58 || size == k80;

  /// Báo giá / HĐ / biên bản — chỉ A4 hoặc A5 (K80 cũ → A4).
  static String normalizeCommercialPaper(String? size) {
    final u = (size ?? '').trim().toUpperCase();
    if (u == a5) return a5;
    return a4;
  }

  /// Khổ máy in nhiệt từ cấu hình (K58 / K80 / 58mm…).
  static String fromPrinterName(String raw) {
    final p = raw.trim().toUpperCase();
    if (p == k58 || p.contains('58')) return k58;
    return k80;
  }

  static String fromWidthMm(int mm) => mm <= 58 ? k58 : k80;

  /// Map khổ V2 (có thể là id tem barcode) → enum API (chỉ 50×30 / 40×30).
  static String toApiPaperSize(String documentType, String v2PaperSize) {
    if (documentType == PosPrintDocumentTypes.kitchenLabel ||
        PosPrintDocumentTypes.isProductLabel(documentType)) {
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
    ('Dien_Thoai_Chi_Nhanh', 'Điện thoại cửa hàng'),
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
    ('Ten_Hang_Hoa', 'Tên hàng hóa'),
    ('Don_Gia', 'Đơn giá'),
    ('So_Luong', 'Số lượng'),
    ('Don_Vi_Tinh', 'ĐVT'),
    ('Chiet_Khau', 'Chiết khấu dòng'),
    ('Thanh_Tien', 'Thành tiền dòng'),
    ('Bao_Hanh', 'Bảo hành dòng'),
    ('Chieu_Dai', 'Chiều dài'),
    ('Chieu_Rong', 'Chiều rộng'),
    ('Chieu_Cao', 'Chiều cao'),
    ('Hinh_Anh', 'Hình ảnh SP (3×3 cm)'),
    ('Ten_Ban', 'Tên bàn'),
  ];

  /// Token chứng từ thương mại A4 (báo giá / HĐ / bàn giao / nghiệm thu).
  static const commercial = [
    ('Ma_Bao_Gia', 'Số báo giá'),
    ('So_Chung_Tu', 'Số chứng từ'),
    ('Han_Bao_Gia', 'Hạn báo giá'),
    ('Dieu_Khoan', 'Điều khoản'),
    ('Bao_Hanh', 'Bảo hành'),
    ('So_Hop_Dong', 'Số hợp đồng'),
    ('Ngay_Hop_Dong', 'Ngày ký HĐ'),
    ('Dia_Diem_Thi_Cong', 'Địa điểm thi công'),
    ('Logo', 'Logo công ty'),
    ('Ten_Cong_Ty', 'Tên công ty (pháp lý)'),
    ('Dia_Chi_Cong_Ty', 'Địa chỉ công ty'),
    ('Dien_Thoai_Cong_Ty', 'Điện thoại công ty'),
    ('MST_Cong_Ty', 'MST công ty'),
    ('MST_Cua_Hang', 'MST công ty shop'),
    ('Email_Cua_Hang', 'Email cửa hàng'),
    ('Tai_Khoan_Cua_Hang', 'Số TK cửa hàng'),
    ('Ngan_Hang_Cua_Hang', 'Ngân hàng cửa hàng'),
    ('Chu_Tai_Khoan_Cua_Hang', 'Chủ tài khoản cửa hàng'),
    ('Nguoi_Dai_Dien_Cua_Hang', 'Đại diện cửa hàng'),
    ('Chuc_Vu_Cua_Hang', 'Chức vụ đại diện CH'),
    ('MST_Khach_Hang', 'MST khách hàng'),
    ('Ten_Cong_Ty_Khach', 'Tên công ty KH'),
    ('Tai_Khoan_Khach_Hang', 'Số TK khách hàng'),
    ('Ngan_Hang_Khach_Hang', 'Ngân hàng khách hàng'),
    ('Nguoi_Dai_Dien_Khach', 'Đại diện khách hàng'),
    ('Chuc_Vu_Khach', 'Chức vụ đại diện KH'),
    ('Tam_Ung', 'Tạm ứng đợt 1'),
    ('Tien_Coc', 'Tiền cọc thực hiện HĐ'),
    ('Phan_Tram_Coc', '% cọc trên giá trị trước VAT'),
    ('Gia_Tri_Truoc_VAT', 'Giá trị trước VAT'),
    ('Con_Lai_Hop_Dong', 'Còn lại sau tạm ứng'),
    ('Ky_Han_Thi_Cong', 'Kỳ hạn thi công'),
    ('Ky_Han_Thanh_Toan', 'Kỳ hạn thanh toán'),
  ];

  /// Token chuyên dùng tem sản phẩm / tem bếp.
  static const label = [
    ('Ma_Hang', 'Mã hàng'),
    ('Ma_Vach', 'Mã vạch'),
    ('Ten_Hang_Hoa', 'Tên hàng hóa'),
    ('Don_Gia', 'Đơn giá'),
    ('Don_Vi_Tinh', 'ĐVT'),
    ('So_Luong', 'Số lượng'),
    ('Ten_Ban', 'Tên bàn'),
    ('Ma_Don_Hang', 'Mã đơn'),
    ('Ngay', 'Ngày'),
    ('Gio', 'Giờ'),
    ('Ghi_Chu', 'Ghi chú / topping'),
    ('Ten_Cua_Hang', 'Tên cửa hàng'),
    ('Thong_So', 'Thông số hàng (thuộc tính, KL, KT, BH)'),
    ('Lo_HSD', 'Lô / NSX / HSD'),
  ];

  /// Token tem thông số / tem tự soạn.
  static const specLabel = [
    ('Ten_Hang_Hoa', 'Tên hàng hóa'),
    ('Ma_Hang', 'Mã hàng'),
    ('Ma_Vach', 'Mã vạch'),
    ('Don_Gia', 'Giá bán'),
    ('Don_Vi_Tinh', 'ĐVT'),
    ('Thuong_Hieu', 'Thương hiệu'),
    ('Nhom_Hang', 'Nhóm hàng'),
    ('Nha_Cung_Cap', 'Nhà cung cấp / xuất xứ'),
    ('Thuoc_Tinh', 'Thuộc tính (Màu: Đỏ · Size: L)'),
    ('Khoi_Luong_SP', 'Khối lượng (vd 500 g)'),
    ('Kich_Thuoc', 'Kích thước (D×R×C cm)'),
    ('Bao_Hanh', 'Bảo hành (vd 12 tháng)'),
    ('Mo_Ta', 'Mô tả hàng'),
    ('Thong_So', 'Thông số gộp (TH · KL · KT · BH)'),
    ('Ten_Cua_Hang', 'Tên cửa hàng'),
    ('Ngay', 'Ngày in'),
  ];

  /// Token tem cân (màn Mẫu in → Tem cân).
  static const scaleLabel = [
    ('Ten_Cua_Hang', 'Tên cửa hàng'),
    ('Ten_Hang_Hoa', 'Tên hàng hóa'),
    ('Ma_Hang', 'Mã hàng'),
    ('Ma_Vach', 'Mã cân (EAN-13)'),
    ('PLU', 'Mã PLU'),
    ('Khoi_Luong', 'Khối lượng (vd 0,456 kg)'),
    ('Don_Vi_Tinh', 'ĐVT'),
    ('Don_Gia_Kg', 'Đơn giá / kg'),
    ('Thanh_Tien', 'Thành tiền'),
    ('Ngay_Dong_Goi', 'Ngày đóng gói'),
    ('Ngay_Gio_In', 'Ngày giờ in'),
    ('Ngay', 'Ngày in'),
    ('Gio', 'Giờ in'),
    ('HSD', 'Hạn sử dụng'),
    ('So_Ngay_Dung', 'Dùng trong (ngày)'),
    ('Lo_HSD', 'Dòng chi tiết (KL × giá · ĐG · HSD)'),
  ];

  static const totals = [
    ('Tong_Tien_Hang', 'Tổng tiền hàng'),
    ('Chiet_Khau_Hoa_Don', 'Chiết khấu đơn'),
    ('Tien_Thue', 'Thuế'),
    ('Phu_Thu', 'Phụ thu'),
    ('Phi_Giao_Hang', 'Phí giao hàng'),
    ('Tong_Cong', 'Tổng cộng'),
    ('Khach_Can_Tra', 'Khách cần trả'),
    ('Khach_Thanh_Toan', 'Khách thanh toán'),
    ('Tien_Thua', 'Tiền thừa'),
    ('Con_Lai', 'Còn lại'),
    ('Tong_Cong_Bang_Chu', 'Tổng bằng chữ'),
    ('Hinh_Thuc_Thanh_Toan', 'Hình thức thanh toán'),
    ('Cong_No', 'Còn nợ (ghi công nợ)'),
    ('Nguoi_Ban', 'Người bán'),
    ('Ghi_Chu', 'Ghi chú'),
    // HĐĐT — chỉ có giá trị khi đơn đã phát hành hóa đơn điện tử.
    ('HDDT_Ky_Hieu', 'HĐĐT: ký hiệu'),
    ('HDDT_So', 'HĐĐT: số hóa đơn'),
    ('HDDT_Ma_CQT', 'HĐĐT: mã CQT'),
    ('HDDT_Ma_Tra_Cuu', 'HĐĐT: mã tra cứu'),
    ('HDDT_Link_Tra_Cuu', 'HĐĐT: link tra cứu'),
  ];

  static const _supplier = [
    ('Nha_Cung_Cap', 'Nhà cung cấp'),
    ('Ma_NCC', 'Mã NCC'),
    ('Dia_Chi_NCC', 'Địa chỉ NCC'),
    ('SDT_NCC', 'Điện thoại NCC'),
    ('MST_NCC', 'MST NCC'),
    ('Chi_Nhanh', 'Chi nhánh'),
    ('Nguoi_Lap', 'Người lập phiếu'),
    ('Tong_So_Luong', 'Tổng số lượng'),
    ('VAT', 'Thuế GTGT'),
  ];

  /// Token riêng chứng từ khổ trang (đặt / giao / trả / đổi / nhập / kho / thu chi).
  static List<(String, String)> forDocument(String documentType) => switch (documentType) {
        PosPrintDocumentTypes.saleOrder => const [
            ('Ngay_Hen_Giao', 'Ngày hẹn giao'),
            ('Dia_Chi_Giao', 'Địa chỉ giao'),
            ('Tien_Coc', 'Tiền cọc'),
            ('Con_Phai_Thu', 'Còn phải thanh toán'),
          ],
        PosPrintDocumentTypes.delivery => const [
            ('Nguoi_Nhan', 'Người nhận'),
            ('SDT_Nguoi_Nhan', 'SĐT người nhận'),
            ('Dia_Chi_Giao', 'Địa chỉ giao'),
            ('Don_Vi_Van_Chuyen', 'Đơn vị vận chuyển'),
            ('Ma_Van_Don', 'Mã vận đơn'),
            ('Ngay_Giao', 'Ngày giao'),
            ('Nguoi_Giao', 'Người giao hàng'),
            ('Thu_Ho', 'Tiền thu hộ (COD)'),
          ],
        PosPrintDocumentTypes.saleReturn => const [
            ('Ma_HD_Goc', 'Hóa đơn gốc'),
            ('Ly_Do', 'Lý do'),
            ('Phi_Tra_Hang', 'Phí trả hàng'),
            ('Da_Hoan', 'Đã hoàn'),
          ],
        PosPrintDocumentTypes.saleExchange => const [
            ('Ma_HD_Goc', 'Hóa đơn gốc'),
            ('Ly_Do', 'Lý do'),
            ('Loai_Dong', 'Loại dòng (Trả lại / Đổi mới)'),
            ('Tien_Hang_Tra', 'Tiền hàng trả lại'),
            ('Tien_Hang_Doi', 'Tiền hàng đổi mới'),
            ('Phi_Tra_Hang', 'Phí đổi hàng'),
            ('Khach_Tra_Them', 'Khách trả thêm'),
            ('Tien_Hoan', 'Cửa hàng hoàn lại'),
          ],
        PosPrintDocumentTypes.purchaseOrder => const [
            ..._supplier,
            ('Ngay_Du_Kien', 'Ngày dự kiến nhận'),
            ('Da_Tra_NCC', 'Đã trả trước'),
            ('Con_No_NCC', 'Còn phải trả'),
          ],
        PosPrintDocumentTypes.purchaseReceipt => const [
            ..._supplier,
            ('So_HD_Dau_Vao', 'Số HĐ đầu vào'),
            ('Ma_Phieu_Goc', 'Theo đơn đặt'),
            ('Da_Tra_NCC', 'Đã trả NCC'),
            ('Con_No_NCC', 'Còn nợ NCC'),
          ],
        PosPrintDocumentTypes.purchaseReturn => const [
            ..._supplier,
            ('Ma_Phieu_Goc', 'Phiếu nhập gốc'),
            ('Ly_Do', 'Lý do'),
            ('NCC_Da_Hoan', 'NCC đã hoàn'),
          ],
        PosPrintDocumentTypes.stockTransfer => const [
            ('Kho_Di', 'Từ kho'),
            ('Kho_Den', 'Đến kho'),
            ('Trang_Thai', 'Trạng thái'),
            ('Ngay_Chuyen', 'Ngày chuyển'),
            ('Ngay_Nhan', 'Ngày nhận'),
            ('Nguoi_Lap', 'Người lập'),
            ('Nguoi_Nhan', 'Người nhận'),
            ('SL_Nhan', 'SL nhận (dòng)'),
            ('Tong_So_Luong', 'Tổng SL chuyển'),
            ('Tong_SL_Nhan', 'Tổng SL nhận'),
          ],
        PosPrintDocumentTypes.stockIssue => const [
            ('Nguoi_Nhan', 'Người nhận hàng'),
            ('Bo_Phan', 'Bộ phận'),
            ('Ly_Do', 'Lý do xuất'),
            ('Kho_Di', 'Xuất tại kho'),
            ('Chung_Tu_Kem_Theo', 'Chứng từ kèm theo'),
            ('Nguoi_Lap', 'Người lập phiếu'),
            ('Ngay_So', 'Ngày (số)'),
            ('Thang', 'Tháng'),
            ('Nam', 'Năm'),
          ],
        PosPrintDocumentTypes.cashReceipt || PosPrintDocumentTypes.cashPayment => const [
            ('Nguoi_Nop_Nhan', 'Người nộp / nhận tiền'),
            ('Dia_Chi_Nguoi_Nop_Nhan', 'Địa chỉ người nộp / nhận'),
            ('SDT_Nguoi_Nop_Nhan', 'SĐT người nộp / nhận'),
            ('Ly_Do', 'Lý do thu / chi'),
            ('Loai_Thu_Chi', 'Loại thu / chi'),
            ('Ma_Chung_Tu_Goc', 'Chứng từ gốc'),
            ('So_Tien', 'Số tiền'),
            ('So_Tien_Bang_Chu', 'Số tiền bằng chữ'),
            ('Chung_Tu_Kem_Theo', 'Số chứng từ kèm theo'),
            ('Quyen_So', 'Quyển số'),
            ('TK_No', 'TK Nợ'),
            ('TK_Co', 'TK Có'),
            ('Nguoi_Lap', 'Người lập phiếu'),
            ('Ngay_So', 'Ngày (số)'),
            ('Thang', 'Tháng'),
            ('Nam', 'Năm'),
          ],
        _ => const [],
      };

  static const blockHint =
      '<!--BEGIN_ITEMS--> ... <!--END_ITEMS--> — lặp cho từng dòng hàng';
}
