/// Sổ tay bán hàng nhanh: một mục = tên chung + danh sách món kèm số lượng.
/// Bấm một mục trên màn bán là cả danh sách vào giỏ, mỗi món một dòng riêng.
/// Khác combo: combo là một món bán ra, sổ tay chỉ là lối tắt nhập giỏ.
library;

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
  return 0;
}

int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String _str(Map<String, dynamic> j, String camel, [String? pascal]) {
  final v = j[camel] ?? j[pascal ?? '${camel[0].toUpperCase()}${camel.substring(1)}'];
  return v?.toString() ?? '';
}

dynamic _raw(Map<String, dynamic> j, String camel) =>
    j[camel] ?? j['${camel[0].toUpperCase()}${camel.substring(1)}'];

class PosQuickSellNoteItem {
  const PosQuickSellNoteItem({
    this.id = '',
    required this.productId,
    required this.productName,
    this.qty = 1,
    this.price = 0,
    this.sortOrder = 0,
  });

  final String id;
  final String productId;
  final String productName;
  final double qty;
  final double price;
  final int sortOrder;

  factory PosQuickSellNoteItem.fromJson(Map<String, dynamic> json) =>
      PosQuickSellNoteItem(
        id: _str(json, 'id'),
        productId: _str(json, 'productId'),
        productName: _str(json, 'productName'),
        qty: _toDouble(_raw(json, 'qty')),
        price: _toDouble(_raw(json, 'price')),
        sortOrder: _toInt(_raw(json, 'sortOrder')),
      );

  /// Gửi lên API khi lưu sổ (không gửi tên / giá — máy chủ tự lấy theo món).
  Map<String, dynamic> toInputJson(int sortOrder) => {
        'productId': productId,
        'qty': qty <= 0 ? 1 : qty,
        'sortOrder': sortOrder,
      };

  PosQuickSellNoteItem copyWith({double? qty}) => PosQuickSellNoteItem(
        id: id,
        productId: productId,
        productName: productName,
        qty: qty ?? this.qty,
        price: price,
        sortOrder: sortOrder,
      );
}

class PosQuickSellNote {
  const PosQuickSellNote({
    this.id = '',
    required this.name,
    this.description,
    this.sortOrder = 0,
    this.items = const [],
  });

  final String id;
  final String name;
  final String? description;
  final int sortOrder;
  final List<PosQuickSellNoteItem> items;

  factory PosQuickSellNote.fromJson(Map<String, dynamic> json) {
    final rawItems = _raw(json, 'items');
    return PosQuickSellNote(
      id: _str(json, 'id'),
      name: _str(json, 'name'),
      description: () {
        final d = _raw(json, 'description')?.toString().trim() ?? '';
        return d.isEmpty ? null : d;
      }(),
      sortOrder: _toInt(_raw(json, 'sortOrder')),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => PosQuickSellNoteItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toUpsertJson() => {
        'name': name,
        'description': description,
        'sortOrder': sortOrder,
        'items': [
          for (var i = 0; i < items.length; i++) items[i].toInputJson(i),
        ],
      };

  /// Tổng số phần trong sổ — hiện trên thẻ cho thu ngân biết bấm vào sẽ thêm bao nhiêu.
  double get totalQty => items.fold(0.0, (s, i) => s + (i.qty <= 0 ? 1 : i.qty));

  /// Tạm tính theo giá niêm yết (chưa tính khuyến mãi / bảng giá) — chỉ để tham khảo.
  double get estimatedTotal =>
      items.fold(0.0, (s, i) => s + i.price * (i.qty <= 0 ? 1 : i.qty));

  PosQuickSellNote copyWith({
    String? name,
    String? description,
    bool clearDescription = false,
    int? sortOrder,
    List<PosQuickSellNoteItem>? items,
  }) =>
      PosQuickSellNote(
        id: id,
        name: name ?? this.name,
        description: clearDescription ? null : (description ?? this.description),
        sortOrder: sortOrder ?? this.sortOrder,
        items: items ?? this.items,
      );
}
