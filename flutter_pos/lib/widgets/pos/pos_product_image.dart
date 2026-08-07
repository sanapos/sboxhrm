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
    this.borderRadius = 4,
    this.fit = BoxFit.cover,
  });

  final String? productId;
  final String? imageUrl;
  final DateTime? updatedAt;
  final double size;
  final double borderRadius;
  final BoxFit fit;

  static final _api = ApiService();

  @override
  Widget build(BuildContext context) {
    final hasId = productId != null && productId!.isNotEmpty;
    final url = imageUrl?.trim();
    final hasUrl = url != null && url.isNotEmpty;

    if (!hasId && !hasUrl) {
      return _placeholder(size, borderRadius);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: _PosProductImageLoader(
        productId: productId,
        paths: [
          if (hasUrl) url,
          if (hasId) ApiService.posProductImagePath(productId!),
        ],
        cacheEpoch: updatedAt?.millisecondsSinceEpoch ?? 0,
        updatedAt: updatedAt,
        apiService: _api,
        size: size,
        fit: fit,
        placeholder: _placeholder(size, borderRadius),
      ),
    );
  }

  static Widget _placeholder(double size, double borderRadius) {
    return Container(
      width: size,
      height: size,
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
    required this.fit,
    required this.placeholder,
  });

  final String? productId;
  final List<String> paths;
  final int cacheEpoch;
  final DateTime? updatedAt;
  final ApiService apiService;
  final double size;
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
      if (mem != null && mem.isNotEmpty) {
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
      if (bytes != null && bytes.isNotEmpty) {
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

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.placeholder;
    if (_bytes == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (widget.size * dpr).round().clamp(1, 512);
    return Image.memory(
      _bytes!,
      width: widget.size,
      height: widget.size,
      fit: widget.fit,
      gaplessPlayback: true,
      cacheWidth: cachePx,
      cacheHeight: cachePx,
      errorBuilder: (_, __, ___) => widget.placeholder,
    );
  }
}
