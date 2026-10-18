import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'pos_print_template_defaults.dart';
import 'pos_print_template_renderer.dart';
import 'pos_print_template_v2_codec.dart';

/// Tự nâng mẫu A4 chứng từ đang dùng (báo giá / hợp đồng / bàn giao / nghiệm thu /
/// đề nghị TT) của cửa hàng lên bố cục chuẩn mới nhất khi mở app — không cần thao tác.
/// Bản cũ (kể cả câu chữ đã tự sửa) được giữ thành mẫu «bản cũ» để quay lại.
/// Chạy ngầm, 1 lần/phiên, không chặn UI; lỗi / thiếu quyền thì bỏ qua.
class PosCommercialTemplateAutoUpgrade {
  PosCommercialTemplateAutoUpgrade._();

  /// Khoá cửa hàng đã chạy trong phiên app này (đổi tài khoản / cửa hàng → chạy lại).
  static String? _ranForStore;

  static const _docTypes = [
    PosPrintDocumentTypes.quote,
    PosPrintDocumentTypes.contract,
    PosPrintDocumentTypes.handover,
    PosPrintDocumentTypes.acceptance,
    PosPrintDocumentTypes.paymentRequest,
  ];

  /// Gọi sau khi quyền đã tải. [canEdit] = quyền sửa «PosPrintTemplates» của user;
  /// [storeKey] = cửa hàng hiện tại (chạy 1 lần cho mỗi cửa hàng trong phiên app).
  static Future<void> runOnce(
    ApiService api, {
    required bool canEdit,
    String? storeKey,
  }) async {
    final key = storeKey ?? '';
    if (!canEdit || _ranForStore == key) return;
    _ranForStore = key;
    try {
      final done = await _upgradeAll(api);
      if (done > 0) {
        NotificationOverlayManager().showSuccess(
          title: 'Đã cập nhật mẫu chứng từ',
          message:
              '$done mẫu dùng bố cục chuẩn mới (bảng tổng khớp số, bỏ dòng trống). Bản cũ vẫn giữ để quay lại.',
        );
      }
    } catch (_) {
      // Ngầm — không làm phiền người dùng nếu lỗi mạng / quyền.
    }
  }

  /// Mẫu A4 đang dùng lưu từ bản chuẩn cũ hơn bản hiện tại (cần nâng cấp).
  /// Mẫu Word, mẫu không đang dùng, mẫu V2, mẫu đã ở rev mới nhất → bỏ qua.
  static bool isOutdated(PosPrintTemplate t) {
    if (t.isDocx || !t.isDefault) return false;
    final raw = t.htmlContent.trim();
    if (!raw.startsWith('<') || PosPrintTemplateV2Codec.isV2Content(raw)) {
      return false;
    }
    return posCommercialBaseRev(raw) < kPosCommercialBaseRev;
  }

  /// Thay nội dung [t] bằng mẫu chuẩn mới nhất (giữ khổ giấy + lề); bản cũ lưu
  /// thành mẫu «bản cũ» để khôi phục. Trả về true nếu đã cập nhật.
  static Future<bool> upgradeOne(
    ApiService api,
    PosPrintTemplate t, {
    required int backupSortOrder,
    required String stamp,
  }) async {
    final backup = await api.createPosPrintTemplate({
      'name': '${t.name} (bản cũ $stamp)',
      'documentType': t.documentType,
      'paperSize': t.paperSize,
      'htmlContent': t.htmlContent,
      'isDefault': false,
      'isActive': true,
      'sortOrder': backupSortOrder,
    });
    if (backup['isSuccess'] != true) return false;
    final paper = PosPrintPaperSizes.normalizeCommercialPaper(t.paperSize);
    final setup = PosCommercialPageSetup.parse(t.htmlContent, fallbackPaper: paper)
        .copyWith(paperSize: paper, baseRev: kPosCommercialBaseRev);
    final html = ensurePosPrintItemLoop(
      setup.applyToHtml(
        posPrintDefaultHtml(documentType: t.documentType, paperSize: paper),
      ),
    );
    final res = await api.updatePosPrintTemplate(
      t.id,
      t.copyWith(htmlContent: html, paperSize: paper).toSaveJson(),
    );
    return res['isSuccess'] == true;
  }

  static Future<int> _upgradeAll(ApiService api) async {
    final stamp = DateFormat('dd/MM').format(DateTime.now());
    var done = 0;
    for (final docType in _docTypes) {
      final res = await api.getPosPrintTemplates(documentType: docType);
      if (res['isSuccess'] != true || res['data'] is! List) continue;
      final list = (res['data'] as List)
          .whereType<Map>()
          .map((e) => PosPrintTemplate.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final outdated = list.where(isOutdated).toList();
      for (final t in outdated) {
        final ok = await upgradeOne(api, t,
            backupSortOrder: list.length + done + 1, stamp: stamp);
        if (ok) done++;
      }
    }
    return done;
  }
}
