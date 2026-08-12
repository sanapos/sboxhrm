import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import 'pos/pos_theme.dart';

/// Thẻ hiển thị thông tin liên hệ đại lý hỗ trợ (Zalo / SĐT / email).
/// Tone xanh POS (không dùng cam/đỏ HRM).
class StoreAgentSupportCard extends StatelessWidget {
  const StoreAgentSupportCard({
    super.key,
    required this.agentName,
    this.agentCode,
    this.phone,
    this.email,
    this.address,
    this.zaloUrl,
    this.compact = false,
  });

  final String agentName;
  final String? agentCode;
  final String? phone;
  final String? email;
  final String? address;
  final String? zaloUrl;
  final bool compact;

  factory StoreAgentSupportCard.fromMap(
    Map<String, dynamic> data, {
    bool compact = false,
  }) {
    return StoreAgentSupportCard(
      agentName: data['agentName']?.toString() ?? data['name']?.toString() ?? 'Đại lý',
      agentCode: data['agentCode']?.toString() ?? data['code']?.toString(),
      phone: data['phone']?.toString(),
      email: data['email']?.toString(),
      address: data['address']?.toString(),
      zaloUrl: data['zaloUrl']?.toString(),
      compact: compact,
    );
  }

  String? get _zaloDigits {
    final raw = zaloUrl ?? phone;
    if (raw == null || raw.isEmpty) return null;
    return raw
        .replaceAll('https://zalo.me/', '')
        .replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _openZalo() async {
    final digits = _zaloDigits;
    if (digits == null || digits.isEmpty) return;
    final uri = Uri.parse('https://zalo.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openTel() async {
    if (phone == null || phone!.isEmpty) return;
    final digits = phone!.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse(
      'tel:+84${digits.startsWith('0') ? digits.substring(1) : digits}',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone != null && phone!.isNotEmpty;
    final hasZalo = _zaloDigits != null && _zaloDigits!.isNotEmpty;
    final codeLabel = agentCode != null && agentCode!.isNotEmpty
        ? '$agentName ($agentCode)'
        : agentName;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: PosTheme.kiotBlueLight,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(color: PosTheme.kiotBlue.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.support_agent_rounded,
                  color: PosTheme.kiotBlue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Đại lý hỗ trợ: $codeLabel'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: PosTheme.kiotBlue,
                  ),
                ),
              ),
            ],
          ),
          if (!compact && address != null && address!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              tr(address!),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          ],
          if (!compact && email != null && email!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              tr(email!),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          ],
          if (hasPhone || hasZalo) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hasPhone)
                  OutlinedButton.icon(
                    onPressed: _openTel,
                    icon: const Icon(Icons.phone_rounded, size: 16),
                    label: Text(tr(phone!)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PosTheme.kiotBlue,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: PosTheme.kiotBlue.withOpacity(0.45)),
                    ),
                  ),
                if (hasZalo)
                  FilledButton.icon(
                    onPressed: _openZalo,
                    icon: const Icon(Icons.chat_rounded, size: 16),
                    label: Text(
                      tr(compact ? 'Chat Zalo' : 'Zalo hỗ trợ: ${phone ?? ''}'),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: PosTheme.kiotBlue,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
