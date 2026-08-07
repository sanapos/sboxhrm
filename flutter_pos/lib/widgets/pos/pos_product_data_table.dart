import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_product.dart';
import '../../providers/permission_provider.dart';
import 'pos_product_expansion_panel.dart';
import 'pos_product_table_columns.dart';
import 'pos_product_image.dart';
import 'pos_product_type_badge.dart';
import 'pos_product_unit_view.dart';
import 'pos_theme.dart';
import 'pos_unit_chip_selector.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

typedef PosProductRowAction = void Function(PosProduct product);

typedef PosVariantEditAction = void Function(
    PosProduct product, PosProductVariant variant);

typedef PosVariantAction = void Function(
    PosProduct product, PosProductVariant variant);

class PosProductDataTable extends StatelessWidget {
  const PosProductDataTable({
    super.key,
    required this.items,
    required this.moneyFmt,
    required this.dateFmt,
    required this.sortBy,
    required this.sortDesc,
    required this.visibleColumns,
    required this.onSort,
    required this.onToggleExpand,
    required this.expandedProductId,
    this.selectedVariantId,
    required this.onSelectVariant,
    required this.onEdit,
    this.onEditVariant,
    this.onDeleteVariant,
    required this.onToggleFavorite,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onToggleSelectAll,
    required this.onCopy,
    required this.onDelete,
    required this.onPrintLabel,
    required this.onExpansionChanged,
    this.onQuickPrice,
    this.onQuickStock,
    this.onQuickVariantPrice,
    this.onQuickVariantStock,
    this.canEdit = false,
    this.variantsByProductId = const {},
    this.variantsLoadingIds = const {},
    this.unitViewVariantIdByProductId = const {},
    this.onUnitViewChanged,
    this.onAddSameType,
  });

  final List<PosProduct> items;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;
  final PosProductSortBy sortBy;
  final bool sortDesc;
  final Set<PosProductTableColumn> visibleColumns;
  final void Function(PosProductSortBy col, bool desc) onSort;
  final void Function(PosProduct p) onToggleExpand;
  final String? expandedProductId;
  final String? selectedVariantId;
  final void Function(PosProduct p, PosProductVariant? v) onSelectVariant;
  final PosProductRowAction onEdit;
  final PosVariantEditAction? onEditVariant;
  final PosVariantAction? onDeleteVariant;
  final PosProductRowAction onCopy;
  final PosProductRowAction onDelete;
  final PosProductRowAction onPrintLabel;
  final VoidCallback onExpansionChanged;
  final void Function(PosProduct p, bool next) onToggleFavorite;
  final Set<String> selectedIds;
  final void Function(PosProduct p, bool selected) onToggleSelect;
  final void Function(bool selectAll) onToggleSelectAll;
  final void Function(PosProduct p)? onQuickPrice;
  final void Function(PosProduct p)? onQuickStock;
  final PosVariantAction? onQuickVariantPrice;
  final PosVariantAction? onQuickVariantStock;
  final bool canEdit;
  final Map<String, List<PosProductVariant>> variantsByProductId;
  final Set<String> variantsLoadingIds;
  final Map<String, String?> unitViewVariantIdByProductId;
  final void Function(PosProduct p, String? variantId)? onUnitViewChanged;
  final void Function(PosProduct p)? onAddSameType;

  bool get _allSelected =>
      items.isNotEmpty && items.every((p) => selectedIds.contains(p.id));

  static const _fixedCols = {
    PosProductTableColumn.select,
    PosProductTableColumn.star,
    PosProductTableColumn.image,
    PosProductTableColumn.actions,
  };

  static const _fixedWidth = <PosProductTableColumn, double>{
    PosProductTableColumn.select: 42,
    PosProductTableColumn.star: 36,
    PosProductTableColumn.image: 72,
    PosProductTableColumn.actions: 36,
  };

  static const _colFlex = <PosProductTableColumn, int>{
    PosProductTableColumn.code: 2,
    PosProductTableColumn.barcode: 2,
    PosProductTableColumn.name: 4,
    PosProductTableColumn.group: 2,
    PosProductTableColumn.type: 2,
    PosProductTableColumn.price: 2,
    PosProductTableColumn.cost: 2,
    PosProductTableColumn.brand: 2,
    PosProductTableColumn.stock: 1,
    PosProductTableColumn.location: 2,
    PosProductTableColumn.reserved: 1,
    PosProductTableColumn.createdAt: 2,
    PosProductTableColumn.stockout: 2,
  };

  List<PosProductTableColumn> _visibleCols() =>
      PosProductTableColumn.values.where(visibleColumns.contains).toList();

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(),
          ...items.expand((p) sync* {
            final loadedVariants = variantsByProductId[p.id] ?? [];
            final displayCount = loadedVariants.isNotEmpty
                ? loadedVariants.length
                : p.variantCount;
            final unitViewId = unitViewVariantIdByProductId[p.id];
            final activeView = resolveUnitView(p, loadedVariants, unitViewId);
            yield _dataRow(
              p,
              displayCount: displayCount,
              activeView: activeView,
              unitViews: buildPosProductUnitViews(p, loadedVariants),
              unitViewVariantId: unitViewId,
            );
            if (expandedProductId == p.id) {
              if (p.variantCount > 0 && variantsLoadingIds.contains(p.id)) {
                yield _variantLoadingRow();
              }
              PosProductVariant? focusVariant;
              if (activeView.variantId != null) {
                focusVariant = loadedVariants.cast<PosProductVariant?>().firstWhere(
                      (v) => v!.id == activeView.variantId,
                      orElse: () => null,
                    );
              }
              yield PosProductExpansionPanel(
                product: p,
                focusVariant: focusVariant,
                moneyFmt: moneyFmt,
                dateFmt: dateFmt,
                canEdit: perm.canEdit('PosProducts'),
                canCreate: perm.canCreate('PosProducts'),
                canDelete: perm.canDelete('PosProducts'),
                onEdit: () {
                  if (focusVariant != null && onEditVariant != null) {
                    onEditVariant!(p, focusVariant);
                  } else {
                    onEdit(p);
                  }
                },
                onCopy: () => onCopy(p),
                onDelete: () => onDelete(p),
                onPrintLabel: () => onPrintLabel(p),
                onChanged: onExpansionChanged,
              );
              if (canEdit && onAddSameType != null && displayCount > 0) {
                yield _variantGroupFooter(p);
              }
            }
          }),
        ],
      ),
    );
  }

  Widget _headerRow() {
    return Container(
      height: 40,
      color: const Color(0xFFF5F7FA),
      child: Row(
        children: _visibleCols().map(_headerCell).toList(),
      ),
    );
  }

  Widget _headerCell(PosProductTableColumn c) {
    final child = switch (c) {
      PosProductTableColumn.select => Center(
          child: Checkbox(
            value: _allSelected,
            tristate: true,
            activeColor: PosTheme.kiotBlue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: items.isEmpty ? null : (v) => onToggleSelectAll(v == true),
          ),
        ),
      PosProductTableColumn.star => const SizedBox.shrink(),
      PosProductTableColumn.image => _imageHeader(),
      PosProductTableColumn.actions => const SizedBox.shrink(),
      _ => _sortHeader(c),
    };
    return _colWrap(c, child);
  }

  Widget _imageHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Center(
        child: Text(
          tr(PosProductTableColumn.image.headerLabel),
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.visible,
          softWrap: false,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _sortHeader(PosProductTableColumn c) {
    final sortCol = switch (c) {
      PosProductTableColumn.code => PosProductSortBy.code,
      PosProductTableColumn.name => PosProductSortBy.name,
      PosProductTableColumn.price => PosProductSortBy.price,
      PosProductTableColumn.stock => PosProductSortBy.stock,
      PosProductTableColumn.createdAt => PosProductSortBy.createdAt,
      _ => null,
    };
    final label = c.headerLabel;
    final align = _isNumericCol(c) ? TextAlign.right : TextAlign.left;

    if (sortCol == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(
          alignment: align == TextAlign.right
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            tr(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    final active = sortBy == sortCol;
    return InkWell(
      onTap: () => onSort(sortCol, active ? !sortDesc : true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisAlignment:
              align == TextAlign.right ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                tr(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? PosTheme.kiotBlue : PosTheme.textPrimary,
                ),
              ),
            ),
            if (active)
              Icon(
                sortDesc ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                size: 16,
                color: PosTheme.kiotBlue,
              ),
          ],
        ),
      ),
    );
  }

  bool _isNumericCol(PosProductTableColumn c) =>
      c == PosProductTableColumn.price ||
      c == PosProductTableColumn.cost ||
      c == PosProductTableColumn.stock ||
      c == PosProductTableColumn.reserved;

  Widget _colWrap(PosProductTableColumn c, Widget child) {
    if (_fixedCols.contains(c)) {
      return SizedBox(width: _fixedWidth[c], child: child);
    }
    return Expanded(
      flex: _colFlex[c] ?? 1,
      child: child,
    );
  }

  Widget _dataRow(
    PosProduct p, {
    required int displayCount,
    required PosProductUnitView activeView,
    required List<PosProductUnitView> unitViews,
    required String? unitViewVariantId,
  }) {
    final inactive = !p.isActive || !p.isDirectSale;
    final expanded = expandedProductId == p.id;
    final selected = selectedIds.contains(p.id);

    Color? bg;
    if (expanded) {
      bg = PosTheme.kiotBlueLight.withOpacity(0.5);
    } else if (selected) {
      bg = PosTheme.kiotBlueLight.withOpacity(0.35);
    }

    return Material(
      color: bg,
      child: InkWell(
        onTap: () {
          onSelectVariant(p, null);
          onToggleExpand(p);
        },
        hoverColor: const Color(0xFFF5F9FF),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
            ),
          ),
          child: Row(
            children: _visibleCols()
                .map((c) => _dataCell(
                      p,
                      c,
                      inactive,
                      displayCount: displayCount,
                      activeView: activeView,
                      unitViews: unitViews,
                      unitViewVariantId: unitViewVariantId,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _cellText(
    String text, {
    TextAlign align = TextAlign.left,
    FontWeight? weight,
    Color? color,
    TextDecoration? decoration,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Align(
        alignment:
            align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          tr(text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          textAlign: align,
          style: TextStyle(
            fontSize: 12,
            fontWeight: weight,
            color: color,
            decoration: decoration,
          ),
        ),
      ),
    );
  }

  Widget _dataCell(
    PosProduct p,
    PosProductTableColumn c,
    bool inactive, {
    required int displayCount,
    required PosProductUnitView activeView,
    required List<PosProductUnitView> unitViews,
    required String? unitViewVariantId,
  }) {
    final showVariantCount = displayCount > 0;
    final child = switch (c) {
      PosProductTableColumn.select => Center(
          child: Checkbox(
            value: selectedIds.contains(p.id),
            activeColor: PosTheme.kiotBlue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: (v) => onToggleSelect(p, v == true),
          ),
        ),
      PosProductTableColumn.star => IconButton(
          icon: Icon(
            p.isFavorite ? Icons.star : Icons.star_border,
            color: p.isFavorite ? const Color(0xFFFFB800) : Colors.grey.shade400,
            size: 18,
          ),
          onPressed: canEdit ? () => onToggleFavorite(p, !p.isFavorite) : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      PosProductTableColumn.image =>
        Center(child: PosProductImage(productId: p.id, imageUrl: p.imageUrl, size: 32)),
      PosProductTableColumn.code => _cellText(
          showVariantCount && displayCount > 0
              ? '($displayCount) ${activeView.displayCode}'
              : activeView.displayCode,
        ),
      PosProductTableColumn.barcode =>
        _cellText(p.barcode ?? '—'),
      PosProductTableColumn.name => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tr(p.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: inactive ? Colors.grey : PosTheme.textPrimary,
                  decoration: inactive ? TextDecoration.lineThrough : null,
                ),
              ),
              if (p.productType == PosProductType.goods)
                PosUnitChipSelector(
                  views: unitViews,
                  selectedVariantId: unitViewVariantId,
                  compact: true,
                  onChanged: (vid) => onUnitViewChanged?.call(p, vid),
                ),
            ],
          ),
        ),
      PosProductTableColumn.group =>
        _cellText(p.categoryName ?? '—'),
      PosProductTableColumn.type => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: PosProductTypeBadge(type: p.productType, compact: true),
          ),
        ),
      PosProductTableColumn.price => _priceCell(p, activeView),
      PosProductTableColumn.cost => _cellText(
          moneyFmt.format(activeView.costPrice),
          align: TextAlign.right,
        ),
      PosProductTableColumn.brand =>
        _cellText(p.brandName ?? '—'),
      PosProductTableColumn.stock => _stockCell(p, activeView),
      PosProductTableColumn.location =>
        _cellText(p.storageLocationName ?? '—'),
      PosProductTableColumn.reserved => _cellText(
          p.reservedQty > 0 ? moneyFmt.format(p.reservedQty) : '0',
          align: TextAlign.right,
        ),
      PosProductTableColumn.createdAt => _cellText(
          p.createdAt != null ? dateFmt.format(p.createdAt!) : '—',
          color: PosTheme.textSecondary,
        ),
      PosProductTableColumn.stockout => _cellText(
          p.estimatedStockoutDate != null
              ? dateFmt.format(p.estimatedStockoutDate!)
              : '—',
          color: PosTheme.textSecondary,
        ),
      PosProductTableColumn.actions => IconButton(
          icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey.shade600),
          onPressed: () => onEdit(p),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
    };
    return _colWrap(c, child);
  }

  Widget _priceCell(PosProduct p, PosProductUnitView view) {
    final text = _cellText(
      moneyFmt.format(view.basePrice),
      align: TextAlign.right,
      weight: FontWeight.w500,
    );
    if (canEdit && p.productType == PosProductType.goods && onQuickPrice != null) {
      return InkWell(
        onTap: () {
          if (view.variantId != null && onQuickVariantPrice != null) {
            final variants = variantsByProductId[p.id] ?? [];
            final v = variants.cast<PosProductVariant?>().firstWhere(
                  (x) => x?.id == view.variantId,
                  orElse: () => null,
                );
            if (v != null) {
              onQuickVariantPrice!(p, v);
              return;
            }
          }
          onQuickPrice!(p);
        },
        child: text,
      );
    }
    return text;
  }

  Widget _stockCell(PosProduct p, PosProductUnitView view) {
    if (p.productType == PosProductType.service) {
      return _cellText('—', align: TextAlign.right, color: Colors.grey);
    }
    final text = _cellText(
      moneyFmt.format(view.onHandQty),
      align: TextAlign.right,
      color: view.onHandQty <= 0 ? const Color(0xFFE53935) : null,
    );
    if (canEdit && p.productType == PosProductType.goods && onQuickStock != null) {
      return InkWell(
        onTap: () {
          if (view.variantId != null && onQuickVariantStock != null) {
            final variants = variantsByProductId[p.id] ?? [];
            final v = variants.cast<PosProductVariant?>().firstWhere(
                  (x) => x?.id == view.variantId,
                  orElse: () => null,
                );
            if (v != null) {
              onQuickVariantStock!(p, v);
              return;
            }
          }
          onQuickStock!(p);
        },
        child: text,
      );
    }
    return text;
  }

  Widget _variantLoadingRow() {
    return Container(
      height: 40,
      color: const Color(0xFFFAFCFF),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 88),
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: PosTheme.kiotBlue),
      ),
    );
  }

  /// Dòng hàng cùng loại (biến thể) — thụt vào kiểu KiotViet, bấm xem chi tiết.
  Widget _variantDataRow(PosProduct parent, PosProductVariant v) {
    final selected = selectedVariantId == v.id;
    return Material(
      color: selected
          ? PosTheme.kiotBlueLight.withOpacity(0.65)
          : const Color(0xFFFAFCFF),
      child: InkWell(
        onTap: () => onSelectVariant(parent, v),
        hoverColor: PosTheme.kiotBlueLight.withOpacity(0.35),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
            ),
          ),
          child: Row(
            children:
                _visibleCols().map((c) => _variantCell(parent, v, c)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _variantCell(
      PosProduct parent, PosProductVariant v, PosProductTableColumn c) {
    final child = switch (c) {
      PosProductTableColumn.select ||
      PosProductTableColumn.star ||
      PosProductTableColumn.image =>
        const SizedBox.shrink(),
      PosProductTableColumn.code => Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Tooltip(
            message: v.skuCode,
            waitDuration: const Duration(milliseconds: 400),
            child: _cellText(v.skuCode, color: PosTheme.textSecondary),
          ),
        ),
      PosProductTableColumn.barcode =>
        _cellText(v.barcode ?? '—', color: PosTheme.textSecondary),
      PosProductTableColumn.name => Padding(
          padding: const EdgeInsets.only(left: 12),
          child: _cellText(
            v.name,
            color: PosTheme.textSecondary,
            weight: FontWeight.w400,
          ),
        ),
      PosProductTableColumn.price => _variantPriceCell(parent, v),
      PosProductTableColumn.cost => _cellText(
          moneyFmt.format(v.costPrice),
          align: TextAlign.right,
          color: PosTheme.textSecondary,
        ),
      PosProductTableColumn.stock => _variantStockCell(parent, v),
      PosProductTableColumn.createdAt => _cellText(
          parent.createdAt != null ? dateFmt.format(parent.createdAt!) : '—',
          color: PosTheme.textSecondary,
        ),
      _ => _cellText('—', color: PosTheme.textSecondary),
    };
    return _colWrap(c, child);
  }

  Widget _variantPriceCell(PosProduct parent, PosProductVariant v) {
    final text = _cellText(
      moneyFmt.format(v.basePrice),
      align: TextAlign.right,
      color: PosTheme.textSecondary,
    );
    if (canEdit && onQuickVariantPrice != null) {
      return InkWell(onTap: () => onQuickVariantPrice!(parent, v), child: text);
    }
    return text;
  }

  Widget _variantStockCell(PosProduct parent, PosProductVariant v) {
    final text = _cellText(
      moneyFmt.format(v.onHandQty),
      align: TextAlign.right,
      color: v.onHandQty <= 0
          ? const Color(0xFFE53935)
          : PosTheme.textSecondary,
    );
    if (canEdit && onQuickVariantStock != null) {
      return InkWell(onTap: () => onQuickVariantStock!(parent, v), child: text);
    }
    return text;
  }

  Widget _variantGroupFooter(PosProduct p) {
    return Container(
      color: const Color(0xFFFAFCFF),
      padding: const EdgeInsets.fromLTRB(88, 4, 16, 10),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => onCopy!(p),
            icon: const Icon(Icons.copy, size: 16),
            label: Text(tr('Sao chép')),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => onAddSameType!(p),
            style: FilledButton.styleFrom(
              backgroundColor: PosTheme.kiotBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            icon: const Icon(Icons.add, size: 16),
            label: Text(tr('Thêm hàng hóa cùng loại')),
          ),
        ],
      ),
    );
  }
}
