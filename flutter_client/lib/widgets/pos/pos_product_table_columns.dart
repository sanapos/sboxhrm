/// Cột bảng hàng hóa — có thể bật/tắt như KiotViet.
enum PosProductTableColumn {
  select,
  star,
  image,
  code,
  barcode,
  name,
  group,
  type,
  price,
  cost,
  brand,
  stock,
  location,
  reserved,
  createdAt,
  stockout,
  actions,
}

extension PosProductTableColumnX on PosProductTableColumn {
  String get label => switch (this) {
        PosProductTableColumn.select => 'Chọn',
        PosProductTableColumn.star => 'Yêu thích',
        PosProductTableColumn.image => 'Hình ảnh',
        PosProductTableColumn.code => 'Mã hàng',
        PosProductTableColumn.barcode => 'Mã vạch',
        PosProductTableColumn.name => 'Tên hàng',
        PosProductTableColumn.group => 'Nhóm hàng',
        PosProductTableColumn.type => 'Loại hàng',
        PosProductTableColumn.price => 'Giá bán',
        PosProductTableColumn.cost => 'Giá vốn',
        PosProductTableColumn.brand => 'Thương hiệu',
        PosProductTableColumn.stock => 'Tồn kho',
        PosProductTableColumn.location => 'Vị trí',
        PosProductTableColumn.reserved => 'Khách đặt',
        PosProductTableColumn.createdAt => 'Thời gian tạo',
        PosProductTableColumn.stockout => 'Dự kiến hết hàng',
        PosProductTableColumn.actions => '',
      };

  /// Nhãn cột trên header bảng (cột hẹp dùng tên ngắn).
  String get headerLabel => switch (this) {
        PosProductTableColumn.image => 'Hình ảnh',
        _ => label,
      };

  bool get canToggle => this != PosProductTableColumn.select && this != PosProductTableColumn.actions;
}

/// Cột mặc định hiển thị (giống KiotViet).
Set<PosProductTableColumn> defaultPosProductVisibleColumns() => {
      PosProductTableColumn.select,
      PosProductTableColumn.star,
      PosProductTableColumn.image,
      PosProductTableColumn.code,
      PosProductTableColumn.name,
      PosProductTableColumn.price,
      PosProductTableColumn.cost,
      PosProductTableColumn.stock,
      PosProductTableColumn.reserved,
      PosProductTableColumn.createdAt,
      PosProductTableColumn.stockout,
      PosProductTableColumn.actions,
    };
