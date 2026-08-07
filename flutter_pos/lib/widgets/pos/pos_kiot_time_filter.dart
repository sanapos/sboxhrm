import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/pos_kiot_time_range.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';
import 'package:sbox_pos/l10n/app_ui_locale.dart';

const _blue = Color(0xFF2563EB);

/// Bộ lọc thời gian sidebar kiểu KiotViet: preset popover + tùy chỉnh.
class PosKiotTimeFilter extends StatelessWidget {
  const PosKiotTimeFilter({
    super.key,
    required this.state,
    required this.onChanged,
    this.title,
    this.dense = true,
  });

  final PosKiotTimeFilterState state;
  final ValueChanged<PosKiotTimeFilterState> onChanged;
  final String? title;
  final bool dense;

  Future<void> _openPresetDialog(BuildContext context) async {
    final picked = await showDialog<PosKiotTimePreset>(
      context: context,
      builder: (ctx) => _PosKiotTimePresetDialog(selected: state.preset),
    );
    if (picked == null) return;
    onChanged(PosKiotTimeFilterState(preset: picked, isCustom: false));
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final initial = state.isCustom &&
            state.customFrom != null &&
            state.customTo != null
        ? DateTimeRange(start: state.customFrom!, end: state.customTo!)
        : DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: initial,
      locale: appUiLocale(),
      helpText: 'Chọn khoảng thời gian',
    );
    if (picked == null) return;
    onChanged(PosKiotTimeFilterState(
      isCustom: true,
      customFrom: picked.start,
      customTo: picked.end,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _openPresetDialog(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Radio<bool>(
                  value: false,
                  groupValue: state.isCustom,
                  activeColor: _blue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => _openPresetDialog(context),
                ),
                Expanded(
                  child: Text(
                    tr(state.isCustom ? 'Chọn khoảng' : state.displayLabel),
                    style: TextStyle(
                      fontSize: dense ? 13 : 14,
                      fontWeight:
                          !state.isCustom ? FontWeight.w500 : FontWeight.normal,
                      color: !state.isCustom ? _blue : PosTheme.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down,
                    size: 18, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: () => _pickCustomRange(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: state.isCustom,
                  activeColor: _blue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => _pickCustomRange(context),
                ),
                Expanded(
                  child: Text(tr('Tùy chỉnh'), style: TextStyle(fontSize: 13)),
                ),
                Icon(Icons.calendar_today_outlined,
                    size: 16, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
        if (state.isCustom || state.preset != PosKiotTimePreset.allTime) ...[
          const SizedBox(height: 4),
          Text(
            tr(_rangeHint(state)),
            style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
          ),
        ],
      ],
    );

    if (title == null || title!.isEmpty) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr(title!),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: PosTheme.textSecondary)),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  static String _rangeHint(PosKiotTimeFilterState s) {
    final fmt = DateFormat('dd/MM/yyyy');
    final from = s.from;
    final to = s.to;
    if (from == null && to == null) return 'Toàn thời gian';
    if (from != null && to != null) {
      return '${fmt.format(from)} – ${fmt.format(to)}';
    }
    if (from != null) return 'Từ ${fmt.format(from)}';
    if (to != null) return 'Đến ${fmt.format(to)}';
    return s.displayLabel;
  }
}

class _PosKiotTimePresetDialog extends StatelessWidget {
  const _PosKiotTimePresetDialog({required this.selected});

  final PosKiotTimePreset selected;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(tr('Chọn thời gian'),
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: kPosKiotTimePresetGroups
                        .map((g) => _buildGroup(context, g))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(BuildContext context, PosKiotTimePresetGroup group) {
    return SizedBox(
      width: 128,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr(group.title),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PosTheme.textSecondary)),
          const SizedBox(height: 8),
          ...group.presets.map((p) {
            final active = p == selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: active ? _blue : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () => Navigator.pop(context, p),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Text(
                      tr(p.label),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: active ? Colors.white : PosTheme.textPrimary,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
