import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/vietnamese_font.dart';

/// Tông màu ngữ nghĩa cho nhãn / thẻ số liệu / thông báo.
enum SboxTone { neutral, brand, success, warning, danger, violet }

extension SboxToneColors on SboxTone {
  Color get fg => switch (this) {
        SboxTone.neutral => SboxColors.slate700,
        SboxTone.brand => SboxColors.brand800,
        SboxTone.success => SboxColors.successText,
        SboxTone.warning => SboxColors.warningText,
        SboxTone.danger => SboxColors.dangerText,
        SboxTone.violet => SboxColors.violetText,
      };
  Color get bg => switch (this) {
        SboxTone.neutral => SboxColors.slate100,
        SboxTone.brand => SboxColors.brand50,
        SboxTone.success => SboxColors.successSoft,
        SboxTone.warning => SboxColors.warningSoft,
        SboxTone.danger => SboxColors.dangerSoft,
        SboxTone.violet => SboxColors.violetSoft,
      };
  Color get solid => switch (this) {
        SboxTone.neutral => SboxColors.slate500,
        SboxTone.brand => SboxColors.brand600,
        SboxTone.success => SboxColors.success,
        SboxTone.warning => SboxColors.warning,
        SboxTone.danger => SboxColors.danger,
        SboxTone.violet => SboxColors.violet,
      };
}

// ─── Nút ────────────────────────────────────────────────────────────

enum SboxButtonKind { primary, secondary, ghost, danger, pay }

enum SboxButtonSize { sm, md, lg }

/// Nút chuẩn: 5 kiểu × 3 cỡ. Có trạng thái đang xử lý.
class SboxButton extends StatelessWidget {
  const SboxButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = SboxButtonKind.primary,
    this.size = SboxButtonSize.md,
    this.loading = false,
    this.expand = false,
  });

  const SboxButton.secondary({super.key, required this.label, this.onPressed, this.icon, this.size = SboxButtonSize.md, this.loading = false, this.expand = false})
      : kind = SboxButtonKind.secondary;
  const SboxButton.ghost({super.key, required this.label, this.onPressed, this.icon, this.size = SboxButtonSize.md, this.loading = false, this.expand = false})
      : kind = SboxButtonKind.ghost;
  const SboxButton.danger({super.key, required this.label, this.onPressed, this.icon, this.size = SboxButtonSize.md, this.loading = false, this.expand = false})
      : kind = SboxButtonKind.danger;
  const SboxButton.pay({super.key, required this.label, this.onPressed, this.icon, this.size = SboxButtonSize.lg, this.loading = false, this.expand = true})
      : kind = SboxButtonKind.pay;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SboxButtonKind kind;
  final SboxButtonSize size;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final h = switch (size) {
      SboxButtonSize.sm => SboxSize.controlSm,
      SboxButtonSize.md => SboxSize.control,
      SboxButtonSize.lg => SboxSize.controlLg,
    };
    final fs = size == SboxButtonSize.sm ? SboxType.small : (size == SboxButtonSize.lg ? SboxType.titleSm : SboxType.body);
    final padH = size == SboxButtonSize.sm ? 12.0 : (size == SboxButtonSize.lg ? 22.0 : 16.0);
    final (bg, fg, side, hover) = switch (kind) {
      SboxButtonKind.primary => (SboxColors.primary, Colors.white, null, SboxColors.primaryHover),
      SboxButtonKind.secondary => (SboxColors.white, SboxColors.slate700, SboxColors.borderStrong, SboxColors.slate50),
      SboxButtonKind.ghost => (Colors.transparent, SboxColors.primary, null, SboxColors.brand50),
      SboxButtonKind.danger => (SboxColors.danger, Colors.white, null, SboxColors.dangerText),
      SboxButtonKind.pay => (SboxColors.pay, Colors.white, null, SboxColors.payHover),
    };
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(expand ? double.infinity : 0, h)),
      fixedSize: WidgetStatePropertyAll(Size.fromHeight(h)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: padH)),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: SboxRadius.mdAll)),
      elevation: const WidgetStatePropertyAll(0),
      side: WidgetStatePropertyAll(side == null ? BorderSide.none : BorderSide(color: side)),
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return kind == SboxButtonKind.ghost ? Colors.transparent : SboxColors.slate100;
        }
        if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) return hover;
        return bg;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? SboxColors.textDisabled : fg),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      textStyle: WidgetStatePropertyAll(TextStyle(
        fontFamily: kVietnameseFontFamily,
        fontFamilyFallback: kVietnameseFontFallback,
        fontSize: fs,
        fontWeight: SboxType.semibold,
      )),
    );
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: fs + 2,
            height: fs + 2,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: fs + 4),
        if (loading || icon != null) const SizedBox(width: SboxSpace.sm),
        Flexible(child: Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
    // Đang xử lý: giữ màu nút (không xám như nút tắt), chặn bấm lặp.
    return TextButton(onPressed: loading ? () {} : onPressed, style: style, child: child);
  }
}

/// Nút chỉ có biểu tượng, luôn có chú thích khi rê chuột.
class SboxIconButton extends StatelessWidget {
  const SboxIconButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.tone = SboxTone.neutral, this.bordered = true});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final SboxTone tone;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr(tooltip),
      child: Material(
        color: SboxColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: SboxRadius.mdAll,
          side: bordered ? const BorderSide(color: SboxColors.border) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: SboxRadius.mdAll,
          onTap: onPressed,
          child: SizedBox(
            width: SboxSize.control,
            height: SboxSize.control,
            child: Icon(icon, size: 20, color: tone == SboxTone.neutral ? SboxColors.slate600 : tone.solid),
          ),
        ),
      ),
    );
  }
}

// ─── Nhãn trạng thái ───────────────────────────────────────────────

class SboxStatusChip extends StatelessWidget {
  const SboxStatusChip({super.key, required this.label, this.tone = SboxTone.neutral, this.icon, this.dot = false});

  final String label;
  final SboxTone tone;
  final IconData? icon;
  /// Chấm tròn trước chữ (kiểu trạng thái đơn hàng).
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: tone.bg, borderRadius: SboxRadius.pillAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: tone.solid, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ] else if (icon != null) ...[
          Icon(icon, size: 13, color: tone.fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            tr(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: SboxType.caption, fontWeight: SboxType.semibold, color: tone.fg, height: 1.3),
          ),
        ),
      ]),
    );
  }
}

// ─── Thẻ / mục ─────────────────────────────────────────────────────

/// Thẻ trắng bo 14, viền mảnh — khung chuẩn cho mọi khối nội dung.
class SboxCard extends StatelessWidget {
  const SboxCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(SboxSpace.lg),
    this.onTap,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final header = title == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.md, SboxSpace.md, SboxSpace.md),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(title!), style: SboxType.titleSmStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(tr(subtitle!), style: SboxType.smallStyle(SboxColors.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
          );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null) ...[header, const Divider(height: 1, color: SboxColors.divider)],
        Padding(padding: padding, child: child),
      ],
    );
    return Material(
      color: SboxColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: SboxRadius.lgAll, side: BorderSide(color: SboxColors.border)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

/// Tiêu đề trang: tên + mô tả + nút hành động (tự xuống dòng trên điện thoại).
class SboxPageHeader extends StatelessWidget {
  const SboxPageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.leading});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final mobile = SboxBreakpoints.isMobile(context);
    final titleBlock = Row(children: [
      if (leading != null) ...[leading!, const SizedBox(width: SboxSpace.md)],
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            tr(title),
            style: mobile ? SboxType.titleStyle() : SboxType.headlineStyle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(tr(subtitle!), style: SboxType.smallStyle(SboxColors.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
    ]);
    if (actions.isEmpty) return titleBlock;
    final acts = Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: actions);
    if (mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        titleBlock,
        const SizedBox(height: SboxSpace.md),
        acts,
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(child: titleBlock),
      const SizedBox(width: SboxSpace.lg),
      acts,
    ]);
  }
}

// ─── Trạng thái rỗng / đang tải ────────────────────────────────────

class SboxEmptyState extends StatelessWidget {
  const SboxEmptyState({super.key, this.icon = Icons.inbox_outlined, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SboxSpace.xxl, horizontal: SboxSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: SboxColors.brand50, shape: BoxShape.circle),
            child: Icon(icon, size: 28, color: SboxColors.brand600),
          ),
          const SizedBox(height: SboxSpace.md),
          Text(tr(title), style: SboxType.titleSmStyle(), textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: SboxSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(tr(message!), style: SboxType.smallStyle(SboxColors.textMuted), textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[const SizedBox(height: SboxSpace.lg), action!],
        ]),
      ),
    );
  }
}

class SboxLoading extends StatelessWidget {
  const SboxLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SboxSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          if (message != null) ...[
            const SizedBox(height: SboxSpace.md),
            Text(tr(message!), style: SboxType.smallStyle(SboxColors.textMuted)),
          ],
        ]),
      ),
    );
  }
}

// ─── Thẻ số liệu ───────────────────────────────────────────────────

class SboxMetricCard extends StatelessWidget {
  const SboxMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone = SboxTone.brand,
    this.delta,
    this.deltaUp,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final SboxTone tone;
  /// Ví dụ "+12% so với hôm qua".
  final String? delta;
  final bool? deltaUp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SboxCard(
      onTap: onTap,
      padding: const EdgeInsets.all(SboxSpace.lg),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(label), style: SboxType.smallStyle(SboxColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: SboxSpace.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: SboxType.moneyStyle(size: SboxType.headline)),
            ),
            if (delta != null) ...[
              const SizedBox(height: SboxSpace.xs),
              Row(children: [
                if (deltaUp != null)
                  Icon(deltaUp! ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 16, color: deltaUp! ? SboxColors.success : SboxColors.danger),
                if (deltaUp != null) const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    tr(delta!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SboxType.captionStyle(deltaUp == null
                        ? SboxColors.textMuted
                        : (deltaUp! ? SboxColors.successText : SboxColors.dangerText)),
                  ),
                ),
              ]),
            ],
          ]),
        ),
        if (icon != null)
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tone.bg, borderRadius: SboxRadius.mdAll),
            child: Icon(icon, size: 22, color: tone.solid),
          ),
      ]),
    );
  }
}

// ─── Hộp thoại xác nhận ────────────────────────────────────────────

abstract final class SboxDialogs {
  /// Hộp thoại xác nhận chuẩn. Trả về true nếu người dùng đồng ý.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String confirmLabel = 'Đồng ý',
    String cancelLabel = 'Hủy',
    bool danger = false,
    IconData? icon,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(SboxSpace.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(SboxSpace.xl),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: danger ? SboxColors.dangerSoft : SboxColors.brand50,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon ?? (danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
                    color: danger ? SboxColors.danger : SboxColors.brand600),
              ),
              const SizedBox(height: SboxSpace.lg),
              Text(tr(title), style: SboxType.titleStyle()),
              if (message != null) ...[
                const SizedBox(height: SboxSpace.sm),
                Text(tr(message), style: SboxType.bodyStyle(SboxColors.textSecondary)),
              ],
              const SizedBox(height: SboxSpace.xl),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                SboxButton.secondary(label: cancelLabel, onPressed: () => Navigator.pop(ctx, false)),
                const SizedBox(width: SboxSpace.sm),
                SboxButton(
                  label: confirmLabel,
                  kind: danger ? SboxButtonKind.danger : SboxButtonKind.primary,
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    return ok == true;
  }
}
