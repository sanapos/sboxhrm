import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/auth_provider.dart';

/// Thanh cảnh báo khi Super Admin đang đăng nhập thay tài khoản cửa hàng.
class ImpersonationBanner extends StatelessWidget {
  const ImpersonationBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isImpersonating) return child;
    return Column(children: [
      Material(
        color: const Color(0xFFB45309),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              const Icon(Icons.support_agent, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Đang đăng nhập thay: ${auth.impersonationLabel ?? ''} — mọi thao tác được ghi nhật ký'),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white24),
                onPressed: () => context.read<AuthProvider>().stopImpersonation(),
                child: Text(tr('Thoát')),
              ),
            ]),
          ),
        ),
      ),
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
    ]);
  }
}
