import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Kiểu tô ô giờ chấm.
enum PunchTone { normal, warn }

/// Chip giờ chấm trên bảng tổng hợp:
/// - Giờ vào xanh SBOX, giờ ra xám đậm; muộn / về sớm tô cam (không dùng đỏ cho giờ ra bình thường).
/// - Chấm nhỏ ở góc = giờ đã được thêm / sửa tay; rê chuột xem giờ gốc, lý do, người duyệt.
/// - Bấm: mở hộp thoại sửa (như cũ). Bấm đúp: sửa nhanh ngay trong ô — gõ HH:mm, Enter lưu, Esc huỷ.
class PunchTimeChip extends StatefulWidget {
  const PunchTimeChip({
    super.key,
    required this.time,
    required this.isIn,
    this.tone = PunchTone.normal,
    this.toneHint,
    this.editMarkTooltip,
    this.onTap,
    this.onQuickSave,
    this.readOnly = false,
    this.suggestions = const [],
  });

  /// Giờ gợi ý từ ca — bấm đúp mở menu chọn nhanh.
  final List<TimeSuggestion> suggestions;
  final DateTime time;
  final bool isIn;
  final PunchTone tone;
  final String? toneHint;
  final String? editMarkTooltip;
  final VoidCallback? onTap;

  /// Trả về true nếu lưu thành công. Null = không hỗ trợ sửa nhanh (bấm đúp mở hộp thoại).
  final Future<bool> Function(TimeOfDay newTime)? onQuickSave;
  final bool readOnly;

  @override
  State<PunchTimeChip> createState() => _PunchTimeChipState();
}

class _PunchTimeChipState extends State<PunchTimeChip> {
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing && !_saving) setState(() => _editing = false);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _hm =>
      '${widget.time.hour.toString().padLeft(2, '0')}:${widget.time.minute.toString().padLeft(2, '0')}';

  Future<void> _startEdit() async {
    if (widget.onQuickSave == null) {
      widget.onTap?.call();
      return;
    }
    if (widget.suggestions.isNotEmpty) {
      final choice = await showQuickTimeMenu(context,
          suggestions: widget.suggestions, isIn: widget.isIn, currentHm: _hm);
      if (!mounted || choice == null) return;
      if (choice.full) {
        widget.onTap?.call();
        return;
      }
      if (choice.suggestion != null) {
        final t = choice.suggestion!.time;
        if (t.hour == widget.time.hour && t.minute == widget.time.minute) return;
        setState(() => _saving = true);
        await widget.onQuickSave!(t);
        if (mounted) setState(() => _saving = false);
        return;
      }
    }
    _openInline();
  }

  void _openInline() {
    setState(() {
      _editing = true;
      _ctl.text = _hm;
      _ctl.selection = TextSelection(baseOffset: 0, extentOffset: _ctl.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  /// Nhận «8:05», «0805», «805», «8h05», «8.05».
  static TimeOfDay? parse(String raw) {
    final s = raw.trim().toLowerCase().replaceAll(RegExp(r'[h\.\s]'), ':');
    int? h, m;
    if (s.contains(':')) {
      final p = s.split(':').where((x) => x.isNotEmpty).toList();
      if (p.isEmpty || p.length > 2) return null;
      h = int.tryParse(p[0]);
      m = p.length > 1 ? int.tryParse(p[1]) : 0;
    } else if (RegExp(r'^\d{3,4}$').hasMatch(s)) {
      h = int.tryParse(s.substring(0, s.length - 2));
      m = int.tryParse(s.substring(s.length - 2));
    } else if (RegExp(r'^\d{1,2}$').hasMatch(s)) {
      h = int.tryParse(s);
      m = 0;
    }
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _submit() async {
    final t = parse(_ctl.text);
    if (t == null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(tr('Giờ không hợp lệ — nhập dạng 08:05'))));
      _focus.requestFocus();
      return;
    }
    if (t.hour == widget.time.hour && t.minute == widget.time.minute) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onQuickSave!(t);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _editing = false;
    });
    if (!ok) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final warn = widget.tone == PunchTone.warn;
    final color = warn ? SboxColors.warningText : (widget.isIn ? SboxColors.brand700 : SboxColors.slate700);
    final bg = warn ? SboxColors.warningSoft : (widget.isIn ? SboxColors.brand50 : SboxColors.slate100);

    if (_editing) {
      return SizedBox(
        width: 72,
        height: 28,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => setState(() => _editing = false),
          },
          child: TextField(
            controller: _ctl,
            focusNode: _focus,
            enabled: !_saving,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.datetime,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              suffixIconConstraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              suffixIcon: _saving
                  ? const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: SboxColors.brand600, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
      );
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(widget.isIn ? Icons.login_rounded : Icons.logout_rounded, size: 11, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 3),
        Text(_hm,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );

    Widget body = Stack(clipBehavior: Clip.none, children: [
      _saving ? Opacity(opacity: 0.5, child: chip) : chip,
      if (widget.editMarkTooltip != null)
        Positioned(
          right: -3,
          top: -3,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: SboxColors.violet,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
    ]);

    final tips = [
      if (widget.toneHint != null) widget.toneHint!,
      if (widget.editMarkTooltip != null) widget.editMarkTooltip!,
      if (!widget.readOnly)
        widget.onQuickSave != null
            ? (widget.suggestions.isNotEmpty
                ? 'Bấm: sửa / xoá · Bấm đúp: chọn nhanh giờ theo ca'
                : 'Bấm: sửa / xoá · Bấm đúp: sửa nhanh')
            : 'Bấm để sửa / xoá',
    ];
    if (tips.isNotEmpty) {
      body = Tooltip(message: tips.map(tr).join('\n'), waitDuration: const Duration(milliseconds: 350), child: body);
    }
    if (widget.readOnly) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: _startEdit,
        child: body,
      ),
    );
  }
}

/// Ô giờ trống:
/// - [missing] = thiếu giờ thật (có vào mà không có ra, ngày đã qua) → nền vàng «Thiếu giờ ra», luôn hiện.
/// - Ngược lại: trên bảng máy tính chỉ hiện «+» khi rê chuột vào hàng ([hoverOnly]); ở danh sách chi tiết hiện luôn.
class EmptyPunchCell extends StatefulWidget {
  const EmptyPunchCell({
    super.key,
    required this.isIn,
    this.missing = false,
    this.hoverOnly = false,
    this.rowHovered = false,
    this.onTap,
    this.suggestions = const [],
    this.onQuickAdd,
  });

  /// Giờ gợi ý từ ca + hàm thêm nhanh (null = bấm mở hộp thoại như cũ).
  final List<TimeSuggestion> suggestions;
  final Future<bool> Function(TimeSuggestion s)? onQuickAdd;

  final bool isIn;
  final bool missing;
  final bool hoverOnly;

  /// Hàng đang được rê chuột (từ bảng) — hiện «+» cả khi chuột ở ô khác cùng hàng.
  final bool rowHovered;
  final VoidCallback? onTap;

  @override
  State<EmptyPunchCell> createState() => _EmptyPunchCellState();
}

class _EmptyPunchCellState extends State<EmptyPunchCell> {
  bool _hover = false;
  bool _busy = false;

  Future<void> _tap() async {
    if (widget.onQuickAdd == null) {
      widget.onTap?.call();
      return;
    }
    final choice = await showQuickTimeMenu(context, suggestions: widget.suggestions, isIn: widget.isIn);
    if (!mounted || choice == null) return;
    if (choice.full) {
      widget.onTap?.call();
      return;
    }
    TimeSuggestion? pick = choice.suggestion;
    if (choice.custom) {
      final t = await askTimeText(context, title: widget.isIn ? 'Thêm giờ vào' : 'Thêm giờ ra');
      if (t == null) return;
      pick = TimeSuggestion(t, 'Nhập tay');
    }
    if (pick == null || !mounted) return;
    setState(() => _busy = true);
    await widget.onQuickAdd!(pick);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.missing) {
      final w = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: SboxColors.warningSoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: SboxColors.warning.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.warning_amber_rounded, size: 12, color: SboxColors.warningText),
          const SizedBox(width: 3),
          Text(tr(widget.isIn ? 'Thiếu giờ vào' : 'Thiếu giờ ra'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SboxColors.warningText)),
          if (widget.onTap != null) ...[
            const SizedBox(width: 3),
            const Icon(Icons.add_rounded, size: 13, color: SboxColors.warningText),
          ],
        ]),
      );
      if (widget.onTap == null) return w;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
            onTap: _busy ? null : _tap,
            child: Tooltip(
                message: tr(widget.onQuickAdd != null ? 'Bấm để chọn nhanh giờ theo ca' : 'Bấm để thêm giờ bị thiếu'),
                child: _busy ? Opacity(opacity: 0.5, child: w) : w)),
      );
    }
    if (widget.onTap == null) {
      return const Text('—', style: TextStyle(fontSize: 11, color: SboxColors.slate300));
    }
    final visible = !widget.hoverOnly || _hover || widget.rowHovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _busy ? null : _tap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 24,
          child: Center(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: SboxColors.brand500.withValues(alpha: 0.5)),
                  color: SboxColors.brand50,
                ),
                child: const Icon(Icons.add_rounded, size: 14, color: SboxColors.brand600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bọc ô trong bảng để tô cả hàng khi rê chuột (dùng chung 1 ValueNotifier cho mọi ô).
class HoverRowCell extends StatelessWidget {
  const HoverRowCell({super.key, required this.rowKey, required this.hovered, required this.child});

  final String rowKey;
  final ValueNotifier<String?> hovered;
  final Widget child;

  static const hoverColor = Color(0x12158DC0);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => hovered.value = rowKey,
      onExit: (_) {
        if (hovered.value == rowKey) hovered.value = null;
      },
      child: ValueListenableBuilder<String?>(
        valueListenable: hovered,
        child: child,
        builder: (_, v, c) => ColoredBox(color: v == rowKey ? hoverColor : Colors.transparent, child: c),
      ),
    );
  }
}

/// Nội dung tooltip «đã sửa tay» từ 1 bản ghi dấu sửa (API attendance-edit-marks).
String? editMarkTooltip(Map<String, dynamic>? m) {
  if (m == null) return null;
  final at = DateTime.tryParse(m['at']?.toString() ?? '')?.toLocal();
  final when = at == null
      ? ''
      : ' lúc ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} ${at.day}/${at.month}';
  final head = m['action'] == 'add'
      ? 'Giờ thêm tay'
      : 'Đã sửa tay: gốc ${m['originalTime'] ?? '?'} → ${m['newTime'] ?? '?'}';
  return [
    head,
    if ((m['reason']?.toString() ?? '').isNotEmpty) 'Lý do: ${m['reason']}',
    if ((m['by']?.toString() ?? '').isNotEmpty) 'Bởi ${m['by']}$when',
    if ((m['times'] is num) && (m['times'] as num) > 1) 'Đã sửa ${m['times']} lần',
  ].join('\n');
}

// ═════════════ GIỜ GỢI Ý TỪ CA ═════════════

/// 1 giờ gợi ý (từ ca mẫu): giờ, nhãn, có phải ca của NV hôm đó không, giờ thuộc ngày hôm sau (ca qua đêm).
class TimeSuggestion {
  const TimeSuggestion(this.time, this.label, {this.preferred = false, this.nextDay = false});
  final TimeOfDay time;
  final String label;
  final bool preferred;
  final bool nextDay;

  String get hm => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

TimeOfDay? _parseSpan(dynamic v) {
  final s = v?.toString() ?? '';
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return TimeOfDay(hour: h, minute: mi);
}

/// Giờ gợi ý theo ca mẫu: ô «Vào» → giờ bắt đầu ca (+ vào lại sau nghỉ trưa);
/// ô «Ra» → giờ kết thúc ca (+ ra nghỉ trưa). Ca của nhân viên hôm đó ([preferredNames]) lên trước.
List<TimeSuggestion> shiftTimeSuggestions(
  List<Map<String, dynamic>> templates, {
  required bool isIn,
  Iterable<String> preferredNames = const [],
  int max = 8,
}) {
  final pref = preferredNames.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
  final out = <TimeSuggestion>[];
  for (final t in templates) {
    if (t['isActive'] == false) continue;
    final name = (t['name'] ?? t['code'] ?? 'Ca').toString();
    final start = _parseSpan(t['startTime']), end = _parseSpan(t['endTime']);
    if (start == null || end == null) continue;
    final overnight = end.hour * 60 + end.minute <= start.hour * 60 + start.minute;
    final isPref = pref.contains(name.trim().toLowerCase());
    final lunchStart = _parseSpan(t['lunchBreakStartTime']), lunchEnd = _parseSpan(t['lunchBreakEndTime']);
    if (isIn) {
      out.add(TimeSuggestion(start, '$name · vào ca', preferred: isPref));
      if (lunchEnd != null) out.add(TimeSuggestion(lunchEnd, '$name · vào lại sau nghỉ trưa', preferred: isPref));
    } else {
      out.add(TimeSuggestion(end, '$name · hết ca${overnight ? ' (hôm sau)' : ''}', preferred: isPref, nextDay: overnight));
      if (lunchStart != null) out.add(TimeSuggestion(lunchStart, '$name · ra nghỉ trưa', preferred: isPref));
    }
  }
  // Ca của NV lên trước, rồi theo giờ; bỏ trùng giờ
  out.sort((a, b) {
    if (a.preferred != b.preferred) return a.preferred ? -1 : 1;
    return (a.time.hour * 60 + a.time.minute).compareTo(b.time.hour * 60 + b.time.minute);
  });
  final seen = <String>{};
  return [
    for (final s in out)
      if (seen.add('${s.hm}${s.nextDay}')) s,
  ].take(max).toList();
}

/// Kết quả chọn nhanh: giờ gợi ý / nhập giờ khác / mở hộp thoại đầy đủ.
class QuickTimeChoice {
  const QuickTimeChoice.pick(this.suggestion)
      : custom = false,
        full = false;
  const QuickTimeChoice.custom()
      : suggestion = null,
        custom = true,
        full = false;
  const QuickTimeChoice.full()
      : suggestion = null,
        custom = false,
        full = true;
  final TimeSuggestion? suggestion;
  final bool custom;
  final bool full;
}

/// Menu bật ngay tại ô: giờ gợi ý từ ca (bấm là lưu), «Nhập giờ khác…», «Hộp thoại đầy đủ…».
Future<QuickTimeChoice?> showQuickTimeMenu(
  BuildContext cellContext, {
  required List<TimeSuggestion> suggestions,
  required bool isIn,
  bool allowFull = true,
  String? currentHm,
}) async {
  final box = cellContext.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(cellContext).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return null;
  final topLeft = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
  final position = RelativeRect.fromRect(
    Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, 0),
    Offset.zero & overlay.size,
  );
  final color = isIn ? SboxColors.brand700 : SboxColors.slate700;
  return showMenu<QuickTimeChoice>(
    context: cellContext,
    position: position,
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
    items: [
      PopupMenuItem<QuickTimeChoice>(
        enabled: false,
        height: 30,
        child: Text(tr(isIn ? 'Giờ vào gợi ý theo ca' : 'Giờ ra gợi ý theo ca'),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
      ),
      for (final s in suggestions)
        PopupMenuItem<QuickTimeChoice>(
          value: QuickTimeChoice.pick(s),
          height: 40,
          child: Row(children: [
            Container(
              width: 54,
              padding: const EdgeInsets.symmetric(vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: s.preferred ? SboxColors.brand600 : SboxColors.slate100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(s.hm,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: s.preferred ? Colors.white : color,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr(s.label),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ),
            if (s.hm == currentHm) const Icon(Icons.check_rounded, size: 16, color: SboxColors.success),
            if (s.preferred && s.hm != currentHm)
              const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF5A524)),
          ]),
        ),
      if (suggestions.isNotEmpty) const PopupMenuDivider(),
      PopupMenuItem<QuickTimeChoice>(
        value: const QuickTimeChoice.custom(),
        height: 38,
        child: Row(children: [
          const Icon(Icons.keyboard_rounded, size: 18, color: SboxColors.slate600),
          const SizedBox(width: 10),
          Text(tr('Nhập giờ khác…'), style: const TextStyle(fontSize: 12.5)),
        ]),
      ),
      if (allowFull)
        PopupMenuItem<QuickTimeChoice>(
          value: const QuickTimeChoice.full(),
          height: 38,
          child: Row(children: [
            const Icon(Icons.open_in_new_rounded, size: 18, color: SboxColors.slate600),
            const SizedBox(width: 10),
            Text(tr('Hộp thoại đầy đủ (ngày, lý do, xoá)…'), style: const TextStyle(fontSize: 12.5)),
          ]),
        ),
    ],
  );
}

/// Hỏi nhanh 1 giờ (HH:mm) — dùng cho «Nhập giờ khác…» khi thêm giờ.
Future<TimeOfDay?> askTimeText(BuildContext context, {String? title, String? initial}) async {
  final ctl = TextEditingController(text: initial ?? '');
  TimeOfDay? result;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(title ?? 'Nhập giờ')),
      content: SizedBox(
        width: 220,
        child: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(hintText: tr('VD: 08:05, 805, 8h05'), border: const OutlineInputBorder()),
          onSubmitted: (v) {
            result = parsePunchTimeText(v);
            if (result != null) Navigator.pop(ctx);
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
        FilledButton(
          onPressed: () {
            result = parsePunchTimeText(ctl.text);
            if (result != null) Navigator.pop(ctx);
          },
          child: Text(tr('Lưu')),
        ),
      ],
    ),
  );
  ctl.dispose();
  return result;
}

/// Nhận «8:05», «0805», «805», «8h05», «8.05».
TimeOfDay? parsePunchTimeText(String raw) => _PunchTimeChipState.parse(raw);

/// Hàng nút giờ gợi ý trong hộp thoại thêm / sửa giờ — bấm là chọn giờ.
class ShiftTimeSuggestionChips extends StatelessWidget {
  const ShiftTimeSuggestionChips({super.key, required this.suggestions, required this.selected, required this.onPick});

  final List<TimeSuggestion> suggestions;
  final TimeOfDay selected;
  final ValueChanged<TimeSuggestion> onPick;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Giờ gợi ý theo ca (bấm để chọn):'),
            style: const TextStyle(fontSize: 12, color: SboxColors.slate500, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in suggestions)
            Tooltip(
              message: tr(s.label),
              child: ChoiceChip(
                visualDensity: VisualDensity.compact,
                avatar: s.preferred ? const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF5A524)) : null,
                label: Text('${s.hm}${s.nextDay ? ' (+1)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                selected: selected.hour == s.time.hour && selected.minute == s.time.minute,
                onSelected: (_) => onPick(s),
              ),
            ),
        ]),
      ]),
    );
  }
}
