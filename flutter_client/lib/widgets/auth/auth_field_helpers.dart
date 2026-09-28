import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Trạng thái kiểm tra trực tiếp dưới ô nhập (đang kiểm tra / hợp lệ / cảnh báo / lỗi).
enum FieldCheckState { idle, checking, ok, warn, error }

class FieldStatusLine extends StatelessWidget {
  const FieldStatusLine({super.key, required this.state, required this.text, this.trailing});
  final FieldCheckState state;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (state == FieldCheckState.idle || text.isEmpty) return const SizedBox.shrink();
    final (color, icon) = switch (state) {
      FieldCheckState.ok => (SboxColors.success, Icons.check_circle_rounded),
      FieldCheckState.warn => (SboxColors.warningText, Icons.info_rounded),
      FieldCheckState.error => (SboxColors.danger, Icons.error_rounded),
      _ => (SboxColors.slate500, Icons.hourglass_top_rounded),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(children: [
        state == FieldCheckState.checking
            ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.6))
            : Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(tr(text), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Cảnh báo đang bật Caps Lock khi gõ mật khẩu (bàn phím máy tính).
class CapsLockHint extends StatefulWidget {
  const CapsLockHint({super.key, required this.focusNode});
  final FocusNode focusNode;

  @override
  State<CapsLockHint> createState() => _CapsLockHintState();
}

class _CapsLockHintState extends State<CapsLockHint> {
  bool _on = false;

  bool _check(KeyEvent _) {
    final on = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (on != _on && mounted) setState(() => _on = on);
    return false;
  }

  void _onFocus() {
    _check(const KeyUpEvent(physicalKey: PhysicalKeyboardKey.capsLock, logicalKey: LogicalKeyboardKey.capsLock, timeStamp: Duration.zero));
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_check);
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_check);
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_on || !widget.focusNode.hasFocus) return const SizedBox.shrink();
    return const FieldStatusLine(state: FieldCheckState.warn, text: 'Đang bật Caps Lock — mật khẩu phân biệt chữ hoa / thường');
  }
}

/// Độ mạnh mật khẩu: 0 yếu … 4 rất mạnh.
int passwordScore(String p) {
  if (p.isEmpty) return 0;
  var score = 0;
  if (p.length >= 6) score++;
  if (p.length >= 10) score++;
  if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) score++;
  if (RegExp(r'\d').hasMatch(p)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
  if (RegExp(r'^(.)\1+$').hasMatch(p) || const ['123456', '12345678', 'password', 'matkhau', '111111'].contains(p.toLowerCase())) {
    score = 0;
  }
  return score.clamp(0, 4);
}

class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final s = passwordScore(password);
    const labels = ['Rất yếu', 'Yếu', 'Trung bình', 'Mạnh', 'Rất mạnh'];
    const colors = [SboxColors.danger, SboxColors.danger, SboxColors.warning, SboxColors.success, SboxColors.success];
    final tips = <String>[
      if (password.length < 10) 'dài từ 10 ký tự',
      if (!RegExp(r'\d').hasMatch(password)) 'thêm số',
      if (!(RegExp(r'[a-z]').hasMatch(password) && RegExp(r'[A-Z]').hasMatch(password))) 'chữ hoa + thường',
      if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) 'ký tự đặc biệt',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i < (s == 0 ? 1 : s) ? colors[s] : SboxColors.slate200,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          tr('Độ mạnh: ${labels[s]}${s < 3 && tips.isNotEmpty ? ' · Gợi ý: ${tips.take(2).join(', ')}' : ''}'),
          style: TextStyle(fontSize: 11.5, color: colors[s], fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}
