import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_sale_order.dart';
import '../../services/api_service.dart';
import '../../utils/pos_print_template_loader.dart';
import '../notification_overlay.dart';

/// Kết quả chọn mẫu khi in lại một hóa đơn.
class PosSaleTemplateChoice {
  const PosSaleTemplateChoice(this.templateId, {this.remember = false});

  /// null = bỏ mẫu nhớ riêng (theo thiết lập máy in).
  final String? templateId;
  final bool remember;
}

/// Tùy chọn in riêng cho MỘT hóa đơn: in với mẫu khác (lần này / nhớ cho hóa đơn), ghi chú in riêng.
/// Không đổi số liệu bán, không đụng mẫu in chung.
///
/// [onPrint] nhận hóa đơn (đã gắn mẫu chọn cho lần in) để in.
Future<void> showPosSalePrintOptions(
  BuildContext context, {
  required PosSaleOrder order,
  required Future<void> Function(PosSaleOrder order) onPrint,
  VoidCallback? onChanged,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(tr('Tùy chọn in ${order.orderNo}'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('Chỉ áp dụng cho hóa đơn này — mẫu in chung giữ nguyên.')),
          ),
          ListTile(
            leading: const Icon(Icons.style_outlined),
            title: Text(tr('In với mẫu khác…')),
            subtitle: order.printTemplateId != null ? Text(tr('Hóa đơn đang nhớ mẫu riêng')) : null,
            onTap: () => Navigator.pop(ctx, 'template'),
          ),
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(tr('Ghi chú in riêng…')),
            subtitle: (order.printNote ?? '').trim().isEmpty
                ? null
                : Text(order.printNote!.trim(), maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(ctx, 'note'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'template') {
    final choice = await pickPosSalePrintTemplate(context, order: order);
    if (choice == null || !context.mounted) return;
    if (choice.remember) {
      final res = await ApiService().setPosSalePrintSettings(
        order.id,
        printTemplateId: choice.templateId,
        clearTemplate: choice.templateId == null,
      );
      if (res['isSuccess'] != true) {
        NotificationOverlayManager().showError(
          title: 'Chưa lưu được mẫu',
          message: res['message']?.toString() ?? tr('Vui lòng thử lại'),
        );
        return;
      }
      onChanged?.call();
    }
    if (!context.mounted) return;
    // '' = bỏ mẫu nhớ riêng → in theo thiết lập máy in.
    await onPrint(order.copyWithPrintContext(printTemplateIdOverride: choice.templateId ?? ''));
    return;
  }
  if (action == 'note') {
    final note = await editPosSalePrintNote(context, order: order);
    if (note != null) onChanged?.call();
  }
}

/// Danh sách mẫu hóa đơn bán (trừ mẫu Word) + «Nhớ cho hóa đơn này».
Future<PosSaleTemplateChoice?> pickPosSalePrintTemplate(
  BuildContext context, {
  required PosSaleOrder order,
}) async {
  List<PosPrintTemplate> list;
  try {
    list = (await loadPosPrintTemplates(ApiService(), PosPrintDocumentTypes.saleInvoice))
        .where((t) => !t.isDocx)
        .toList();
  } catch (_) {
    list = const [];
  }
  if (!context.mounted) return null;
  if (list.isEmpty) {
    NotificationOverlayManager().showWarning(
      title: 'Chưa có mẫu',
      message: tr('Cửa hàng chưa có mẫu hóa đơn nào khác'),
    );
    return null;
  }
  var remember = false;
  return showDialog<PosSaleTemplateChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(tr('Mẫu in cho ${order.orderNo}')),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (order.printTemplateId != null)
                      ListTile(
                        leading: const Icon(Icons.undo),
                        title: Text(tr('Theo thiết lập máy in (bỏ mẫu nhớ riêng)')),
                        onTap: () => Navigator.pop(ctx, const PosSaleTemplateChoice(null, remember: true)),
                      ),
                    for (final t in list)
                      ListTile(
                        leading: Icon(
                          t.id == order.printTemplateId ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 20,
                        ),
                        title: Text(t.name),
                        subtitle: Text(t.paperSize),
                        onTap: () => Navigator.pop(ctx, PosSaleTemplateChoice(t.id, remember: remember)),
                      ),
                  ],
                ),
              ),
              CheckboxListTile(
                value: remember,
                onChanged: (v) => setLocal(() => remember = v ?? false),
                title: Text(tr('Nhớ mẫu này cho hóa đơn này (in lại lần sau dùng luôn)')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy')))],
      ),
    ),
  );
}

/// Sửa ghi chú in riêng của hóa đơn. Trả ghi chú mới ('' = đã xóa) hoặc null nếu hủy / lỗi.
Future<String?> editPosSalePrintNote(BuildContext context, {required PosSaleOrder order}) async {
  final ctrl = TextEditingController(text: order.printNote ?? '');
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Ghi chú in riêng — ${order.orderNo}')),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: ctrl,
          maxLines: 4,
          maxLength: 1000,
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr('VD: Cảm ơn quý khách! Đổi trả trong 7 ngày kèm hóa đơn.'),
            helperText: tr('In kèm ghi chú trên hóa đơn này. Không đổi số liệu bán.'),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Lưu'))),
      ],
    ),
  );
  ctrl.dispose();
  if (text == null) return null;
  final res = await ApiService().setPosSalePrintSettings(order.id, printNote: text);
  if (res['isSuccess'] != true) {
    NotificationOverlayManager().showError(
      title: 'Chưa lưu được ghi chú',
      message: res['message']?.toString() ?? tr('Vui lòng thử lại'),
    );
    return null;
  }
  NotificationOverlayManager().showSuccess(
    title: text.isEmpty ? 'Đã xóa ghi chú in' : 'Đã lưu ghi chú in',
    message: order.orderNo,
  );
  return text;
}
