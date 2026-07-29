import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/app_error_utils.dart';
import '../utils/navigation_notifier.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Màn hình thay thế [ErrorWidget] mặc định — tránh nền xanh/tối chung chung.
class AppFatalErrorScreen extends StatelessWidget {
  final FlutterErrorDetails details;

  const AppFatalErrorScreen({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    final info = AppErrorUtils.fromException(details.exception);
    final screen = NavigationNotifier.currentScreenLabel.value?.trim();
    final icon = switch (info.kind) {
      AppErrorKind.network => Icons.wifi_off_rounded,
      AppErrorKind.timeout => Icons.hourglass_disabled_rounded,
      AppErrorKind.server => Icons.cloud_off_rounded,
      AppErrorKind.unknown => Icons.error_outline_rounded,
    };
    final iconColor = switch (info.kind) {
      AppErrorKind.network => const Color(0xFFF59E0B),
      AppErrorKind.timeout => const Color(0xFF6366F1),
      AppErrorKind.server => const Color(0xFFEF4444),
      AppErrorKind.unknown => const Color(0xFFEF4444),
    };

    return Material(
      color: const Color(0xFFFAFAFA),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 56, color: iconColor),
                ),
                const SizedBox(height: 20),
                Text(
                  tr(info.title),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF18181B),
                  ),
                ),
                if (screen != null && screen.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(tr('Màn hình: $screen'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF71717A),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  tr(info.message),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: Color(0xFF52525B),
                  ),
                ),
                if (info.technicalHint != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Chi tiết lỗi (gửi ảnh màn hình này cho IT):'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF71717A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          tr(info.technicalHint!),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Color(0xFF3F3F46),
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (details.library != null) ...[
                          const SizedBox(height: 6),
                          Text(tr('Vị trí: ${details.library}'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFA1A1AA),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (kDebugMode && details.stack != null) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: Text(
                      tr('Stack trace (debug)'),
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      SelectableText(
                        tr(details.stack.toString()),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text(tr('Đóng app hoàn toàn rồi mở lại. Nếu lỗi lặp lại, chụp màn hình này và báo quản trị.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
