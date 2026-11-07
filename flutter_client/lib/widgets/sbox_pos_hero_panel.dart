import 'package:flutter/material.dart';

import '../theme/sbox_tokens.dart';
/// Panel trái đăng nhập POS — ảnh phủ kín 2/3, decode theo DPR để khỏi vỡ nét.
class SboxPosHeroPanel extends StatelessWidget {
  const SboxPosHeroPanel({super.key});

  static const green = SboxColors.successText;
  /// Nền nhạt lúc ảnh chưa tải xong: khối xanh đậm trống trông như lỗi.
  static const placeholder = SboxColors.posApp ? SboxColors.brand50 : Color(0xFFF1F6F2);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: placeholder,
      child: LayoutBuilder(
        builder: (context, c) {
          final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
          final cacheW = (c.maxWidth * dpr).round().clamp(1024, 2560);
          return SizedBox.expand(
            child: Image.asset(
              SboxColors.posApp ? 'assets/sbox_pos_login_hero_gsm.webp' : 'assets/sbox_pos_login_hero.webp',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.08),
              filterQuality: FilterQuality.medium,
              isAntiAlias: true,
              cacheWidth: cacheW,
              gaplessPlayback: true,
              frameBuilder: (_, child, frame, wasSync) => wasSync
                  ? child
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      child: child,
                    ),
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
