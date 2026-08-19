import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/pos_product_image_cache.dart';
import 'pos_theme.dart';

/// Ảnh sản phẩm POS — memory + disk cache (Android) + HTTP Bearer.
class PosProductImage extends StatelessWidget {
  const PosProductImage({
    super.key,
    this.productId,
    required this.imageUrl,
    this.updatedAt,
    this.size = 36,
    this.fill = false,
    this.borderRadius = 4,
    this.fit = BoxFit.cover,
  });

  final String? productId;
  final String? imageUrl;
  final DateTime? updatedAt;
  final double size;
  /// Ô lưới: chiếm hết chỗ, decode theo [size] (A6 không LayoutBuilder).
  final bool fill;
  final double borderRadius;
  final BoxFit fit;

  static final _api = ApiService();

  @override
  Widget build(BuildContext context) {
    final hasId = productId != null && productId!.isNotEmpty;
    final url = imageUrl?.trim();
    final hasUrl = url != null && url.isNotEmpty;

    if (!hasId && !hasUrl) {
      return _placeholder(size, borderRadius, fill: fill);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: _PosProductImageLoader(
        productId: productId,
        paths: [
          if (hasId) ApiService.posProductImagePath(productId!),
          if (hasUrl) url,
        ],
        cacheEpoch: updatedAt?.millisecondsSinceEpoch ?? 0,
        updatedAt: updatedAt,
        apiService: _api,
        size: size,
        fill: fill,
        fit: fit,
        placeholder: _placeholder(size, borderRadius, fill: fill),
      ),
    );
  }

  static Widget _placeholder(double size, double borderRadius, {bool fill = false}) {
    return Container(
      width: fill ? double.infinity : size,
      height: fill ? double.infinity : size,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: PosTheme.border),
      ),
      child: Icon(Icons.image_outlined,
          size: size * 0.45, color: Colors.grey.shade500),
    );
  }
}

class _PosProductImageLoader extends StatefulWidget {
  const _PosProductImageLoader({
    required this.productId,
    required this.paths,
    required this.cacheEpoch,
    required this.updatedAt,
    required this.apiService,
    required this.size,
    this.fill = false,
    required this.fit,
    required this.placeholder,
  });

  final String? productId;
  final List<String> paths;
  final int cacheEpoch;
  final DateTime? updatedAt;
  final ApiService apiService;
  final double size;
  final bool fill;
  final BoxFit fit;
  final Widget placeholder;

  @override
  State<_PosProductImageLoader> createState() => _PosProductImageLoaderState();
}

class _PosProductImageLoaderState extends State<_PosProductImageLoader> {
  Uint8List? _bytes;
  bool _failed = false;
  Object? _loadToken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PosProductImageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paths.join('|') != widget.paths.join('|') ||
        oldWidget.cacheEpoch != widget.cacheEpoch ||
        oldWidget.productId != widget.productId) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final token = Object();
    _loadToken = token;
    final cache = PosProductImageCacheManager.instance;
    final headers = <String, String>{
      ...?widget.apiService.imageAuthHeaders,
    };

    for (final path in widget.paths) {
      final url = widget.apiService.getFileUrl(path);
      if (url.isEmpty) continue;
      final key = PosProductImageCacheManager.cacheKey(
        productId: widget.productId,
        updatedAt: widget.updatedAt,
        path: path,
        cacheEpoch: widget.cacheEpoch,
      );
      final mem = cache.memoryGet(key);
      if (mem != null && mem.isNotEmpty && _looksLikeRasterImage(mem)) {
        if (!mounted || !identical(_loadToken, token)) return;
        setState(() {
          _bytes = mem;
          _failed = false;
        });
        return;
      }
      final bytes = await cache.loadBytes(
        url: url,
        key: key,
        headers: headers,
        cacheEpoch: widget.cacheEpoch,
      );
      if (!mounted || !identical(_loadToken, token)) return;
      if (bytes != null && bytes.isNotEmpty && _looksLikeRasterImage(bytes)) {
        setState(() {
          _bytes = bytes;
          _failed = false;
        });
        return;
      }
    }

    if (!mounted || !identical(_loadToken, token)) return;
    setState(() => _failed = true);
  }

  static bool _looksLikeRasterImage(Uint8List b) {
    if (b.length < 12) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
    if (b[0] == 0x89 && b[1] == 0x50) return true; // PNG
    if (b[0] == 0x47 && b[1] == 0x49) return true; // GIF
    if (b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57) return true; // WEBP
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.placeholder;
    if (_bytes == null) return widget.placeholder;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Chỉ cacheWidth: set cả Height sẽ vuông hóa JPEG (méo ảnh catalog mẫu landscape).
    // Tăng cacheWidth để ảnh không bị mờ khi hiển thị trong ô lưới nhỏ.
    // decode theo ~1.25x kích thước ô — cap 480px để A7 không đơ khi lưới nhiều ảnh.
    final cachePx = (widget.size * dpr * 1.25).round().clamp(96, 480);
    // PNG có thể có nền trong suốt — bọc nền trắng để ảnh không bị lẫn màu nền container.
    return ColoredBox(
      color: Colors.white,
      child: Image.memory(
        _bytes!,
        width: widget.fill ? double.infinity : widget.size,
        height: widget.fill ? double.infinity : widget.size,
        fit: widget.fit,
        gaplessPlayback: true,
        cacheWidth: cachePx,
        errorBuilder: (_, __, ___) => widget.placeholder,
      ),
    );
  }
}
