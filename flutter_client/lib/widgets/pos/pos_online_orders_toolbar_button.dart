import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Một dòng đơn online chờ xử lý — hiển thị trên toolbar bán hàng.
class PosOnlineToolbarOrder {
  const PosOnlineToolbarOrder({
    required this.id,
    required this.orderNo,
    required this.customerName,
    required this.phone,
    required this.total,
    required this.statusLabel,
  });

  final String id;
  final String orderNo;
  final String customerName;
  final String phone;
  final double total;
  final String statusLabel;
}

/// Nút «Đơn online» trên thanh công cụ POS (cạnh Đặt lịch).
class PosOnlineOrdersToolbarButton extends StatelessWidget {
  const PosOnlineOrdersToolbarButton({
    super.key,
    required this.pending,
    required this.onOpenAll,
    required this.onOpenOrder,
    this.iconColor = Colors.white,
    this.labeled = true,
  });

  final List<PosOnlineToolbarOrder> pending;
  final VoidCallback onOpenAll;
  final ValueChanged<PosOnlineToolbarOrder> onOpenOrder;
  final Color iconColor;
  final bool labeled;

  static final _money = NumberFormat('#,##0', 'vi_VN');

  Future<void> _showQuickList(BuildContext context) async {
    if (pending.isEmpty) {
      onOpenAll();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  tr('Đơn online chờ xử lý'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: pending.length.clamp(0, 8),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final o = pending[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor:
                            PosTheme.kiotBlue.withValues(alpha: 0.12),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: PosTheme.kiotBlue,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        o.orderNo,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${o.customerName} · ${o.phone}\n${o.statusLabel}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '${_money.format(o.total)}₫',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFC2410C),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        onOpenOrder(o);
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onOpenAll();
                  },
                  child: Text(tr('Xem tất cả đơn online')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = pending.length;
    final badge = count > 0 ? (count > 99 ? '99+' : '$count') : null;

    if (!labeled) {
      return IconButton(
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        tooltip: tr('Đơn online'),
        onPressed: () => _showQuickList(context),
        icon: Badge(
          isLabelVisible: badge != null,
          label: badge != null ? Text(badge) : null,
          child: Icon(Icons.delivery_dining_outlined,
              size: 22, color: iconColor),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Badge(
        isLabelVisible: badge != null,
        label: badge != null ? Text(badge) : null,
        child: TextButton.icon(
          onPressed: () => _showQuickList(context),
          icon: Icon(Icons.delivery_dining_outlined,
              size: 18, color: iconColor),
          label: Text(
            tr('Đơn online'),
            style: TextStyle(
              color: iconColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: iconColor,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            side: BorderSide(color: iconColor.withValues(alpha: 0.45)),
          ),
        ),
      ),
    );
  }
}
