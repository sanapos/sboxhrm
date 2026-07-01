import 'package:flutter/material.dart';

import '../../models/pos_print_template.dart';
import '../../services/api_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../screens/settings_hub_screen.dart';
import '../../utils/pos_sell_print_settings.dart';
import 'pos_theme.dart';

const _blue = Color(0xFF2563EB);

Future<List<PosPrintTemplate>> _loadSaleInvoiceTemplates(ApiService api) async {
  List<PosPrintTemplate> parse(Map<String, dynamic> res) {
    if (res['isSuccess'] == true && res['data'] is List) {
      return (res['data'] as List)
          .map((e) => PosPrintTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // API tự tạo mẫu mặc định K58/K80/A5/A4 khi danh sách trống.
  var res = await api.getPosPrintTemplates(
    documentType: PosPrintDocumentTypes.saleInvoice,
  );
  var templates = parse(res);

  if (templates.isEmpty && res['isSuccess'] != true) {
    // Thử seed khi list lỗi hoặc rỗng (cần quyền View PosPrintTemplates).
    await api.seedPosPrintTemplates(documentType: PosPrintDocumentTypes.saleInvoice);
    res = await api.getPosPrintTemplates(
      documentType: PosPrintDocumentTypes.saleInvoice,
    );
    templates = parse(res);
  }

  return templates;
}

bool _templateIdMatches(PosPrintTemplate t, String? id) =>
    id != null && id.isNotEmpty && t.id.toLowerCase() == id.toLowerCase();

/// Chọn id hợp lệ trong [templates] — tránh Dropdown value lệch danh sách.
String? _resolveDropdownTemplateId(
  String? savedId,
  List<PosPrintTemplate> templates,
) {
  if (templates.isEmpty) return null;
  if (savedId != null) {
    final hit = templates.where((t) => _templateIdMatches(t, savedId)).firstOrNull;
    if (hit != null) return hit.id;
  }
  return templates.where((t) => t.isDefault).firstOrNull?.id ?? templates.first.id;
}

/// Popover thiết lập in kiểu KiotViet (tự động in, gộp hàng, số bản in, mẫu).
Future<PosSellPrintSettings?> showPosSellPrintPopover(
  BuildContext context, {
  required PosSellPrintSettings initial,
  required Offset anchor,
}) async {
  final api = ApiService();
  final templates = await _loadSaleInvoiceTemplates(api);

  if (!context.mounted) return null;

  return showDialog<PosSellPrintSettings>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      var settings = initial.copyWith(
        templateId: _resolveDropdownTemplateId(initial.templateId, templates),
      );

      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: anchor.dx.clamp(8, MediaQuery.sizeOf(ctx).width - 320),
            top: anchor.dy.clamp(8, MediaQuery.sizeOf(ctx).height - 400),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (ctx, setLocal) {
                    final dropdownId =
                        _resolveDropdownTemplateId(settings.templateId, templates);
                    final selected = templates
                        .where((t) => _templateIdMatches(t, dropdownId))
                        .firstOrNull;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _toggleRow(
                            'Tự động in hóa đơn',
                            settings.autoPrint,
                            (v) => setLocal(() => settings = settings.copyWith(autoPrint: v)),
                          ),
                          const SizedBox(height: 8),
                          _toggleRow(
                            'Gộp hàng cùng loại',
                            settings.mergeSameItems,
                            (v) =>
                                setLocal(() => settings = settings.copyWith(mergeSameItems: v)),
                          ),
                          const SizedBox(height: 12),
                          const Text('Số bản in (Liên)',
                              style: TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            value: settings.copies.clamp(1, 10),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            items: List.generate(
                              10,
                              (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                            ),
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(() => settings = settings.copyWith(copies: v));
                            },
                          ),
                          const SizedBox(height: 12),
                          const Text('Mẫu in hóa đơn',
                              style: TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: dropdownId,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            hint: templates.isEmpty
                                ? const Text('Chưa có mẫu in')
                                : const Text('Chọn mẫu in'),
                            items: templates
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(
                                      '${t.name} (${PosPrintPaperSizes.labels[t.paperSize] ?? t.paperSize})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: templates.isEmpty
                                ? null
                                : (v) => setLocal(
                                      () => settings = settings.copyWith(templateId: v),
                                    ),
                          ),
                          if (templates.isEmpty) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Chưa có mẫu in — hệ thống sẽ tạo sẵn K58, K80, A5, A4 khi bạn mở lại.',
                              style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                            ),
                          ],
                          if (selected != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Khổ: ${PosPrintPaperSizes.labels[selected.paperSize] ?? selected.paperSize}',
                              style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                            ),
                          ],
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              SettingsHubScreen.pendingSubIndex.value = 15;
                              NavigationNotifier.goToModule('SettingsHub');
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _blue,
                              side: const BorderSide(color: _blue),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: const Text('Thiết lập mẫu in…',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Bỏ qua'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: _blue),
                                  onPressed: () async {
                                    await settings.save();
                                    if (ctx.mounted) Navigator.pop(ctx, settings);
                                  },
                                  child: const Text('Xong'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
  return Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      Switch(
        value: value,
        activeThumbColor: _blue,
        onChanged: onChanged,
      ),
    ],
  );
}
