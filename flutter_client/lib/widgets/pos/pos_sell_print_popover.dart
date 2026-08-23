import 'package:flutter/material.dart';

import '../../utils/pos_print_template_loader.dart';
import '../../models/pos_print_template.dart';
import '../../services/api_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../screens/settings_hub_screen.dart';
import '../../utils/pos_sell_print_settings.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

Future<List<PosPrintTemplate>> _loadSaleInvoiceTemplates(ApiService api) =>
    loadPosPrintTemplates(api, PosPrintDocumentTypes.saleInvoice);

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
  final warehouseTemplates = await loadPosPrintTemplates(
    api,
    PosPrintDocumentTypes.stockIssue,
  );

  if (!context.mounted) return null;

  return showDialog<PosSellPrintSettings>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      var settings = initial.copyWith(
        templateId: _resolveDropdownTemplateId(initial.templateId, templates),
        warehouseTemplateId: _resolveDropdownTemplateId(
          initial.warehouseTemplateId,
          warehouseTemplates,
        ),
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
                    final warehouseDropdownId = _resolveDropdownTemplateId(
                      settings.warehouseTemplateId,
                      warehouseTemplates,
                    );
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
                            'In hóa đơn khi thanh toán',
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
                          const SizedBox(height: 8),
                          _toggleRow(
                            'In mã VietQR trên hóa đơn',
                            settings.printVietQrOnReceipt,
                            (v) => setLocal(
                              () => settings = settings.copyWith(printVietQrOnReceipt: v),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(tr('Số bản in (Liên)'),
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
                              (i) => DropdownMenuItem(value: i + 1, child: Text(tr('${i + 1}'))),
                            ),
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(() => settings = settings.copyWith(copies: v));
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(tr('Tem dán ly (trà sữa)'),
                              style: TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(
                            tr('Chọn một chế độ — không cần công tắc riêng.'),
                            style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<PosCupLabelPrintMode>(
                            value: settings.cupLabelPrintMode,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            items: PosCupLabelPrintMode.values
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(tr(m.label), overflow: TextOverflow.ellipsis),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(
                                () => settings = settings.copyWith(
                                  cupLabelPrintMode: v,
                                  printCupOnCheckout:
                                      v == PosCupLabelPrintMode.onCheckout,
                                ),
                              );
                            },
                          ),
                          if (settings.cupLabelPrintMode.enabled) ...[
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                tr('In tem khi Báo bếp'),
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                tr('Mặc định bật'),
                                style: const TextStyle(fontSize: 11),
                              ),
                              value: settings.printCupOnKitchenNotify,
                              dense: true,
                              onChanged: (v) => setLocal(
                                () => settings = settings.copyWith(
                                  printCupOnKitchenNotify: v,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(tr('Phiếu báo bếp'),
                              style: TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<PosKitchenSlipPrintMode>(
                            value: settings.kitchenSlipPrintMode,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            items: PosKitchenSlipPrintMode.values
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(tr(m.label), overflow: TextOverflow.ellipsis),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(
                                () => settings =
                                    settings.copyWith(kitchenSlipPrintMode: v),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(tr('Phiếu báo xuất kho'),
                              style: TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<PosWarehousePrintMode>(
                            value: settings.warehousePrintMode,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            items: PosWarehousePrintMode.values
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(tr(m.label), overflow: TextOverflow.ellipsis),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(
                                () => settings = settings.copyWith(warehousePrintMode: v),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(tr('Mẫu in phiếu xuất kho'),
                              style: TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: warehouseDropdownId,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            hint: warehouseTemplates.isEmpty
                                ? Text(tr('Chưa có mẫu'))
                                : Text(tr('Chọn mẫu in')),
                            items: warehouseTemplates
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(
                                      tr(t.shortLabel),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: warehouseTemplates.isEmpty
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    setLocal(() => settings =
                                        settings.copyWith(warehouseTemplateId: v));
                                  },
                          ),
                          const SizedBox(height: 12),
                          Text(tr('Mẫu in hóa đơn'),
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
                                ? Text(tr('Chưa có mẫu in'))
                                : Text(tr('Chọn mẫu in')),
                            items: templates
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(
                                      tr(t.shortLabel),
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
                            Text(tr('Chưa có mẫu in — hệ thống sẽ tạo sẵn K58, K80, A5, A4 khi bạn mở lại.'),
                              style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                            ),
                          ],
                          if (selected != null) ...[
                            const SizedBox(height: 4),
                            Text(tr('Khổ: ${PosPrintPaperSizes.displayLabel(selected.paperSize)}'),
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
                              foregroundColor: PosTheme.kiotBlue,
                              side: BorderSide(color: PosTheme.kiotBlue),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: Text(tr('Thiết lập mẫu in…'),
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text(tr('Bỏ qua')),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
                                  onPressed: () async {
                                    await settings.save();
                                    if (ctx.mounted) Navigator.pop(ctx, settings);
                                  },
                                  child: Text(tr('Xong')),
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
      Expanded(child: Text(tr(label), style: const TextStyle(fontSize: 13))),
      Switch(
        value: value,
        activeColor: PosTheme.kiotBlue,
        onChanged: onChanged,
      ),
    ],
  );
}
