import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_sell_industry.dart';

const _prefKey = 'pos_product_editor_sections_v1';

/// Các khối tùy chọn trên form thêm/sửa hàng — tắt để form gọn.
enum PosProductEditorSection {
  codes('Mã hàng & barcode'),
  brand('Thương hiệu'),
  supplier('Nhà cung cấp'),
  vat('Thuế VAT'),
  warranty('Bảo hành, seri & lô/HSD'),
  stockLimits('Định mức tồn thấp/cao'),
  locationWeight('Vị trí & trọng lượng'),
  unitsVariants('Đơn vị / hàng cùng loại'),
  serviceBilling('Tính giờ / gói buổi (dịch vụ)'),
  staffCommission('Hoa hồng nhân viên'),
  description('Tab Mô tả & ghi chú bán');

  const PosProductEditorSection(this.label);
  final String label;
}

/// Mặc định form gọn: không bật mục nâng cao.
Set<PosProductEditorSection> defaultPosProductEditorSections() => {};

/// Bộ mục gợi ý theo ngành hàng — chỉ hiện những ô ngành đó thật sự dùng.
enum PosProductIndustryPreset {
  grocery('Tạp hóa / siêu thị', 'Mã vạch, ĐVT thùng/lốc, NCC, định mức tồn, VAT', {
    PosProductEditorSection.codes, PosProductEditorSection.supplier, PosProductEditorSection.vat, PosProductEditorSection.stockLimits, PosProductEditorSection.unitsVariants,
  }),
  pharmacy('Nhà thuốc / mỹ phẩm', 'Lô / hạn dùng, ĐVT hộp/vỉ/viên, NCC, định mức tồn', {
    PosProductEditorSection.codes, PosProductEditorSection.supplier, PosProductEditorSection.vat, PosProductEditorSection.warranty, PosProductEditorSection.stockLimits, PosProductEditorSection.unitsVariants,
  }),
  electronics('Điện thoại / điện máy', 'Thương hiệu, bảo hành, số seri / IMEI, NCC', {
    PosProductEditorSection.codes, PosProductEditorSection.brand, PosProductEditorSection.supplier, PosProductEditorSection.vat, PosProductEditorSection.warranty,
  }),
  fashion('Thời trang / giày dép', 'Thương hiệu, size / màu (hàng cùng loại), mã vạch', {
    PosProductEditorSection.codes, PosProductEditorSection.brand, PosProductEditorSection.unitsVariants, PosProductEditorSection.stockLimits,
  }),
  food('Quán ăn / cafe', 'Form gọn: giá, topping, ghi chú bán nhanh', {
    PosProductEditorSection.description,
  }),
  beauty('Spa / salon / gym', 'Gói buổi, thời lượng, hoa hồng nhân viên', {
    PosProductEditorSection.serviceBilling, PosProductEditorSection.staffCommission, PosProductEditorSection.description,
  }),
  hourly('Karaoke / bida / khách sạn', 'Tính giờ, block giờ, phí mở phòng', {
    PosProductEditorSection.serviceBilling,
  }),
  building('Vật liệu / nội thất', 'Mã hàng, NCC, ĐVT quy đổi, vị trí kho, trọng lượng', {
    PosProductEditorSection.codes, PosProductEditorSection.supplier, PosProductEditorSection.vat, PosProductEditorSection.stockLimits, PosProductEditorSection.locationWeight, PosProductEditorSection.unitsVariants,
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
}

Set<PosProductEditorSection> fullPosProductEditorSections() =>
    PosProductEditorSection.values.toSet();

/// Chưa từng lưu tùy chọn → trả `null` để form dùng bộ mục theo ngành của cửa hàng.
Future<Set<PosProductEditorSection>?> loadSavedPosProductEditorSections() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getStringList(_prefKey) == null) return null;
  } catch (_) {
    return null;
  }
  return loadPosProductEditorSections();
}

Future<Set<PosProductEditorSection>> loadPosProductEditorSections() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefKey);
    if (raw == null) return defaultPosProductEditorSections();
    final out = <PosProductEditorSection>{};
    for (final name in raw) {
      try {
        out.add(PosProductEditorSection.values.byName(name));
      } catch (_) {}
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
    final names = sections.map((s) => s.name).toList()..sort();
    await prefs.setStringList(_prefKey, names);
  } catch (_) {}
}
