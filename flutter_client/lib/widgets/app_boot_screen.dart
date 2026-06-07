import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';

/// Màn chờ khi [AuthProvider.isInitializing] — tránh Scaffold trắng trống trên iOS.
class AppBootScreen extends StatelessWidget {
  const AppBootScreen({super.key});

  static const Color _navy = ThemeProvider.primaryColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Image.asset(
                  'assets/logo.png',
                  width: 72,
                  height: 72,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.business_rounded,
                    size: 72,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'SBOX HRM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Đang tải…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
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
