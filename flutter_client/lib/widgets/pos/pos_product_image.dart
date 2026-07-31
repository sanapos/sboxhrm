import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import 'pos_theme.dart';

/// Ảnh sản phẩm POS — tải qua HTTP + Bearer (ổn định trên web; CachedNetworkImage
/// hay fail khi cache/header trên browser).
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
        paths: [
          if (hasUrl) url,
          if (hasId) ApiService.posProductImagePath(productId!),
        ],
        cacheEpoch: updatedAt?.millisecondsSinceEpoch ?? 0,
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
    required this.paths,
    required this.cacheEpoch,
    required this.apiService,
    required this.size,
    required this.fit,
    required this.placeholder,
  });

  final List<String> paths;
  final int cacheEpoch;
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

  static final Map<String, Uint8List> _memoryCache = {};
  static const _maxMemoryEntries = 120;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PosProductImageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paths.join('|') != widget.paths.join('|') ||
        oldWidget.cacheEpoch != widget.cacheEpoch) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  String _cacheKey(String path) => '${path}_${widget.cacheEpoch}';

  Future<void> _load() async {
    final token = Object();
    _loadToken = token;

    for (final path in widget.paths) {
      final key = _cacheKey(path);
      final cached = _memoryCache[key];
      if (cached != null && cached.isNotEmpty) {
        if (!mounted || !identical(_loadToken, token)) return;
        setState(() {
          _bytes = cached;
          _failed = false;
        });
        return;
      }

      final url = widget.apiService.getFileUrl(path);
      if (url.isEmpty) continue;

      try {
        final headers = <String, String>{
          ...?widget.apiService.imageAuthHeaders,
        };
        // Web: tránh cache browser trả 401 cũ khi token đổi.
        final uri = kIsWeb
            ? Uri.parse(url).replace(
                queryParameters: {
                  ...Uri.parse(url).queryParameters,
                  '_': widget.cacheEpoch.toString(),
                },
              )
            : Uri.parse(url);
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 25));
        if (!mounted || !identical(_loadToken, token)) return;
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          _putMemory(key, response.bodyBytes);
          setState(() {
            _bytes = response.bodyBytes;
            _failed = false;
          });
          return;
        }
      } catch (_) {}
    }

    if (!mounted || !identical(_loadToken, token)) return;
    setState(() => _failed = true);
  }

  void _putMemory(String key, Uint8List bytes) {
    if (_memoryCache.length >= _maxMemoryEntries) {
      final first = _memoryCache.keys.first;
      _memoryCache.remove(first);
    }
    _memoryCache[key] = bytes;
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
