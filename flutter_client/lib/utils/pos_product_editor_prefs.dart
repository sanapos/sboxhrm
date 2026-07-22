import 'package:shared_preferences/shared_preferences.dart';

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
  description('Tab Mô tả & ghi chú bán');

  const PosProductEditorSection(this.label);
  final String label;
}

/// Mặc định form gọn: không bật mục nâng cao.
Set<PosProductEditorSection> defaultPosProductEditorSections() => {};

Set<PosProductEditorSection> fullPosProductEditorSections() =>
    PosProductEditorSection.values.toSet();

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
