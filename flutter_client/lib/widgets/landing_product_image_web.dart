import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class LandingProductImageImpl extends StatefulWidget {
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
  State<LandingProductImageImpl> createState() =>
      _LandingProductImageImplState();
}

class _LandingProductImageImplState extends State<LandingProductImageImpl> {
  static int _nextId = 0;

  late final String _viewType;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'landing-product-image-${_nextId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final img = web.HTMLImageElement()
        ..src = widget.imageUrl
        ..alt = 'product image'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        ..style.objectFit = _cssObjectFit(widget.fit)
        ..style.backgroundColor = '#F3F4F6';
      img.onError.listen((_) {
        if (mounted) setState(() => _failed = true);
      });
      return img;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || widget.imageUrl.trim().isEmpty) {
      return Container(
        color: const Color(0xFFF3F4F6),
        child: Icon(
          Icons.devices_rounded,
          size: widget.errorIconSize,
          color: const Color(0xFFD1D5DB),
        ),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }

  String _cssObjectFit(BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        return 'contain';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.fitHeight:
        return 'scale-down';
      case BoxFit.fitWidth:
        return 'scale-down';
      case BoxFit.none:
        return 'none';
      case BoxFit.scaleDown:
        return 'scale-down';
      case BoxFit.cover:
        return 'cover';
    }
  }
}
