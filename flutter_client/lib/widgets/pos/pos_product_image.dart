import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/pos_product_image_cache.dart';
import 'pos_theme.dart';

import '../../theme/sbox_tokens.dart';
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
          if (hasUrl) url,
          if (hasId) ApiService.posProductImagePath(productId!),
        ],
        cacheEpoch: PosProductImageCacheManager.imageEpoch(
          imageUrl: url,
          updatedAt: updatedAt,
        ),
        updatedAt: null,
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
          size: size * 0.45, color: SboxColors.slate500),
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
      final ownHost = url.startsWith(ApiService.baseUrl);
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
        headers: ownHost ? headers : const {},
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
    if (!widget.fill) return _image(context, widget.size, widget.size);
    // Ô lưới: giải mã theo kích thước THẬT của ô (trước đây theo size=96 cố định →
    // ~120px trên màn PC rồi phóng to lên ô 200–300px ⇒ ảnh mờ).
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : widget.size;
      final h = c.maxHeight.isFinite ? c.maxHeight : widget.size;
      return _image(context, w, h);
    });
  }

  Widget _image(BuildContext context, double boxW, double boxH) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Giải mã giữ đúng tỉ lệ ảnh, vừa trong khung vuông cạnh S. Với BoxFit.cover, ảnh ngang/dọc
    // tới 1,5:1 vẫn phủ kín ô mà không phải phóng to. Ảnh gốc nhỏ hơn S thì không phóng to
    // (allowUpscaling mặc định false). Trần 1024px (ảnh lưu tối đa 1200px) để lưới nhiều ảnh
    // trên máy yếu không tốn RAM: ô 200px ở dpr 1 → ~300px.
    final longest = boxW > boxH ? boxW : boxH;
    final factor = widget.fit == BoxFit.cover ? 1.5 : 1.0;
    final target = (longest * dpr * factor).round().clamp(96, 1024);
    // PNG có thể có nền trong suốt — bọc nền trắng để ảnh không bị lẫn màu nền container.
    return ColoredBox(
      color: Colors.white,
      child: Image(
        image: ResizeImage(
          MemoryImage(_bytes!),
          width: target,
          height: target,
          policy: ResizeImagePolicy.fit,
        ),
        width: widget.fill ? double.infinity : widget.size,
        height: widget.fill ? double.infinity : widget.size,
        fit: widget.fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => widget.placeholder,
      ),
    );
  }
}
