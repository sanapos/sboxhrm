import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';

/// Một thao tác trong [SboxActionFab].
class SboxFabAction {
  const SboxFabAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;

  /// null = tạm khóa (đang tải…).
  final VoidCallback? onTap;

  /// Hiện vòng xoay thay biểu tượng (vd đang đồng bộ).
  final bool busy;
}

/// Nút nổi góc dưới phải gom các thao tác phụ của màn: bấm «Thao tác» → bung danh sách nút có chữ.
/// Thay hàng biểu tượng không chữ trên thanh tiêu đề (khó đoán nút nào làm gì).
class SboxActionFab extends StatefulWidget {
  const SboxActionFab({super.key, required this.actions, this.label = 'Thao tác'});

  final List<SboxFabAction> actions;
  final String label;

  @override
  State<SboxActionFab> createState() => _SboxActionFabState();
}

class _SboxActionFabState extends State<SboxActionFab> {
  bool _open = false;

  void _close() {
    if (_open) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      // Bấm ra ngoài là thu lại — khỏi che nội dung.
      onTapOutside: (_) => _close(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_open)
            for (final a in widget.actions)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: _item(a)),
          FloatingActionButton.extended(
            // Nhiều Scaffold lồng nhau (tab Máy in) — heroTag mặc định trùng nhau sẽ lỗi.
            heroTag: null,
            onPressed: () => setState(() => _open = !_open),
            backgroundColor: _open ? SboxColors.slate700 : SboxColors.primary,
            foregroundColor: Colors.white,
            icon: Icon(_open ? Icons.close : Icons.more_horiz),
            label: Text(tr(_open ? 'Đóng' : widget.label)),
          ),
        ],
      ),
    );
  }

  Widget _item(SboxFabAction a) {
    final enabled = a.onTap != null && !a.busy;
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const StadiumBorder(side: BorderSide(color: SboxColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled
            ? () {
                setState(() => _open = false);
                a.onTap!();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (a.busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: SboxColors.primary),
              )
            else
              Icon(a.icon, size: 20, color: enabled ? SboxColors.primary : SboxColors.slate400),
            const SizedBox(width: 10),
            Text(
              tr(a.label),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: enabled ? SboxColors.text : SboxColors.slate400,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
