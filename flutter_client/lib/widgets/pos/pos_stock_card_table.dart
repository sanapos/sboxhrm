import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/responsive_helper.dart';
import '../../models/pos_product.dart';
import 'pos_mobile_widgets.dart';
import 'pos_theme.dart';

/// Bảng thẻ kho kiểu KiotViet: chứng từ, thời gian, loại GD, số lượng, tồn cuối.
class PosStockCardTable extends StatelessWidget {
  const PosStockCardTable({
    super.key,
    required this.items,
    required this.moneyFmt,
    required this.dateFmt,
    this.onDocumentTap,
    this.onExport,
  });

  final List<PosStockTransaction> items;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;
  final void Function(PosStockTransaction tx)? onDocumentTap;
  final VoidCallback? onExport;

  static String txTypeLabel(String raw, {String? referenceNo, String? note}) {
    if (referenceNo != null && referenceNo.startsWith('CP')) {
      return 'Cập nhật giá vốn';
    }
    if (referenceNo != null && referenceNo.startsWith('KK')) {
      return 'Kiểm kê kho';
    }
    if (referenceNo != null && referenceNo.startsWith('TH')) {
      return 'Trả hàng';
    }
    if (note != null && note.contains('Cập nhật giá vốn')) {
      return 'Cập nhật giá vốn';
    }
    switch (raw) {
      case 'StockIn':
        return 'Nhập kho';
      case 'StockOut':
        return 'Xuất kho';
      case 'Adjust':
      case 'Adjustment':
        return 'Điều chỉnh tồn';
      case 'Sale':
        return 'Bán hàng';
      case 'Purchase':
        return 'Mua hàng';
      case 'Return':
        return 'Trả hàng';
      case 'PurchaseReturn':
        return 'Trả NCC';
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'Chưa có biến động tồn kho',
          style: TextStyle(fontSize: 13, color: PosTheme.textSecondary),
        ),
      );
    }

    if (posUseMobileList(context)) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        children: [
          if (onExport != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Xuất file'),
              ),
            ),
          ...items.map((t) => _mobileCard(t)),
        ],
      );
    }

    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: PosTheme.textSecondary,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onExport != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Xuất file'),
                  ),
                ),
              ),
            Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Row(
                children: [
                  SizedBox(width: 100, child: Text('Chứng từ', style: headerStyle)),
                  SizedBox(width: 120, child: Text('Thời gian', style: headerStyle)),
                  Expanded(flex: 2, child: Text('Loại giao dịch', style: headerStyle)),
                  SizedBox(width: 72, child: Text('Số lượng', style: headerStyle, textAlign: TextAlign.right)),
                  SizedBox(width: 72, child: Text('Tồn cuối', style: headerStyle, textAlign: TextAlign.right)),
                  SizedBox(width: 100, child: Text('Đối tác', style: headerStyle)),
                ],
              ),
            ),
            ...items.map(_row),
          ],
        ),
      ),
    );
  }

  Widget _mobileCard(PosStockTransaction t) {
    final sign = t.qtyChange > 0 ? '+' : '';
    final qtyColor = t.qtyChange < 0
        ? const Color(0xFFE53935)
        : (t.qtyChange > 0 ? const Color(0xFF2E7D32) : PosTheme.textPrimary);
    final doc = t.referenceNo?.trim();
    final when = t.createdAt != null ? dateFmt.format(t.createdAt!) : '—';
  final typeLabel = txTypeLabel(t.transactionType,
        referenceNo: t.referenceNo, note: t.note);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: doc != null && doc.isNotEmpty
                    ? InkWell(
                        onTap: onDocumentTap == null
                            ? null
                            : () => onDocumentTap!(t),
                        child: Text(doc,
                            style: const TextStyle(
                                color: PosTheme.kiotBlue,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      )
                    : Text('—',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500)),
              ),
              Text(when,
                  style: const TextStyle(
                      fontSize: 11, color: PosTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(typeLabel, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('SL: $sign${moneyFmt.format(t.qtyChange)}',
                    style: TextStyle(
                        fontSize: 13,
                        color: qtyColor,
                        fontWeight: FontWeight.w600)),
              ),
              Text('Tồn: ${moneyFmt.format(t.qtyAfter)}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
          if (t.partnerName?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(t.partnerName!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ],
      ),
    );
  }

  Widget _row(PosStockTransaction t) {
    final sign = t.qtyChange > 0 ? '+' : '';
    final qtyColor = t.qtyChange < 0
        ? const Color(0xFFE53935)
        : (t.qtyChange > 0 ? const Color(0xFF2E7D32) : PosTheme.textPrimary);
    final doc = t.referenceNo?.trim();
    final when = t.createdAt != null
        ? dateFmt.format(t.createdAt!)
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: doc != null && doc.isNotEmpty
                ? InkWell(
                    onTap: onDocumentTap == null ? null : () => onDocumentTap!(t),
                    child: Text(
                      doc,
                      style: const TextStyle(
                        fontSize: 12,
                        color: PosTheme.kiotBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : Text(
                    '—',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
          ),
          SizedBox(
            width: 120,
            child: Text(when, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              txTypeLabel(t.transactionType,
                  referenceNo: t.referenceNo, note: t.note),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              '$sign${moneyFmt.format(t.qtyChange)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: qtyColor, fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              moneyFmt.format(t.qtyAfter),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              t.partnerName?.trim().isNotEmpty == true ? t.partnerName! : '—',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
