import 'package:flutter/material.dart';

import 'pos/pos_theme.dart';
import 'sbox_hrm_brand.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Màn chờ khi [AuthProvider.isInitializing] — tránh Scaffold trắng trống trên iOS.
class AppBootScreen extends StatelessWidget {
  const AppBootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SboxHrmBrandMark(
                logoSize: 96,
                showSlogan: true,
                darkText: true,
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: PosTheme.kiotBlue,
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('Đang tải…'),
                style: TextStyle(
                  color: PosTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
