import 'package:flutter/material.dart';

/// Mobile / desktop — sửa HTML trực tiếp khi không có contenteditable.
class PosCommercialWordSurface extends StatefulWidget {
  const PosCommercialWordSurface({
    super.key,
    required this.html,
    required this.onChanged,
    this.editable = true,
  });

  final String html;
  final ValueChanged<String> onChanged;
  final bool editable;

  @override
  State<PosCommercialWordSurface> createState() =>
      PosCommercialWordSurfaceState();
}

class PosCommercialWordSurfaceState extends State<PosCommercialWordSurface> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.html);
  }

  @override
  void didUpdateWidget(covariant PosCommercialWordSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html && widget.html != _ctrl.text) {
      _ctrl.text = widget.html;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void exec(String cmd, [String? value]) {
    final wrap = switch (cmd) {
      'bold' => ('<b>', '</b>'),
      'italic' => ('<i>', '</i>'),
      'underline' => ('<u>', '</u>'),
      'justifyCenter' => ('<div style="text-align:center">', '</div>'),
      'justifyRight' => ('<div style="text-align:right">', '</div>'),
      'insertUnorderedList' => ('<ul><li>', '</li></ul>'),
      _ => ('', ''),
    };
    if (wrap.$1.isEmpty && (value == null || value.isEmpty)) return;
    final t = _ctrl.value;
    final start = t.selection.start < 0 ? t.text.length : t.selection.start;
    final end = t.selection.end < 0 ? start : t.selection.end;
    final sel = t.text.substring(start, end);
    final insert = value != null && value.isNotEmpty
        ? value
        : '${wrap.$1}$sel${wrap.$2}';
    final next = t.text.replaceRange(start, end, insert);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    widget.onChanged(next);
  }

  void insertHtml(String html) => exec('insertHTML', html);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      readOnly: !widget.editable,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(
        fontFamily: 'Times New Roman',
        fontSize: 13.5,
        height: 1.45,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(16),
      ),
      onChanged: widget.onChanged,
    );
  }
}
