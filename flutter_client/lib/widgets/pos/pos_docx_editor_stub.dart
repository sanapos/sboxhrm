import 'package:flutter/material.dart';

/// Trình soạn mẫu Word trực quan chỉ có trên bản web (máy tính).
const bool posDocxEditorSupported = false;

class PosDocxEditorFrame extends StatelessWidget {
  const PosDocxEditorFrame({super.key, required this.html, required this.onMessage});

  final String html;
  final void Function(Map<String, dynamic> message) onMessage;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
