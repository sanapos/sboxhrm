import 'package:flutter/material.dart';

import '../pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

enum PosGoodsInventoryFilter {
  all,
  belowMin,
  aboveMin,
  inStock,
  outOfStock,
}

class PosGoodsReportFilter {
  const PosGoodsReportFilter({
    this.includeGoods = true,
    this.includeService = true,
    this.includeCombo = true,
    this.activeOnly = true,
    this.inactiveOnly = false,
    this.inventoryStatus = PosGoodsInventoryFilter.all,
  });

  final bool includeGoods;
  final bool includeService;
  final bool includeCombo;
  final bool activeOnly;
  final bool inactiveOnly;
  final PosGoodsInventoryFilter inventoryStatus;

  PosGoodsReportFilter copyWith({
    bool? includeGoods,
    bool? includeService,
    bool? includeCombo,
    bool? activeOnly,
    bool? inactiveOnly,
    PosGoodsInventoryFilter? inventoryStatus,
  }) =>
      PosGoodsReportFilter(
        includeGoods: includeGoods ?? this.includeGoods,
        includeService: includeService ?? this.includeService,
        includeCombo: includeCombo ?? this.includeCombo,
        activeOnly: activeOnly ?? this.activeOnly,
        inactiveOnly: inactiveOnly ?? this.inactiveOnly,
        inventoryStatus: inventoryStatus ?? this.inventoryStatus,
      );
}

/// Lọc báo cáo hàng hóa kiểu KiotViet.
class PosGoodsFilterSheet extends StatefulWidget {
  const PosGoodsFilterSheet({super.key, required this.initial});

  final PosGoodsReportFilter initial;

  @override
  State<PosGoodsFilterSheet> createState() => _PosGoodsFilterSheetState();
}

class _PosGoodsFilterSheetState extends State<PosGoodsFilterSheet> {
  late PosGoodsReportFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initial;
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(tr(label)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: PosTheme.kiotBlueLight,
      checkmarkColor: PosTheme.kiotBlue,
      labelStyle: TextStyle(
        color: selected ? PosTheme.kiotBlue : PosTheme.textPrimary,
        fontSize: 13,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(tr('Lọc báo cáo'),
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _filter),
                    child: Text(tr('Áp dụng')),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                children: [
                  _section(
                    'Loại hàng',
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _chip('Hàng hóa', _filter.includeGoods, () {
                          setState(() => _filter = _filter.copyWith(includeGoods: !_filter.includeGoods));
                        }),
                        _chip('Dịch vụ', _filter.includeService, () {
                          setState(() => _filter = _filter.copyWith(includeService: !_filter.includeService));
                        }),
                        _chip('Combo - Đóng gói', _filter.includeCombo, () {
                          setState(() => _filter = _filter.copyWith(includeCombo: !_filter.includeCombo));
                        }),
                      ],
                    ),
                  ),
                  _section(
                    'Tồn kho',
                    Column(
                      children: [
                        _radio('Tất cả', PosGoodsInventoryFilter.all),
                        _radio('Dưới định mức tồn', PosGoodsInventoryFilter.belowMin),
                        _radio('Vượt định mức tồn', PosGoodsInventoryFilter.aboveMin),
                        _radio('Còn hàng trong kho', PosGoodsInventoryFilter.inStock),
                        _radio('Hết hàng trong kho', PosGoodsInventoryFilter.outOfStock),
                      ],
                    ),
                  ),
                  _section(
                    'Trạng thái',
                    Wrap(
                      spacing: 8,
                      children: [
                        _chip('Đang kinh doanh', _filter.activeOnly, () {
                          setState(() => _filter = _filter.copyWith(activeOnly: !_filter.activeOnly));
                        }),
                        _chip('Ngừng kinh doanh', _filter.inactiveOnly, () {
                          setState(() => _filter = _filter.copyWith(inactiveOnly: !_filter.inactiveOnly));
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: PosTheme.mobileCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _radio(String label, PosGoodsInventoryFilter value) {
    final selected = _filter.inventoryStatus == value;
    return InkWell(
      onTap: () => setState(() => _filter = _filter.copyWith(inventoryStatus: value)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(tr(label), style: const TextStyle(fontSize: 14))),
            if (selected) const Icon(Icons.check, color: PosTheme.kiotBlue, size: 20),
          ],
        ),
      ),
    );
  }
}
