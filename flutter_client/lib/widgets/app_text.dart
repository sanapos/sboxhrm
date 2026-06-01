import 'package:flutter/material.dart';
import '../utils/vietnamese_font.dart';

/// Text variants with safe overflow defaults for Vietnamese UI.
enum AppTextVariant { body, title, label, chip, tableCell, metric }

/// Drop-in [Text] ?? replacement — always sets [maxLines] + [overflow] ?? unless multiline.
class AppText extends StatelessWidget {
  final String data;
  final AppTextVariant variant;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;
  final bool softWrap;
  final bool fit;

  const AppText(
    this.data, {
    super.key,
    this.variant = AppTextVariant.body,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
    this.softWrap = false,
    this.fit = false,
  });

  factory AppText.title(
    String data, {
    Key? key,
    TextStyle? style,
    int maxLines = 1,
    TextAlign? textAlign,
  }) =>
      AppText(
        data,
        key: key,
        variant: AppTextVariant.title,
        style: style,
        maxLines: maxLines,
        textAlign: textAlign,
      );

  factory AppText.label(
    String data, {
    Key? key,
    TextStyle? style,
    int maxLines = 1,
  }) =>
      AppText(
        data,
        key: key,
        variant: AppTextVariant.label,
        style: style,
        maxLines: maxLines,
      );

  factory AppText.chip(String data, {Key? key, TextStyle? style}) => AppText(
        data,
        key: key,
        variant: AppTextVariant.chip,
        style: style,
        maxLines: 1,
      );

  factory AppText.table(
    String data, {
    Key? key,
    TextStyle? style,
    int maxLines = 2,
    TextAlign? textAlign,
  }) =>
      AppText(
        data,
        key: key,
        variant: AppTextVariant.tableCell,
        style: style,
        maxLines: maxLines,
        softWrap: true,
        textAlign: textAlign,
      );

  factory AppText.metric(
    String data, {
    Key? key,
    TextStyle? style,
  }) =>
      AppText(
        data,
        key: key,
        variant: AppTextVariant.metric,
        style: style,
        maxLines: 1,
        fit: true,
      );

  factory AppText.body(
    String data, {
    Key? key,
    TextStyle? style,
    int maxLines = 3,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) =>
      AppText(
        data,
        key: key,
        variant: AppTextVariant.body,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: true,
      );

  TextStyle _baseStyle(TextTheme theme) {
    switch (variant) {
      case AppTextVariant.title:
        return theme.titleMedium ?? const TextStyle(fontSize: 15);
      case AppTextVariant.label:
        return theme.labelMedium ?? const TextStyle(fontSize: 12);
      case AppTextVariant.chip:
        return theme.labelLarge ?? const TextStyle(fontSize: 12);
      case AppTextVariant.tableCell:
        return theme.bodyMedium ?? const TextStyle(fontSize: 13);
      case AppTextVariant.metric:
        return theme.headlineMedium ?? const TextStyle(fontSize: 22);
      case AppTextVariant.body:
        return theme.bodyMedium ?? const TextStyle(fontSize: 14);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final effective = _baseStyle(theme).merge(style);
    final text = Text(
      data,
      style: effective,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap || maxLines > 1,
    );
    if (!fit) return text;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: switch (textAlign) {
        TextAlign.center => Alignment.center,
        TextAlign.end || TextAlign.right => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      child: text,
    );
  }
}

/// Vietnamese-safe “code” style (avoid system monospace missing diacritics).
TextStyle appCodeTextStyle(
  BuildContext context, {
  double fontSize = 12,
  FontWeight fontWeight = FontWeight.w500,
  Color? color,
}) {
  return vietnameseTextStyle(TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: 0.4,
    color: color ?? Theme.of(context).colorScheme.onSurface,
    fontFeatures: const [FontFeature.tabularFigures()],
  ));
}
