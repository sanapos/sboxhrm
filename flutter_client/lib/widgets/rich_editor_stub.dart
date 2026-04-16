// Fallback rich editor for non-web platforms (Windows, mobile, etc.)
// Uses a simple TextFormField for HTML content editing.

import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════
// Controller
// ══════════════════════════════════════════════════════════

class RichEditorController {
  final TextEditingController _textController = TextEditingController();

  String get html => _textController.text;

  set html(String value) {
    _textController.text = value;
  }

  bool get isEmpty => _textController.text.trim().isEmpty;

  TextEditingController get textEditingController => _textController;

  void dispose() => _textController.dispose();
}

// ══════════════════════════════════════════════════════════
// Rich Editor (fallback: plain text field)
// ══════════════════════════════════════════════════════════

/// Callback type for image upload.
typedef ImageUploadCallback = Future<String?> Function(List<int> bytes, String fileName);

class RichEditor extends StatelessWidget {
  final RichEditorController controller;
  final ValueChanged<String>? onChanged;
  final double minHeight;
  final String? placeholder;
  final ImageUploadCallback? onImageUpload;

  const RichEditor({
    super.key,
    required this.controller,
    this.onChanged,
    this.minHeight = 350,
    this.placeholder,
    this.onImageUpload,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller.textEditingController,
      decoration: InputDecoration(
        hintText: placeholder ?? 'Nhập nội dung HTML...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        alignLabelWithHint: true,
      ),
      maxLines: null,
      minLines: (minHeight / 24).round(),
      onChanged: onChanged,
    );
  }
}

// ══════════════════════════════════════════════════════════
// HTML Content View (fallback: strip tags and show text)
// ══════════════════════════════════════════════════════════

class HtmlContentView extends StatelessWidget {
  final String html;
  final double? minHeight;

  const HtmlContentView({super.key, required this.html, this.minHeight});

  @override
  Widget build(BuildContext context) {
    final text = html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'</p>'), '\n')
        .replaceAll(RegExp(r'</li>'), '\n')
        .replaceAll(RegExp(r'</h[1-6]>'), '\n\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
    return SelectableText(
      text,
      style: const TextStyle(fontSize: 15, height: 1.7),
    );
  }
}
