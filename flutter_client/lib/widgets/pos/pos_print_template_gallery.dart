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

/// Biểu tượng từng loại phiếu (cột trái / chọn loại phiếu).
IconData posPrintDocIcon(String type) => switch (type) {
      PosPrintDocumentTypes.saleInvoice => Icons.receipt_long_outlined,
      PosPrintDocumentTypes.saleOrder => Icons.shopping_cart_checkout_outlined,
      PosPrintDocumentTypes.delivery => Icons.local_shipping_outlined,
      PosPrintDocumentTypes.saleReturn => Icons.assignment_return_outlined,
      PosPrintDocumentTypes.saleExchange => Icons.swap_horiz,
      PosPrintDocumentTypes.kitchenSlip => Icons.soup_kitchen_outlined,
      PosPrintDocumentTypes.kitchenVoid => Icons.no_meals_outlined,
      PosPrintDocumentTypes.kitchenLabel => Icons.local_cafe_outlined,
      PosPrintDocumentTypes.barcodeLabel => Icons.qr_code_2,
      PosPrintDocumentTypes.purchaseOrder => Icons.request_page_outlined,
      PosPrintDocumentTypes.purchaseReceipt => Icons.move_to_inbox_outlined,
      PosPrintDocumentTypes.purchaseReturn => Icons.outbox_outlined,
      PosPrintDocumentTypes.stockTransfer => Icons.compare_arrows,
      PosPrintDocumentTypes.stockIssue => Icons.inventory_2_outlined,
      PosPrintDocumentTypes.cashReceipt => Icons.south_west,
      PosPrintDocumentTypes.cashPayment => Icons.north_east,
      PosPrintDocumentTypes.quote => Icons.request_quote_outlined,
      PosPrintDocumentTypes.contract => Icons.handshake_outlined,
      PosPrintDocumentTypes.handover => Icons.fact_check_outlined,
      PosPrintDocumentTypes.acceptance => Icons.verified_outlined,
      PosPrintDocumentTypes.paymentRequest => Icons.payments_outlined,
      _ => Icons.description_outlined,
    };

/// Danh sách loại phiếu theo nhóm (máy tính: cột trái).
class PosPrintDocTypeNav extends StatelessWidget {
  const PosPrintDocTypeNav({super.key, required this.current, required this.onSelect});

  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      children: [
        for (final g in posPrintDocGroupsWithOthers()) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 8, 4),
            child: Text(tr(g.title).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: .6)),
          ),
          for (final t in g.types) _DocItem(type: t, active: t == current, onTap: () => onSelect(t)),
        ],
      ],
    );
  }
}

class _DocItem extends StatefulWidget {
  const _DocItem({required this.type, required this.active, required this.onTap});
  final String type;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_DocItem> createState() => _DocItemState();
}

class _DocItemState extends State<_DocItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.active;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: a ? const Color(0xFFEFF6FF) : (_hover ? const Color(0xFFF8FAFC) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: a ? _blue : Colors.transparent, width: 3)),
          ),
          child: Row(children: [
            Icon(posPrintDocIcon(widget.type), size: 17, color: a ? _blue : const Color(0xFF64748B)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(posPrintDocLabel(widget.type)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: a ? FontWeight.w700 : FontWeight.w500,
                  color: a ? _blue : const Color(0xFF334155),
                ),
              ),
            ),
          ]),
        ),
      ),
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
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(14, 26, 14, 0),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.white, boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 6, offset: const Offset(0, 2)),
          ]),
          child: child,
        ),
      ),
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

/// Tên mẫu gọn: bỏ ★ / «· K80» cũ lẫn trong tên.
String posPrintCleanName(String name) {
  var n = name.replaceAll('★', '').trim();
  if (n.isEmpty) return 'Mẫu in';
  return n;
}

/// Thẻ một mẫu in của cửa hàng.
class PosPrintTemplateCard extends StatefulWidget {
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
  State<PosPrintTemplateCard> createState() => _PosPrintTemplateCardState();
}

class _PosPrintTemplateCardState extends State<PosPrintTemplateCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final updated = t.updatedAt ?? t.createdAt;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.isDefault ? _green : const Color(0xFFE2E8F0), width: t.isDefault ? 1.6 : 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_hover ? .10 : .04),
              blurRadius: _hover ? 18 : 8,
              offset: Offset(0, _hover ? 8 : 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.canEdit ? widget.onEdit : widget.onTestPrint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                    child: Stack(children: [
                      Positioned.fill(
                        child: PosPrintTemplateThumb(
                          htmlContent: t.htmlContent,
                          documentType: t.documentType,
                          paperSize: t.paperSize,
                          isDocx: t.isDocx,
                        ),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (t.isDocx) ...[
                            _Badge(text: 'Word', color: const Color(0xFF2B579A), solid: true),
                            const SizedBox(width: 4),
                          ],
                          _Badge(text: PosPrintPaperSizes.shortLabel(t.paperSize), color: const Color(0xFF334155), solid: true),
                        ]),
                      ),
                      if (t.isDefault)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: _Badge(text: tr('Đang dùng'), color: _green, icon: Icons.check_circle, solid: true),
                        ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr(posPrintCleanName(t.name)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A))),
                        const SizedBox(height: 2),
                        Text(
                          updated == null
                              ? PosPrintPaperSizes.displayLabel(t.paperSize)
                              : tr('Cập nhật ${updated.toLocal().day.toString().padLeft(2, '0')}/'
                                  '${updated.toLocal().month.toString().padLeft(2, '0')}/${updated.toLocal().year}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                        ),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      tooltip: tr('Thao tác khác'),
                      icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
                      onSelected: (v) => switch (v) {
                        'edit' => widget.onEdit(),
                        'test' => widget.onTestPrint(),
                        'dup' => widget.onDuplicate?.call(),
                        'del' => widget.onDelete?.call(),
                        _ => null,
                      },
                      itemBuilder: (_) => [
                        if (widget.canEdit)
                          PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: const Icon(Icons.edit_outlined), title: Text(tr('Sửa')))),
                        PopupMenuItem(value: 'test', child: ListTile(dense: true, leading: const Icon(Icons.print_outlined), title: Text(tr('In thử')))),
                        if (widget.onDuplicate != null)
                          PopupMenuItem(value: 'dup', child: ListTile(dense: true, leading: const Icon(Icons.copy_all_outlined), title: Text(tr('Nhân bản')))),
                        if (widget.onDelete != null)
                          PopupMenuItem(value: 'del', child: ListTile(dense: true, leading: const Icon(Icons.delete_outline, color: Colors.red), title: Text(tr('Xóa'), style: const TextStyle(color: Colors.red)))),
                      ],
                    ),
                  ]),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Row(children: [
                    if (widget.canEdit)
                      Expanded(
                        child: TextButton.icon(
                          onPressed: widget.onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: Text(tr('Sửa')),
                        ),
                      ),
                    Expanded(
                      child: t.isDefault
                          ? TextButton.icon(
                              onPressed: widget.onTestPrint,
                              icon: const Icon(Icons.print_outlined, size: 16),
                              label: Text(tr('In thử')),
                            )
                          : FilledButton(
                              onPressed: widget.canEdit ? widget.onUse : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: _green,
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(tr('Dùng mẫu này'), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, this.icon, this.solid = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: solid ? color : color.withOpacity(.12),
          borderRadius: BorderRadius.circular(20),
          boxShadow: solid ? [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 4)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: solid ? Colors.white : color), const SizedBox(width: 3)],
          Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: solid ? Colors.white : color)),
        ]),
      );
}

/// Thẻ «Thêm mẫu» cuối lưới.
class PosPrintAddTemplateCard extends StatelessWidget {
  const PosPrintAddTemplateCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFF8FAFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFBFDBFE), width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: Color(0xFFDBEAFE), shape: BoxShape.circle),
                  child: const Icon(Icons.add, size: 30, color: _blue),
                ),
                const SizedBox(height: 12),
                Text(tr('Thêm mẫu'), style: const TextStyle(fontWeight: FontWeight.w800, color: _blue, fontSize: 15)),
                const SizedBox(height: 4),
                Text(tr('Mẫu có sẵn · File Word · Mẫu trống'),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ]),
            ),
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
