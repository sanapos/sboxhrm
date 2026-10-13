import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';

const kUnsavedChangesMessage =
    'Bạn đã nhập dữ liệu nhưng chưa lưu. Thoát sẽ mất các thay đổi này.';

/// Hỏi trước khi đóng form/phiếu còn dữ liệu chưa lưu. true = bỏ thay đổi và thoát.
Future<bool> confirmDiscardUnsavedChanges(
  BuildContext context, {
  String message = kUnsavedChangesMessage,
}) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Dữ liệu chưa được lưu')),
      content: Text(tr(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Ở lại')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Bỏ thay đổi')),
        ),
      ],
    ),
  );
  return leave == true;
}

/// Chặn nút back hệ thống / nút quay lại (Navigator.maybePop) khi [isDirty] trả true.
/// Navigator.pop trực tiếp (sau khi lưu) không bị chặn.
class UnsavedChangesScope extends StatelessWidget {
  const UnsavedChangesScope({
    super.key,
    required this.isDirty,
    required this.child,
    this.message,
  });

  final bool Function() isDirty;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (!isDirty()) {
          nav.pop();
          return;
        }
        final leave = await confirmDiscardUnsavedChanges(
          context,
          message: message ?? kUnsavedChangesMessage,
        );
        if (leave) nav.pop();
      },
      child: child,
    );
  }
}
