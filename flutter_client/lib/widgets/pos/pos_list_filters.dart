import 'package:flutter/material.dart';

import '../../utils/pos_kiot_time_range.dart';
import '../../utils/responsive_helper.dart';
import '../sbox/sbox_ui.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Bộ lọc dùng chung cho các màn danh sách POS (phiếu kho, trả hàng, hóa đơn…):
/// cùng kiểu với [SboxFilterChip] để thanh lọc gọn một hàng như HRM.

/// Khung nút lọc « Nhãn: Giá trị ▾ ».
class PosChipFrame extends StatelessWidget {
  const PosChipFrame({super.key, required this.label, required this.value, this.active = false, this.icon});

  final String label;
  final String value;
  final bool active;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: SboxSize.control,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active ? SboxColors.brand50 : SboxColors.surface,
        border: Border.all(color: active ? SboxColors.primary : SboxColors.borderStrong),
        borderRadius: SboxRadius.mdAll,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 16, color: SboxColors.slate500), const SizedBox(width: 6)],
        if (label.isNotEmpty) Text('${tr(label)}: ', style: SboxType.smallStyle(SboxColors.textMuted)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(tr(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SboxType.smallStyle(SboxColors.text).copyWith(fontWeight: SboxType.semibold)),
        ),
        const SizedBox(width: 2),
        const Icon(Icons.expand_more_rounded, size: 18, color: SboxColors.slate500),
      ]),
    );
  }
}

/// Lọc thời gian: các mốc hay dùng + « Tùy chỉnh… » (chọn khoảng ngày).
class PosTimeRangeChip extends StatelessWidget {
  const PosTimeRangeChip({super.key, required this.state, required this.onChanged, this.label = 'Thời gian'});

  final PosKiotTimeFilterState state;
  final ValueChanged<PosKiotTimeFilterState> onChanged;
  final String label;

  static const _presets = [
    PosKiotTimePreset.today,
    PosKiotTimePreset.yesterday,
    PosKiotTimePreset.thisWeek,
    PosKiotTimePreset.last7Days,
    PosKiotTimePreset.thisMonth,
    PosKiotTimePreset.lastMonth,
    PosKiotTimePreset.last30Days,
    PosKiotTimePreset.thisQuarter,
    PosKiotTimePreset.thisYear,
    PosKiotTimePreset.allTime,
  ];

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final (f, t) = state.resolvedRange;
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: f ?? DateTime(now.year, now.month, 1), end: t ?? now),
    );
    if (r == null) return;
    onChanged(PosKiotTimeFilterState(preset: state.preset, isCustom: true, customFrom: r.start, customTo: r.end));
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: tr(label),
      onSelected: (v) {
        if (v is PosKiotTimePreset) {
          onChanged(PosKiotTimeFilterState(preset: v));
        } else {
          _pickCustom(context);
        }
      },
      itemBuilder: (_) => [
        for (final p in _presets)
          PopupMenuItem<Object>(
            value: p,
            child: Row(children: [
              SizedBox(
                width: 22,
                child: !state.isCustom && state.preset == p
                    ? const Icon(Icons.check_rounded, size: 16, color: SboxColors.primary)
                    : null,
              ),
              Text(tr(p.label)),
            ]),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: 'custom',
          child: Row(children: [
            SizedBox(
              width: 22,
              child: state.isCustom ? const Icon(Icons.check_rounded, size: 16, color: SboxColors.primary) : null,
            ),
            Text(tr('Tùy chỉnh…')),
          ]),
        ),
      ],
      child: PosChipFrame(label: label, value: state.displayLabel, icon: Icons.calendar_today_outlined),
    );
  }
}

/// Lọc nhiều lựa chọn (vd. trạng thái phiếu). Chọn hết = « Tất cả ».
class PosMultiChip extends StatelessWidget {
  const PosMultiChip({super.key, required this.label, required this.options, required this.selected, required this.onChanged});

  final String label;
  /// value → nhãn.
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  String get _valueText {
    if (selected.length == options.length || selected.isEmpty) return 'Tất cả';
    final picked = options.entries.where((e) => selected.contains(e.key)).map((e) => tr(e.value)).toList();
    // Gọn một dòng: « Hoàn thành +1 ».
    return picked.length == 1 ? picked.first : '${picked.first} +${picked.length - 1}';
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tr(label),
      onSelected: (v) {
        final next = {...selected};
        if (!next.remove(v)) next.add(v);
        // Bỏ hết = xem tất cả (không để danh sách trống vô lý).
        onChanged(next.isEmpty ? options.keys.toSet() : next);
      },
      itemBuilder: (_) => [
        for (final e in options.entries)
          PopupMenuItem<String>(
            value: e.key,
            child: Row(children: [
              Icon(selected.contains(e.key) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  size: 18, color: selected.contains(e.key) ? SboxColors.primary : SboxColors.slate400),
              const SizedBox(width: 10),
              Text(tr(e.value)),
            ]),
          ),
      ],
      child: PosChipFrame(label: label, value: _valueText, active: selected.length != options.length),
    );
  }
}

/// Nút « Lọc thêm (n) » — mở hộp các ô lọc phụ (người tạo, số HĐ…), có Xóa lọc / Áp dụng.
class PosMoreFiltersButton extends StatelessWidget {
  const PosMoreFiltersButton({
    super.key,
    required this.activeCount,
    required this.fields,
    required this.onApply,
    required this.onClear,
    this.title = 'Lọc thêm',
  });

  final int activeCount;
  final List<Widget> Function() fields;
  final VoidCallback onApply;
  final VoidCallback onClear;
  final String title;

  Future<void> _open(BuildContext context) async {
    Widget body(BuildContext ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final f in fields()) Padding(padding: const EdgeInsets.only(bottom: SboxSpace.md), child: f),
          Row(children: [
            SboxButton.ghost(
                label: 'Xóa lọc',
                onPressed: () {
                  Navigator.pop(ctx);
                  onClear();
                }),
            const Spacer(),
            SboxButton(
                label: 'Áp dụng',
                onPressed: () {
                  Navigator.pop(ctx);
                  onApply();
                }),
          ]),
        ]);

    if (Responsive.isMobile(context)) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr(title), style: SboxType.titleSmStyle()),
              const SizedBox(height: SboxSpace.md),
              body(ctx),
            ]),
          ),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(title)),
          content: SizedBox(width: 420, child: SingleChildScrollView(child: body(ctx))),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: SboxRadius.mdAll,
      onTap: () => _open(context),
      child: Container(
        height: SboxSize.control,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: activeCount > 0 ? SboxColors.brand50 : SboxColors.surface,
          border: Border.all(color: activeCount > 0 ? SboxColors.primary : SboxColors.borderStrong),
          borderRadius: SboxRadius.mdAll,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.tune_rounded, size: 16, color: activeCount > 0 ? SboxColors.primary : SboxColors.slate500),
          const SizedBox(width: 6),
          Text(activeCount > 0 ? '${tr(title)} ($activeCount)' : tr(title),
              style: SboxType.smallStyle(activeCount > 0 ? SboxColors.primary : SboxColors.text)
                  .copyWith(fontWeight: SboxType.semibold)),
        ]),
      ),
    );
  }
}

/// Ô nhập dùng trong hộp « Lọc thêm ».
class PosFilterField extends StatelessWidget {
  const PosFilterField({super.key, required this.label, required this.controller, this.hint});

  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(label), style: SboxType.smallStyle(SboxColors.textMuted)),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        style: SboxType.bodyStyle(),
        decoration: InputDecoration(hintText: hint == null ? null : tr(hint!), isDense: true),
      ),
    ]);
  }
}

/// Lọc theo một danh sách lớn (NCC, nhân viên…) — tự thêm « Tất cả ».
class PosPickChip extends StatelessWidget {
  const PosPickChip({super.key, required this.label, required this.value, required this.options, required this.onChanged, this.allLabel = 'Tất cả'});

  final String label;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tr(label),
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 220),
      onSelected: (v) => onChanged(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: _row(allLabel, value == null)),
        for (final e in options.entries) PopupMenuItem(value: e.key, child: _row(e.value, value == e.key)),
      ],
      child: PosChipFrame(label: label, value: value == null ? allLabel : (options[value] ?? allLabel), active: value != null),
    );
  }

  Widget _row(String text, bool on) => Row(children: [
        SizedBox(width: 22, child: on ? const Icon(Icons.check_rounded, size: 16, color: SboxColors.primary) : null),
        Flexible(child: Text(tr(text), overflow: TextOverflow.ellipsis)),
      ]);
}
