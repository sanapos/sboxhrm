import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
/// Hiển thị ảnh chấm (khuôn mặt / hiện trường); fallback avatar nếu có.
class PunchPhotoPreview extends StatefulWidget {
  const PunchPhotoPreview({
    super.key,
    required this.imagePath,
    this.fallbackPath,
    required this.apiService,
    this.aspectRatio = 4 / 3,
    this.compact = false,
    this.emptyHint,
  });

  final String? imagePath;
  final String? fallbackPath;
  final ApiService apiService;
  final double aspectRatio;
  final bool compact;
  final String? emptyHint;

  @override
  State<PunchPhotoPreview> createState() => _PunchPhotoPreviewState();
}

/// Thumbnail nhỏ trên danh sách.
/// [sitePhotoOnly]: chỉ ảnh CT — tránh hiển thị ảnh mặt rồi chi tiết báo «chưa có ảnh hiện trường».
class MobilePunchPhotoThumb extends StatelessWidget {
  const MobilePunchPhotoThumb({
    super.key,
    required this.sitePhotoUrl,
    required this.faceImageUrl,
    required this.apiService,
    this.size = 44,
    this.sitePhotoOnly = false,
  });

  final String? sitePhotoUrl;
  final String? faceImageUrl;
  final ApiService apiService;
  final double size;
  final bool sitePhotoOnly;

  @override
  Widget build(BuildContext context) {
    final path = sitePhotoOnly
        ? _firstNonEmpty(sitePhotoUrl, null)
        : _firstNonEmpty(sitePhotoUrl, faceImageUrl);
    if (path == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: SboxColors.slate100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: const Icon(Icons.image_not_supported_outlined,
            size: 20, color: SboxColors.slate400),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: PunchPhotoPreview(
          imagePath: path,
          fallbackPath: _firstNonEmpty(faceImageUrl, sitePhotoUrl),
          apiService: apiService,
          aspectRatio: 1,
          compact: true,
        ),
      ),
    );
  }

  static String? _firstNonEmpty(String? a, String? b) {
    final ta = a?.trim();
    if (ta != null && ta.isNotEmpty) return ta;
    final tb = b?.trim();
    if (tb != null && tb.isNotEmpty) return tb;
    return null;
  }
}

class _PunchPhotoPreviewState extends State<PunchPhotoPreview> {
  String? _resolvedPath;
  bool _loadFailed = false;

  static String? _trimmed(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  void initState() {
    super.initState();
    _resolvedPath = _trimmed(widget.imagePath) ?? _trimmed(widget.fallbackPath);
  }

  @override
  void didUpdateWidget(covariant PunchPhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath ||
        oldWidget.fallbackPath != widget.fallbackPath) {
      _loadFailed = false;
      _resolvedPath = _trimmed(widget.imagePath) ?? _trimmed(widget.fallbackPath);
    }
  }

  void _onLoadFailed() {
    final primary = _trimmed(widget.imagePath);
    final fallback = _trimmed(widget.fallbackPath);
    if (_resolvedPath == primary && fallback != null) {
      setState(() {
        _resolvedPath = fallback;
        _loadFailed = false;
      });
      return;
    }
    setState(() => _loadFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedPath == null) {
      if (widget.emptyHint == null) return const SizedBox.shrink();
      return _placeholderBox(
        child: Text(
          tr(widget.emptyHint!),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
        ),
      );
    }

    if (_loadFailed) {
      return _placeholderBox(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined,
                color: SboxColors.slate400, size: 36),
            if (!widget.compact) ...[
              const SizedBox(height: 8),
              Text(tr('Không tải được ảnh'),
                style: TextStyle(fontSize: 12, color: SboxColors.slate500),
              ),
            ],
          ],
        ),
      );
    }

    final url = widget.apiService.getFileUrl(_resolvedPath!);
    final image = CachedNetworkImage(
      key: ValueKey(url),
      imageUrl: url,
      httpHeaders: widget.apiService.imageAuthHeaders,
      fit: BoxFit.cover,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _onLoadFailed();
        });
        return _placeholderBox(
          child: const Icon(Icons.broken_image_outlined,
              color: SboxColors.slate400, size: 36),
        );
      },
    );

    if (widget.compact) return image;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: image,
      ),
    );
  }

  Widget _placeholderBox({required Widget child}) {
    if (widget.compact) {
      return ColoredBox(
        color: SboxColors.slate100,
        child: Center(child: child),
      );
    }
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: SboxColors.slate100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SboxColors.slate200),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
