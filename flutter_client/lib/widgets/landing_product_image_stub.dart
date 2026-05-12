import 'package:flutter/material.dart';

class LandingProductImageImpl extends StatelessWidget {
  const LandingProductImageImpl({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.errorIconSize = 48,
  });

  final String imageUrl;
  final BoxFit fit;
  final double errorIconSize;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      fit: fit,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : Container(
              color: const Color(0xFFF3F4F6),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFFF3F4F6),
        child: Icon(
          Icons.devices_rounded,
          size: errorIconSize,
          color: const Color(0xFFD1D5DB),
        ),
      ),
    );
  }
}
