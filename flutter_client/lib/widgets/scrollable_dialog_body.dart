import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Scrollable body for [AlertDialog] / [Dialog] ?? on web & desktop when content can grow tall.
class ScrollableDialogBody {
  ScrollableDialogBody._();

  static double maxHeight(BuildContext context, {double factor = 0.65}) =>
      MediaQuery.sizeOf(context).height * factor;

  static double dialogWidth(BuildContext context, {double maxWidth = 500}) =>
      math.min(maxWidth, MediaQuery.sizeOf(context).width - 32);

  /// Shorthand for [AlertDialog.content] / form bodies that may overflow on web.
  static Widget forAlert(
    BuildContext context,
    Widget child, {
    double? width,
    double maxWidth = 500,
    double maxHeightFactor = 0.65,
  }) =>
      wrap(
        context,
        child: child,
        width: width,
        maxWidth: maxWidth,
        maxHeightFactor: maxHeightFactor,
      );

  /// Same as [forAlert] ?? but accepts `child:` for generated / legacy call sites.
  static Widget forAlertChild({
    required BuildContext context,
    required Widget child,
    double? width,
    double maxWidth = 500,
    double maxHeightFactor = 0.65,
  }) =>
      forAlert(context, child,
          width: width, maxWidth: maxWidth, maxHeightFactor: maxHeightFactor);

  /// Constrains height and enables vertical scroll.
  static Widget wrap(
    BuildContext context, {
    required Widget child,
    double? width,
    double maxWidth = 500,
    double maxHeightFactor = 0.65,
  }) {
    return SizedBox(
      width: width ?? dialogWidth(context, maxWidth: maxWidth),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight(context, factor: maxHeightFactor)),
        child: SingleChildScrollView(child: child),
      ),
    );
  }

  /// Dialog with header, scrollable body, and pinned footer (actions).
  static Widget panel({
    required BuildContext context,
    required Widget title,
    required Widget body,
    required List<Widget> actions,
    double maxWidth = 450,
    double maxHeightFactor = 0.75,
  }) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth(context, maxWidth: maxWidth),
          maxHeight: maxHeight(context, factor: maxHeightFactor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: title,
            ),
            const Divider(height: 1, color: Color(0xFFE4E4E7)),
            Flexible(child: body),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
