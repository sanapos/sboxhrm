import 'package:flutter/material.dart';

import 'pos/pos_theme.dart';

/// Logo vector SBOX HRM — sắc nét, không phụ thuộc PNG nhỏ bị scale mờ.
class SboxHrmBrandMark extends StatelessWidget {
  const SboxHrmBrandMark({
    super.key,
    this.logoSize = 88,
    this.showSlogan = true,
    this.darkText = false,
  });

  final double logoSize;
  final bool showSlogan;
  final bool darkText;

  static const String slogan = 'Chấm công nhanh - Tính lương chuẩn';

  @override
  Widget build(BuildContext context) {
    final titleColor =
        darkText ? PosTheme.textPrimary : Colors.white;
    final subtitleColor = darkText
        ? PosTheme.textSecondary
        : Colors.white.withValues(alpha: 0.88);
    final radius = logoSize * 0.22;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0070F4), Color(0xFF0056C7)],
            ),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: PosTheme.kiotBlue.withValues(alpha: 0.32),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: logoSize * 0.1,
                left: logoSize * 0.14,
                child: Container(
                  width: logoSize * 0.38,
                  height: logoSize * 0.16,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: logoSize * 0.36,
                  ),
                  SizedBox(height: logoSize * 0.03),
                  Text(
                    'SBOX',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: logoSize * 0.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: logoSize * 0.26),
        Text(
          'SBOX HRM',
          style: TextStyle(
            color: titleColor,
            fontSize: logoSize * 0.26,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        if (showSlogan) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              slogan,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: subtitleColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
