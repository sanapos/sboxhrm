import 'package:flutter/material.dart';

import 'pos_theme.dart';

/// Dãy số gợi ý 1…[max] bấm 1 lần (số khách, số lượng trả…) — khỏi mở bàn phím số trên máy cảm ứng.
class PosQuickNumberChips extends StatelessWidget {
  const PosQuickNumberChips({
    super.key,
    required this.max,
    required this.selected,
    required this.onPick,
  });

  final int max;
  final num? selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    // Rộng cố định: Wrap trong AlertDialog không tự xuống dòng mà kéo hộp ra hết màn hình.
    return SizedBox(
      width: 380,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var n = 1; n <= max; n++) _chip(n, selected == n),
        ],
      ),
    );
  }

  Widget _chip(int n, bool on) {
    return SizedBox(
      width: 42,
      height: 38,
      child: Material(
        color: on ? PosTheme.kiotBlue : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => onPick(n),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: on ? PosTheme.kiotBlue : PosTheme.border),
            ),
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : PosTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
