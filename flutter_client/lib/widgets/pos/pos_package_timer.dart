import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
/// Trạng thái gói giờ: chưa bắt đầu / đang chạy / sắp hết / hết giờ (đang tính quá giờ).
enum PosPackageTimerStage { notStarted, running, soon, over }

/// Tính thời điểm hết gói + trạng thái (dùng chung giỏ hàng, sơ đồ bàn và kiểm tra báo).
class PosPackageTimerCalc {
  const PosPackageTimerCalc({
    required this.startedAt,
    required this.totalMinutes,
    this.pauseMinutes = 0,
    this.alertBeforeMinutes = 5,
  });

  final DateTime? startedAt;
  final int totalMinutes;
  final int pauseMinutes;
  final int alertBeforeMinutes;

  DateTime? get endsAt =>
      startedAt?.toUtc().add(Duration(minutes: totalMinutes + pauseMinutes));

  /// Còn lại (âm = đã quá giờ).
  Duration? remaining([DateTime? now]) {
    final e = endsAt;
    return e == null ? null : e.difference((now ?? DateTime.now()).toUtc());
  }

  PosPackageTimerStage stage([DateTime? now]) {
    final r = remaining(now);
    if (r == null) return PosPackageTimerStage.notStarted;
    if (r <= Duration.zero) return PosPackageTimerStage.over;
    if (alertBeforeMinutes > 0 && r <= Duration(minutes: alertBeforeMinutes)) return PosPackageTimerStage.soon;
    return PosPackageTimerStage.running;
  }

  static String fmt(Duration d) {
    final a = d.abs();
    final h = a.inHours;
    final m = a.inMinutes % 60;
    final s = a.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

/// Nhãn đếm ngược trên dòng giỏ hàng: ▶ Bắt đầu · Còn 42:15 · Hết giờ +05:12 (tự cập nhật mỗi giây).
class PosPackageTimerChip extends StatefulWidget {
  const PosPackageTimerChip({
    super.key,
    required this.calc,
    required this.onStart,
    this.paused = false,
    this.compact = false,
  });

  final PosPackageTimerCalc calc;
  final VoidCallback? onStart;
  final bool paused;
  final bool compact;

  @override
  State<PosPackageTimerChip> createState() => _PosPackageTimerChipState();
}

class _PosPackageTimerChipState extends State<PosPackageTimerChip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.calc.startedAt != null && !widget.paused) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.calc;
    final stage = c.stage();
    if (stage == PosPackageTimerStage.notStarted) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: widget.onStart,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(tr('Bắt đầu tính ${_minutesLabel(c.totalMinutes)}')),
          style: FilledButton.styleFrom(
            backgroundColor: SboxColors.success,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }
    final r = c.remaining()!;
    final (Color color, IconData icon, String text) = switch (stage) {
      PosPackageTimerStage.over => (SboxColors.danger, Icons.alarm_on, tr('Hết giờ · quá ${PosPackageTimerCalc.fmt(r)}')),
      PosPackageTimerStage.soon => (SboxColors.warning, Icons.alarm, tr('Sắp hết · còn ${PosPackageTimerCalc.fmt(r)}')),
      _ => (SboxColors.success, Icons.timer_outlined, tr('Còn ${PosPackageTimerCalc.fmt(r)}')),
    };
    final total = c.totalMinutes <= 0 ? 1 : c.totalMinutes * 60;
    final used = (total - r.inSeconds).clamp(0, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Icon(widget.paused ? Icons.pause_circle_outline : icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              widget.paused ? tr('Tạm dừng · $text') : text,
              style: TextStyle(
                fontSize: widget.compact ? 12 : 13,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(tr('gói ${_minutesLabel(c.totalMinutes)}'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate400)),
        ]),
        if (stage != PosPackageTimerStage.over) ...[
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: used / total,
              minHeight: 4,
              color: color,
              backgroundColor: color.withOpacity(.15),
            ),
          ),
        ],
      ],
    );
  }
}

String _minutesLabel(int m) {
  if (m % 60 == 0) return '${m ~/ 60} giờ';
  if (m > 60) return '${m ~/ 60} giờ ${m % 60} phút';
  return '$m phút';
}
