import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../models/comm_v2.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import 'comm_common.dart';

/// Số ảnh tối đa một bình luận (khớp máy chủ).
const commCommentMaxImages = 4;
const _kCommentImageExts = ['jpg', 'jpeg', 'png', 'webp', 'gif'];

/// Ảnh đang đính kèm vào bình luận chưa gửi: chọn, tải lên ngay, bỏ bớt.
class CommCommentDraftImages extends ChangeNotifier {
  CommCommentDraftImages({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;
  final List<String> urls = [];
  bool uploading = false;

  bool get isEmpty => urls.isEmpty;
  bool get full => urls.length >= commCommentMaxImages;

  Future<void> pick(BuildContext context) async {
    if (uploading) return;
    if (full) {
      commToast(context, 'Mỗi bình luận tối đa $commCommentMaxImages ảnh', error: true);
      return;
    }
    final r = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: true, type: FileType.custom, allowedExtensions: _kCommentImageExts);
    if (r == null || !context.mounted) return;
    final room = commCommentMaxImages - urls.length;
    final files = <({List<int> bytes, String name})>[];
    for (final f in r.files) {
      if (f.bytes == null) continue;
      if (f.size > 20 * 1024 * 1024) {
        commToast(context, '${f.name} vượt quá 20 MB', error: true);
        continue;
      }
      files.add((bytes: f.bytes!, name: f.name));
    }
    if (files.isEmpty) return;
    if (files.length > room) {
      commToast(context, 'Chỉ thêm được $room ảnh nữa', error: true);
      files.removeRange(room, files.length);
    }
    uploading = true;
    notifyListeners();
    final res = await _api.commUpload(files);
    uploading = false;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final d = res['data'] as Map;
      final atts = (d['attachments'] as List? ?? [])
          .whereType<Map>()
          .map((e) => CommAttachment.fromJson(Map<String, dynamic>.from(e)))
          .where((a) => a.isImage);
      for (final a in atts) {
        if (!full) urls.add(a.url);
      }
      final warns = (d['warnings'] as List? ?? []).map((e) => '$e').toList();
      if (warns.isNotEmpty && context.mounted) commToast(context, warns.join('\n'), error: true);
    } else if (context.mounted) {
      commToast(context, '${res['message'] ?? 'Không tải được ảnh'}', error: true);
    }
    notifyListeners();
  }

  void removeAt(int i) {
    urls.removeAt(i);
    notifyListeners();
  }

  void clear() {
    if (urls.isEmpty) return;
    urls.clear();
    notifyListeners();
  }
}

/// Ô nhập bình luận dùng chung:
/// - Enter (phím thật, adb `keyevent ENTER`, web) gửi; Shift+Enter xuống dòng; đang gõ dấu (IME) thì để IME xử lý.
/// - Mã định danh cố định ([identifier] → `resource-id` trên Android) và nhãn «Ô bình luận» không mất khi ô đã có chữ.
/// - Hành động Trợ năng «Gửi bình luận» (TalkBack / công cụ tự động không gửi được Enter qua Trợ năng).
class CommCommentField extends StatelessWidget {
  const CommCommentField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.decoration,
    this.identifier = 'comm-comment-input',
    this.minLines = 1,
    this.maxLines = 4,
    this.onEnter,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final InputDecoration decoration;
  final String identifier;
  final int minLines;
  final int maxLines;

  /// Thay hành vi Enter (ví dụ chọn gợi ý @nhắc tên). Mặc định gọi [onSend].
  final VoidCallback? onEnter;

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.enter && e.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    if (controller.value.composing.isValid && !controller.value.composing.isCollapsed) return KeyEventResult.ignored;
    (onEnter ?? onSend)();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: identifier,
      label: tr('Ô bình luận'),
      customSemanticsActions: {CustomSemanticsAction(label: tr('Gửi bình luận')): onSend},
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          minLines: minLines,
          maxLines: maxLines,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => (onEnter ?? onSend)(),
          decoration: decoration,
        ),
      ),
    );
  }
}

/// Nút đính kèm ảnh vào bình luận.
class CommCommentImageButton extends StatelessWidget {
  const CommCommentImageButton({super.key, required this.images});
  final CommCommentDraftImages images;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: images,
      builder: (context, _) => Semantics(
        identifier: 'comm-comment-image',
        child: IconButton(
          tooltip: tr('Thêm ảnh'),
          visualDensity: VisualDensity.compact,
          icon: images.uploading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.image_outlined, color: images.full ? SboxColors.slate400 : SboxColors.slate600),
          onPressed: images.uploading ? null : () => images.pick(context),
        ),
      ),
    );
  }
}

/// Ảnh xem trước của bình luận chưa gửi (bấm × để bỏ).
class CommCommentImageStrip extends StatelessWidget {
  const CommCommentImageStrip({super.key, required this.images, this.padding = const EdgeInsets.only(bottom: 6)});
  final CommCommentDraftImages images;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: images,
      builder: (context, _) {
        if (images.urls.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) => Stack(children: [
                ClipRRect(
                  borderRadius: SboxRadius.smAll,
                  child: Image.network(commUrl(images.urls[i]),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      cacheWidth: 192,
                      errorBuilder: (_, __, ___) =>
                          Container(width: 64, height: 64, color: SboxColors.slate100, child: const Icon(Icons.broken_image_outlined))),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Semantics(
                    button: true,
                    label: tr('Bỏ ảnh ${i + 1}'),
                    child: InkWell(
                      onTap: () => images.removeAt(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
