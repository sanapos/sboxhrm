import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wh_mobile_theme.dart';
import '../../l10n/app_tr.dart';

/// Scaffold chuẩn cho màn Kho mobile — nền xám, bottom bar cố định.
class WhMobileScaffold extends StatelessWidget {
  const WhMobileScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    required this.body,
    this.bottomBar,
    this.floatingAction,
    this.extendBodyBehindAppBar = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget body;
  final Widget? bottomBar;
  final Widget? floatingAction;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: WhMobileTheme.bg,
        extendBody: true,
        floatingActionButton: floatingAction,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WhGlassAppBar(
              title: title,
              subtitle: subtitle,
              leading: leading,
              actions: actions,
              topPadding: top,
            ),
            Expanded(child: body),
            if (bottomBar != null) bottomBar!,
          ],
        ),
      ),
    );
  }
}

class _WhGlassAppBar extends StatelessWidget {
  const _WhGlassAppBar({
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    required this.topPadding,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, topPadding + 4, 8, 12),
          decoration: BoxDecoration(
            color: WhMobileTheme.surfaceGlass,
            border: Border(
              bottom: BorderSide(color: WhMobileTheme.divider.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              leading ??
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    color: WhMobileTheme.primary,
                    onPressed: () => Navigator.maybePop(context),
                  ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr(title), style: WhMobileTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(tr(subtitle!), style: WhMobileTheme.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Thanh hành động cố định dưới cùng — Lưu nháp + Hoàn thành.
class WhMobileBottomBar extends StatelessWidget {
  const WhMobileBottomBar({
    super.key,
    this.onSaveDraft,
    this.onComplete,
    this.saveDraftLabel = 'Lưu nháp',
    this.completeLabel = 'Hoàn thành',
    this.loading = false,
    this.readOnly = false,
    this.secondaryAction,
    this.dangerAction,
  });

  final VoidCallback? onSaveDraft;
  final VoidCallback? onComplete;
  final String saveDraftLabel;
  final String completeLabel;
  final bool loading;
  final bool readOnly;
  final Widget? secondaryAction;
  final Widget? dangerAction;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
          decoration: BoxDecoration(
            color: WhMobileTheme.surfaceGlass,
            border: Border(
              top: BorderSide(color: WhMobileTheme.divider.withValues(alpha: 0.5)),
            ),
          ),
          child: readOnly
              ? (dangerAction ?? secondaryAction ?? const SizedBox.shrink())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (onSaveDraft != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: loading ? null : onSaveDraft,
                              style: WhMobileTheme.secondaryButton(),
                              child: Text(tr(loading ? 'Đang lưu…' : saveDraftLabel)),
                            ),
                          ),
                        if (onSaveDraft != null && onComplete != null)
                          const SizedBox(width: 10),
                        if (onComplete != null)
                          Expanded(
                            flex: onSaveDraft != null ? 1 : 2,
                            child: FilledButton(
                              onPressed: loading ? null : onComplete,
                              style: WhMobileTheme.primaryButton(),
                              child: Text(tr(loading ? 'Đang lưu…' : completeLabel)),
                            ),
                          ),
                      ],
                    ),
                    if (secondaryAction != null) ...[
                      const SizedBox(height: 8),
                      secondaryAction!,
                    ],
                    if (dangerAction != null) ...[
                      const SizedBox(height: 8),
                      dangerAction!,
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class WhStatusPill extends StatelessWidget {
  const WhStatusPill({super.key, required this.status, this.draftLabel = 'Nháp'});

  final String status;
  final String draftLabel;

  @override
  Widget build(BuildContext context) {
    final color = WhMobileTheme.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tr(WhMobileTheme.statusLabel(status, draftLabel: draftLabel)),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color == WhMobileTheme.textTertiary
              ? WhMobileTheme.textSecondary
              : color,
        ),
      ),
    );
  }
}

class WhGlassCard extends StatelessWidget {
  const WhGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: WhMobileTheme.card(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(WhMobileTheme.radiusLg),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
    return card;
  }
}

/// Thẻ phiếu trong danh sách.
class WhDocListTile extends StatelessWidget {
  const WhDocListTile({
    super.key,
    required this.docNo,
    required this.status,
    required this.amountLabel,
    required this.meta,
    this.subtitle,
    this.onTap,
    this.draftLabel = 'Nháp',
  });

  final String docNo;
  final String status;
  final String amountLabel;
  final String meta;
  final String? subtitle;
  final VoidCallback? onTap;
  final String draftLabel;

  @override
  Widget build(BuildContext context) {
    return WhGlassCard(
      margin: const EdgeInsets.only(bottom: WhMobileTheme.gap),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tr(docNo), style: WhMobileTheme.titleMedium),
                    ),
                    WhStatusPill(status: status, draftLabel: draftLabel),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(tr(subtitle!), style: WhMobileTheme.caption),
                ],
                const SizedBox(height: 6),
                Text(tr(meta), style: WhMobileTheme.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(tr(amountLabel), style: WhMobileTheme.money),
              const SizedBox(height: 4),
              Icon(Icons.chevron_right_rounded, color: WhMobileTheme.textTertiary, size: 22),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bộ điều chỉnh số lượng — nút lớn, thao tác một tay.
class WhQtyStepper extends StatelessWidget {
  const WhQtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.step = 1,
    this.readOnly = false,
    this.label,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double? max;
  final double step;
  final bool readOnly;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final canDec = !readOnly && value > min;
    final canInc = !readOnly && (max == null || value + step <= max!);
    final display = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(tr(label!), style: WhMobileTheme.label),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            _StepBtn(
              icon: Icons.remove_rounded,
              enabled: canDec,
              onTap: () => onChanged((value - step).clamp(min, max ?? double.infinity)),
            ),
            Expanded(
              child: Center(
                child: Text(tr(display), style: WhMobileTheme.titleLarge.copyWith(fontSize: 24)),
              ),
            ),
            _StepBtn(
              icon: Icons.add_rounded,
              enabled: canInc,
              onTap: () => onChanged((value + step).clamp(min, max ?? double.infinity)),
              primary: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? (primary ? WhMobileTheme.primary : WhMobileTheme.bg)
          : WhMobileTheme.bg.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(WhMobileTheme.radiusMd),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(WhMobileTheme.radiusMd),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            icon,
            size: 26,
            color: enabled
                ? (primary ? Colors.white : WhMobileTheme.textPrimary)
                : WhMobileTheme.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Thẻ dòng hàng trong editor.
class WhLineCard extends StatelessWidget {
  const WhLineCard({
    super.key,
    required this.index,
    required this.name,
    this.code,
    this.unit,
    required this.child,
    this.trailing,
    this.onRemove,
    this.readOnly = false,
  });

  final int index;
  final String name;
  final String? code;
  final String? unit;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onRemove;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: WhMobileTheme.gap),
      decoration: WhMobileTheme.card(radius: WhMobileTheme.radiusMd),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WhMobileTheme.primaryMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tr('$index'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WhMobileTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(name), style: WhMobileTheme.titleMedium.copyWith(fontSize: 15)),
                    if (code != null && code!.isNotEmpty)
                      Text(tr('$code${unit != null ? ' · $unit' : ''}'), style: WhMobileTheme.caption),
                  ],
                ),
              ),
              if (!readOnly && onRemove != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 20, color: WhMobileTheme.danger.withValues(alpha: 0.8)),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
          if (trailing != null) ...[const SizedBox(height: 8), trailing!],
        ],
      ),
    );
  }
}

class WhSectionHeader extends StatelessWidget {
  const WhSectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(tr(title.toUpperCase()), style: WhMobileTheme.label)),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class WhSearchField extends StatelessWidget {
  const WhSearchField({
    super.key,
    required this.controller,
    this.hint = 'Tìm kiếm…',
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: WhMobileTheme.body,
      decoration: WhMobileTheme.fieldDecoration(
        hint: hint,
        prefix: const Icon(Icons.search_rounded, color: WhMobileTheme.textSecondary, size: 22),
      ).copyWith(
        suffixIcon: ValueListenableBuilder(
          valueListenable: controller,
          builder: (_, __, ___) {
            if (controller.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.cancel_rounded, size: 20),
              color: WhMobileTheme.textTertiary,
              onPressed: () {
                controller.clear();
                onChanged?.call('');
              },
            );
          },
        ),
      ),
    );
  }
}

class WhSummaryRow extends StatelessWidget {
  const WhSummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr(label), style: WhMobileTheme.caption),
          Text(
            tr(value),
            style: (bold ? WhMobileTheme.money : WhMobileTheme.body).copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class WhEmptyState extends StatelessWidget {
  const WhEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: WhMobileTheme.textTertiary),
            const SizedBox(height: 16),
            Text(tr(title), style: WhMobileTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(tr(subtitle!), style: WhMobileTheme.caption, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class WhHubTile extends StatelessWidget {
  const WhHubTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? WhMobileTheme.primary;
    return Material(
      color: WhMobileTheme.surface,
      borderRadius: BorderRadius.circular(WhMobileTheme.radiusLg),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WhMobileTheme.radiusLg),
        child: Ink(
          decoration: WhMobileTheme.card(),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: c, size: 26),
              ),
              const SizedBox(height: 10),
              Text(
                tr(label),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WhMobileTheme.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
