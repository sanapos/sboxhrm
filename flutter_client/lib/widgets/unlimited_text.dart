import 'package:flutter/material.dart';
import '../l10n/app_tr.dart';

/// Multiline text — opts out of app-wide [DefaultTextStyle] ?? line limits.
class UnlimitedText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;

  const UnlimitedText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      tr(data),
      style: style,
      textAlign: textAlign,
      maxLines: null,
      overflow: TextOverflow.visible,
      softWrap: true,
    );
  }
}

/// Wrap rich HTML / editors so content is not ellipsized by the app default.
class UnlimitedTextScope extends StatelessWidget {
  final Widget child;

  const UnlimitedTextScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      maxLines: null,
      overflow: TextOverflow.visible,
      softWrap: true,
      child: child,
    );
  }
}
