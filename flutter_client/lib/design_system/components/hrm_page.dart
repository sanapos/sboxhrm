import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_elevation.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_space.dart';

/// Theme extension for density + content max widths.
@immutable
class AppDesignTokens extends ThemeExtension<AppDesignTokens> {
  const AppDesignTokens({
    required this.density,
    required this.contentMaxWidth,
    required this.dashboardMaxWidth,
    required this.formMaxWidth,
    required this.listRowHeight,
  });

  final VisualDensity density;
  final double contentMaxWidth;
  final double dashboardMaxWidth;
  final double formMaxWidth;
  final double listRowHeight;

  static const comfortable = AppDesignTokens(
    density: VisualDensity.standard,
    contentMaxWidth: 1280,
    dashboardMaxWidth: 1440,
    formMaxWidth: 720,
    listRowHeight: 52,
  );

  static const compact = AppDesignTokens(
    density: VisualDensity.compact,
    contentMaxWidth: 1360,
    dashboardMaxWidth: 1600,
    formMaxWidth: 720,
    listRowHeight: 40,
  );

  static AppDesignTokens of(BuildContext context) =>
      Theme.of(context).extension<AppDesignTokens>() ?? comfortable;

  @override
  AppDesignTokens copyWith({
    VisualDensity? density,
    double? contentMaxWidth,
    double? dashboardMaxWidth,
    double? formMaxWidth,
    double? listRowHeight,
  }) {
    return AppDesignTokens(
      density: density ?? this.density,
      contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
      dashboardMaxWidth: dashboardMaxWidth ?? this.dashboardMaxWidth,
      formMaxWidth: formMaxWidth ?? this.formMaxWidth,
      listRowHeight: listRowHeight ?? this.listRowHeight,
    );
  }

  @override
  AppDesignTokens lerp(ThemeExtension<AppDesignTokens>? other, double t) {
    if (other is! AppDesignTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// Page shell: centers content with max-width + optional header.
class HrmPage extends StatelessWidget {
  const HrmPage({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.padding,
    this.maxWidth,
    this.fillHeight = true,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = AppDesignTokens.of(context);
    final pad = padding ?? AppSpace.page(context);
    final max = maxWidth ?? tokens.contentMaxWidth;

    final hasHeader = title != null || (actions != null && actions!.isNotEmpty);

    Widget inner = child;
    if (hasHeader) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(
            title: title ?? '',
            subtitle: subtitle,
            actions: actions,
          ),
          const SizedBox(height: AppSpace.sm),
          if (fillHeight) Expanded(child: child) else child,
        ],
      );
    }

    final constrained = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: Padding(padding: pad, child: inner),
      ),
    );

    if (fillHeight && hasHeader) {
      return SizedBox.expand(child: constrained);
    }
    return constrained;
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    this.subtitle,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.of(context).onSurface,
                  ),
                ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions != null) ...[
          const SizedBox(width: AppSpace.sm),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: actions!,
          ),
        ],
      ],
    );
  }
}

class HrmCard extends StatelessWidget {
  const HrmCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.elevated = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool elevated;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deco = AppElevation.cardSurface(
      color: color ?? scheme.surface,
      borderColor: scheme.outlineVariant,
      elevated: elevated,
    );
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpace.md),
      child: child,
    );
    if (onTap == null) {
      return DecoratedBox(decoration: deco, child: content);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Ink(decoration: deco, child: content),
      ),
    );
  }
}
