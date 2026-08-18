import 'package:flutter/material.dart';

import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Header cột giỏ hàng Kiot — tách khỏi PosSellScreen để tránh rebuild cả màn.
class PosSellKiotCartHeader extends StatelessWidget {
  const PosSellKiotCartHeader({
    super.key,
    required this.catalogColumnLabel,
    this.height = 28,
    this.sidePadding = 10,
    this.wDel = 28,
    this.wQty = 118,
    this.wUnit = 48,
    this.wPrice = 72,
    this.wTotal = 80,
  });

  final String catalogColumnLabel;
  final double height;
  final double sidePadding;
  final double wDel;
  final double wQty;
  final double wUnit;
  final double wPrice;
  final double wTotal;

  @override
  Widget build(BuildContext context) {
    const hdr = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: PosTheme.textSecondary,
    );
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: sidePadding),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: wDel),
          Expanded(child: Text(tr(catalogColumnLabel), style: hdr)),
          SizedBox(
            width: wQty,
            child: Text(tr('SL'), style: hdr, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: wUnit,
            child: Text(tr('ĐVT'), style: hdr, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: wPrice,
            child: Text(tr('Đơn giá'), style: hdr, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: wTotal,
            child: Text(tr('Thành tiền'), style: hdr, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class PosSellDraftSyncBar extends StatelessWidget {
  const PosSellDraftSyncBar({super.key, this.draftOrderNo});

  final String? draftOrderNo;

  @override
  Widget build(BuildContext context) {
    final no = draftOrderNo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: const Color(0xFFEFF6FF),
      child: Text(
        tr(no != null && no.isNotEmpty
            ? 'Đồng bộ server · $no · tự lưu khi sửa hàng'
            : 'Đồng bộ server · tự lưu khi sửa hàng'),
        style: const TextStyle(fontSize: 11, color: Color(0xFF1D4ED8)),
      ),
    );
  }
}

class PosSellMissingTimedServiceBanner extends StatelessWidget {
  const PosSellMissingTimedServiceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7ED),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.timer_off_outlined,
                size: 18, color: Color(0xFFC2410C)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Chưa có dịch vụ tính giờ trên đơn — thêm SP theo giờ hoặc cấu hình SP mặc định khi mở bàn.'),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9A3412),
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
