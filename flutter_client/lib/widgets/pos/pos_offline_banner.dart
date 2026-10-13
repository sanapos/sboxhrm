import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../screens/pos/pos_offline_sales_screen.dart';
import '../../services/pos_network_monitor.dart';
import '../../services/pos_offline_service.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Thanh trạng thái mạng trên màn bán hàng: mất kết nối máy chủ / đang gửi đơn offline / đơn offline lỗi.
class PosOfflineBanner extends StatelessWidget {
  const PosOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final mon = PosNetworkMonitor.instance;
    final off = PosOfflineService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([
        mon.reachable,
        off.pendingSales,
        off.errorSales,
        off.pendingCarts,
        off.enabledNotifier,
      ]),
      builder: (context, _) {
        final online = mon.reachable.value;
        final pending = off.pendingSales.value;
        final errors = off.errorSales.value;
        final carts = off.pendingCarts.value;
        String? text;
        Color? bg;
        IconData icon = Icons.cloud_off;
        if (!online) {
          final since = mon.offlineSince;
          final mode = off.enabled
              ? (off.offlineSaleBlockedReason() == null
                  ? 'Bán offline: BẬT (tiền mặt, còn ${off.remainingSerials} số HĐ)'
                  : 'Bán offline: không dùng được')
              : 'Chưa bật bán offline — chỉ giữ giỏ hàng';
          text = 'Mất kết nối máy chủ${since == null ? '' : ' từ ${DateFormat('HH:mm').format(since)}'}'
              '${mon.simulateOffline ? ' (giả lập)' : ''} · giỏ hàng giữ trên máy · $mode'
              '${pending > 0 ? ' · $pending đơn offline chờ gửi' : ''}';
          bg = const Color(0xFFC62828);
        } else if (errors > 0) {
          text = '$errors đơn offline lỗi đồng bộ — bấm để xem, xử lý rồi gửi lại';
          bg = const Color(0xFFE65100);
          icon = Icons.error_outline;
        } else if (pending > 0 || carts > 0) {
          text = 'Có mạng lại — đang gửi'
              '${pending > 0 ? ' $pending đơn offline' : ''}'
              '${carts > 0 ? '${pending > 0 ? ',' : ''} $carts giỏ hàng chưa lưu' : ''}'
              ' lên máy chủ…';
          bg = const Color(0xFF1565C0);
          icon = Icons.cloud_upload_outlined;
        }
        if (text == null) return const SizedBox.shrink();
        return Material(
          color: bg,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PosOfflineSalesScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(text),
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
