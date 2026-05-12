import 'package:flutter/material.dart';

import 'landing_product_image_stub.dart'
    if (dart.library.html) 'landing_product_image_web.dart' as impl;

class LandingProductImage extends StatelessWidget {
  const LandingProductImage({
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
    return impl.LandingProductImageImpl(
      imageUrl: imageUrl,
      fit: fit,
      errorIconSize: errorIconSize,
    );
  }
}
