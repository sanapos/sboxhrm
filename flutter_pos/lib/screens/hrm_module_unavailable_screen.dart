import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Module HRM chưa có trong app POS độc lập — hướng người dùng sang SBOX HRM.
class HrmModuleUnavailableScreen extends StatelessWidget {
  const HrmModuleUnavailableScreen({
    super.key,
    required this.title,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr(title)),
        backgroundColor: Colors.white,
        foregroundColor: PosTheme.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: PosTheme.kiotBlueLight,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.groups_outlined,
                      size: 36, color: PosTheme.kiotBlue),
                ),
                const SizedBox(height: 16),
                Text(
                  tr(title),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: PosTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(description ??
                      'Chức năng HRM dùng chung được cấu hình trên ứng dụng SBOX HRM. '
                      'App POS tập trung bán hàng, kho và thiết lập cửa hàng.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: PosTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('https://sboxhrm.com');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: PosTheme.kiotBlue,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(tr('Mở SBOX HRM')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
