import 'package:flutter/material.dart';

/// Empty-state cột giỏ: logo SBox POS hơi mờ khi chưa chọn bàn / chưa có món.
class PosEmptyCartBrand extends StatelessWidget {
  const PosEmptyCartBrand({
    super.key,
    this.hint,
    this.below,
    this.logoWidth = 168,
  });

  final String? hint;
  final Widget? below;
  final double logoWidth;

  static const assetPath = 'assets/sbox_pos_logo.png';
  static const opacity = 0.72;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: opacity,
              child: Image.asset(
                assetPath,
                width: logoWidth,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            if (hint != null && hint!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ],
            if (below != null) ...[
              const SizedBox(height: 16),
              below!,
            ],
          ],
        ),
      ),
    );
  }
}
