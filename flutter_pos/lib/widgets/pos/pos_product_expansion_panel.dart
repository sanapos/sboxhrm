import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/file_saver.dart' as file_saver;
import '../../utils/pos_qty_rules.dart';
import '../../widgets/notification_overlay.dart';
import 'pos_product_image.dart';
import 'pos_stock_card_table.dart';
import 'pos_stock_document_sheet.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Chi ti?t hàng hóa m? r?ng inline — giao di?n ki?u KiotViet.
class PosProductExpansionPanel extends StatefulWidget {
  const PosProductExpansionPanel({
    super.key,
    required this.product,
    required this.moneyFmt,
    required this.dateFmt,
    required this.canEdit,
    required this.canCreate,
    required this.canDelete,
    required this.onEdit,
    required this.onCopy,
    required this.onDelete,
    required this.onPrintLabel,
    required this.onChanged,
    this.focusVariant,
  });

  final PosProduct product;
  final PosProductVariant? focusVariant;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;
  final bool canEdit;
  final bool canCreate;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onPrintLabel;
  final VoidCallback onChanged;

  @override
  State<PosProductExpansionPanel> createState() =>
      _PosProductExpansionPanelState();
}

class _PosProductExpansionPanelState extends State<PosProductExpansionPanel> {
  final _api = ApiService();
  int _tabIndex = 0;
  bool _loading = true;
  late PosProduct _p;
  List<PosStockTransaction> _stockTx = [];
  bool _exportingStock = false;

  @override
  void initState() {
    super.initState();
    _p = widget.product;
    _load();
  }

  @override
  void didUpdateWidget(covariant PosProductExpansionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id ||
        oldWidget.focusVariant?.id != widget.focusVariant?.id) {
      _p = widget.product;
      _tabIndex = 0;
      _load();
    }
  }

  void _onTabTap(int i) {
    setState(() => _tabIndex = i);
    if (i == 2) _loadStockTx();
  }

  Future<void> _loadStockTx() async {
    final variantId = widget.focusVariant?.id;
    final txRes = await _api.getPosStockTransactions(
      productId: _p.id,
      variantId: variantId,
      pageSize: 50,
    );
    if (!mounted) return;
    if (txRes['isSuccess'] == true && txRes['data'] is Map) {
      setState(() {
        _stockTx = ((txRes['data'] as Map)['items'] as List? ?? [])
            .map((e) => PosStockTransaction.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getPosProduct(_p.id);
      if (mounted && res['isSuccess'] == true && res['data'] != null) {
        _p = PosProduct.fromJson(res['data'] as Map<String, dynamic>);
      }
      final txRes = await _api.getPosStockTransactions(
        productId: _p.id,
        variantId: widget.focusVariant?.id,
        pageSize: 50,
      );
      if (mounted && txRes['isSuccess'] == true && txRes['data'] is Map) {
        _stockTx = ((txRes['data'] as Map)['items'] as List? ?? [])
            .map((e) => PosStockTransaction.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _tabs = [
    'Thông tin',
    'Mô t?, ghi chú',
    'Th? kho',
    'T?n kho',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PosTheme.border),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final active = _tabIndex == i;
                return InkWell(
                  onTap: () => _onTabTap(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: active ? PosTheme.kiotBlue : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Text(
                      tr(_tabs[i]),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                        color: active ? PosTheme.kiotBlue : PosTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220, maxHeight: 340),
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: PosTheme.kiotBlue),
                  )
                : _buildTabContent(),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return switch (_tabIndex) {
      0 => _buildInfoTab(),
      1 => _buildDescriptionTab(),
      2 => _buildStockCardTab(),
      _ => _buildInventoryTab(),
    };
  }

  Widget _buildInfoTab() {
    final isGoods = _p.productType == PosProductType.goods;
    final v = widget.focusVariant;
    final displayName = v?.name ?? _p.name;
    final displayCode = v?.skuCode ?? _p.productCode;
    final displayBarcode = v?.barcode ?? _p.barcode;
    final displayCost = v?.costPrice ?? _p.costPrice;
    final displayPrice = v?.basePrice ?? _p.basePrice;
    final displayStock = v?.onHandQty ?? _p.onHandQty;
    final weightStr = _p.weight != null && _p.weight! > 0
        ? '${_p.weight!.toStringAsFixed(_p.weight! % 1 == 0 ? 0 : 2)} ${_p.weightUnit}'
        : 'Chua có';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: PosProductImage(
              productId: _p.id,
              imageUrl: _p.imageUrl,
              size: 100,
              borderRadius: 6,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(displayName),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: PosTheme.textPrimary,
                  ),
                ),
                if (_p.categoryPath != null && _p.categoryPath!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(tr('Nhóm hàng: ${_p.categoryPath}'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: PosTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _badge(_goodsTypeLabel(_p.productType)),
                    if (_p.isDirectSale) _badge('Bán tr?c ti?p'),
                    if (!_p.isActive)
                      _badge('Ng?ng kinh doanh', color: Colors.orange.shade800),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 32,
                  runSpacing: 8,
                  children: [
                    _infoCell('Mã hàng', displayCode),
                    if (_p.productType != PosProductType.service)
                      _infoCell('Mã v?ch', displayBarcode ?? 'Chua có'),
                    _infoCell('Giá v?n', widget.moneyFmt.format(displayCost)),
                    _infoCell('Giá bán', widget.moneyFmt.format(displayPrice)),
                    if (isGoods)
                      _infoCell('T?n kho', widget.moneyFmt.format(displayStock)),
                    if (isGoods) _infoCell('Tr?ng lu?ng', weightStr),
                    if (isGoods)
                      _infoCell(
                        'Ð?nh m?c t?n',
                        '${widget.moneyFmt.format(_p.minStockQty)} - ${widget.moneyFmt.format(_p.maxStockQty)}',
                      ),
                    _infoCell('Thuong hi?u', _p.brandName ?? 'Chua có'),
                    if (isGoods)
                      _infoCell('V? trí', _p.storageLocationName ?? 'Chua có'),
                  ],
                ),
                if (isGoods && widget.canEdit) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _linkBtn('Thêm don v? tính', widget.onEdit),
                      const SizedBox(width: 16),
                      _linkBtn('Thêm thu?c tính', widget.onEdit),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _goodsTypeLabel(PosProductType t) => switch (t) {
        PosProductType.goods => 'Hàng hóa thu?ng',
        PosProductType.service => 'D?ch v?',
        PosProductType.combo => 'Combo - dóng gói',
      };

  Widget _badge(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? PosTheme.textSecondary).withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr(text),
        style: TextStyle(
          fontSize: 11,
          color: color ?? PosTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _infoCell(String label, String value) {
    return SizedBox(
      width: 180,
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 12, color: PosTheme.textPrimary),
          children: [
            TextSpan(
              text: tr('$label: '),
              style: const TextStyle(color: PosTheme.textSecondary),
            ),
            TextSpan(text: tr(value)),
          ],
        ),
      ),
    );
  }

  Widget _linkBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Text(
        tr(label),
        style: const TextStyle(
          fontSize: 12,
          color: PosTheme.kiotBlue,
          decoration: TextDecoration.underline,
          decorationColor: PosTheme.kiotBlue,
        ),
      ),
    );
  }

  Widget _buildDescriptionTab() {
    final desc = _p.description?.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: desc == null || desc.isEmpty
          ? Text(tr('Chua có mô t?'),
              style: TextStyle(fontSize: 13, color: PosTheme.textSecondary),
            )
          : Text(tr(desc), style: const TextStyle(fontSize: 13)),
    );
  }

  Future<void> _exportStockCard() async {
    setState(() => _exportingStock = true);
    try {
      final res = await _api.exportPosStockTransactionsExcel(
        productId: _p.id,
        variantId: widget.focusVariant?.id,
      );
      if (res['isSuccess'] == true) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        await file_saver.saveFileBytes(
          bytes,
          'the_kho_${_p.productCode}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        NotificationOverlayManager()
            .showSuccess(title: 'Xu?t file', message: tr('Ðã xu?t th? kho'));
      }
    } finally {
      if (mounted) setState(() => _exportingStock = false);
    }
  }

  Widget _buildStockCardTab() {
    return PosStockCardTable(
      items: _stockTx,
      moneyFmt: widget.moneyFmt,
      dateFmt: widget.dateFmt,
      onExport: _exportingStock ? null : _exportStockCard,
      onDocumentTap: (t) => showPosStockDocumentSheet(
        context,
        tx: t,
        moneyFmt: widget.moneyFmt,
        dateFmt: widget.dateFmt,
      ),
    );
  }

  Widget _buildInventoryTab() {
    final v = widget.focusVariant;
    final stock = v?.onHandQty ?? _p.onHandQty;
    if (_p.productType == PosProductType.service) {
      return Center(
        child: Text(tr('D?ch v? không qu?n lý t?n kho'),
          style: TextStyle(fontSize: 13, color: PosTheme.textSecondary),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 40,
        runSpacing: 12,
        children: [
          _infoCell('T?n kho', PosQtyRules.format(stock, product: _p)),
          _infoCell(
            'Khách d?t',
            PosQtyRules.format(_p.reservedQty, product: _p),
          ),
          _infoCell(
            'Có th? bán',
            PosQtyRules.format(_p.onHandQty - _p.reservedQty, product: _p),
          ),
          _infoCell(
            'Ð?nh m?c t?n',
            '${widget.moneyFmt.format(_p.minStockQty)} - ${widget.moneyFmt.format(_p.maxStockQty)}',
          ),
          if (_p.estimatedStockoutDate != null)
            _infoCell(
              'D? ki?n h?t hàng',
              widget.dateFmt.format(_p.estimatedStockoutDate!.toLocal()),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          if (widget.canDelete)
            TextButton.icon(
              onPressed: widget.onDelete,
              icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade700),
              label: Text(tr('Xóa'), style: TextStyle(color: Colors.red.shade700)),
            ),
          if (widget.canCreate)
            TextButton.icon(
              onPressed: widget.onCopy,
              icon: const Icon(Icons.copy, size: 18),
              label: Text(tr('Sao chép')),
            ),
          const Spacer(),
          if (widget.canEdit)
            FilledButton.icon(
              onPressed: widget.onEdit,
              style: FilledButton.styleFrom(
                backgroundColor: PosTheme.kiotBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.edit, size: 16),
              label: Text(tr('Ch?nh s?a')),
            ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: widget.onPrintLabel,
            style: OutlinedButton.styleFrom(
              foregroundColor: PosTheme.textPrimary,
              side: const BorderSide(color: PosTheme.border),
            ),
            icon: const Icon(Icons.print_outlined, size: 16),
            label: Text(tr('In tem mã')),
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.more_horiz, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
