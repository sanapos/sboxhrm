import 'package:flutter/material.dart';

/// Panel trái đăng nhập POS — ảnh phủ kín 2/3, decode theo DPR để khỏi vỡ nét.
class SboxPosHeroPanel extends StatelessWidget {
  const SboxPosHeroPanel({super.key});

  static const green = Color(0xFF2E7D32);
  static const wallGreen = Color(0xFF1B4D3E);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: wallGreen,
      child: LayoutBuilder(
        builder: (context, c) {
          final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
          final cacheW = (c.maxWidth * dpr).round().clamp(1024, 2560);
          return SizedBox.expand(
            child: Image.asset(
              'assets/sbox_pos_login_hero.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.08),
              filterQuality: FilterQuality.medium,
              isAntiAlias: true,
              cacheWidth: cacheW,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/sbox_pos_poster.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                isAntiAlias: true,
              ),
            ),
          );
        },
      ),
    );
  }
}
