import 'package:flutter/material.dart';

import 'pos/pos_theme.dart';
import '../l10n/app_tr.dart';

/// Nhận diện thương hiệu dùng chung HRM + POS.
abstract final class SboxBrand {
  static const productLine = 'SBOX HRM - SBOX POS';
  static const slogan = 'Giải pháp quản lý toàn diện cho doanh nghiệp';
}

/// Logo vector SBOX — sắc nét, không phụ thuộc PNG nhỏ bị scale mờ.
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

  static const String slogan = SboxBrand.slogan;

  @override
  Widget build(BuildContext context) {
    final titleColor = darkText ? PosTheme.textPrimary : Colors.white;
    final subtitleColor = darkText
        ? PosTheme.textSecondary
        : Colors.white.withOpacity(0.88);
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
                color: PosTheme.kiotBlue.withOpacity(0.32),
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
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.point_of_sale_rounded,
                    color: Colors.white,
                    size: logoSize * 0.36,
                  ),
                  SizedBox(height: logoSize * 0.03),
                  Text(
                    tr('SBOX'),
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
        SizedBox(height: logoSize * 0.22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            tr(SboxBrand.productLine),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor,
              fontSize: (logoSize * 0.20).clamp(16.0, 22.0),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              height: 1.25,
            ),
          ),
        ),
        if (showSlogan) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              tr(SboxBrand.slogan),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: subtitleColor,
                fontSize: 13,
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

/// Logo PNG + tên sản phẩm (đăng nhập, sidebar, header).
class SboxBrandLockup extends StatelessWidget {
  const SboxBrandLockup({
    super.key,
    this.logoSize = 44,
    this.showSlogan = true,
    this.titleSize = 18,
    this.sloganSize = 11,
    this.titleColor = const Color(0xFF0C56D0),
    this.sloganColor,
    this.alignment = MainAxisAlignment.start,
    this.expandText = true,
  });

  final double logoSize;
  final bool showSlogan;
  final double titleSize;
  final double sloganSize;
  final Color titleColor;
  final Color? sloganColor;
  final MainAxisAlignment alignment;
  /// `false` khi nằm trong FittedBox (đăng nhập) — tránh Expanded unbounded.
  final bool expandText;

  @override
  Widget build(BuildContext context) {
    final muted = sloganColor ?? titleColor.withOpacity(0.62);
    final text = Column(
      crossAxisAlignment: alignment == MainAxisAlignment.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr(SboxBrand.productLine),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: titleColor,
            letterSpacing: -0.2,
            height: 1.15,
          ),
        ),
        if (showSlogan) ...[
          const SizedBox(height: 2),
          Text(
            tr(SboxBrand.slogan),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: sloganSize,
              fontWeight: FontWeight.w500,
              color: muted,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
    return Row(
      mainAxisAlignment: alignment,
      mainAxisSize: expandText ? MainAxisSize.max : MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(logoSize * 0.22),
          child: Image.asset(
            'assets/logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.point_of_sale_rounded,
              color: titleColor,
              size: logoSize,
            ),
          ),
        ),
        SizedBox(width: logoSize * 0.28),
        if (expandText) Expanded(child: text) else text,
      ],
    );
  }
}
