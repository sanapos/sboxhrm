import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_product.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_barcode_label_dialog.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_product_image.dart';
import '../../widgets/pos/pos_stock_card_table.dart';
import '../../widgets/pos/pos_product_type_badge.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_product_editor_page.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import 'package:sbox_pos/l10n/app_tr.dart';

class PosProductDetailScreen extends StatefulWidget {
  const PosProductDetailScreen({super.key, required this.product});

  final PosProduct product;

  @override
  State<PosProductDetailScreen> createState() => _PosProductDetailScreenState();
}

class _PosProductDetailScreenState extends State<PosProductDetailScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  bool _loading = true;
  late PosProduct _product;
  List<PosComboLine> _comboLines = [];
  List<PosProductVariant> _variants = [];

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    final res = await _api.getPosProduct(_product.id);
    if (mounted && res['isSuccess'] == true && res['data'] != null) {
      _product = PosProduct.fromJson(res['data'] as Map<String, dynamic>);
    }
    if (_product.productType == PosProductType.combo) {
      final comboRes = await _api.getPosComboLines(_product.id);
      if (mounted && comboRes['isSuccess'] == true && comboRes['data'] is List) {
        _comboLines = (comboRes['data'] as List)
            .map((e) => PosComboLine.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    if (_product.productType == PosProductType.goods) {
      final varRes = await _api.getPosProductVariants(_product.id);
      if (mounted && varRes['isSuccess'] == true && varRes['data'] is List) {
        _variants = (varRes['data'] as List)
            .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleActive(bool value) async {
    final res = await _api.patchPosProductSellingStatus(
      _product.id,
      isDirectSale: _product.isDirectSale,
      isActive: value,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _loadDetail();
      NotificationOverlayManager().showSuccess(
        title: 'Đã cập nhật',
        message: value ? 'Đã mở kinh doanh' : 'Đã ngừng kinh doanh',
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Cập nhật thất bại',
      );
    }
  }

  Future<void> _toggleDirectSale(bool value) async {
    final res = await _api.patchPosProductSellingStatus(
      _product.id,
      isDirectSale: value,
      isActive: _product.isActive,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _loadDetail();
      NotificationOverlayManager().showSuccess(
        title: 'Đã cập nhật',
        message: value ? 'Hiện trên POS' : 'Đã ẩn khỏi POS',
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Cập nhật thất bại',
      );
    }
  }

  Future<void> _openEditor() async {
    final saved = await PosProductEditorPage.open(
      context,
      productType: _product.productType,
      product: _product,
    );
    if (saved == true) await _loadDetail();
  }

  Future<void> _copyProduct() async {
    final saved = await PosProductEditorPage.open(
      context,
      productType: _product.productType,
      templateProduct: _product,
    );
    if (!mounted) return;
    if (saved == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: tr('Đã tạo hàng hóa mới từ bản sao'),
      );
    }
  }

  Future<void> _deleteProduct() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa hàng hóa')),
        content: Text(tr('Xóa «${_product.name}»?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosProduct(_product.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: tr('Đã xóa hàng hóa'),
      );
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không thể xóa',
      );
    }
  }

  Future<void> _showStockCard() async {
    final res = await _api.getPosStockTransactions(
      productId: _product.id,
      pageSize: 100,
    );
    if (!mounted) return;
    final list = res['isSuccess'] == true && res['data'] is Map
        ? ((res['data'] as Map)['items'] as List? ?? [])
            .map((e) => PosStockTransaction.fromJson(e as Map<String, dynamic>))
            .toList()
        : <PosStockTransaction>[];

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thẻ kho — ${_product.name}')),
        content: SizedBox(
          width: 720,
          height: 400,
          child: PosStockCardTable(
            items: list,
            moneyFmt: _moneyFmt,
            dateFmt: _dateFmt,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Đóng')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final p = _product;
    final isGoods = p.productType == PosProductType.goods;
    final isCombo = p.productType == PosProductType.combo;

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Chi tiết hàng hóa')),
        backgroundColor: PosTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: PosTheme.primary),
            )
          : RefreshIndicator(
              color: PosTheme.primary,
              onRefresh: _loadDetail,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(p),
                  const SizedBox(height: 16),
                  _buildSellingToggles(perm),
                  const SizedBox(height: 16),
                  _sectionCard('Thông tin', _buildInfoRows(p)),
                  if (isCombo && _comboLines.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _sectionCard('Thành phần combo', _buildComboLines()),
                  ],
                  if (isGoods && _variants.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _sectionCard('Biến thể (${_variants.length})', _buildVariants()),
                  ],
                  const SizedBox(height: 12),
                  _sectionCard('Thao tác', _buildActions(perm)),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(PosProduct p) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: PosTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 88,
                height: 88,
                child: p.imageUrl != null && p.imageUrl!.isNotEmpty
                    ? PosProductImage(imageUrl: p.imageUrl, productId: p.id, size: 88, borderRadius: 10)
                    : _imagePlaceholder(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(p.name),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: PosTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(p.productCode),
                    style: const TextStyle(
                      fontSize: 13,
                      color: PosTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      PosProductTypeBadge(type: p.productType),
                      PosSellingStatusBadge(
                        isActive: p.isActive,
                        isDirectSale: p.isDirectSale,
                      ),
                      if (p.isFavorite)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star,
                                  size: 12, color: Colors.amber.shade700),
                              const SizedBox(width: 4),
                              Text(tr('Yêu thích'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (p.categoryPath != null && p.categoryPath!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      tr(p.categoryPath!),
                      style: const TextStyle(
                        fontSize: 12,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: Colors.grey.shade100,
      child: Icon(Icons.inventory_2_outlined,
          color: Colors.grey.shade400, size: 36),
    );
  }

  Widget _buildSellingToggles(PermissionProvider perm) {
    if (!perm.canEdit('PosProducts')) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: PosTheme.border),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(tr('Ngừng kinh doanh')),
            subtitle: Text(tr('Ẩn sản phẩm khỏi mọi kênh bán')),
            value: !_product.isActive,
            activeColor: PosTheme.primary,
            onChanged: (v) => _toggleActive(!v),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(tr('Ẩn POS')),
            subtitle: Text(tr('Không hiển thị trên màn hình bán hàng')),
            value: !_product.isDirectSale,
            activeColor: PosTheme.primary,
            onChanged: _product.isActive ? (v) => _toggleDirectSale(!v) : null,
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, Widget child) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: PosTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(title),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: PosTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRows(PosProduct p) {
    final isService = p.productType == PosProductType.service;
    final isGoods = p.productType == PosProductType.goods;
    return Column(
      children: [
        _detailRow('Mã hàng', p.productCode),
        if (!isService) _detailRow('Mã vạch', p.barcode ?? 'Chưa có'),
        _detailRow('Giá vốn', _moneyFmt.format(p.costPrice)),
        _detailRow('Giá bán', _moneyFmt.format(p.basePrice)),
        if (isGoods)
          _detailRow('Tồn kho', _moneyFmt.format(p.onHandQty)),
        if (isGoods) ...[
          _detailRow('Khách đặt', _moneyFmt.format(p.reservedQty)),
          _detailRow(
            'Định mức tồn',
            '${_moneyFmt.format(p.minStockQty)} - ${_moneyFmt.format(p.maxStockQty)}',
          ),
        ],
        _detailRow('Thương hiệu', p.brandName ?? 'Chưa có'),
        if (isGoods) _detailRow('Nhà cung cấp', p.supplierName ?? 'Chưa có'),
        if (isGoods) _detailRow('Vị trí', p.storageLocationName ?? 'Chưa có'),
        if (isGoods && p.baseUnitName.isNotEmpty)
          _detailRow('Đơn vị', p.baseUnitName),
        if (p.estimatedStockoutDate != null)
          _detailRow(
            'Dự kiến hết hàng',
            _dateFmt.format(p.estimatedStockoutDate!.toLocal()),
          ),
        if (p.avgDailySales != null && p.avgDailySales! > 0)
          _detailRow(
            'Bán TB/ngày (30 ngày)',
            _moneyFmt.format(p.avgDailySales),
          ),
        if (p.description != null && p.description!.trim().isNotEmpty)
          _detailRow('Mô tả', p.description!),
        if (p.attributes != null && p.attributes!.isNotEmpty)
          ...p.attributes!.map((a) => _detailRow(a.attributeName, a.value)),
        if (p.createdAt != null)
          _detailRow('Thời gian tạo', _dateFmt.format(p.createdAt!)),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              tr(label),
              style: const TextStyle(
                fontSize: 13,
                color: PosTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              tr(value),
              style: const TextStyle(fontSize: 13, color: PosTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComboLines() {
    return Column(
      children: _comboLines.map((c) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr(c.componentProductName.isNotEmpty
                      ? c.componentProductName
                      : c.componentProductCode),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                tr('× ${c.qty}'),
                style: const TextStyle(
                  fontSize: 13,
                  color: PosTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                tr(_moneyFmt.format(c.componentBasePrice * c.qty)),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildVariants() {
    return Column(
      children: _variants.map((v) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(v.name),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    if (v.skuCode.isNotEmpty)
                      Text(
                        tr(v.skuCode),
                        style: const TextStyle(
                          fontSize: 11,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                tr(_moneyFmt.format(v.basePrice)),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 12),
              Text(tr('Tồn: ${_moneyFmt.format(v.onHandQty)}'),
                style: const TextStyle(
                  fontSize: 12,
                  color: PosTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActions(PermissionProvider perm) {
    final isGoods = _product.productType == PosProductType.goods;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (perm.canEdit('PosProducts'))
          FilledButton.icon(
            onPressed: _openEditor,
            style: PosTheme.filledButtonStyle,
            icon: const Icon(Icons.edit, size: 18),
            label: Text(tr('Chỉnh sửa')),
          ),
        if (perm.canCreate('PosProducts'))
          OutlinedButton.icon(
            onPressed: _copyProduct,
            icon: const Icon(Icons.copy, size: 18),
            label: Text(tr('Sao chép')),
            style: OutlinedButton.styleFrom(
              foregroundColor: PosTheme.primary,
              side: const BorderSide(color: PosTheme.primary),
            ),
          ),
        if (perm.canDelete('PosProducts'))
          OutlinedButton.icon(
            onPressed: _deleteProduct,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(tr('Xóa')),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        if (isGoods)
          OutlinedButton.icon(
            onPressed: _showStockCard,
            icon: const Icon(Icons.receipt_long, size: 18),
            label: Text(tr('Thẻ kho')),
            style: OutlinedButton.styleFrom(
              foregroundColor: PosTheme.textPrimary,
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => showPosBarcodeLabelDialog(context, [_product]),
          icon: const Icon(Icons.qr_code, size: 18),
          label: Text(tr('In tem mã')),
          style: OutlinedButton.styleFrom(
            foregroundColor: PosTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
