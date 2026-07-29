import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import 'sbox_hrm_brand.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Màn chờ khi [AuthProvider.isInitializing] — brand SBOX, không dùng POS palette.
class AppBootScreen extends StatelessWidget {
  const AppBootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
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
              const SizedBox(height: AppSpace.xxl),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                tr('Đang tải…'),
                style: const TextStyle(
                  color: AppColors.textSecondary,
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
