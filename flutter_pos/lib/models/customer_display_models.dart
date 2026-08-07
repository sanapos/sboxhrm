import 'dart:convert';

/// Trạng thái đẩy sang màn hình phụ (khách).
enum CustomerDisplayMode {
  idle,
  active,
}

class CustomerDisplayLine {
  const CustomerDisplayLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
    this.unitLabel,
    this.imageUrl,
    this.note,
  });

  final String name;
  final double qty;
  final double unitPrice;
  final double lineTotal;
  final String? unitLabel;
  final String? imageUrl;
  final String? note;

  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': qty,
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
        if (unitLabel != null) 'unitLabel': unitLabel,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (note != null) 'note': note,
      };

  factory CustomerDisplayLine.fromJson(Map<String, dynamic> j) =>
      CustomerDisplayLine(
        name: (j['name'] ?? '').toString(),
        qty: (j['qty'] as num?)?.toDouble() ?? 0,
        unitPrice: (j['unitPrice'] as num?)?.toDouble() ?? 0,
        lineTotal: (j['lineTotal'] as num?)?.toDouble() ?? 0,
        unitLabel: j['unitLabel']?.toString(),
        imageUrl: j['imageUrl']?.toString(),
        note: j['note']?.toString(),
      );
}

class CustomerDisplayPromoItem {
  const CustomerDisplayPromoItem({
    required this.title,
    this.imageUrl,
    this.videoUrl,
    this.subtitle,
    this.price,
  });

  final String title;
  final String? imageUrl;
  final String? videoUrl;
  final String? subtitle;
  final double? price;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (videoUrl != null) 'videoUrl': videoUrl,
        if (subtitle != null) 'subtitle': subtitle,
        if (price != null) 'price': price,
      };

  factory CustomerDisplayPromoItem.fromJson(Map<String, dynamic> j) =>
      CustomerDisplayPromoItem(
        title: (j['title'] ?? '').toString(),
        imageUrl: j['imageUrl']?.toString(),
        videoUrl: j['videoUrl']?.toString(),
        subtitle: j['subtitle']?.toString(),
        price: (j['price'] as num?)?.toDouble(),
      );
}

class CustomerDisplayState {
  const CustomerDisplayState({
    this.mode = CustomerDisplayMode.idle,
    this.tableLabel,
    this.areaName,
    this.orderNo,
    this.guestCount = 0,
    this.lines = const [],
    this.subtotal = 0,
    this.discount = 0,
    this.total = 0,
    this.promoItems = const [],
    this.storeName,
    this.idleSeconds = 8,
    this.updatedAtMs = 0,
  });

  final CustomerDisplayMode mode;
  final String? tableLabel;
  final String? areaName;
  final String? orderNo;
  final int guestCount;
  final List<CustomerDisplayLine> lines;
  final double subtotal;
  final double discount;
  final double total;
  final List<CustomerDisplayPromoItem> promoItems;
  final String? storeName;
  /// Đồng bộ từ POS — engine phụ không có sell-settings.
  final int idleSeconds;
  final int updatedAtMs;

  bool get isActive =>
      mode == CustomerDisplayMode.active &&
      ((tableLabel ?? '').isNotEmpty || lines.isNotEmpty);

  CustomerDisplayState copyWith({
    CustomerDisplayMode? mode,
    String? tableLabel,
    String? areaName,
    String? orderNo,
    int? guestCount,
    List<CustomerDisplayLine>? lines,
    double? subtotal,
    double? discount,
    double? total,
    List<CustomerDisplayPromoItem>? promoItems,
    String? storeName,
    int? idleSeconds,
    int? updatedAtMs,
    bool clearTable = false,
  }) {
    return CustomerDisplayState(
      mode: mode ?? this.mode,
      tableLabel: clearTable ? null : (tableLabel ?? this.tableLabel),
      areaName: clearTable ? null : (areaName ?? this.areaName),
      orderNo: clearTable ? null : (orderNo ?? this.orderNo),
      guestCount: guestCount ?? this.guestCount,
      lines: lines ?? this.lines,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      promoItems: promoItems ?? this.promoItems,
      storeName: storeName ?? this.storeName,
      idleSeconds: idleSeconds ?? this.idleSeconds,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'tableLabel': tableLabel,
        'areaName': areaName,
        'orderNo': orderNo,
        'guestCount': guestCount,
        'lines': lines.map((e) => e.toJson()).toList(),
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'promoItems': promoItems.map((e) => e.toJson()).toList(),
        'storeName': storeName,
        'idleSeconds': idleSeconds,
        'updatedAtMs': updatedAtMs,
      };

  factory CustomerDisplayState.fromJson(Map<String, dynamic> j) {
    final modeRaw = (j['mode'] ?? 'idle').toString();
    final mode = modeRaw == 'active'
        ? CustomerDisplayMode.active
        : CustomerDisplayMode.idle;
    return CustomerDisplayState(
      mode: mode,
      tableLabel: j['tableLabel']?.toString(),
      areaName: j['areaName']?.toString(),
      orderNo: j['orderNo']?.toString(),
      guestCount: (j['guestCount'] as num?)?.toInt() ?? 0,
      lines: ((j['lines'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => CustomerDisplayLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (j['discount'] as num?)?.toDouble() ?? 0,
      total: (j['total'] as num?)?.toDouble() ?? 0,
      promoItems: ((j['promoItems'] as List?) ?? [])
          .whereType<Map>()
          .map((e) =>
              CustomerDisplayPromoItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      storeName: j['storeName']?.toString(),
      idleSeconds: (j['idleSeconds'] as num?)?.toInt().clamp(3, 60) ?? 8,
      updatedAtMs: (j['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  String encode() => jsonEncode(toJson());

  static CustomerDisplayState? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        return CustomerDisplayState.fromJson(Map<String, dynamic>.from(j));
      }
    } catch (_) {}
    return null;
  }

  static const idle = CustomerDisplayState();
}

/// Cấu hình trong sell-settings.extraJson → customerDisplay.
class CustomerDisplayConfig {
  const CustomerDisplayConfig({
    this.enabled = false,
    this.idleSeconds = 8,
    this.useProductImages = true,
    this.promoVideoUrls = const [],
    this.promoImageUrls = const [],
    this.autoOpenOnPos = false,
    this.viewerCode = '',
  });

  final bool enabled;
  final int idleSeconds;
  final bool useProductImages;
  final List<String> promoVideoUrls;
  /// Ảnh trình chiếu riêng (path stores/... hoặc URL http).
  final List<String> promoImageUrls;
  final bool autoOpenOnPos;
  /// Mã mở link màn phụ trên máy khác: /#/customer-display?v=CODE
  final String viewerCode;

  static String newViewerCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer();
    var x = r;
    for (var i = 0; i < 8; i++) {
      buf.write(chars[x % chars.length]);
      x = (x ~/ chars.length) ^ (r >> (i * 3));
    }
    return buf.toString();
  }

  factory CustomerDisplayConfig.fromExtraJson(String? extraJson) {
    if (extraJson == null || extraJson.trim().isEmpty) {
      return CustomerDisplayConfig(viewerCode: newViewerCode());
    }
    try {
      final root = jsonDecode(extraJson);
      if (root is! Map) {
        return CustomerDisplayConfig(viewerCode: newViewerCode());
      }
      final cd = root['customerDisplay'] ?? root['CustomerDisplay'];
      if (cd is! Map) {
        return CustomerDisplayConfig(viewerCode: newViewerCode());
      }
      final m = Map<String, dynamic>.from(cd);
      final videos = (m['promoVideoUrls'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      final images = (m['promoImageUrls'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      var code = (m['viewerCode'] ?? m['ViewerCode'] ?? '').toString().trim();
      if (code.length < 4) code = newViewerCode();
      return CustomerDisplayConfig(
        enabled: m['enabled'] == true,
        idleSeconds: (m['idleSeconds'] as num?)?.toInt().clamp(3, 60) ?? 8,
        useProductImages: m['useProductImages'] != false,
        promoVideoUrls: videos,
        promoImageUrls: images,
        autoOpenOnPos: m['autoOpenOnPos'] == true,
        viewerCode: code,
      );
    } catch (_) {
      return CustomerDisplayConfig(viewerCode: newViewerCode());
    }
  }

  String mergeIntoExtraJson(String? existing) {
    Map<String, dynamic> root = {};
    if (existing != null && existing.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(existing);
        if (decoded is Map) root = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    final code = viewerCode.trim().length >= 4 ? viewerCode.trim() : newViewerCode();
    root['customerDisplay'] = {
      'enabled': enabled,
      'idleSeconds': idleSeconds,
      'useProductImages': useProductImages,
      'promoVideoUrls': promoVideoUrls,
      'promoImageUrls': promoImageUrls,
      'autoOpenOnPos': autoOpenOnPos,
      'viewerCode': code,
    };
    return jsonEncode(root);
  }

  CustomerDisplayConfig copyWith({
    bool? enabled,
    int? idleSeconds,
    bool? useProductImages,
    List<String>? promoVideoUrls,
    List<String>? promoImageUrls,
    bool? autoOpenOnPos,
    String? viewerCode,
  }) {
    return CustomerDisplayConfig(
      enabled: enabled ?? this.enabled,
      idleSeconds: idleSeconds ?? this.idleSeconds,
      useProductImages: useProductImages ?? this.useProductImages,
      promoVideoUrls: promoVideoUrls ?? this.promoVideoUrls,
      promoImageUrls: promoImageUrls ?? this.promoImageUrls,
      autoOpenOnPos: autoOpenOnPos ?? this.autoOpenOnPos,
      viewerCode: viewerCode ?? this.viewerCode,
    );
  }

  /// Chuẩn hoá link Drive/Dropbox → URL file trực tiếp (không YouTube).
  static String normalizeExternalMediaUrl(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return u;
    // Google Drive: /file/d/FILE_ID/...
    final driveFile = RegExp(r'drive\.google\.com/file/d/([a-zA-Z0-9_-]+)')
        .firstMatch(u);
    if (driveFile != null) {
      final id = driveFile.group(1)!;
      return 'https://drive.google.com/uc?export=download&confirm=t&id=$id';
    }
    // Google Drive: open?id= / uc?id=
    if (u.contains('drive.google.com')) {
      final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(u);
      if (idMatch != null) {
        final id = idMatch.group(1)!;
        return 'https://drive.google.com/uc?export=download&confirm=t&id=$id';
      }
    }
    // Dropbox share → direct
    if (u.contains('dropbox.com')) {
      return u
          .replaceAll('?dl=0', '?dl=1')
          .replaceAll('&dl=0', '&dl=1')
          .replaceFirst('www.dropbox.com', 'dl.dropboxusercontent.com');
    }
    return u;
  }
}
