import 'package:flutter/material.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../../theme/sbox_tokens.dart';
import '../pos_theme.dart';

/// Báo cáo «tình trạng» cho người không chuyên kỹ thuật: màu đèn giao thông (xanh / vàng / đỏ / xám),
/// kết luận 1 câu, chỉ số kèm ngưỡng dễ hiểu, việc cần làm đánh số, giải thích từ ngữ.
/// Dùng cho «Mạng cửa hàng» và «Bán offline & kiểm soát».
class PosHealth {
  PosHealth._();

  static const green = Color(0xFF16A34A);
  static const yellow = Color(0xFFD97706);
  static const red = Color(0xFFDC2626);
  static const grey = SboxColors.slate400;

  /// [s]: green / yellow / red; còn lại (none / off / insufficient / null) = xám.
  static Color color(String? s) => switch (s) {
        'green' => green,
        'yellow' => yellow,
        'red' => red,
        _ => grey,
      };

  static IconData icon(String? s) => switch (s) {
        'green' => Icons.check_circle_rounded,
        'yellow' => Icons.error_rounded,
        'red' => Icons.cancel_rounded,
        _ => Icons.help_rounded,
      };

  static String label(String? s) => switch (s) {
        'green' => 'Tốt',
        'yellow' => 'Cần chú ý',
        'red' => 'Có vấn đề',
        'off' => 'Chưa bật',
        _ => 'Chưa có số liệu',
      };

  /// Mức của 1 chỉ số: ≤ [good] xanh, ≤ [warn] vàng, còn lại đỏ. null → xám.
  static String level(num? v, num good, num warn) {
    if (v == null) return 'none';
    if (v <= good) return 'green';
    if (v <= warn) return 'yellow';
    return 'red';
  }
}

/// Chip nhỏ «● Tốt».
class PosHealthChip extends StatelessWidget {
  const PosHealthChip({super.key, required this.status, this.text});

  final String? status;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final c = PosHealth.color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PosHealth.icon(status), size: 14, color: c),
          const SizedBox(width: 4),
          Text(
            tr(text ?? PosHealth.label(status)),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c),
          ),
        ],
      ),
    );
  }
}

/// Khung kết luận lớn đầu báo cáo: vòng điểm (hoặc biểu tượng) + 1 câu kết luận + giải thích.
class PosHealthHero extends StatelessWidget {
  const PosHealthHero({
    super.key,
    required this.status,
    required this.title,
    this.detail,
    this.score,
    this.note,
  });

  final String? status;
  final String title;
  final String? detail;

  /// 0..100; null → hiện biểu tượng đèn.
  final int? score;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = PosHealth.color(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withOpacity(0.07), Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: score == null
                ? Icon(PosHealth.icon(status), color: c, size: 64)
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: score!.clamp(0, 100) / 100,
                          strokeWidth: 7,
                          backgroundColor: c.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation(c),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$score',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c, height: 1)),
                          Text(tr('điểm'), style: const TextStyle(fontSize: 10, color: SboxColors.slate500)),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PosHealthChip(status: status),
                const SizedBox(height: 6),
                Text(tr(title), style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: c, height: 1.25)),
                if ((detail ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(tr(detail!), style: const TextStyle(fontSize: 13, color: SboxColors.slate700, height: 1.35)),
                ],
                if ((note ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(tr(note!), style: const TextStyle(fontSize: 12, color: SboxColors.slate500, height: 1.3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 1 chỉ số: tên, giá trị, màu mức, dòng giải thích ngắn («Dưới 1% là tốt»).
class PosHealthKpi {
  const PosHealthKpi(this.label, this.value, {this.status, this.hint, this.icon});

  final String label;
  final String value;
  final String? status;
  final String? hint;
  final IconData? icon;
}

/// Lưới chỉ số 2 cột (điện thoại) / 3 cột (máy tính bảng, web).
class PosHealthKpiGrid extends StatelessWidget {
  const PosHealthKpiGrid({super.key, required this.items});

  final List<PosHealthKpi> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 720 ? 3 : 2;
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final k in items) SizedBox(width: w, child: _tile(k))],
        ),
      );
    });
  }

  Widget _tile(PosHealthKpi k) {
    final c = PosHealth.color(k.status);
    final hasStatus = k.status != null && k.status != 'none';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hasStatus ? c.withOpacity(0.45) : PosTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (k.icon != null) ...[
                Icon(k.icon, size: 15, color: SboxColors.slate500),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(tr(k.label),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate600, fontWeight: FontWeight.w500)),
              ),
              if (hasStatus) Icon(PosHealth.icon(k.status), size: 16, color: c),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(k.value,
                maxLines: 1,
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: hasStatus ? c : SboxColors.slate800)),
          ),
          if ((k.hint ?? '').isNotEmpty)
            Text(tr(k.hint!), style: const TextStyle(fontSize: 11, color: SboxColors.slate500, height: 1.25)),
        ],
      ),
    );
  }
}

/// Thẻ mục báo cáo (tiêu đề + phụ đề giải thích + nội dung).
class PosHealthSection extends StatelessWidget {
  const PosHealthSection({super.key, required this.title, this.subtitle, required this.children, this.trailing});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      // Material trong suốt: ListTile bên trong cần Material ngay trên (hiệu ứng chạm không bị nền che).
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr(title),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SboxColors.slate800)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if ((subtitle ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(tr(subtitle!), style: const TextStyle(fontSize: 12, color: SboxColors.slate500, height: 1.3)),
            ],
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Chú thích màu.
class PosHealthLegend extends StatelessWidget {
  const PosHealthLegend({super.key, required this.items});

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final (label, color) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 4),
              Text(tr(label), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate600)),
            ],
          ),
      ],
    );
  }
}

/// Thanh tỷ lệ nhiều đoạn (vd 18 giờ tốt / 3 giờ chập chờn / 1 giờ kém) + chú thích kèm số và %.
class PosHealthSegmentBar extends StatelessWidget {
  const PosHealthSegmentBar({super.key, required this.segments, this.unit = '', this.height = 16});

  final List<({String label, int value, Color color})> segments;
  final String unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (a, s) => a + s.value);
    if (total <= 0) {
      return Text(tr('Chưa có số liệu.'), style: const TextStyle(color: SboxColors.slate500, fontSize: 12.5));
    }
    final shown = segments.where((s) => s.value > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(flex: shown[i].value, child: Container(color: shown[i].color)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final s in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 4),
                  Text(
                    '${tr(s.label)}: ${s.value}${unit.isEmpty ? '' : ' ${tr(unit)}'} '
                    '(${(100 * s.value / total).round()}%)',
                    style: const TextStyle(fontSize: 11.5, color: SboxColors.slate600),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// 1 việc nên làm: mức (high / medium / info), tiêu đề, chi tiết, cách xử lý.
class PosHealthAction {
  const PosHealthAction({required this.level, required this.title, this.detail, this.howTo});

  final String level;
  final String title;
  final String? detail;
  final String? howTo;
}

/// Danh sách việc nên làm, đánh số, việc gấp lên đầu.
class PosHealthActionList extends StatelessWidget {
  const PosHealthActionList({super.key, required this.items, this.emptyText = 'Không có việc gì cần làm.'});

  final List<PosHealthAction> items;
  final String emptyText;

  static String _status(String level) => switch (level) {
        'high' => 'red',
        'medium' => 'yellow',
        'info' => 'none',
        _ => 'green',
      };

  static String _tag(String level) => switch (level) {
        'high' => 'Làm ngay',
        'medium' => 'Nên làm',
        'ok' => 'Tốt',
        _ => 'Để biết',
      };

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: PosHealth.green, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(emptyText), style: const TextStyle(fontSize: 13))),
        ],
      );
    }
    int rank(String l) => switch (l) { 'high' => 0, 'medium' => 1, _ => 2 };
    final sorted = [...items]..sort((a, b) => rank(a.level).compareTo(rank(b.level)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sorted.length; i++) _row(i + 1, sorted[i]),
      ],
    );
  }

  Widget _row(int n, PosHealthAction a) {
    final st = _status(a.level);
    final c = a.level == 'info' ? SboxColors.slate500 : PosHealth.color(st);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(tr(a.title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text(tr(_tag(a.level)),
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
                    ),
                  ],
                ),
                if ((a.detail ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(tr(a.detail!),
                        style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600, height: 1.35)),
                  ),
                if ((a.howTo ?? '').isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: SboxColors.slate50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SboxColors.slate200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.build_circle_outlined, size: 16, color: SboxColors.slate600),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('${tr('Cách xử lý')}: ${tr(a.howTo!)}',
                              style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700, height: 1.35)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «Giải thích từ ngữ» — thu gọn mặc định.
class PosHealthGlossary extends StatelessWidget {
  const PosHealthGlossary({super.key, required this.entries, this.title = 'Giải thích từ ngữ'});

  final List<(String, String)> entries;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: PosTheme.mobileCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: const Icon(Icons.menu_book_outlined, color: SboxColors.slate600),
            title: Text(tr(title), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              for (final (term, meaning) in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${tr(term)}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: tr(meaning)),
                    ]),
                    style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700, height: 1.4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mục thu gọn (danh sách dài: lịch sử cài app, đơn chi tiết…).
class PosHealthExpandable extends StatelessWidget {
  const PosHealthExpandable({super.key, required this.title, required this.children, this.subtitle, this.icon});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: PosTheme.mobileCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: icon == null ? null : Icon(icon, color: SboxColors.slate600),
            title: Text(tr(title), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            subtitle: subtitle == null
                ? null
                : Text(tr(subtitle!), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
