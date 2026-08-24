import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import 'pos_theme.dart';

/// Ô số không mở soft keyboard — tap mở [showPosNumericKeypad].
/// Vẫn nhận bàn phím cứng khi đã focus (`showSoftInputOnFocus: false`).
class PosNoSoftKeyboardField extends StatelessWidget {
  const PosNoSoftKeyboardField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration,
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.allowDecimal = true,
    this.allowNegative = false,
    this.keypadTitle,
    this.onChanged,
    this.onSubmitted,
    this.onOpen,
    this.enabled = true,
    this.openKeypadOnTap = true,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final bool allowDecimal;
  final bool allowNegative;
  final String? keypadTitle;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  /// Gọi khi người dùng chạm ô (trước khi mở keypad) — ví dụ hiện chip gợi ý.
  final VoidCallback? onOpen;
  final bool enabled;
  final bool openKeypadOnTap;

  Future<void> _openPad(BuildContext context) async {
    if (!enabled || !openKeypadOnTap) return;
    onOpen?.call();
    final next = await showPosNumericKeypad(
      context: context,
      title: keypadTitle ?? 'Nhập số',
      initial: controller.text,
      allowDecimal: allowDecimal,
      allowNegative: allowNegative,
    );
    if (next == null || !context.mounted) return;
    controller.text = next;
    controller.selection = TextSelection.collapsed(offset: next.length);
    onChanged?.call(next);
    onSubmitted?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      // readOnly + pad: không mở soft IME trên máy cảm ứng.
      readOnly: openKeypadOnTap,
      showCursor: true,
      enableInteractiveSelection: true,
      keyboardType: allowDecimal
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.number,
      textAlign: textAlign,
      style: style,
      decoration: decoration,
      onTap: openKeypadOnTap ? () => unawaited(_openPad(context)) : null,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(allowDecimal
              ? (allowNegative ? r'[-0-9.,]' : r'[0-9.,]')
              : (allowNegative ? r'[-0-9]' : r'[0-9]')),
        ),
      ],
    );
  }
}

/// Bottom sheet bàn phím số POS (tiền / CK / giá / SL / khách).
Future<String?> showPosNumericKeypad({
  required BuildContext context,
  required String title,
  String initial = '',
  bool allowDecimal = true,
  bool allowNegative = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => _PosNumericKeypadSheet(
      title: title,
      initial: initial,
      allowDecimal: allowDecimal,
      allowNegative: allowNegative,
    ),
  );
}

class _PosNumericKeypadSheet extends StatefulWidget {
  const _PosNumericKeypadSheet({
    required this.title,
    required this.initial,
    required this.allowDecimal,
    required this.allowNegative,
  });

  final String title;
  final String initial;
  final bool allowDecimal;
  final bool allowNegative;

  @override
  State<_PosNumericKeypadSheet> createState() => _PosNumericKeypadSheetState();
}

class _PosNumericKeypadSheetState extends State<_PosNumericKeypadSheet> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = _normalize(widget.initial);
  }

  String _normalize(String raw) {
    var s = raw.trim().replaceAll(',', '');
    if (s == '-' || s.isEmpty) return s;
    return s;
  }

  void _append(String ch) {
    setState(() {
      if (ch == '.' || ch == ',') {
        if (!widget.allowDecimal) return;
        if (_value.contains('.')) return;
        _value = _value.isEmpty || _value == '-' ? '${_value}0.' : '$_value.';
        return;
      }
      if (ch == '-') {
        if (!widget.allowNegative) return;
        _value = _value.startsWith('-') ? _value.substring(1) : '-$_value';
        return;
      }
      if (_value == '0') {
        _value = ch;
      } else {
        _value = '$_value$ch';
      }
    });
  }

  void _backspace() {
    setState(() {
      if (_value.isEmpty) return;
      _value = _value.substring(0, _value.length - 1);
    });
  }

  void _clear() => setState(() => _value = '');

  Widget _key(
    String label, {
    VoidCallback? onTap,
    Color? bg,
    Color? fg,
    int flex = 1,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: bg ?? const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Center(
                child: Text(
                  tr(label),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: fg ?? PosTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(widget.title),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Đóng'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 10, top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: PosTheme.border),
            ),
            child: Text(
              _value.isEmpty ? '0' : _value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: _value.isEmpty
                    ? PosTheme.textSecondary
                    : PosTheme.textPrimary,
              ),
            ),
          ),
          Row(children: [
            _key('7', onTap: () => _append('7')),
            _key('8', onTap: () => _append('8')),
            _key('9', onTap: () => _append('9')),
          ]),
          Row(children: [
            _key('4', onTap: () => _append('4')),
            _key('5', onTap: () => _append('5')),
            _key('6', onTap: () => _append('6')),
          ]),
          Row(children: [
            _key('1', onTap: () => _append('1')),
            _key('2', onTap: () => _append('2')),
            _key('3', onTap: () => _append('3')),
          ]),
          Row(children: [
            if (widget.allowDecimal)
              _key('.', onTap: () => _append('.'))
            else if (widget.allowNegative)
              _key('±', onTap: () => _append('-'))
            else
              _key('C', onTap: _clear, fg: Colors.red.shade700),
            _key('0', onTap: () => _append('0')),
            _key('⌫', onTap: _backspace, fg: Colors.red.shade700),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clear,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(tr('Xóa')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _value),
                  style: FilledButton.styleFrom(
                    backgroundColor: PosTheme.kiotBlue,
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(tr('Xong')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
