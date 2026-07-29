import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import 'auth_cached_image.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

bool isLikelyImageUrl(String url) {
  final raw = url.trim().toLowerCase();
  if (raw.isEmpty) return false;
  if (raw.startsWith('data:image')) return true;
  final path = Uri.tryParse(url.trim())?.path.toLowerCase() ?? raw;
  const exts = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.heic'];
  if (exts.any(path.endsWith) || exts.any(raw.contains)) return true;
  if (raw.contains('.pdf') || path.endsWith('.pdf')) return false;
  // Uploads from camera/gallery often have no extension in path.
  if (raw.contains('/upload') || raw.contains('image') || raw.contains('photo')) {
    return true;
  }
  return false;
}

/// Full-screen in-app image viewer (pinch-zoom). Prefer over external browser.
Future<void> showInAppImageViewer(
  BuildContext context, {
  required ApiService apiService,
  required List<String> urls,
  int initialIndex = 0,
  String title = 'Hình ảnh',
}) async {
  final cleaned = urls.map((u) => u.trim()).where((u) => u.isNotEmpty).toList();
  if (cleaned.isEmpty || !context.mounted) return;
  final start = initialIndex.clamp(0, cleaned.length - 1);

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) {
      final pageCtrl = PageController(initialPage: start);
      var current = start;
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: SizedBox(
              width: MediaQuery.sizeOf(ctx).width,
              height: MediaQuery.sizeOf(ctx).height,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: pageCtrl,
                    itemCount: cleaned.length,
                    onPageChanged: (i) => setDialogState(() => current = i),
                    itemBuilder: (_, i) => Center(
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 6,
                        panEnabled: true,
                        scaleEnabled: true,
                        boundaryMargin: const EdgeInsets.all(80),
                        child: AuthCachedImage(
                          imagePath: cleaned[i],
                          apiService: apiService,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                          errorWidget: (_, __, ___) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image,
                                  color: Colors.white54, size: 64),
                              SizedBox(height: 8),
                              Text(tr('Không tải được ảnh'),
                                  style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(ctx).top + 4,
                    left: 4,
                    right: 4,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 28),
                        ),
                        Expanded(
                          child: Text(
                            tr(cleaned.length > 1
                                ? '$title (${current + 1}/${cleaned.length})'
                                : title),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Open image in-app; non-images fall back to external app/browser.
Future<void> openAttachmentInApp(
  BuildContext context, {
  required ApiService apiService,
  required String? url,
  List<String>? galleryUrls,
  int initialIndex = 0,
  String title = 'Đính kèm',
}) async {
  final u = url?.trim() ?? '';
  if (u.isEmpty) return;

  if (isLikelyImageUrl(u)) {
    final gallery = (galleryUrls ?? [u])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && isLikelyImageUrl(e))
        .toList();
    final idx = gallery.indexOf(u);
    await showInAppImageViewer(
      context,
      apiService: apiService,
      urls: gallery.isEmpty ? [u] : gallery,
      initialIndex: idx >= 0 ? idx : initialIndex,
      title: title,
    );
    return;
  }

  final uri = Uri.tryParse(u);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Không mở được tệp đính kèm'))),
    );
  }
}
