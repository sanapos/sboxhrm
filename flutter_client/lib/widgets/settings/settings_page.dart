import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../pos/pos_vnd_thousands_formatter.dart';
import '../sbox/sbox_ui.dart';

/// Chặn rời trang thiết lập khi còn thay đổi chưa lưu (nút back của Thiết lập SBOX, chuyển mục).
class SettingsLeaveGuard {
  SettingsLeaveGuard._();

  static Future<bool> Function()? _confirm;

  static void set(Future<bool> Function()? confirm) => _confirm = confirm;

  static bool get active => _confirm != null;

  /// true = được rời trang.
  static Future<bool> canLeave() async {
    final f = _confirm;
    if (f == null) return true;
    final ok = await f();
    if (ok) _confirm = null;
    return ok;
  }
}

/// Khung chuẩn cho mọi trang thiết lập: tiêu đề + mô tả, các khối, thanh «Lưu» cố định khi có thay đổi,
/// hỏi trước khi rời trang chưa lưu, nút khôi phục mặc định (tùy chọn).
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.dirty = false,
    this.saving = false,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onSave,
    this.onDiscard,
    this.onResetDefaults,
    this.headerActions = const [],
    this.maxWidth = 920,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;
  final bool dirty;
  final bool saving;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;
  final VoidCallback? onResetDefaults;
  final List<Widget> headerActions;
  final double maxWidth;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    _syncGuard();
  }

  @override
  void didUpdateWidget(covariant SettingsPage old) {
    super.didUpdateWidget(old);
    if (old.dirty != widget.dirty) _syncGuard();
  }

  @override
  void dispose() {
    if (widget.dirty) SettingsLeaveGuard.set(null);
    super.dispose();
  }

  void _syncGuard() => SettingsLeaveGuard.set(widget.dirty ? _confirmLeave : null);

  Future<bool> _confirmLeave() async {
    if (!mounted) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bỏ thay đổi chưa lưu?')),
        content: Text(tr('Các thay đổi trên trang «${widget.title}» chưa được lưu.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ở lại'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bỏ thay đổi'))),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _confirmReset() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Khôi phục mặc định?')),
        content: Text(tr('Các giá trị trên trang sẽ về mặc định. Bấm «Lưu» để áp dụng.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Khôi phục'))),
        ],
      ),
    );
    if (r == true) widget.onResetDefaults?.call();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 640;
    Widget body;
    if (widget.loading) {
      body = const SboxLoading(message: 'Đang tải thiết lập…');
    } else if (widget.error != null) {
      body = SboxEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Không tải được thiết lập',
        message: widget.error,
        action: widget.onRetry == null ? null : SboxButton.secondary(label: 'Thử lại', icon: Icons.refresh_rounded, onPressed: widget.onRetry),
      );
    } else {
      final header = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.icon != null) ...[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(12)),
            child: Icon(widget.icon, color: SboxColors.brand600),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(widget.title), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
            if (widget.subtitle != null)
              Text(tr(widget.subtitle!), style: const TextStyle(color: SboxColors.slate500)),
          ]),
        ),
        ...widget.headerActions,
        if (widget.onResetDefaults != null)
          narrow
              ? IconButton(tooltip: tr('Khôi phục mặc định'), onPressed: _confirmReset, icon: const Icon(Icons.restart_alt_rounded))
              : TextButton.icon(onPressed: _confirmReset, icon: const Icon(Icons.restart_alt_rounded, size: 18), label: Text(tr('Khôi phục mặc định'))),
      ]);
      body = ListView(
        padding: EdgeInsets.fromLTRB(narrow ? 12 : 24, 16, narrow ? 12 : 24, 110),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                header,
                const SizedBox(height: 16),
                for (final c in widget.children) ...[c, const SizedBox(height: 14)],
              ]),
            ),
          ),
        ],
      );
    }
    return PopScope(
      canPop: !widget.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          SettingsLeaveGuard.set(null);
          Navigator.of(context).maybePop();
        }
      },
      child: ColoredBox(
        color: SboxColors.slate50,
        child: Stack(children: [
          Positioned.fill(child: body),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !widget.dirty,
              child: ExcludeSemantics(
                excluding: !widget.dirty,
                child: AnimatedSlide(
                  offset: widget.dirty ? Offset.zero : const Offset(0, 1.2),
                  duration: const Duration(milliseconds: 180),
                  child: _saveBar(narrow),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _saveBar(bool narrow) => SafeArea(
        top: false,
        child: Container(
          margin: EdgeInsets.fromLTRB(narrow ? 8 : 24, 0, narrow ? 8 : 24, 12),
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          decoration: BoxDecoration(
            color: SboxColors.slate900,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            const Icon(Icons.edit_note_rounded, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Có thay đổi chưa lưu'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            if (widget.onDiscard != null)
              TextButton(
                onPressed: widget.saving ? null : widget.onDiscard,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: Text(tr('Hủy')),
              ),
            const SizedBox(width: 6),
            SboxButton(label: 'Lưu', icon: Icons.check_rounded, loading: widget.saving, onPressed: widget.saving ? null : widget.onSave),
          ]),
        ),
      );
}

/// Một khối thiết lập: tiêu đề + mô tả + nội dung.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children, this.subtitle, this.icon, this.trailing});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SboxCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 20, color: SboxColors.brand600)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(title), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(tr(subtitle!), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
                ),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 6),
        ...children,
      ]),
    );
  }
}

/// Một dòng thiết lập: nhãn + giải thích bên trái, ô điều khiển bên phải (điện thoại: xuống dòng).
class SettingsTile extends StatelessWidget {
  const SettingsTile({super.key, required this.label, required this.control, this.help, this.divider = true});

  final String label;
  final String? help;
  final Widget control;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 640;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate800)),
      if (help != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(tr(help!), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
        ),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (divider) const Divider(height: 1, color: SboxColors.divider),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: narrow
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, const SizedBox(height: 8), control])
            : Row(children: [Expanded(child: text), const SizedBox(width: 16), control]),
      ),
    ]);
  }
}

/// Hộp giải thích / ví dụ trong một khối.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key, this.icon = Icons.lightbulb_outline_rounded, this.tone = SboxTone.brand});

  final String text;
  final IconData icon;
  final SboxTone tone;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: tone.fg),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(text), style: TextStyle(fontSize: 12.5, color: tone.fg, height: 1.4))),
        ]),
      );
}

/// Chọn 1 trong vài giá trị dạng nút.
class SettingsSegment<T> extends StatelessWidget {
  const SettingsSegment({super.key, required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [for (final o in options) ButtonSegment(value: o.$1, label: Text(tr(o.$2)))],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

/// Ô nhập số tiền (có dấu chấm ngăn cách nghìn).
class SettingsMoneyField extends StatelessWidget {
  const SettingsMoneyField({super.key, required this.controller, required this.onChanged, this.enabled = true, this.width = 180});

  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          enabled: enabled,
          textAlign: TextAlign.right,
          keyboardType: TextInputType.number,
          inputFormatters: [PosVndThousandsFormatter()],
          decoration: InputDecoration(isDense: true, suffixText: '₫', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: (v) => onChanged(PosVndThousandsFormatter.parse(v)),
        ),
      );
}

/// Ô nhập phần trăm (cho phép số thập phân, dấu phẩy hoặc chấm).
class SettingsPercentField extends StatelessWidget {
  const SettingsPercentField({super.key, required this.controller, required this.onChanged, this.enabled = true, this.width = 110});

  final TextEditingController controller;
  final ValueChanged<double?> onChanged;
  final bool enabled;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          enabled: enabled,
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(isDense: true, suffixText: '%', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: (v) => onChanged(double.tryParse(v.replaceAll(',', '.'))),
        ),
      );
}

String settingsMoney(num v) => PosVndThousandsFormatter.format(v).isEmpty ? '0' : PosVndThousandsFormatter.format(v);

String settingsNum(num v) {
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString().replaceAll('.', ',');
}
