import 'package:shared_preferences/shared_preferences.dart';

/// Thiết lập in hóa đơn trên màn bán hàng (lưu local).
class PosSellPrintSettings {
  const PosSellPrintSettings({
    this.autoPrint = false,
    this.mergeSameItems = true,
    this.copies = 1,
    this.templateId,
  });

  final bool autoPrint;
  final bool mergeSameItems;
  final int copies;

  /// Id mẫu in từ server (null = mẫu mặc định theo loại chứng từ).
  final String? templateId;

  static const _kAuto = 'pos_sell_print_auto';
  static const _kMerge = 'pos_sell_print_merge';
  static const _kCopies = 'pos_sell_print_copies';
  static const _kTemplate = 'pos_sell_print_template_id';

  PosSellPrintSettings copyWith({
    bool? autoPrint,
    bool? mergeSameItems,
    int? copies,
    String? templateId,
    bool clearTemplateId = false,
  }) =>
      PosSellPrintSettings(
        autoPrint: autoPrint ?? this.autoPrint,
        mergeSameItems: mergeSameItems ?? this.mergeSameItems,
        copies: copies ?? this.copies,
        templateId: clearTemplateId ? null : (templateId ?? this.templateId),
      );

  static Future<PosSellPrintSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = prefs.getString(_kTemplate);
    return PosSellPrintSettings(
      autoPrint: prefs.getBool(_kAuto) ?? false,
      mergeSameItems: prefs.getBool(_kMerge) ?? true,
      copies: (prefs.getInt(_kCopies) ?? 1).clamp(1, 10),
      templateId: tid != null && tid.isNotEmpty ? tid : null,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuto, autoPrint);
    await prefs.setBool(_kMerge, mergeSameItems);
    await prefs.setInt(_kCopies, copies.clamp(1, 10));
    if (templateId != null && templateId!.isNotEmpty) {
      await prefs.setString(_kTemplate, templateId!);
    } else {
      await prefs.remove(_kTemplate);
    }
  }
}
