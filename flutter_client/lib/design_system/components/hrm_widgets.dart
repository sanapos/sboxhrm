import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_space.dart';
import 'hrm_page.dart';

enum HrmButtonVariant { filled, outlined, text, tonal }

class HrmButton extends StatelessWidget {
  const HrmButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = HrmButtonVariant.filled,
    this.expanded = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final HrmButtonVariant variant;
  final bool expanded;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: AppSpace.xs),
                  Text(label),
                ],
              );

    final min = Size(expanded ? double.infinity : 0, 44);
    Widget button;
    switch (variant) {
      case HrmButtonVariant.filled:
        button = FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: min,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          ),
          child: child,
        );
      case HrmButtonVariant.outlined:
        button = OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: min,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          ),
          child: child,
        );
      case HrmButtonVariant.text:
        button = TextButton(
          onPressed: loading ? null : onPressed,
          style: TextButton.styleFrom(minimumSize: min),
          child: child,
        );
      case HrmButtonVariant.tonal:
        button = FilledButton.tonal(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: min,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          ),
          child: child,
        );
    }
    if (expanded) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

class HrmBadge extends StatelessWidget {
  const HrmBadge({
    super.key,
    required this.label,
    this.color,
    this.foreground,
  });

  final String label;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.info.withValues(alpha: 0.12);
    final fg = foreground ?? color ?? AppColors.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class HrmSkeleton extends StatelessWidget {
  const HrmSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? AppColors.surfaceMutedDark
        : AppColors.surfaceMuted;
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class HrmSkeletonList extends StatelessWidget {
  const HrmSkeletonList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (_, __) => HrmCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            HrmSkeleton(width: 180, height: 14),
            SizedBox(height: 10),
            HrmSkeleton(height: 12),
            SizedBox(height: 8),
            HrmSkeleton(width: 120, height: 12),
          ],
        ),
      ),
    );
  }
}

/// Lightweight data table with sticky-ish header + density.
class HrmDataGrid extends StatelessWidget {
  const HrmDataGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.headingRowHeight,
    this.dataRowHeight,
    this.onSelectAll,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final double? headingRowHeight;
  final double? dataRowHeight;
  final ValueChanged<bool?>? onSelectAll;

  @override
  Widget build(BuildContext context) {
    final tokens = AppDesignTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width > 400
                ? MediaQuery.sizeOf(context).width - 48
                : 400,
          ),
          child: DataTable(
            headingRowHeight: headingRowHeight ?? 48,
            dataRowMinHeight: dataRowHeight ?? tokens.listRowHeight,
            dataRowMaxHeight: (dataRowHeight ?? tokens.listRowHeight) + 16,
            headingRowColor: WidgetStatePropertyAll(
              scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            ),
            columns: columns,
            rows: rows,
            onSelectAll: onSelectAll,
            dividerThickness: 0.5,
            showCheckboxColumn: false,
          ),
        ),
      ),
    );
  }
}

abstract final class HrmToast {
  static void show(
    BuildContext context,
    String message, {
    bool error = false,
    bool success = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Color bg = scheme.inverseSurface;
    Color fg = scheme.onInverseSurface;
    if (error) {
      bg = AppColors.danger;
      fg = Colors.white;
    } else if (success) {
      bg = AppColors.success;
      fg = Colors.white;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: fg)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
        margin: const EdgeInsets.all(AppSpace.md),
      ),
    );
  }
}
