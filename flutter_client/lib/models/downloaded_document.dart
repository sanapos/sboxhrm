/// Một tệp đã tải/xuất trong app (bản sao quản lý nội bộ).
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
  final String? externalUri;

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
  });

  String get extension {
    final i = fileName.lastIndexOf('.');
    if (i <= 0) return '';
    return fileName.substring(i).toLowerCase();
  }

  bool get isImage =>
      mimeType.startsWith('image/') ||
      extension == '.png' ||
      extension == '.jpg' ||
      extension == '.jpeg';

  bool get isExcel =>
      extension == '.xlsx' ||
      extension == '.xls' ||
      mimeType.contains('spreadsheet');

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
      };

  factory DownloadedDocument.fromJson(Map<String, dynamic> json) {
    return DownloadedDocument(
      id: json['id']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      localPath: json['localPath']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      category: json['category']?.toString() ?? 'Khác',
      sourceModule: json['sourceModule']?.toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      downloadedAt: DateTime.tryParse(json['downloadedAt']?.toString() ?? '') ??
          DateTime.now(),
      externalUri: json['externalUri']?.toString(),
    );
  }
}

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
    'Chấm công',
    'Nhân sự',
    'KPI',
    'Lịch làm việc',
    'Thiết bị',
    other,
  ];

  static String inferFromFileName(String name, {String? hint}) {
    if (hint != null && hint.isNotEmpty && hint != other) return hint;
    final n = name.toLowerCase();
    if (n.contains('phat') || n.contains('penalty')) return 'Báo cáo phạt';
    if (n.contains('thu_chi') || n.contains('cash')) return 'Báo cáo thu chi';
    if (n.contains('ung_luong') || n.contains('advance')) {
      return 'Báo cáo ứng lương';
    }
    if (n.contains('nghi_phep') || n.contains('leave')) return 'Báo cáo nghỉ phép';
    if (n.contains('tai_san') || n.contains('asset')) return 'Báo cáo tài sản';
    if (n.contains('cham_cong') ||
        n.contains('attendance') ||
        n.contains('cong_')) {
      return 'Chấm công';
    }
    if (n.contains('nhan_vien') || n.contains('employee')) return 'Nhân sự';
    if (n.contains('kpi')) return 'KPI';
    if (n.contains('lich') || n.contains('schedule')) return 'Lịch làm việc';
    if (n.contains('thiet_bi') || n.contains('device')) return 'Thiết bị';
    if (n.contains('bao_cao') || n.contains('report')) return 'Báo cáo';
    return other;
  }
}
