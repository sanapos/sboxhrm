import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/comm_v2.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Nhân viên rút gọn cho chọn đối tượng nhận / @nhắc tên.
class CommPerson {
  const CommPerson({required this.employeeId, this.userId, required this.name, this.branchId, this.departmentId, this.position, this.photo});
  final String employeeId;
  final String? userId;
  final String name;
  final String? branchId;
  final String? departmentId;
  final String? position;
  final String? photo;
}

/// Dữ liệu dùng chung giữa bảng tin, trình soạn thảo, chi tiết bài.
class CommContext {
  CommContext({
    required this.isManager,
    required this.channels,
    this.people = const [],
    this.branches = const [],
    this.departments = const [],
    this.myName = '',
    this.myUserId,
    bool? canManageChannels,
  }) : canManageChannels = canManageChannels ?? isManager;

  /// Người kiểm duyệt: quyền Truyền thông «Duyệt» hoặc «Sửa» (ghim, duyệt, đối tượng nhận, bắt buộc đọc).
  final bool isManager;
  /// Quản lý kênh (cấp quản lý trở lên).
  final bool canManageChannels;
  List<CommChannel> channels;
  final List<CommPerson> people;
  final List<({String id, String name})> branches;
  final List<({String id, String name})> departments;
  final String myName;
  final String? myUserId;

  List<String> get positions {
    final set = <String>{};
    for (final p in people) {
      final v = p.position?.trim();
      if (v != null && v.isNotEmpty) set.add(v);
    }
    return set.toList()..sort();
  }

  CommChannel? channel(String? id) => channels.where((c) => c.id == id).firstOrNull;
}

String commUrl(String url) {
  if (url.startsWith('http')) return url;
  final base = ApiService.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}

Future<void> commOpenUrl(String url) async {
  final uri = Uri.tryParse(commUrl(url));
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

void commToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(tr(message)),
    backgroundColor: error ? SboxColors.danger : null,
    behavior: SnackBarBehavior.floating,
  ));
}

String commInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return '${parts[parts.length - 2].characters.first}${parts.last.characters.first}'.toUpperCase();
}

class CommAvatar extends StatelessWidget {
  const CommAvatar({super.key, required this.name, this.photo, this.size = 40});
  final String name;
  final String? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = SboxChartColors.at(name.hashCode.abs() % 5);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Text(commInitials(name), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.36)),
    );
    if (photo == null || photo!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(commUrl(photo!), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
    );
  }
}

/// Nội dung bài (HTML đã được máy chủ làm sạch).
class CommHtml extends StatelessWidget {
  const CommHtml({super.key, required this.html, this.maxLines});
  final String html;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Html(
      data: html,
      onLinkTap: (url, _, __) {
        if (url != null) commOpenUrl(url);
      },
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: FontSize(15),
          lineHeight: const LineHeight(1.6),
          color: SboxColors.text,
          maxLines: maxLines,
          textOverflow: maxLines == null ? null : TextOverflow.ellipsis,
        ),
        'h1': Style(fontSize: FontSize(22), fontWeight: FontWeight.w700, margin: Margins.only(top: 12, bottom: 6)),
        'h2': Style(fontSize: FontSize(19), fontWeight: FontWeight.w700, margin: Margins.only(top: 12, bottom: 6)),
        'h3': Style(fontSize: FontSize(16.5), fontWeight: FontWeight.w700, margin: Margins.only(top: 10, bottom: 4)),
        'p': Style(margin: Margins.only(bottom: 8)),
        'blockquote': Style(
          margin: Margins.only(left: 0, bottom: 8),
          padding: HtmlPaddings.only(left: 12),
          border: const Border(left: BorderSide(color: SboxColors.brand300, width: 3)),
          color: SboxColors.textSecondary,
        ),
        'a': Style(color: SboxColors.brand700),
        'li': Style(margin: Margins.only(bottom: 4)),
      },
    );
  }
}

/// Dòng tệp đính kèm: biểu tượng theo loại, tên, dung lượng; bấm để mở / tải.
class CommFileTile extends StatelessWidget {
  const CommFileTile({super.key, required this.file, this.onRemove, this.dense = false});
  final CommAttachment file;
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SboxColors.surfaceMuted,
      shape: const RoundedRectangleBorder(borderRadius: SboxRadius.mdAll, side: BorderSide(color: SboxColors.border)),
      child: InkWell(
        borderRadius: SboxRadius.mdAll,
        onTap: () => commOpenUrl(file.url),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 10),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: file.color.withValues(alpha: 0.12), borderRadius: SboxRadius.smAll),
              child: Icon(file.icon, color: file.color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.text).copyWith(fontWeight: FontWeight.w600)),
                Text([file.kind.toUpperCase(), if (file.sizeLabel.isNotEmpty) file.sizeLabel].join(' · '), style: SboxType.captionStyle()),
              ]),
            ),
            if (onRemove != null)
              IconButton(tooltip: tr('Bỏ tệp'), icon: const Icon(Icons.close_rounded, size: 18), onPressed: onRemove)
            else
              const Icon(Icons.open_in_new_rounded, size: 18, color: SboxColors.slate400),
          ]),
        ),
      ),
    );
  }
}

/// Lưới ảnh kiểu mạng xã hội (1 / 2 / 3 / 4+ ảnh).
class CommImageGrid extends StatelessWidget {
  const CommImageGrid({super.key, required this.urls, this.onRemove, this.height = 260});
  final List<String> urls;
  final void Function(int index)? onRemove;
  final double height;

  void _open(BuildContext context, int start) => showCommGallery(context, urls, start);

  Widget _cell(BuildContext context, int i, {String? more}) {
    return GestureDetector(
      onTap: () => _open(context, i),
      child: Stack(fit: StackFit.expand, children: [
        Image.network(commUrl(urls[i]), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: SboxColors.slate100, child: const Icon(Icons.broken_image_outlined))),
        if (more != null)
          Container(color: Colors.black45, alignment: Alignment.center, child: Text(more, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700))),
        if (onRemove != null)
          Positioned(
            top: 6,
            right: 6,
            child: InkWell(
              onTap: () => onRemove!(i),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    const gap = 3.0;
    Widget body;
    if (urls.length == 1) {
      body = _cell(context, 0);
    } else if (urls.length == 2) {
      body = Row(children: [Expanded(child: _cell(context, 0)), const SizedBox(width: gap), Expanded(child: _cell(context, 1))]);
    } else {
      body = Row(children: [
        Expanded(flex: 2, child: _cell(context, 0)),
        const SizedBox(width: gap),
        Expanded(
          child: Column(children: [
            Expanded(child: _cell(context, 1)),
            const SizedBox(height: gap),
            Expanded(child: _cell(context, 2, more: urls.length > 3 ? '+${urls.length - 3}' : null)),
          ]),
        ),
      ]);
    }
    return ClipRRect(borderRadius: SboxRadius.mdAll, child: SizedBox(height: height, child: body));
  }
}

/// Xem ảnh toàn màn hình: vuốt / phím mũi tên, đếm ảnh, phóng to.
Future<void> showCommGallery(BuildContext context, List<String> urls, int start) => showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _CommGallery(urls: urls, start: start),
    );

class _CommGallery extends StatefulWidget {
  const _CommGallery({required this.urls, required this.start});
  final List<String> urls;
  final int start;

  @override
  State<_CommGallery> createState() => _CommGalleryState();
}

class _CommGalleryState extends State<_CommGallery> {
  late final _page = PageController(initialPage: widget.start);
  late int _i = widget.start;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int d) {
    final n = (_i + d).clamp(0, widget.urls.length - 1);
    if (n != _i) _page.animateToPage(n, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.urls.length > 1;
    Widget arrow(IconData icon, int d, bool enabled) => IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white, disabledBackgroundColor: Colors.white10),
          icon: Icon(icon),
          onPressed: enabled ? () => _go(d) : null,
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(children: [
            PageView(
              controller: _page,
              onPageChanged: (i) => setState(() => _i = i),
              children: [
                for (final u in widget.urls)
                  InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                      child: Image.network(commUrl(u), fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
                    ),
                  ),
              ],
            ),
            if (many)
              Positioned(
                top: 18,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: Text('${_i + 1} / ${widget.urls.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            if (many) Positioned(left: 12, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_left_rounded, -1, _i > 0))),
            if (many)
              Positioned(right: 12, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_right_rounded, 1, _i < widget.urls.length - 1))),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Nội dung HTML dài (cần «Xem thêm»).
bool commLongHtml(String html) {
  final text = html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final blocks = RegExp(r'<(p|li|br|h\d|blockquote)', caseSensitive: false).allMatches(html).length;
  return text.length > 320 || blocks > 6;
}
