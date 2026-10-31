import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_sell_industry.dart';

const _prefKey = 'pos_product_editor_sections_v1';

/// Ngành bán của cửa hàng đang mở form — tùy chọn mục lưu RIÊNG theo ngành. Trước lưu chung cả
/// máy: máy từng dùng cho cửa hàng vật liệu, sang cửa hàng gym form vẫn ẩn «Gói buổi / thẻ tập».
PosSellProfile? posProductEditorProfile;

String get _key {
  final p = posProductEditorProfile;
  return p == null ? _prefKey : '${_prefKey}_${p.name}';
}

/// Các khối tùy chọn trên form thêm/sửa hàng — tắt để form gọn.
/// Tên enum lưu trên server (ExtraJson.productForm) — KHÔNG đổi tên giá trị cũ.
enum PosProductEditorSection {
  codes('Mã hàng & barcode'),
  brand('Thương hiệu'),
  supplier('Nhà cung cấp'),
  vat('Thuế VAT'),
  warranty('Bảo hành'),
  serial('Số seri / IMEI khi bán'),
  expiry('Lô / hạn sử dụng'),
  stockLimits('Định mức tồn thấp/cao'),
  decimalQty('Bán số lẻ & tem cân (kg, mét, lít…)'),
  sizeMadeToOrder('Bán theo kích thước & hàng gia công'),
  locationWeight('Vị trí & trọng lượng'),
  packageSize('Kích thước đóng gói (vận chuyển)'),
  unitsVariants('Đơn vị / hàng cùng loại'),
  recipe('Định lượng nguyên vật liệu'),
  kitchenPrinter('Máy in bếp của món'),
  serviceBilling('Tính giờ / gói buổi (dịch vụ)'),
  staffCommission('Hoa hồng nhân viên'),
  loyalty('% tích điểm riêng của món'),
  description('Tab Mô tả & ghi chú bán');

  const PosProductEditorSection(this.label);
  final String label;

  static PosProductEditorSection? tryParse(String name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Mặc định form gọn: không bật mục nâng cao.
Set<PosProductEditorSection> defaultPosProductEditorSections() => {};

/// Bộ mục gợi ý theo ngành hàng — chỉ hiện những ô ngành đó thật sự dùng.
/// Bán lẻ có nhiều ngành con (thuốc, điện máy, thời trang, vật liệu…) — cửa hàng chọn ngành chi tiết
/// một lần trong ⚙ của form, lưu chung cho mọi máy.
enum PosProductIndustryPreset {
  // Siêu thị bán nhiều đồ ăn / uống có hạn dùng → mặc định hiện mục lô / HSD.
  grocery('Tạp hóa / siêu thị', 'Mã vạch, ĐVT thùng/lốc, lô / hạn dùng, NCC, định mức tồn, VAT, bán cân', {
    PosProductEditorSection.codes, PosProductEditorSection.supplier, PosProductEditorSection.vat, PosProductEditorSection.expiry, PosProductEditorSection.stockLimits, PosProductEditorSection.unitsVariants, PosProductEditorSection.decimalQty,
  }),
  pharmacy('Nhà thuốc / mỹ phẩm', 'Lô / hạn dùng, ĐVT hộp/vỉ/viên, NCC, định mức tồn', {
    PosProductEditorSection.codes, PosProductEditorSection.supplier, PosProductEditorSection.vat, PosProductEditorSection.expiry, PosProductEditorSection.stockLimits, PosProductEditorSection.unitsVariants,
  }),
  electronics('Điện thoại / điện máy', 'Thương hiệu, bảo hành, số seri / IMEI, NCC', {
    PosProductEditorSection.codes, PosProductEditorSection.brand, PosProductEditorSection.supplier, PosProductEditorSection.vat, PosProductEditorSection.warranty, PosProductEditorSection.serial,
  }),
  fashion('Thời trang / giày dép', 'Thương hiệu, size / màu (hàng cùng loại), mã vạch, đóng gói gửi hàng', {
    PosProductEditorSection.codes, PosProductEditorSection.brand, PosProductEditorSection.unitsVariants, PosProductEditorSection.stockLimits, PosProductEditorSection.packageSize,
  }),
  food('Quán ăn / cafe', 'Form gọn: giá, máy in bếp, định lượng NVL, ghi chú bán nhanh', {
    PosProductEditorSection.description, PosProductEditorSection.recipe, PosProductEditorSection.kitchenPrinter,
  }),
  beauty('Spa / salon / gym', 'Gói buổi, thời lượng, hoa hồng nhân viên, định lượng hóa chất', {
    PosProductEditorSection.serviceBilling, PosProductEditorSection.staffCommission, PosProductEditorSection.description, PosProductEditorSection.recipe,
  }),
  hourly('Karaoke / bida / khách sạn', 'Tính giờ, block giờ, phí mở phòng, máy in bếp/bar', {
    PosProductEditorSection.serviceBilling, PosProductEditorSection.kitchenPrinter,
  }),
  building('Vật liệu / nội thất', 'Mã hàng, NCC, ĐVT quy đổi, vị trí kho, trọng lượng, bán theo kích thước, hàng gia công', {
    PosProductEditorSection.codes, PosProductEditorSection.supplier, PosProductEditorSection.vat, PosProductEditorSection.stockLimits, PosProductEditorSection.locationWeight, PosProductEditorSection.unitsVariants, PosProductEditorSection.decimalQty, PosProductEditorSection.sizeMadeToOrder,
  });

  const PosProductIndustryPreset(this.label, this.hint, this.sections);
  final String label;
  final String hint;
  final Set<PosProductEditorSection> sections;

  static PosProductIndustryPreset forProfile(PosSellProfile p) => switch (p) {
        PosSellProfile.retail => grocery,
        PosSellProfile.restaurant => food,
        PosSellProfile.salon || PosSellProfile.gym => beauty,
        PosSellProfile.roomHourly || PosSellProfile.hotel => hourly,
      };

  static PosProductIndustryPreset? tryParse(String? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// Form hàng hóa của cả cửa hàng (sell-settings ExtraJson.productForm).
class PosProductFormLayout {
  const PosProductFormLayout(this.preset, this.sections);

  final PosProductIndustryPreset? preset;
  final Set<PosProductEditorSection> sections;

  /// `null` = cửa hàng chưa chỉnh form (dùng tùy chọn cũ trên máy / bộ mục theo ngành).
  static PosProductFormLayout? fromExtraJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final root = jsonDecode(raw);
      if (root is! Map) return null;
      final node = root['productForm'] ?? root['ProductForm'];
      if (node is! Map || node['sections'] is! List) return null;
      return PosProductFormLayout(
        PosProductIndustryPreset.tryParse(node['preset']?.toString()),
        {
          for (final e in node['sections'] as List)
            if (PosProductEditorSection.tryParse(e.toString()) case final s?) s,
        },
      );
    } catch (_) {
      return null;
    }
  }
}

Set<PosProductEditorSection> fullPosProductEditorSections() =>
    PosProductEditorSection.values.toSet();

/// Mục mới tách ra (trước luôn hiện / gộp chung) — tùy chọn cũ trên máy chưa có, lấy theo ngành.
const _sectionsAddedV2 = {
  PosProductEditorSection.serial,
  PosProductEditorSection.expiry,
  PosProductEditorSection.decimalQty,
  PosProductEditorSection.sizeMadeToOrder,
  PosProductEditorSection.packageSize,
  PosProductEditorSection.recipe,
  PosProductEditorSection.kitchenPrinter,
  PosProductEditorSection.loyalty,
};

/// Danh sách lưu từ bản có mục tách — không chuyển đổi lại (người dùng có thể đã tắt hết mục mới).
const _v2Marker = '_v2';

/// Chưa từng lưu tùy chọn → trả `null` để form dùng bộ mục theo ngành của cửa hàng.
Future<Set<PosProductEditorSection>?> loadSavedPosProductEditorSections() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getStringList(_key) == null) return null;
  } catch (_) {
    return null;
  }
  return loadPosProductEditorSections();
}

Future<Set<PosProductEditorSection>> loadPosProductEditorSections() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null) return defaultPosProductEditorSections();
    final out = <PosProductEditorSection>{
      for (final name in raw)
        if (PosProductEditorSection.tryParse(name) case final s?) s,
    };
    // Lưu từ bản cũ (chưa có mục tách): «Bảo hành, seri & lô/HSD» = cả 3; mục mới theo ngành.
    if (!raw.contains(_v2Marker)) {
      if (out.contains(PosProductEditorSection.warranty)) {
        out.addAll({PosProductEditorSection.serial, PosProductEditorSection.expiry});
      }
      if (out.contains(PosProductEditorSection.locationWeight)) {
        out.add(PosProductEditorSection.packageSize);
      }
      final p = posProductEditorProfile;
      if (p != null) {
        out.addAll(PosProductIndustryPreset.forProfile(p).sections.intersection(_sectionsAddedV2));
      }
    }
    return out;
  } catch (_) {
    return defaultPosProductEditorSections();
  }
}

Future<void> savePosProductEditorSections(
    Set<PosProductEditorSection> sections) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final names = [...sections.map((s) => s.name), _v2Marker]..sort();
    await prefs.setStringList(_key, names);
  } catch (_) {}
}
