import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../utils/pos_print_template_defaults.dart';
import '../../utils/pos_print_template_renderer.dart';
import '../../utils/pos_print_template_v2_codec.dart';
import 'pos_html_preview_stub.dart';
import 'pos_print_template_preview.dart';

const _blue = Color(0xFF2563EB);
const _green = Color(0xFF16A34A);

/// Nhóm loại phiếu cho thanh chọn bên trái (thay dải 21 nút ngang khó tìm).
class PosPrintDocGroup {
  const PosPrintDocGroup(this.title, this.icon, this.types);
  final String title;
  final IconData icon;
  final List<String> types;
}

const posPrintDocGroups = <PosPrintDocGroup>[
  PosPrintDocGroup('Bán hàng', Icons.point_of_sale_outlined, [
    PosPrintDocumentTypes.saleInvoice,
    PosPrintDocumentTypes.saleOrder,
    PosPrintDocumentTypes.delivery,
    PosPrintDocumentTypes.saleReturn,
    PosPrintDocumentTypes.saleExchange,
  ]),
  PosPrintDocGroup('Bếp & tem', Icons.restaurant_outlined, [
    PosPrintDocumentTypes.kitchenSlip,
    PosPrintDocumentTypes.kitchenVoid,
    PosPrintDocumentTypes.kitchenLabel,
    PosPrintDocumentTypes.barcodeLabel,
  ]),
  PosPrintDocGroup('Kho hàng', Icons.warehouse_outlined, [
    PosPrintDocumentTypes.purchaseOrder,
    PosPrintDocumentTypes.purchaseReceipt,
    PosPrintDocumentTypes.purchaseReturn,
    PosPrintDocumentTypes.stockTransfer,
    PosPrintDocumentTypes.stockIssue,
  ]),
  PosPrintDocGroup('Thu chi', Icons.account_balance_wallet_outlined, [
    PosPrintDocumentTypes.cashReceipt,
    PosPrintDocumentTypes.cashPayment,
  ]),
  PosPrintDocGroup('Báo giá & hợp đồng (A4)', Icons.description_outlined, [
    PosPrintDocumentTypes.quote,
    PosPrintDocumentTypes.contract,
    PosPrintDocumentTypes.handover,
    PosPrintDocumentTypes.acceptance,
    PosPrintDocumentTypes.paymentRequest,
  ]),
];

/// Loại phiếu chưa thuộc nhóm nào (thêm loại mới về sau) → nhóm «Khác».
List<PosPrintDocGroup> posPrintDocGroupsWithOthers() {
  final known = posPrintDocGroups.expand((g) => g.types).toSet();
  final others = PosPrintDocumentTypes.all.keys.where((k) => !known.contains(k)).toList();
  return [
    ...posPrintDocGroups,
    if (others.isNotEmpty) PosPrintDocGroup('Khác', Icons.more_horiz, others),
  ];
}

String posPrintDocLabel(String type) => PosPrintDocumentTypes.all[type] ?? type;

/// Danh sách loại phiếu theo nhóm (máy tính: cột trái).
class PosPrintDocTypeNav extends StatelessWidget {
  const PosPrintDocTypeNav({super.key, required this.current, required this.onSelect});

  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final g in posPrintDocGroupsWithOthers()) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
            child: Row(children: [
              Icon(g.icon, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr(g.title).toUpperCase(),
                    maxLines: 2,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: .3)),
              ),
            ]),
          ),
          for (final t in g.types)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: Material(
                color: t == current ? const Color(0xFFE8F0FE) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelect(t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Text(
                      tr(posPrintDocLabel(t)),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: t == current ? FontWeight.w700 : FontWeight.w500,
                        color: t == current ? _blue : const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Chọn loại phiếu trên điện thoại: một nút mở danh sách theo nhóm.
Future<String?> showPosPrintDocTypePicker(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * .8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(tr('Chọn loại phiếu'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Expanded(child: PosPrintDocTypeNav(current: current, onSelect: (t) => Navigator.pop(ctx, t))),
        ],
      ),
    ),
  );
}

/// Ảnh thu nhỏ của mẫu (dựng từ nội dung mẫu với dữ liệu mẫu).
class PosPrintTemplateThumb extends StatelessWidget {
  const PosPrintTemplateThumb({super.key, required this.htmlContent, required this.documentType,
      required this.paperSize, this.isDocx = false});

  final String htmlContent;
  final String documentType;
  final String paperSize;
  final bool isDocx;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (isDocx) {
      child = const _IconThumb(icon: Icons.description, color: Color(0xFF2B579A), label: 'Mẫu Word');
    } else if (PosPrintTemplateV2Codec.tryParse(htmlContent) case final v2?) {
      child = IgnorePointer(
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          child: SizedBox(width: 320, height: 480, child: buildPosPrintTemplatePreview(v2)),
        ),
      );
    } else if (htmlContent.trim().startsWith('<') || PosPrintDocumentTypes.isCommercial(documentType)) {
      final raw = htmlContent.trim().isEmpty
          ? posPrintDefaultHtml(documentType: documentType, paperSize: paperSize)
          : htmlContent;
      final html = renderPosPrintTemplateHtml(
        raw,
        data: posPrintSampleData(documentType: documentType),
        lineItems: posPrintSampleLines(count: 3),
        wrapDocument: false,
        paperSize: paperSize,
      );
      // Trang A4 tĩnh thu nhỏ (không dùng khung xem trước có thanh cuộn).
      child = IgnorePointer(
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: Container(
            width: 794,
            height: 1123,
            color: Colors.white,
            padding: const EdgeInsets.all(40),
            child: buildPosRenderedHtml(stripPosHtmlDocumentShell(html),
                a4Width: true, shrinkWrap: true, pageWidth: 714),
          ),
        ),
      );
    } else {
      child = const _IconThumb(icon: Icons.receipt_long, color: _blue, label: 'Mẫu in');
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRect(child: child),
    );
  }
}

class _IconThumb extends StatelessWidget {
  const _IconThumb({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 6),
          Text(tr(label), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Thẻ một mẫu in của cửa hàng.
class PosPrintTemplateCard extends StatelessWidget {
  const PosPrintTemplateCard({
    super.key,
    required this.template,
    required this.onEdit,
    required this.onUse,
    required this.onTestPrint,
    this.onDuplicate,
    this.onDelete,
    this.canEdit = true,
  });

  final PosPrintTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onUse;
  final VoidCallback onTestPrint;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final t = template;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.isDefault ? _green : const Color(0xFFE5E7EB), width: t.isDefault ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canEdit ? onEdit : onTestPrint,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(children: [
                  Positioned.fill(
                    child: PosPrintTemplateThumb(
                      htmlContent: t.htmlContent,
                      documentType: t.documentType,
                      paperSize: t.paperSize,
                      isDocx: t.isDocx,
                    ),
                  ),
                  if (t.isDefault)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _Badge(text: tr('Đang dùng'), color: _green, icon: Icons.check_circle),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Text(t.name.trim().isEmpty ? tr('Mẫu in') : t.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _Badge(text: PosPrintPaperSizes.shortLabel(t.paperSize), color: const Color(0xFF475569)),
                if (t.isDocx) _Badge(text: 'Word', color: const Color(0xFF2B579A)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canEdit ? onEdit : onTestPrint,
                    icon: Icon(canEdit ? Icons.edit_outlined : Icons.print_outlined, size: 16),
                    label: Text(canEdit ? tr('Sửa') : tr('In thử')),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('Thao tác khác'),
                  onSelected: (v) => switch (v) {
                    'test' => onTestPrint(),
                    'dup' => onDuplicate?.call(),
                    'del' => onDelete?.call(),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'test', child: ListTile(dense: true, leading: const Icon(Icons.print_outlined), title: Text(tr('In thử')))),
                    if (onDuplicate != null)
                      PopupMenuItem(value: 'dup', child: ListTile(dense: true, leading: const Icon(Icons.copy_all_outlined), title: Text(tr('Nhân bản')))),
                    if (onDelete != null)
                      PopupMenuItem(value: 'del', child: ListTile(dense: true, leading: const Icon(Icons.delete_outline, color: Colors.red), title: Text(tr('Xóa'), style: const TextStyle(color: Colors.red)))),
                  ],
                ),
              ]),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: t.isDefault
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check, size: 16, color: _green),
                        label: Text(tr('Đang dùng'), style: const TextStyle(color: _green)),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      )
                    : FilledButton(
                        onPressed: canEdit ? onUse : null,
                        style: FilledButton.styleFrom(backgroundColor: _green, visualDensity: VisualDensity.compact),
                        child: Text(tr('Dùng mẫu này'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 3)],
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

/// Thẻ «Thêm mẫu» cuối lưới.
class PosPrintAddTemplateCard extends StatelessWidget {
  const PosPrintAddTemplateCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF93C5FD), width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_circle_outline, size: 40, color: _blue),
              const SizedBox(height: 8),
              Text(tr('Thêm mẫu'), style: const TextStyle(fontWeight: FontWeight.w700, color: _blue, fontSize: 15)),
              const SizedBox(height: 4),
              Text(tr('Mẫu có sẵn · File Word · Mẫu trống'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
          ),
        ),
      );
}

/// Lựa chọn khi bấm «Thêm mẫu». Trả: 'catalog:<id>' / 'word' / 'blank'.
Future<String?> showPosPrintAddTemplateSheet(
  BuildContext context, {
  required String documentType,
  required List<PosPrintTemplateCatalog> catalog,
  required bool allowWord,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * .85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Thêm mẫu · ${posPrintDocLabel(documentType)}'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              if (allowWord)
                Expanded(
                  child: _AddOption(
                    icon: Icons.upload_file,
                    color: const Color(0xFF2B579A),
                    title: tr('Tải file Word của bạn'),
                    subtitle: tr('Giữ nguyên bố cục, AI gắn dữ liệu, soạn trên trang in'),
                    onTap: () => Navigator.pop(ctx, 'word'),
                  ),
                ),
              if (allowWord) const SizedBox(width: 10),
              Expanded(
                child: _AddOption(
                  icon: Icons.note_add_outlined,
                  color: _blue,
                  title: tr('Mẫu trống'),
                  subtitle: tr('Chọn khổ giấy rồi tự sắp xếp nội dung'),
                  onTap: () => Navigator.pop(ctx, 'blank'),
                ),
              ),
            ]),
            if (catalog.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(tr('Mẫu có sẵn — chọn là dùng ngay, sửa được'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.extent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: .72,
                  children: [
                    for (final c in catalog)
                      Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: c.isRecommended ? _green : const Color(0xFFE5E7EB)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.pop(ctx, 'catalog:${c.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(
                                child: PosPrintTemplateThumb(
                                  htmlContent: c.htmlContent,
                                  documentType: c.documentType,
                                  paperSize: c.paperSize,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                '${PosPrintPaperSizes.shortLabel(c.paperSize)}${c.isRecommended ? ' · ${tr('Khuyên dùng')}' : ''}',
                                style: TextStyle(fontSize: 12, color: c.isRecommended ? _green : Colors.grey.shade600),
                              ),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ] else
              const Spacer(),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
          ],
        ),
      ),
    ),
  );
}

class _AddOption extends StatelessWidget {
  const _AddOption({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color.withOpacity(.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ]),
              ),
            ]),
          ),
        ),
      );
}
