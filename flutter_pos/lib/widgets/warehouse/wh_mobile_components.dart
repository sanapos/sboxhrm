import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wh_mobile_theme.dart';
import '../../l10n/app_tr.dart';
import '../../utils/play_system_ui.dart';

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
    this.showAppBar = true,
  });

  /// false khi màn nằm trong MainLayout (thanh trên đã có tiêu đề) — tránh tiêu đề lặp.
  final bool showAppBar;
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
      value: kPlayOverlayOnLightBg,
      child: Scaffold(
        backgroundColor: WhMobileTheme.bg,
        extendBody: true,
        floatingActionButton: floatingAction,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showAppBar)
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
              bottom: BorderSide(color: WhMobileTheme.divider.withOpacity(0.5)),
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

/// Thanh hành động cố định dưới cùng — Lưu tạm + Hoàn thành.
class WhMobileBottomBar extends StatelessWidget {
  const WhMobileBottomBar({
    super.key,
    this.onSaveDraft,
    this.onComplete,
    this.saveDraftLabel = 'Lưu tạm',
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
              top: BorderSide(color: WhMobileTheme.divider.withOpacity(0.5)),
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
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(tr(loading ? 'Đang lưu…' : completeLabel), maxLines: 1, softWrap: false),
                              ),
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
  const WhStatusPill({super.key, required this.status, this.draftLabel = 'Phiếu tạm'});

  final String status;
  final String draftLabel;

  @override
  Widget build(BuildContext context) {
    final color = WhMobileTheme.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
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
    this.draftLabel = 'Phiếu tạm',
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
    // Mã phiếu + số tiền một hàng; NCC / số dòng · ngày + trạng thái hàng dưới — không bẻ mã phiếu
    // khi chữ hệ thống phóng to (trước đây «PN00 / 0015»).
    return WhGlassCard(
      margin: const EdgeInsets.only(bottom: WhMobileTheme.gap),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(docNo),
                  style: WhMobileTheme.titleMedium.copyWith(fontSize: 16),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                tr(amountLabel),
                style: WhMobileTheme.money.copyWith(fontSize: 16),
                maxLines: 1,
                softWrap: false,
              ),
            ],
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              tr(subtitle!),
              style: WhMobileTheme.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(meta),
                  style: WhMobileTheme.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              WhStatusPill(status: status, draftLabel: draftLabel),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bộ điều chỉnh số lượng — nút lớn, thao tác một tay.
///
/// Ô nhập giữ controller/focus riêng: trước đây ô dùng key theo giá trị nên mỗi phím gõ
/// tạo lại ô, mất con trỏ — xóa «42» rồi gõ «1» ra số sai.
class WhQtyStepper extends StatefulWidget {
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
  State<WhQtyStepper> createState() => _WhQtyStepperState();
}

class _WhQtyStepperState extends State<WhQtyStepper> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  /// 1 → «1», 1.5 → «1,5» (dấu phẩy thập phân kiểu VN, không phân tách nghìn).
  static String _fmt(double v) {
    var t = v.toStringAsFixed(3);
    t = t.replaceFirst(RegExp(r'\.?0+$'), '');
    return t.replaceAll('.', ',');
  }

  static double? _parse(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  double _clamp(double v) => v.clamp(widget.min, widget.max ?? double.infinity).toDouble();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant WhQtyStepper old) {
    super.didUpdateWidget(old);
    // Giá trị đổi từ ngoài (nút +/−, quy đổi ĐVT, «Khớp tồn») — chỉ ghi lại ô khi
    // khác số đang gõ, để không phá con trỏ lúc người dùng đang nhập.
    if (_parse(_ctrl.text) != widget.value) {
      final t = _fmt(widget.value);
      _ctrl.value = TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
    }
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      // Chọn sẵn cả số — gõ là thay số cũ.
      _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    } else {
      _commit();
    }
  }

  /// Rời ô / Enter: ô trống hoặc sai thì trả về giá trị hiện tại.
  void _commit() {
    final v = _parse(_ctrl.text);
    if (v == null) {
      _ctrl.text = _fmt(widget.value);
      return;
    }
    final c = _clamp(v);
    if (c != widget.value) widget.onChanged(c);
    if (c != v) _ctrl.text = _fmt(c);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final canDec = !widget.readOnly && value > widget.min;
    final canInc = !widget.readOnly && (widget.max == null || value + widget.step <= widget.max!);

    return Row(
      children: [
        if (widget.label != null) ...[
          SizedBox(
            width: 72,
            child: Text(
              tr(widget.label!),
              style: WhMobileTheme.label.copyWith(fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
        ],
        _StepBtn(
          icon: Icons.remove_rounded,
          enabled: canDec,
          onTap: () => widget.onChanged(_clamp(value - widget.step)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: !widget.readOnly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textAlign: TextAlign.center,
              style: WhMobileTheme.titleLarge.copyWith(fontSize: 16),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
              ),
              onSubmitted: (_) => _commit(),
              onChanged: (raw) {
                // Đang gõ: báo giá trị hợp lệ ngay (cập nhật lệch / thành tiền),
                // ô trống thì chờ — không ép về 0.
                final v = _parse(raw);
                if (v != null && v >= widget.min) {
                  final c = _clamp(v);
                  if (c != widget.value) widget.onChanged(c);
                }
              },
            ),
          ),
        ),
        _StepBtn(
          icon: Icons.add_rounded,
          enabled: canInc,
          onTap: () => widget.onChanged(_clamp(value + widget.step)),
          primary: true,
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
          : WhMobileTheme.bg.withOpacity(0.5),
      borderRadius: BorderRadius.circular(WhMobileTheme.radiusMd),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(WhMobileTheme.radiusMd),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 18,
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: WhMobileTheme.card(radius: WhMobileTheme.radiusSm),
      // Xem phiếu (chỉ đọc): lề 16 như thẻ tổng phía trên — số tiền dòng thẳng cột với tổng phiếu.
      padding: readOnly
          ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
          : const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WhMobileTheme.primaryMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tr('$index'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: WhMobileTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WhMobileTheme.titleMedium.copyWith(fontSize: 13),
                    ),
                    if (code != null && code!.isNotEmpty)
                      Text(
                        tr('$code${unit != null ? ' · $unit' : ''}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WhMobileTheme.caption.copyWith(fontSize: 10),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                DefaultTextStyle.merge(
                  style: WhMobileTheme.money.copyWith(fontSize: 13),
                  child: trailing!,
                ),
              ],
              if (!readOnly && onRemove != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: WhMobileTheme.danger.withOpacity(0.8)),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: 6),
          child,
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
        // Nền trắng + viền nhạt: fieldDecoration tô nền trùng màu nền trang, ô tìm gần như vô hình.
        fillColor: WhMobileTheme.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WhMobileTheme.radiusSm),
          borderSide: const BorderSide(color: WhMobileTheme.divider),
        ),
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
                  color: c.withOpacity(0.1),
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
