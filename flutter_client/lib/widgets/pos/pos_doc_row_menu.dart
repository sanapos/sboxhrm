import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import 'pos_theme.dart';

/// Một thao tác trên phiếu (nhập / trả / xuất / kiểm kho) hiện ở menu «⋮» của từng dòng danh sách.
class PosDocAction {
  const PosDocAction(this.icon, this.label, this.onTap, {this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// Menu thao tác ngay trên dòng phiếu — không phải mở rộng dòng mới thấy Sửa / Hủy / Xóa.
class PosDocRowMenu extends StatelessWidget {
  const PosDocRowMenu({super.key, required this.actions});

  final List<PosDocAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox(width: 40);
    return PopupMenuButton<int>(
      tooltip: tr('Thao tác'),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, size: 20, color: PosTheme.textSecondary),
      onSelected: (i) => actions[i].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++) ...[
          if (actions[i].danger && i > 0) const PopupMenuDivider(height: 1),
          PopupMenuItem<int>(
            value: i,
            height: 40,
            child: Row(
              children: [
                Icon(actions[i].icon, size: 18, color: actions[i].danger ? Colors.red : PosTheme.textSecondary),
                const SizedBox(width: 10),
                Text(
                  tr(actions[i].label),
                  style: TextStyle(fontSize: 13, color: actions[i].danger ? Colors.red : null),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Phiếu đã hoàn thành không sửa trực tiếp được: hủy phiếu (hoàn kho) rồi mở bản sao ở dạng phiếu tạm để chỉnh.
Future<bool> confirmReopenForEdit(BuildContext context, String docNo, {String effect = 'hoàn lại tồn kho'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Hủy và sửa lại phiếu')),
      content: Text(tr(
          'Phiếu $docNo đã hoàn thành nên không sửa trực tiếp được.\n\nSẽ hủy phiếu này ($effect) rồi tạo phiếu tạm mới với nội dung giống hệt để bạn chỉnh sửa và hoàn thành lại.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Hủy và sửa lại'))),
      ],
    ),
  );
  return ok == true;
}
