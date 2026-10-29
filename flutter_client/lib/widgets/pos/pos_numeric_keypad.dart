import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import 'pos_theme.dart';

import '../../theme/sbox_tokens.dart';

/// Máy cảm ứng (Android / iOS) dùng bàn phím số của app cho ô tiền — bàn phím số hệ thống
/// lẫn ( ) # * = và che nửa form. Web / desktop gõ phím thường (ô chỉ-đọc sẽ không gõ được).
bool get posUsesAppKeypad =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Ô tiền (TextField thường, có formatter riêng) trên máy cảm ứng: chạm → bàn phím số app,
/// ghi lại số nguyên định dạng nghìn «30.000». Dùng với `readOnly: posUsesAppKeypad`.
Future<void> posPickAmountInto(BuildContext context, TextEditingController c, {String title = 'Số tiền'}) async {
  final next = await showPosNumericKeypad(
    context: context,
    title: title,
    initial: c.text.replaceAll(RegExp(r'[^\d]'), ''),
    allowDecimal: false,
  );
  if (next == null || !context.mounted) return;
  final n = int.tryParse(next);
  c.text = n == null ? '' : NumberFormat('#,##0', 'vi_VN').format(n);
  c.selection = TextSelection.collapsed(offset: c.text.length);
}

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
    this.offerDecimalToggle = false,
    this.onDecimalToggle,
    this.offerCashNotes = false,
    this.quickPercents,
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
  /// Hiện chip «Bán số lẻ» trên bàn phím số.
  final bool offerDecimalToggle;
  final ValueChanged<bool>? onDecimalToggle;
  /// Hiện nút mệnh giá tiền mặt «+1k … +500k» (cộng dồn) trên bàn phím số.
  final bool offerCashNotes;
  /// Nút % chọn nhanh (bấm là thay giá trị) — ô giảm giá theo %.
  final List<int>? quickPercents;

  Future<void> _openPad(BuildContext context) async {
    if (!enabled || !openKeypadOnTap) return;
    onOpen?.call();
    final next = await showPosNumericKeypad(
      context: context,
      title: keypadTitle ?? 'Nhập số',
      // Ô số nguyên hay hiển thị «30.000» — keypad sẽ hiểu dấu chấm là phần thập phân.
      initial: allowDecimal ? controller.text : controller.text.replaceAll(RegExp(r'[^\d-]'), ''),
      allowDecimal: allowDecimal,
      allowNegative: allowNegative,
      offerDecimalToggle: offerDecimalToggle,
      onDecimalToggle: onDecimalToggle,
      offerCashNotes: offerCashNotes,
      quickPercents: quickPercents,
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
  bool offerDecimalToggle = false,
  ValueChanged<bool>? onDecimalToggle,
  bool offerCashNotes = false,
  List<int>? quickPercents,
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
      offerDecimalToggle: offerDecimalToggle,
      onDecimalToggle: onDecimalToggle,
      offerCashNotes: offerCashNotes,
      quickPercents: quickPercents,
    ),
  );
}

class _PosNumericKeypadSheet extends StatefulWidget {
  const _PosNumericKeypadSheet({
    required this.title,
    required this.initial,
    required this.allowDecimal,
    required this.allowNegative,
    required this.offerDecimalToggle,
    required this.onDecimalToggle,
    this.offerCashNotes = false,
    this.quickPercents,
  });

  final String title;
  final String initial;
  final bool allowDecimal;
  final bool allowNegative;
  final bool offerDecimalToggle;
  final ValueChanged<bool>? onDecimalToggle;
  final bool offerCashNotes;
  final List<int>? quickPercents;

  @override
  State<_PosNumericKeypadSheet> createState() => _PosNumericKeypadSheetState();
}

class _PosNumericKeypadSheetState extends State<_PosNumericKeypadSheet> {
  late String _value;
  late bool _allowDecimal;

  /// Giá trị điền sẵn coi như «đang bôi đen»: phím số đầu tiên thay hẳn, xóa lùi đầu tiên xóa hết.
  /// Trước đây gõ nối vào sau — ô tiền thanh toán sẵn «65.000», khách đưa 100.000 → «65.000100000».
  late bool _fresh;

  @override
  void initState() {
    super.initState();
    _value = _normalize(widget.initial);
    _allowDecimal = widget.allowDecimal;
    _fresh = _value.isNotEmpty && _value != '0';
  }

  void _toggleDecimal(bool on) {
    setState(() {
      _allowDecimal = on;
      if (!on) {
        final dot = _value.indexOf('.');
        if (dot >= 0) _value = _value.substring(0, dot);
      }
    });
    widget.onDecimalToggle?.call(on);
  }

  String _normalize(String raw) {
    var s = raw.trim().replaceAll(',', '');
    if (s == '-' || s.isEmpty) return s;
    return s;
  }

  void _append(String ch) {
    setState(() {
      if (_fresh && ch != '-') _value = '';
      _fresh = false;
      if (ch == '.' || ch == ',') {
        if (!_allowDecimal) return;
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
      if (_fresh) {
        _fresh = false;
        _value = '';
        return;
      }
      if (_value.isEmpty) return;
      _value = _value.substring(0, _value.length - 1);
    });
  }

  /// Mệnh giá tiền Việt: bấm lần đầu thay số điền sẵn, bấm tiếp cộng dồn (khách đưa 200k + 50k → 250.000).
  static const _cashNotes = [1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000];

  void _addNote(int note) {
    setState(() {
      final base = _fresh ? 0 : (int.tryParse(_value.split('.').first) ?? 0);
      _value = '${base + note}';
      _fresh = false;
    });
  }

  void _pickPercent(int p) => setState(() {
        _value = '$p';
        _fresh = false;
      });

  String get _shownValue {
    if (_value.isEmpty) return '0';
    // Số nguyên hiện dấu chấm nghìn («250.000») — cộng dồn mệnh giá ra số lớn, khó đọc khi để thô.
    if (_allowDecimal) return _value;
    final n = int.tryParse(_value);
    return n == null ? _value : NumberFormat('#,##0', 'vi_VN').format(n);
  }

  void _clear() => setState(() {
        _fresh = false;
        _value = '';
      });

  /// Bàn phím cứng (USB / bàn phím số gắn máy POS): gõ số, «.», Backspace, Delete xóa hết,
  /// Enter = Xong, Esc = đóng. Trước đây bàn phím chỉ bấm được bằng tay — gõ phím bị bỏ qua.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      Navigator.pop(context, _value);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      _clear();
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch == null || ch.isEmpty) return KeyEventResult.ignored;
    if (RegExp(r'^[0-9]$').hasMatch(ch)) {
      _append(ch);
      return KeyEventResult.handled;
    }
    if (ch == '.' || ch == ',' || ch == '-') {
      _append(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Đơn vị hiện cạnh số: giảm theo % → «%», ô tiền (có nút mệnh giá) → «đ».
  String? get _unit => widget.quickPercents != null && widget.quickPercents!.isNotEmpty
      ? '%'
      : widget.offerCashNotes
          ? 'đ'
          : null;

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
          color: bg ?? SboxColors.slate100,
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
    final unit = _unit;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Padding(
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
            // Giá trị sẵn đang «bôi đen» (phím tiếp theo sẽ thay) → nền xanh nhạt như vùng chọn.
            decoration: BoxDecoration(
              color: _fresh ? SboxColors.brand50 : SboxColors.slate50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _fresh ? SboxColors.brand600 : PosTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    _shownValue,
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
                if (unit != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: PosTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.offerDecimalToggle)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilterChip(
                  label: Text(
                    tr(_allowDecimal ? 'Bán số lẻ: 1,5 · 1,45' : 'Bán số lẻ'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  selected: _allowDecimal,
                  showCheckmark: false,
                  onSelected: _toggleDecimal,
                ),
              ),
            ),
          if (widget.offerCashNotes)
            for (final row in [_cashNotes.sublist(0, 5), _cashNotes.sublist(5)])
              Row(children: [
                for (final n in row)
                  _key('+${n ~/ 1000}k',
                      onTap: () => _addNote(n), bg: SboxColors.successSoft, fg: SboxColors.successText),
              ]),
          if (widget.quickPercents != null && widget.quickPercents!.isNotEmpty)
            for (var i = 0; i < widget.quickPercents!.length; i += 5)
              Row(children: [
                for (final p in widget.quickPercents!.skip(i).take(5))
                  _key('$p%',
                      onTap: () => _pickPercent(p), bg: SboxColors.brand50, fg: SboxColors.brand700),
              ]),
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
            if (_allowDecimal)
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
      ),
    );
  }
}
