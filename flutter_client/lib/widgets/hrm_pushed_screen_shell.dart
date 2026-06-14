import 'package:flutter/material.dart';

import 'hrm_page_chrome.dart';

/// Back bar khi màn hình được mở bằng [Navigator.push] (không qua [MainLayout]).
class HrmPushedScreenShell extends StatelessWidget {
  final String? title;
  final Widget child;

  const HrmPushedScreenShell({
    super.key,
    this.title,
    required this.child,
  });

  /// Chỉ bọc back bar nếu route có thể pop; màn trong menu chính giữ nguyên.
  static Widget maybeWrap(
    BuildContext context, {
    String? title,
    required Widget child,
  }) {
    if (!Navigator.canPop(context)) return child;
    return HrmPushedScreenShell(title: title, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          elevation: 0.5,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Quay lại',
                  ),
                  if (title != null && title!.isNotEmpty)
                    Expanded(
                      child: Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HrmPageChrome.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
