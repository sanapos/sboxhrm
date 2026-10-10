import '../models/attendance.dart';

/// Kết quả xếp lần chấm + giờ ca (tối đa 5 ca / 10 lần) cho Tổng hợp chấm công thô.
class SummaryDayPunchLayout {
  final List<DateTime?> punchTimes;
  final List<String?> punchIds;
  final List<double> shiftHours;

  const SummaryDayPunchLayout({
    required this.punchTimes,
    required this.punchIds,
    required this.shiftHours,
  });

  int get totalPunches =>
      punchTimes.where((t) => t != null).length;

  int get completeShiftCount =>
      shiftHours.where((h) => h > 0).length;
}

/// Một cặp Vào/Ra trong ngày làm việc (tổng hợp chấm công thô).
class SummaryDayPunchPair {
  final Attendance? checkIn;
  final Attendance? checkOut;

  const SummaryDayPunchPair({this.checkIn, this.checkOut});

  DateTime? get pairStart => checkIn?.punchTime ?? checkOut?.punchTime;
}

/// Ca qua đêm: ra sau 0h, ra trước giờ vào trên đồng hồ, hoặc vào tối + ra sáng trước [day_end_time].
bool isSummaryOvernightPair(
  DateTime? punchIn,
  DateTime? punchOut, {
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  final dayEnd = dayEndHour * 60 + dayEndMinute;

  if (punchIn == null && punchOut != null) {
    if (dayEnd > 0) {
      final outMin = punchOut.hour * 60 + punchOut.minute;
      if (outMin < dayEnd) return true;
    }
    return false;
  }
  if (punchIn != null && punchOut == null) {
    final inMin = punchIn.hour * 60 + punchIn.minute;
    if (inMin >= 18 * 60) return true;
    return false;
  }
  if (punchIn == null || punchOut == null) return false;

  if (punchOut.isBefore(punchIn)) return true;
  if (punchOut.year != punchIn.year ||
      punchOut.month != punchIn.month ||
      punchOut.day != punchIn.day) {
    return true;
  }
  if (dayEnd > 0) {
    final inMin = punchIn.hour * 60 + punchIn.minute;
    final outMin = punchOut.hour * 60 + punchOut.minute;
    if (inMin >= 18 * 60 && outMin < dayEnd) return true;
  }
  return false;
}

List<SummaryDayPunchPair> buildSummaryDayPairs(
  List<Attendance> dayAtts, {
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  final workAtts = Attendance.forMainShiftPairing(dayAtts);
  if (workAtts.isEmpty) return [];
  // Chỉ theo giờ, không đọc loại Vào/Ra máy: 1 lần chấm duy nhất = Vào.
  if (workAtts.length == 1) return [SummaryDayPunchPair(checkIn: workAtts.first)];

  // Luôn sort theo punchTime tăng dần, lẻ=Vào / chẵn=Ra (cặp 1–2, 3–4…).
  // Không ghép mọi CheckIn với Out đầu tiên sau đó — dễ 2 ca chồng (VD 07:07–13:04
  // trong khi 08:12–11:16 nằm giữa).
  final pairs = _pairsFromChronological(workAtts);
  return sortSummaryDayPairs(
    pairs,
    dayEndHour: dayEndHour,
    dayEndMinute: dayEndMinute,
  );
}

List<SummaryDayPunchPair> _pairsFromChronological(List<Attendance> dayAtts) {
  // DateTime đầy đủ: chấm qua đêm (giờ nhỏ hơn trên đồng hồ nhưng ngày sau) vẫn đứng cuối.
  final sorted = List<Attendance>.from(dayAtts)
    ..sort((a, b) => a.punchTime.compareTo(b.punchTime));
  final pairs = <SummaryDayPunchPair>[];
  for (var i = 0; i < sorted.length; i += 2) {
    if (i + 1 < sorted.length) {
      pairs.add(
          SummaryDayPunchPair(checkIn: sorted[i], checkOut: sorted[i + 1]));
    } else {
      pairs.add(SummaryDayPunchPair(checkIn: sorted[i]));
    }
  }
  return pairs;
}

/// Ca ngày theo giờ vào; ca qua đêm xếp cuối (vẫn sort theo giờ vào trong nhóm).
List<SummaryDayPunchPair> sortSummaryDayPairs(
  List<SummaryDayPunchPair> pairs, {
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  bool isNight(SummaryDayPunchPair p) => isSummaryOvernightPair(
        p.checkIn?.punchTime,
        p.checkOut?.punchTime,
        dayEndHour: dayEndHour,
        dayEndMinute: dayEndMinute,
      );

  int startMs(SummaryDayPunchPair p) =>
      p.pairStart?.millisecondsSinceEpoch ?? 0;

  final dayPairs = pairs.where((p) => !isNight(p)).toList()
    ..sort((a, b) => startMs(a).compareTo(startMs(b)));
  final nightPairs = pairs.where(isNight).toList()
    ..sort((a, b) => startMs(a).compareTo(startMs(b)));
  return [...dayPairs, ...nightPairs];
}

/// Flatten pairs → danh sách lần chấm (Vào, Ra, Vào, Ra, …).
List<Attendance> orderAttendancesForSummaryDay(
  List<Attendance> dayAtts, {
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  final pairs = buildSummaryDayPairs(
    dayAtts,
    dayEndHour: dayEndHour,
    dayEndMinute: dayEndMinute,
  );
  final ordered = <Attendance>[];
  for (final p in pairs) {
    if (p.checkIn != null) ordered.add(p.checkIn!);
    if (p.checkOut != null) ordered.add(p.checkOut!);
  }
  return ordered;
}

/// Xếp lần chấm theo ca (1–2, 3–4, …) và tính giờ từng ca.
SummaryDayPunchLayout layoutSummaryDayPunches(
  List<Attendance> dayAtts, {
  int lunchBreakMinutes = 60,
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  final pairs = buildSummaryDayPairs(
    dayAtts,
    dayEndHour: dayEndHour,
    dayEndMinute: dayEndMinute,
  );
  final ordered = <Attendance>[];
  for (final p in pairs) {
    if (p.checkIn != null) ordered.add(p.checkIn!);
    if (p.checkOut != null) ordered.add(p.checkOut!);
  }
  final punchTimes = List<DateTime?>.filled(10, null);
  final punchIds = List<String?>.filled(10, null);
  for (var i = 0; i < ordered.length && i < 10; i++) {
    punchTimes[i] = ordered[i].punchTime;
    punchIds[i] = ordered[i].id;
  }

  final shiftHours = List<double>.filled(5, 0);
  for (var i = 0; i < 5; i++) {
    final pin = punchTimes[i * 2];
    final pout = punchTimes[i * 2 + 1];
    if (pin != null && pout != null) {
      shiftHours[i] = summaryPairHours(
        pin,
        pout,
        lunchBreakMinutes: lunchBreakMinutes,
      );
    }
  }

  return SummaryDayPunchLayout(
    punchTimes: punchTimes,
    punchIds: punchIds,
    shiftHours: shiftHours,
  );
}

/// Raw hours between in/out minus lunch when shift is long enough.
double summaryPairHours(
  DateTime punchIn,
  DateTime punchOut, {
  int lunchBreakMinutes = 60,
}) {
  var effectiveOut = punchOut;
  if (effectiveOut.isBefore(punchIn)) {
    effectiveOut = effectiveOut.add(const Duration(days: 1));
  }
  final raw = effectiveOut.difference(punchIn).inMinutes / 60.0;
  if (raw <= 0) return 0;
  final lunchH = lunchBreakMinutes / 60.0;
  final adjusted = raw > 5 ? raw - lunchH : raw;
  return adjusted < 0 ? 0 : adjusted;
}
