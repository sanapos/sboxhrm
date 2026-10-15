/// Một tệp đã tải/xuất trong app (bản sao quản lý nội bộ, riêng từng tài khoản + cửa hàng).
class DownloadedDocument {
  final String id;
  final String fileName;
  final String displayName;
  final String localPath;
  final String mimeType;
  final String category;
  final String? sourceModule;
  final int sizeBytes;
  final DateTime downloadedAt;

  /// Bản công khai ở thư mục Tải xuống (content:// của MediaStore hoặc đường dẫn tệp).
  final String? externalUri;

  /// Tên tệp lúc lưu (đổi tên trong app không đổi tên bản công khai) — dùng để nhận ra cùng một tệp.
  final String originalName;

  const DownloadedDocument({
    required this.id,
    required this.fileName,
    required this.displayName,
    required this.localPath,
    required this.mimeType,
    required this.category,
    this.sourceModule,
    required this.sizeBytes,
    required this.downloadedAt,
    this.externalUri,
    String? originalName,
  }) : originalName = originalName ?? fileName;

  String get extension {
    final i = fileName.lastIndexOf('.');
    if (i <= 0) return '';
    return fileName.substring(i).toLowerCase();
  }

  bool get isImage =>
      mimeType.startsWith('image/') ||
      const ['.png', '.jpg', '.jpeg', '.webp'].contains(extension);

  bool get isExcel =>
      extension == '.xlsx' ||
      extension == '.xls' ||
      mimeType.contains('spreadsheet');

  bool get isPdf => extension == '.pdf' || mimeType == 'application/pdf';

  bool get isCsv => extension == '.csv' || mimeType == 'text/csv';

  bool get isWord =>
      extension == '.docx' || extension == '.doc' || mimeType.contains('wordprocessingml') || mimeType == 'application/msword';

  /// excel | pdf | word | csv | image | other
  String get kind => isExcel
      ? DownloadFileKinds.excel
      : isPdf
          ? DownloadFileKinds.pdf
          : isWord
              ? DownloadFileKinds.word
              : isCsv
                  ? DownloadFileKinds.csv
                  : isImage
                      ? DownloadFileKinds.image
                      : DownloadFileKinds.other;

  DownloadedDocument copyWith({
    String? fileName,
    String? displayName,
    String? localPath,
    String? category,
  }) {
    return DownloadedDocument(
      id: id,
      fileName: fileName ?? this.fileName,
      displayName: displayName ?? this.displayName,
      localPath: localPath ?? this.localPath,
      mimeType: mimeType,
      category: category ?? this.category,
      sourceModule: sourceModule,
      sizeBytes: sizeBytes,
      downloadedAt: downloadedAt,
      externalUri: externalUri,
      originalName: originalName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'displayName': displayName,
        'localPath': localPath,
        'mimeType': mimeType,
        'category': category,
        'sourceModule': sourceModule,
        'sizeBytes': sizeBytes,
        'downloadedAt': downloadedAt.toIso8601String(),
        'externalUri': externalUri,
        'originalName': originalName,
      };

  factory DownloadedDocument.fromJson(Map<String, dynamic> json) {
    final fileName = json['fileName']?.toString() ?? '';
    return DownloadedDocument(
      id: json['id']?.toString() ?? '',
      fileName: fileName,
      displayName: json['displayName']?.toString() ?? '',
      localPath: json['localPath']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      category: json['category']?.toString() ?? 'Khác',
      sourceModule: json['sourceModule']?.toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      downloadedAt: DateTime.tryParse(json['downloadedAt']?.toString() ?? '') ??
          DateTime.now(),
      externalUri: json['externalUri']?.toString(),
      originalName: json['originalName']?.toString() ?? fileName,
    );
  }
}

/// Loại tệp dùng cho bộ lọc / thống kê.
class DownloadFileKinds {
  static const all = 'all';
  static const excel = 'excel';
  static const pdf = 'pdf';
  static const word = 'word';
  static const csv = 'csv';
  static const image = 'image';
  static const other = 'other';

  static const labels = <String, String>{
    all: 'Tất cả',
    excel: 'Excel (.xlsx)',
    pdf: 'PDF',
    word: 'Word (.docx)',
    csv: 'CSV',
    image: 'Ảnh PNG/JPG',
    other: 'Loại khác',
  };
}

/// Cách sắp xếp danh sách.
enum DownloadSort { newest, oldest, name, size }

/// Nhóm tài liệu hiển thị trong bộ lọc.
class DownloadDocCategories {
  static const all = 'Tất cả';
  static const other = 'Khác';

  static const List<String> presets = [
    all,
    'Báo cáo',
    'Báo cáo phạt',
    'Báo cáo thu chi',
    'Báo cáo ứng lương',
    'Báo cáo nghỉ phép',
    'Báo cáo tài sản',
    'Báo cáo suất ăn',
    'Chấm công',
    'Lương',
    'Nhân sự',
    'Hợp đồng',
    'KPI',
    'Lịch làm việc',
    'Nhật ký hệ thống',
    'Bán hàng',
    'Kho',
    'Thiết bị',
    other,
  ];

  /// Bỏ dấu tiếng Việt, về chữ thường, ký tự lạ (gạch ngang, khoảng trắng, dấu chấm…) thành «_».
  static String normalize(String s) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Đoán nhóm từ tên tệp: không phân biệt gạch ngang / gạch dưới / dấu, khớp theo TỪ (không khớp một phần
  /// của từ khác, vd «phat_trien» ≠ phạt, «lich_su» ≠ lịch làm việc).
  static String inferFromFileName(String name, {String? hint}) {
    if (hint != null && hint.isNotEmpty && hint != other && presets.contains(hint)) return hint;
    var base = name;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    final n = '_${normalize(base)}_';
    bool has(String phrase) => n.contains('_${phrase}_');
    bool any(List<String> phrases) => phrases.any(has);

    if (any(['lich_su', 'nhat_ky', 'audit', 'log', 'activity'])) return 'Nhật ký hệ thống';
    if (any(['ung_luong', 'advance'])) return 'Báo cáo ứng lương';
    if (any(['nghi_phep', 'leave'])) return 'Báo cáo nghỉ phép';
    if (any(['tai_san', 'asset'])) return 'Báo cáo tài sản';
    if (any(['suat_an', 'meal'])) return 'Báo cáo suất ăn';
    if (any(['thu_chi', 'cashbook', 'cash_transaction', 'cash_register', 'cashflow', 'so_quy'])) return 'Báo cáo thu chi';
    if (any(['penalty', 'ky_luat']) || (has('phat') && !has('trien'))) return 'Báo cáo phạt';
    if (any(['hop_dong', 'contract'])) return 'Hợp đồng';
    if (any(['bang_luong', 'luong', 'payroll', 'salary', 'san_luong'])) return 'Lương';
    if (any(['cham_cong', 'attendance', 'cong_thang', 'bang_cong'])) return 'Chấm công';
    if (any(['nhan_vien', 'employee', 'nhan_su'])) return 'Nhân sự';
    if (any(['kpi'])) return 'KPI';
    if (any(['lich_lam_viec', 'lich', 'schedule', 'shift', 'ca_lam'])) return 'Lịch làm việc';
    if (any(['hoa_don', 'invoice', 'ban_hang', 'sales', 'don_hang', 'order', 'bao_gia', 'quote'])) return 'Bán hàng';
    if (any(['ton_kho', 'kho', 'stock', 'inventory'])) return 'Kho';
    if (any(['thiet_bi', 'device'])) return 'Thiết bị';
    if (any(['bao_cao', 'report'])) return 'Báo cáo';
    return other;
  }
}
