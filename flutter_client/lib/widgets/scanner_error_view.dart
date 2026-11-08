import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_tr.dart';

/// Lớp phủ trên MobileScanner (khung ngắm, nút đèn): ẩn khi camera lỗi để không đè lên [scannerErrorView].
class ScannerOverlayGate extends StatelessWidget {
  const ScannerOverlayGate({super.key, required this.controller, required this.child});

  final MobileScannerController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MobileScannerState>(
        valueListenable: controller,
        builder: (context, state, child) => state.error != null ? const SizedBox.shrink() : child!,
        child: child,
      );
}

/// Lỗi của màn quét mã bằng tiếng Việt. Mặc định plugin in thẳng câu tiếng Anh, vd «Camera permission denied.».
Widget scannerErrorView(BuildContext context, MobileScannerException error) {
  final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
  return ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(denied ? Icons.no_photography_outlined : Icons.error_outline, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          Text(
            tr(denied ? 'Chưa có quyền dùng camera' : 'Không mở được camera'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            tr(denied
                ? 'Camera chỉ dùng để quét mã. Cấp quyền trong Cài đặt của máy rồi mở lại màn này.'
                : 'Đóng màn này rồi mở lại. Nếu vẫn lỗi, kiểm tra app khác có đang dùng camera không.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          if (denied) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: Colors.white70),
              ),
              onPressed: openAppSettings,
              child: Text(tr('Mở Cài đặt')),
            ),
          ],
        ]),
      ),
    ),
  );
}
