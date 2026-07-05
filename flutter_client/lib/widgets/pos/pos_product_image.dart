import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/pos_product_image_cache.dart';
import 'pos_theme.dart';

/// Ảnh sản phẩm POS — cache đĩa (productId + etag), fallback API image.
class PosProductImage extends StatelessWidget {
  const PosProductImage({
    super.key,
    this.productId,
    required this.imageUrl,
    this.updatedAt,
    this.size = 36,
    this.borderRadius = 4,
  });

  final String? productId;
  final String? imageUrl;
  final DateTime? updatedAt;
  final double size;
  final double borderRadius;

  static final _api = ApiService();

  String get _cacheKey => PosProductImageCacheManager.cacheKey(
        productId: productId,
        updatedAt: updatedAt,
        imageUrl: imageUrl,
      );

  @override
  Widget build(BuildContext context) {
    final hasId = productId != null && productId!.isNotEmpty;
    final url = imageUrl?.trim();
    final hasUrl = url != null && url.isNotEmpty;

    if (!hasId && !hasUrl) {
      return _placeholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: _PosProductImageLoader(
        paths: [
          if (hasUrl) url!,
          if (hasId) ApiService.posProductImagePath(productId!),
        ],
        cacheKey: _cacheKey,
        apiService: _api,
        size: size,
        placeholder: _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
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
    required this.paths,
    required this.cacheKey,
    required this.apiService,
    required this.size,
    required this.placeholder,
  });

  final List<String> paths;
  final String cacheKey;
  final ApiService apiService;
  final double size;
  final Widget placeholder;

  @override
  State<_PosProductImageLoader> createState() => _PosProductImageLoaderState();
}

class _PosProductImageLoaderState extends State<_PosProductImageLoader> {
  int _pathIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (_pathIndex >= widget.paths.length) {
      return widget.placeholder;
    }

    final path = widget.paths[_pathIndex];
    final url = widget.apiService.getFileUrl(path);
    if (url.isEmpty) {
      return widget.placeholder;
    }

    return CachedNetworkImage(
      key: ValueKey('${widget.cacheKey}_$_pathIndex'),
      imageUrl: url,
      cacheKey: widget.cacheKey,
      httpHeaders: widget.apiService.imageAuthHeaders,
      cacheManager: PosProductImageCacheManager.instance.manager,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      placeholder: (_, __) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (_, __, ___) {
        if (_pathIndex + 1 < widget.paths.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _pathIndex++);
          });
        }
        return widget.placeholder;
      },
    );
  }
}
