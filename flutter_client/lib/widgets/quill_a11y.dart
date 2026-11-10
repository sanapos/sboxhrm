import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// flutter_quill bọc ô soạn trong một lớp Trợ năng rỗng: Android không thấy đây là ô nhập chữ,
/// không có lệnh Dán / Đặt chữ, chữ gợi ý cũng không đọc được → TalkBack và công cụ tự động không dùng được.
///
/// Lớp này khai báo một ô nhập chữ có mã định danh cố định ([identifier] → `resource-id` trên Android),
/// nhãn, giá trị là toàn bộ chữ của bài, và hai lệnh:
/// - Dán: dán tại con trỏ (hoặc cuối bài nếu chưa có con trỏ), giữ định dạng như dán bằng tay.
/// - Đặt chữ: KHÔNG xoá nội dung đang có (bài có định dạng, ảnh…). Xem [applyQuillSetText].
class QuillA11y extends StatelessWidget {
  const QuillA11y({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.identifier,
    required this.child,
    this.hint,
  });

  final quill.QuillController controller;
  final FocusNode focusNode;
  final String label;
  final String? hint;
  final String identifier;
  final Widget child;

  void _ensureSelection() {
    if (controller.selection.isValid) return;
    controller.updateSelection(TextSelection.collapsed(offset: controller.document.length - 1), quill.ChangeSource.local);
  }

  Future<void> _paste() async {
    if (controller.readOnly) return;
    _ensureSelection();
    focusNode.requestFocus();
    // Cùng đường dán với menu nhấn giữ của Quill (HTML / ảnh / chữ thường). Plugin đọc HTML
    // (quill_native_bridge) lỗi / chưa có trên nền tảng thì vẫn dán được chữ thường.
    try {
      // ignore: experimental_member_use
      await controller.clipboardPaste();
      return;
    } catch (_) {}
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    final sel = controller.selection;
    final end = controller.document.length - 1;
    final start = sel.start.clamp(0, end);
    final len = (sel.end.clamp(0, end) - start).clamp(0, end);
    controller.replaceText(start, len, text, TextSelection.collapsed(offset: start + text.length));
  }

  void _setText(String text) {
    if (controller.readOnly) return;
    applyQuillSetText(controller, text);
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, child) {
        final plain = quillPlainText(controller.document);
        return Semantics(
          container: true,
          textField: true,
          multiline: true,
          readOnly: controller.readOnly,
          focused: focusNode.hasFocus,
          identifier: identifier,
          label: label,
          hint: plain.isEmpty ? hint : null,
          value: plain,
          onTap: () => focusNode.requestFocus(),
          onPaste: controller.readOnly ? null : _paste,
          onSetText: controller.readOnly ? null : _setText,
          child: ExcludeSemantics(child: child),
        );
      },
      child: child,
    );
  }
}

/// Chữ của tài liệu, bỏ dấu xuống dòng cuối mà Quill luôn giữ.
String quillPlainText(quill.Document doc) {
  final t = doc.toPlainText();
  return t.endsWith('\n') ? t.substring(0, t.length - 1) : t;
}

/// Lệnh «Đặt chữ» của Trợ năng gửi cả nội dung mong muốn của ô. Với ô soạn có định dạng,
/// thay toàn bộ sẽ làm mất định dạng / ảnh / cả bài nếu công cụ gửi nhầm, nên:
/// - Ô trống: chèn chữ.
/// - Chữ mới bắt đầu bằng chữ đang có (công cụ nối thêm): chỉ chèn phần thêm vào cuối.
/// - Trùng chữ đang có, hoặc chuỗi rỗng: không làm gì (xoá bài phải làm rõ ràng bằng chọn + xoá).
/// - Còn lại: chèn tại con trỏ (hoặc cuối bài), không xoá gì.
void applyQuillSetText(quill.QuillController controller, String text) {
  final current = quillPlainText(controller.document);
  if (text.isEmpty || text == current) return;
  final end = controller.document.length - 1;
  String insert;
  int at;
  if (current.isEmpty) {
    insert = text;
    at = 0;
  } else if (text.startsWith(current)) {
    insert = text.substring(current.length);
    at = end;
  } else {
    insert = text;
    final sel = controller.selection;
    at = sel.isValid ? sel.end.clamp(0, end) : end;
  }
  controller.replaceText(at, 0, insert, TextSelection.collapsed(offset: at + insert.length));
}
