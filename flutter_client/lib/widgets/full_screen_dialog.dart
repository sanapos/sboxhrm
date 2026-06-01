import 'package:flutter/material.dart';

/// Dialog phủ toàn màn hình — không đóng khi bấm ra ngoài; dùng [buildPickerCloseAppBar].
Future<T?> showFullScreenDialog<T>(
  BuildContext context, {
  required Widget child,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useSafeArea: true,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.white,
      child: child,
    ),
  );
}

/// AppBar picker: tiêu đề + nút đóng (X) góc trái.
AppBar buildPickerCloseAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget>? actions,
}) {
  return AppBar(
    backgroundColor: Colors.white,
    foregroundColor: const Color(0xFF0F172A),
    elevation: 0,
    surfaceTintColor: Colors.white,
    leading: IconButton(
      icon: const Icon(Icons.close),
      tooltip: 'Đóng',
      onPressed: () => Navigator.pop(context),
    ),
    title: subtitle != null && subtitle.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          )
        : Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
    actions: actions,
    centerTitle: false,
  );
}
