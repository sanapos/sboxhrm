import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';

/// Ảnh lưu trên server (stores/uploads qua /api/upload/serve) hoặc data:image base64.
class AuthCachedImage extends StatefulWidget {
  const AuthCachedImage({
    super.key,
    required this.imagePath,
    required this.apiService,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  final String imagePath;
  final ApiService apiService;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  @override
  State<AuthCachedImage> createState() => _AuthCachedImageState();
}

class _AuthCachedImageState extends State<AuthCachedImage> {
  Uint8List? _bytes;
  bool _failed = false;
  String? _resolvedPath;

  static bool _isDataUrl(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('data:image');
  }

  static Uint8List? _decodeDataUrl(String path) {
    try {
      final comma = path.indexOf(',');
      if (comma < 0) return null;
      return base64Decode(path.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _resolvedPath = widget.imagePath.trim();
    _load();
  }

  @override
  void didUpdateWidget(covariant AuthCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _bytes = null;
      _failed = false;
      _resolvedPath = widget.imagePath.trim();
      _load();
    }
  }

  Future<void> _load() async {
    final trimmed = _resolvedPath ?? '';
    if (trimmed.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    if (_isDataUrl(trimmed)) {
      final bytes = _decodeDataUrl(trimmed);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _failed = bytes == null || bytes.isEmpty;
      });
      return;
    }

    final url = widget.apiService.getFileUrl(trimmed);
    if (url.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    try {
      final headers = <String, String>{
        ...?widget.apiService.imageAuthHeaders,
      };
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        setState(() {
          _bytes = response.bodyBytes;
          _failed = false;
        });
      } else {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _resolvedPath ?? '';
    if (path.isEmpty) {
      return widget.errorWidget?.call(context, '', null) ??
          const SizedBox.shrink();
    }

    if (_failed) {
      return widget.errorWidget?.call(context, path, null) ??
          const Icon(Icons.broken_image, color: Color(0xFF71717A));
    }

    if (_bytes == null) {
      return widget.placeholder?.call(context, path) ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
    }

    return Image.memory(
      _bytes!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      errorBuilder: (_, __, ___) =>
          widget.errorWidget?.call(context, path, null) ??
          const Icon(Icons.broken_image, color: Color(0xFF71717A)),
    );
  }
}

/// Avatar nhân viên / ảnh đại diện qua /api/upload/serve.
class AuthCircleAvatar extends StatelessWidget {
  const AuthCircleAvatar({
    super.key,
    required this.apiService,
    this.imagePath,
    this.radius = 18,
    this.backgroundColor,
    this.child,
    this.onBackgroundImageError,
  });

  final ApiService apiService;
  final String? imagePath;
  final double radius;
  final Color? backgroundColor;
  final Widget? child;
  final ImageErrorListener? onBackgroundImageError;

  @override
  Widget build(BuildContext context) {
    final path = imagePath?.trim();
    final hasImage = path != null && path.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage:
          hasImage ? apiService.storeImageProvider(path!) : null,
      onBackgroundImageError: hasImage ? onBackgroundImageError : null,
      child: child,
    );
  }
}
