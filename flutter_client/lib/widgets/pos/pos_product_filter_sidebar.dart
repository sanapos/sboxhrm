import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../utils/pos_kiot_time_range.dart';
import 'pos_kiot_time_filter.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Sidebar lọc bên trái — layout giống KiotViet (có Tùy chỉnh ngày).
class PosProductFilterSidebar extends StatelessWidget {
  const PosProductFilterSidebar({
    super.key,
    required this.categories,
    required this.brands,
    required this.locations,
    required this.suppliers,
    required this.categoryId,
    required this.brandId,
    required this.locationId,
    required this.supplierId,
    required this.productType,
    required this.stockFilter,
    required this.stockoutFilter,
    required this.directSaleFilter,
    required this.includeInactive,
    required this.createdTimeFilter,
    required this.useStockoutCustom,
    required this.stockoutBefore,
    required this.onCategoryChanged,
    required this.onBrandChanged,
    required this.onLocationChanged,
    required this.onSupplierChanged,
    required this.onProductTypeChanged,
    required this.onStockFilterChanged,
    required this.onStockoutFilterChanged,
    required this.onDirectSaleFilterChanged,
    required this.onIncludeInactiveChanged,
    required this.onCreatedTimeFilterChanged,
    required this.onStockoutCustomChanged,
    required this.onStockoutBeforeChanged,
    this.onCreateCategory,
    this.onManageCategory,
    this.onManageSupplier,
    this.onManageLocation,
    this.onManageBrand,
  });

  final List<PosCatalogItem> categories;
  final List<PosCatalogItem> brands;
  final List<PosCatalogItem> locations;
  final List<PosCatalogItem> suppliers;
  final String? categoryId;
  final String? brandId;
  final String? locationId;
  final String? supplierId;
  final PosProductType? productType;
  final PosStockFilter stockFilter;
  final PosStockoutFilter stockoutFilter;
  final bool? directSaleFilter;
  final bool includeInactive;
  final PosKiotTimeFilterState createdTimeFilter;
  final bool useStockoutCustom;
  final DateTime? stockoutBefore;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onBrandChanged;
  final ValueChanged<String?> onLocationChanged;
  final ValueChanged<String?> onSupplierChanged;
  final ValueChanged<PosProductType?> onProductTypeChanged;
  final ValueChanged<PosStockFilter> onStockFilterChanged;
  final ValueChanged<PosStockoutFilter> onStockoutFilterChanged;
  final ValueChanged<bool?> onDirectSaleFilterChanged;
  final ValueChanged<bool> onIncludeInactiveChanged;
  final ValueChanged<PosKiotTimeFilterState> onCreatedTimeFilterChanged;
  final ValueChanged<bool> onStockoutCustomChanged;
  final ValueChanged<DateTime?> onStockoutBeforeChanged;
  final VoidCallback? onCreateCategory;
  final VoidCallback? onManageCategory;
  final VoidCallback? onManageSupplier;
  final VoidCallback? onManageLocation;
  final VoidCallback? onManageBrand;

  static final _dateFmt = DateFormat('dd/MM/yyyy', 'vi_VN');

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _sectionHeader('Nhóm hàng',
              onCreate: onCreateCategory, onManage: onManageCategory),
          _catalogDropdown(
            value: categoryId,
            items: categories,
            hint: 'Chọn nhóm hàng',
            onChanged: onCategoryChanged,
          ),
          const SizedBox(height: 16),
          _sectionHeader('Tồn kho'),
          _stockDropdown(),
          const SizedBox(height: 16),
          _sectionHeader('Dự kiến hết hàng'),
          _stockoutRadios(context),
          const SizedBox(height: 16),
          _sectionHeader('Thời gian tạo'),
          PosKiotTimeFilter(
            state: createdTimeFilter,
            onChanged: onCreatedTimeFilterChanged,
          ),
          const SizedBox(height: 16),
          _sectionHeader('Nhà cung cấp', onManage: onManageSupplier),
          _catalogDropdown(
            value: supplierId,
            items: suppliers,
            hint: 'Chọn nhà cung cấp',
            onChanged: onSupplierChanged,
          ),
          const SizedBox(height: 16),
          _sectionHeader('Vị trí', onManage: onManageLocation),
          _catalogDropdown(
            value: locationId,
            items: locations,
            hint: 'Chọn vị trí',
            onChanged: onLocationChanged,
          ),
          const SizedBox(height: 16),
          _sectionHeader('Thương hiệu', onManage: onManageBrand),
          _catalogDropdown(
            value: brandId,
            items: brands,
            hint: 'Chọn thương hiệu',
            onChanged: onBrandChanged,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(tr('Gồm ngừng kinh doanh'),
                style: TextStyle(fontSize: 13)),
            value: includeInactive,
            activeColor: PosTheme.kiotBlue,
            onChanged: onIncludeInactiveChanged,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onCreate, VoidCallback? onManage}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr(title),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: PosTheme.textPrimary,
              ),
            ),
          ),
          if (onManage != null)
            TextButton(
              onPressed: onManage,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: PosTheme.textSecondary,
              ),
              child: Text(tr('Quản lý'), style: TextStyle(fontSize: 12)),
            ),
          if (onCreate != null) ...[
            if (onManage != null) const SizedBox(width: 4),
            TextButton(
              onPressed: onCreate,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: PosTheme.kiotBlue,
              ),
              child: Text(tr('Tạo mới'), style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _catalogDropdown({
    required String? value,
    required List<PosCatalogItem> items,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) {
    final valid = value != null && items.any((c) => c.id == value);
    return DropdownButtonFormField<String?>(
      value: valid ? value : null,
      isExpanded: true,
      decoration: _fieldDecoration(hint),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(tr('Tất cả'))),
        ...items.map((c) => DropdownMenuItem<String?>(
              value: c.id,
              child: Text(tr(c.name), overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: onChanged,
    );
  }

  Widget _stockDropdown() {
    return DropdownButtonFormField<PosStockFilter>(
      value: stockFilter,
      isExpanded: true,
      decoration: _fieldDecoration('Tất cả'),
      items: [
        DropdownMenuItem(value: PosStockFilter.all, child: Text(tr('Tất cả'))),
        DropdownMenuItem(
            value: PosStockFilter.outOfStock, child: Text(tr('Hết hàng'))),
        DropdownMenuItem(
            value: PosStockFilter.belowMin,
            child: Text(tr('Dưới định mức tồn'))),
        DropdownMenuItem(
            value: PosStockFilter.aboveMax,
            child: Text(tr('Vượt định mức tồn'))),
      ],
      onChanged: (v) {
        if (v != null) onStockFilterChanged(v);
      },
    );
  }

  Widget _stockoutRadios(BuildContext context) {
    return Column(
      children: [
        _radioTile(
          'Toàn thời gian',
          !useStockoutCustom && stockoutFilter == PosStockoutFilter.all,
          () {
            onStockoutCustomChanged(false);
            onStockoutFilterChanged(PosStockoutFilter.all);
          },
        ),
        _radioTile(
          'Trong 7 ngày',
          !useStockoutCustom &&
              stockoutFilter == PosStockoutFilter.within7Days,
          () {
            onStockoutCustomChanged(false);
            onStockoutFilterChanged(PosStockoutFilter.within7Days);
          },
        ),
        _radioTile(
          'Trong 30 ngày',
          !useStockoutCustom &&
              stockoutFilter == PosStockoutFilter.within30Days,
          () {
            onStockoutCustomChanged(false);
            onStockoutFilterChanged(PosStockoutFilter.within30Days);
          },
        ),
        _radioTile('Tùy chỉnh', useStockoutCustom, () {
          onStockoutCustomChanged(true);
        }),
        if (useStockoutCustom) ...[
          const SizedBox(height: 6),
          _dateField(
            context,
            label: 'Hết hàng trước ngày',
            value: stockoutBefore,
            onPick: onStockoutBeforeChanged,
          ),
        ],
      ],
    );
  }

  Widget _dateField(
    BuildContext context, {
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onPick,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: _fieldDecoration(label),
        child: Text(
          tr(value != null ? _dateFmt.format(value) : 'Chọn ngày'),
          style: TextStyle(
            fontSize: 13,
            color: value != null ? PosTheme.textPrimary : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _radioTile(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? PosTheme.kiotBlue : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(tr(label), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: tr(hint),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: PosTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: PosTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: PosTheme.kiotBlue),
        ),
      );
}
