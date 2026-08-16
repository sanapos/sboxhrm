import 'package:flutter/material.dart';

/// Thanh tab ngang POS (SBOX POS / Hàng hóa / Bán hàng / Đơn hàng…).
/// Đã tắt — điều hướng dùng rail hub / menu ☰.
class PosModuleToolbar extends StatelessWidget {
  const PosModuleToolbar({
    super.key,
    this.activeModule = 'PosProducts',
  });

  final String activeModule;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
