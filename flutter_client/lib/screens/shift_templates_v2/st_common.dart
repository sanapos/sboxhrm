import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Ca mẫu (thiết lập ca) — dữ liệu thô từ /api/shifts/templates.
class ShiftTpl {
  ShiftTpl({
    required this.id,
    required this.name,
    this.code,
    required this.start,
    required this.end,
    this.breakMinutes = 0,
    this.lunchStart,
    this.lunchEnd,
    this.earlyCheckIn = 60,
    this.maxLate = 30,
    this.maxEarlyLeave = 30,
    this.lateGrace = 5,
    this.earlyLeaveGrace = 5,
    this.otAfter = 30,
    this.otBefore = 30,
    this.type = ShiftKind.office,
    this.description,
    this.isActive = true,
  });

  final String id;
  String name;
  String? code;
  int start; // phút trong ngày
  int end;
  int breakMinutes;
  int? lunchStart;
  int? lunchEnd;
  int earlyCheckIn;
  int maxLate;
  int maxEarlyLeave;
  int lateGrace;
  int earlyLeaveGrace;
  int otAfter;
  int otBefore;
  ShiftKind type;
  String? description;
  bool isActive;

  bool get overnight => end < start;
  bool get hasLunchWindow => lunchStart != null && lunchEnd != null;

  /// Độ dài ca (phút) theo giờ đồng hồ — qua đêm khi giờ ra < giờ vào.
  int get spanMinutes => StTime.span(start, end);

  /// Phút nghỉ thực trừ: khung nghỉ (phần nằm trong ca) được ưu tiên, nếu không có thì số phút nghỉ.
  int get effectiveBreak {
    if (hasLunchWindow) return StTime.overlapInShift(start, end, lunchStart!, lunchEnd!);
    return breakMinutes > 0 ? breakMinutes : 0;
  }

  int get workMinutes => (spanMinutes - effectiveBreak).clamp(0, 24 * 60);

  factory ShiftTpl.fromJson(Map<String, dynamic> j) {
    int? t(dynamic v) => StTime.parse(v?.toString());
    final ls = t(j['lunchBreakStartTime']);
    final le = t(j['lunchBreakEndTime']);
    int n(dynamic v, int d) => v is num ? v.toInt() : int.tryParse('$v') ?? d;
    return ShiftTpl(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      code: j['code']?.toString(),
      start: t(j['startTime']) ?? 8 * 60,
      end: t(j['endTime']) ?? 17 * 60,
      breakMinutes: n(j['breakTimeMinutes'] ?? j['breakMinutes'], 0),
      lunchStart: ls != null && le != null ? ls : null,
      lunchEnd: ls != null && le != null ? le : null,
      earlyCheckIn: n(j['earlyCheckInMinutes'], 30),
      maxLate: n(j['maximumAllowedLateMinutes'], 30),
      maxEarlyLeave: n(j['maximumAllowedEarlyLeaveMinutes'], 30),
      lateGrace: n(j['lateGraceMinutes'], 5),
      earlyLeaveGrace: n(j['earlyLeaveGraceMinutes'], 5),
      otAfter: n(j['overtimeMinutesThreshold'], 30),
      otBefore: n(j['earlyOvertimeMinutesThreshold'], 30),
      type: ShiftKind.parse(j['shiftType']?.toString(), j['description']?.toString()),
      description: j['description']?.toString(),
      isActive: j['isActive'] != false,
    );
  }

  ShiftTpl copy() => ShiftTpl.fromJson({...toJson(), 'id': id});

  /// Dữ liệu gửi API tạo / sửa ca (giữ đúng định dạng màn cũ).
  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'code': (code ?? '').trim().isEmpty ? name.trim() : code!.trim(),
        'startTime': StTime.api(start),
        'endTime': StTime.api(end),
        'isActive': isActive,
        'shiftType': type.label,
        'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
        'earlyCheckInMinutes': earlyCheckIn,
        'maximumAllowedLateMinutes': maxLate,
        'maximumAllowedEarlyLeaveMinutes': maxEarlyLeave,
        'lateGraceMinutes': lateGrace,
        'earlyLeaveGraceMinutes': earlyLeaveGrace,
        'breakTimeMinutes': hasLunchWindow ? effectiveBreak : breakMinutes,
        'lunchBreakStartTime': hasLunchWindow ? StTime.api(lunchStart!) : null,
        'lunchBreakEndTime': hasLunchWindow ? StTime.api(lunchEnd!) : null,
        'overtimeMinutesThreshold': otAfter,
        'earlyOvertimeMinutesThreshold': otBefore,
      };

  /// Lỗi chặn lưu (null = hợp lệ).
  String? validate() {
    if (name.trim().isEmpty) return 'Nhập tên ca';
    if (start == end) return 'Giờ vào trùng giờ ra. Ca gần 24 giờ: đặt giờ ra sớm hơn giờ vào 1 phút (vd 06:00–05:59).';
    if (hasLunchWindow && StTime.overlapInShift(start, end, lunchStart!, lunchEnd!) <= 0) {
      return 'Khung nghỉ giữa ca nằm ngoài giờ ca. Chọn lại giờ nghỉ hoặc bấm «Đặt vào giữa ca».';
    }
    if (hasLunchWindow && !StTime.insideShift(start, end, lunchStart!, lunchEnd!)) {
      return 'Khung nghỉ giữa ca phải nằm trọn trong giờ ca.';
    }
    if (otBefore > 0 && earlyCheckIn <= otBefore) {
      return 'Tăng ca trước ca ($otBefore phút) cần «Nhận chấm sớm» ít nhất ${otBefore + 1} phút để khớp ca và tính được tăng ca.';
    }
    return null;
  }

  /// Cảnh báo không chặn lưu.
  List<String> warnings() => [
        if (lateGrace > maxLate) 'Miễn trễ ($lateGrace phút) lớn hơn giới hạn trễ ($maxLate phút) — đi trễ sẽ không bao giờ bị tính.',
        if (earlyLeaveGrace > maxEarlyLeave)
          'Miễn về sớm ($earlyLeaveGrace phút) lớn hơn giới hạn về sớm ($maxEarlyLeave phút).',
        if (workMinutes < 60) 'Ca chỉ có ${StTime.duration(workMinutes)} làm việc.',
        if (type == ShiftKind.overnight && !overnight) 'Loại ca «Qua đêm» nhưng giờ ra sau giờ vào trong cùng ngày.',
      ];
}

/// Loại ca (giá trị lưu giống màn cũ: «Hành chính», «Tăng ca», «Qua đêm»).
enum ShiftKind {
  office('Hành chính', 'Ca chính: tính trễ, về sớm, tăng ca theo ngưỡng', Icons.wb_sunny_outlined, SboxTone.brand),
  overtime('Tăng ca', 'Toàn bộ giờ làm thực tế tính tăng ca', Icons.more_time_rounded, SboxTone.warning),
  overnight('Qua đêm', 'Ca vắt qua nửa đêm, áp hệ số ca đêm', Icons.nightlight_round, SboxTone.violet);

  const ShiftKind(this.label, this.hint, this.icon, this.tone);
  final String label;
  final String hint;
  final IconData icon;
  final SboxTone tone;

  static ShiftKind parse(String? type, [String? description]) {
    final st = (type ?? '').toLowerCase();
    if (st.contains('tăng ca') || st.contains('overtime') || st == 'tangca') return ShiftKind.overtime;
    if (st.contains('qua đêm') || st.contains('overnight') || st == 'quadem') return ShiftKind.overnight;
    if (st.isNotEmpty) return ShiftKind.office;
    final d = (description ?? '').toLowerCase();
    if (d.contains('qua đêm') || d.contains('overnight')) return ShiftKind.overnight;
    if (d.contains('tăng ca') || d.contains('overtime')) return ShiftKind.overtime;
    return ShiftKind.office;
  }
}

/// Mẫu ca nhanh khi tạo ca mới.
class ShiftPreset {
  const ShiftPreset(this.name, this.code, this.start, this.end, {this.lunch, this.breakMin = 0, this.type = ShiftKind.office});
  final String name;
  final String code;
  final int start;
  final int end;
  final (int, int)? lunch;
  final int breakMin;
  final ShiftKind type;

  static const all = <ShiftPreset>[
    ShiftPreset('Hành chính', 'HC', 8 * 60, 17 * 60, lunch: (12 * 60, 13 * 60)),
    ShiftPreset('Ca sáng', 'CS', 6 * 60, 14 * 60, breakMin: 30),
    ShiftPreset('Ca chiều', 'CC', 14 * 60, 22 * 60, breakMin: 30),
    ShiftPreset('Ca đêm', 'CD', 22 * 60, 6 * 60, breakMin: 30, type: ShiftKind.overnight),
    ShiftPreset('Ca gãy', 'CG', 10 * 60, 21 * 60, lunch: (14 * 60, 17 * 60)),
    ShiftPreset('Tăng ca tối', 'TC', 18 * 60, 21 * 60, type: ShiftKind.overtime),
  ];

  void applyTo(ShiftTpl t) {
    if (t.name.trim().isEmpty) t.name = name;
    if ((t.code ?? '').trim().isEmpty) t.code = code;
    t
      ..start = start
      ..end = end
      ..type = type
      ..lunchStart = lunch?.$1
      ..lunchEnd = lunch?.$2
      ..breakMinutes = lunch == null ? breakMin : (lunch!.$2 - lunch!.$1);
  }
}

/// Tiện ích giờ (phút trong ngày).
class StTime {
  static const day = 24 * 60;

  static int? parse(String? s) {
    if (s == null || s.isEmpty) return null;
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0].trim());
    final m = int.tryParse(p[1].trim());
    if (h == null || m == null) return null;
    return (h % 24) * 60 + m;
  }

  static String hm(int m) {
    final v = ((m % day) + day) % day;
    return '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}';
  }

  static String api(int m) => '${hm(m)}:00';

  static String duration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m phút';
    return m == 0 ? '$h giờ' : '${h}g${m.toString().padLeft(2, '0')}';
  }

  /// Độ dài ca; giờ ra < giờ vào = qua đêm; bằng nhau = 0.
  static int span(int start, int end) => end < start ? day - start + end : end - start;

  /// Vị trí [t] tính từ giờ vào ca (−1 nếu ngoài ca).
  static int offset(int start, int end, int t) {
    final dur = span(start, end);
    var o = t - start;
    if (o < 0) o += day;
    return o <= dur ? o : -1;
  }

  static bool insideShift(int start, int end, int a, int b) {
    final oa = offset(start, end, a);
    final ob = offset(start, end, b);
    return oa >= 0 && ob >= 0 && ob > oa;
  }

  /// Phút nghỉ nằm trong ca.
  static int overlapInShift(int start, int end, int a, int b) {
    final oa = offset(start, end, a);
    final ob = offset(start, end, b);
    if (oa < 0 || ob < 0 || ob <= oa) return 0;
    return ob - oa;
  }

  /// Đặt khung nghỉ vào giữa ca, giữ độ dài (tối đa 1/3 ca).
  static (int, int) centerBreak(int start, int end, int length) {
    final dur = span(start, end) == 0 ? day : span(start, end);
    var len = length <= 0 ? 60 : length;
    if (len >= dur) len = (dur ~/ 3).clamp(15, dur);
    final o = (dur - len) ~/ 2;
    return ((start + o) % day, (start + o + len) % day);
  }
}

/// Mức sử dụng của 1 ca (từ /usage).
class ShiftUsage {
  const ShiftUsage(this.m);
  final Map<String, dynamic> m;

  static const empty = ShiftUsage({});

  int _n(String k) => (m[k] as num?)?.toInt() ?? 0;
  int get schedules => _n('schedules');
  int get upcoming => _n('upcomingSchedules');
  int get employees => _n('employees');
  int get salaryLevels => _n('salaryLevels');
  int get allowances => _n('allowances');
  int get quotas => _n('staffingQuotas');
  int get mealSessions => _n('mealSessions');
  bool get hasData => m['hasData'] == true;
  bool get canDelete => m.isEmpty || m['canDelete'] != false;
  String get dataSummary => m['dataSummary']?.toString() ?? '';
  DateTime? get lastUsed => DateTime.tryParse(m['lastUsedDate']?.toString() ?? '');

  /// Những thiết lập sẽ bị gỡ khi xóa ca.
  List<String> get configParts => [
        if (salaryLevels > 0) '$salaryLevels mức lương ca',
        if (allowances > 0) '$allowances phụ cấp theo ca',
        if (quotas > 0) '$quotas định mức nhân sự',
        if (mealSessions > 0) '$mealSessions suất ăn theo ca',
      ];
}

/// Thanh 24 giờ: khung ca (màu), nghỉ giữa ca (gạch), vạch 0/6/12/18/24.
class ShiftDayBar extends StatelessWidget {
  const ShiftDayBar({super.key, required this.shift, this.height = 14, this.showScale = true, this.color});

  final ShiftTpl shift;
  final double height;
  final bool showScale;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? shift.type.tone.solid;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double x(int m) => w * (m / StTime.day);
      List<Widget> seg(int a, int b, Widget Function(double l, double width) make) {
        if (b > a) return [make(x(a), x(b) - x(a))];
        return [make(x(a), w - x(a)), if (b > 0) make(0, x(b))];
      }

      final dur = shift.spanMinutes;
      final end = dur == 0 ? shift.start : shift.end;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: height,
          child: Stack(children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: SboxColors.slate100, borderRadius: BorderRadius.circular(height / 2)),
              ),
            ),
            ...seg(shift.start, end, (l, width) => Positioned(
                  left: l,
                  width: width,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: shift.isActive ? c : SboxColors.slate300,
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                )),
            if (shift.hasLunchWindow)
              ...seg(shift.lunchStart!, shift.lunchEnd!, (l, width) => Positioned(
                    left: l,
                    width: width,
                    top: height * 0.25,
                    bottom: height * 0.25,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(height)),
                    ),
                  )),
          ]),
        ),
        if (showScale)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (final h in const ['0h', '6h', '12h', '18h', '24h'])
                Text(h, style: const TextStyle(fontSize: 10, color: SboxColors.slate400)),
            ]),
          ),
      ]);
    });
  }
}

/// Minh họa quy tắc chấm công của 1 ca: nhận chấm sớm, miễn trễ, giới hạn trễ, về sớm, tăng ca.
class ShiftRuleTimeline extends StatelessWidget {
  const ShiftRuleTimeline({super.key, required this.shift});

  final ShiftTpl shift;

  @override
  Widget build(BuildContext context) {
    final s = shift;
    final isOt = s.type == ShiftKind.overtime;
    Widget row(IconData icon, Color color, String time, String title, String desc) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(time, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(tr(desc), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              ]),
            ),
          ]),
        );

    final items = <Widget>[
      row(Icons.login_rounded, SboxColors.slate500, StTime.hm(s.start - s.earlyCheckIn), 'Bắt đầu nhận chấm vào',
          'Chấm sớm hơn mốc này sẽ không khớp ca (nhận sớm ${s.earlyCheckIn} phút).'),
      if (!isOt && s.otBefore > 0)
        row(Icons.more_time_rounded, SboxColors.warning, '< ${StTime.hm(s.start - s.otBefore)}', 'Tăng ca trước ca',
            'Vào trước mốc này mới tính tăng ca trước ca (ngưỡng ${s.otBefore} phút).'),
      row(Icons.play_circle_rounded, SboxColors.success, StTime.hm(s.start), 'Giờ vào ca', 'Giờ bắt đầu tính công.'),
      if (!isOt)
        row(Icons.timer_outlined, SboxColors.brand600, StTime.hm(s.start + s.lateGrace), 'Hết miễn trễ',
            s.lateGrace > 0 ? 'Vào trong ${s.lateGrace} phút đầu không tính đi trễ.' : 'Vào sau giờ vào ca là tính trễ.'),
      if (!isOt)
        row(Icons.warning_amber_rounded, SboxColors.danger, StTime.hm(s.start + s.maxLate), 'Giới hạn đi trễ',
            'Vào sau mốc này không còn thuộc ca (trễ tối đa ${s.maxLate} phút).'),
      if (s.hasLunchWindow)
        row(Icons.restaurant_rounded, SboxColors.violet, '${StTime.hm(s.lunchStart!)}–${StTime.hm(s.lunchEnd!)}', 'Nghỉ giữa ca',
            'Không tính công ${StTime.duration(s.effectiveBreak)}.')
      else if (s.breakMinutes > 0)
        row(Icons.restaurant_rounded, SboxColors.violet, '${s.breakMinutes}p', 'Nghỉ linh hoạt',
            'Trừ ${s.breakMinutes} phút nghỉ khi tính công.'),
      if (!isOt)
        row(Icons.warning_amber_rounded, SboxColors.danger, StTime.hm(s.end - s.maxEarlyLeave), 'Giới hạn về sớm',
            'Ra trước mốc này không còn thuộc ca (sớm tối đa ${s.maxEarlyLeave} phút).'),
      if (!isOt && s.earlyLeaveGrace > 0)
        row(Icons.timer_outlined, SboxColors.brand600, StTime.hm(s.end - s.earlyLeaveGrace), 'Miễn về sớm',
            'Ra trong ${s.earlyLeaveGrace} phút cuối không tính về sớm.'),
      row(Icons.stop_circle_rounded, SboxColors.success, StTime.hm(s.end), s.overnight ? 'Giờ ra ca (hôm sau)' : 'Giờ ra ca',
          isOt ? 'Toàn bộ giờ làm thực tế của ca được tính tăng ca.' : 'Giờ kết thúc ca.'),
      if (!isOt)
        row(Icons.more_time_rounded, SboxColors.warning, '> ${StTime.hm(s.end + s.otAfter)}', 'Tăng ca sau ca',
            s.otAfter > 0 ? 'Ra sau mốc này mới tính tăng ca (ngưỡng ${s.otAfter} phút).' : 'Ra sau giờ ra ca là tính tăng ca.'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
  }
}

void stToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(tr(message)),
    backgroundColor: error ? SboxColors.danger : null,
    behavior: SnackBarBehavior.floating,
  ));
}

String stDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
