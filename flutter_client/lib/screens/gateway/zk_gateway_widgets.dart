import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/zk_gateway.dart';
import '../../widgets/hrm_page_chrome.dart';

/// Cột vạch tín hiệu WiFi 1..4 vạch.
class WifiSignalBars extends StatelessWidget {
  const WifiSignalBars({super.key, required this.bars, this.color});

  final int bars;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final active = color ?? const Color(0xFF16A34A);
    return SizedBox(
      width: 22,
      height: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          final on = i < bars;
          return Container(
            width: 3.5,
            height: 5.0 + i * 3.5,
            margin: EdgeInsets.only(right: i == 3 ? 0 : 2),
            decoration: BoxDecoration(
              color: on ? active : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// Chip trạng thái nhỏ: chấm màu + nhãn.
class GatewayStatusChip extends StatelessWidget {
  const GatewayStatusChip({
    super.key,
    required this.label,
    required this.ok,
    this.okColor,
  });

  final String label;
  final bool ok;
  final Color? okColor;

  @override
  Widget build(BuildContext context) {
    final color = ok ? (okColor ?? const Color(0xFF16A34A)) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            tr(label),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ô hiển thị một cặp nhãn/giá trị trong lưới trạng thái.
class GatewayInfoTile extends StatelessWidget {
  const GatewayInfoTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(label),
            style: const TextStyle(
              fontSize: 11,
              color: HrmPageChrome.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: HrmPageChrome.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Khối chỉ dẫn màu xanh nhạt, dùng cho hướng dẫn từng bước.
class GatewayNoteBox extends StatelessWidget {
  const GatewayNoteBox({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.color,
  });

  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? HrmPageChrome.primaryNavy;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(text),
              style: const TextStyle(
                fontSize: 12.8,
                height: 1.45,
                color: HrmPageChrome.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thẻ một gateway trong danh sách.
class GatewayCard extends StatelessWidget {
  const GatewayCard({super.key, required this.info, required this.onTap});

  final ZkGatewayInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final healthy = info.isHealthy;
    final accent = healthy ? const Color(0xFF16A34A) : const Color(0xFFF59E0B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.router, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: HrmPageChrome.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (info.ip.isNotEmpty) info.ip,
                          if (info.deviceIp.isNotEmpty) 'ZK ${info.deviceIp}',
                          if (info.gatewayTag.isNotEmpty) '#${info.gatewayTag}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: HrmPageChrome.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                GatewayStatusChip(
                  label: info.wifiConnected ? 'WiFi OK' : 'Mất WiFi',
                  ok: info.wifiConnected,
                ),
                GatewayStatusChip(
                  label: info.deviceOnline ? 'Máy chấm công OK' : 'Mất máy chấm công',
                  ok: info.deviceOnline,
                ),
                GatewayStatusChip(
                  label: info.serverOnline ? 'Máy chủ OK' : 'Mất máy chủ',
                  ok: info.serverOnline,
                ),
                if (!info.provisioned)
                  const GatewayStatusChip(label: 'Chưa cấu hình', ok: false),
                if (info.apSsid.isNotEmpty)
                  GatewayStatusChip(
                    label: info.apSsid,
                    ok: true,
                    okColor: HrmPageChrome.primaryNavy,
                  ),
              ],
            ),
            if (info.serial.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '${tr('Số seri máy')}: ${info.serial}'
                '${info.host.isNotEmpty && info.host != 'sboxadms' ? ' · ${info.host}.local' : ''}',
                style: const TextStyle(
                  fontSize: 11.8,
                  color: HrmPageChrome.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
