import '../models/attendance.dart';
import '../services/api_service.dart';

/// Kết quả tải log chấm công — [truncated] khi dừng sớm vì giới hạn trang.
class AttendanceLoadResult {
  final List<Attendance> items;
  final bool truncated;
  final int? totalCount;

  const AttendanceLoadResult({
    required this.items,
    this.truncated = false,
    this.totalCount,
  });
}

/// Loads attendance rows for a period (paginated). Extends [fromDate] by one
/// calendar day when [dayEndHour]/[dayEndMinute] > 0 so overnight punches map to
/// the correct logical work day.
///
/// Luôn có trần [maxPagesHardCap] để tránh gọi API vô hạn khi totalCount thiếu
/// hoặc mỗi trang luôn đủ [pageSize] bản ghi.
Future<AttendanceLoadResult> loadAttendancesForPeriodResult(
  ApiService api, {
  required List<String> deviceIds,
  required DateTime fromDate,
  required DateTime toDate,
  int dayEndHour = 0,
  int dayEndMinute = 0,
  int pageSize = 1000,
  int parallelPages = 4,
  int maxPagesHardCap = 40,
  void Function(String message)? onProgress,
}) async {
  // deviceIds rỗng: server tự lấy máy trong store + lọc PIN theo role (Employee).

  final fetchFrom = (dayEndHour > 0 || dayEndMinute > 0)
      ? fromDate.subtract(const Duration(days: 1))
      : fromDate;

  List<Attendance> parsePage(Map<String, dynamic> result) {
    final items = (result['items'] as List?) ?? [];
    return items
        .map((a) => Attendance.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> fetchPage(int page) => api.getAttendances(
        deviceIds: deviceIds,
        fromDate: fetchFrom,
        toDate: toDate,
        page: page,
        pageSize: pageSize,
      );

  final all = <Attendance>[];
  final seenIds = <String>{};
  var truncated = false;

  onProgress?.call('Đang tải trang 1...');
  final first = await fetchPage(1);
  final firstItems = parsePage(first);
  if (firstItems.isEmpty) {
    return AttendanceLoadResult(
      items: all,
      totalCount: (first['totalCount'] as num?)?.toInt(),
    );
  }

  for (final a in firstItems) {
    seenIds.add(a.id);
  }
  all.addAll(firstItems);
  final totalCount = (first['totalCount'] as num?)?.toInt() ?? 0;

  if (firstItems.length < pageSize) {
    return AttendanceLoadResult(
      items: all,
      totalCount: totalCount > 0 ? totalCount : all.length,
    );
  }

  // Trang 1 đủ pageSize: không dừng chỉ vì totalCount == pageSize (API đôi khi
  // báo 1000 trong khi tháng có hàng chục nghìn log → chỉ thấy đến ~ngày 20).
  final firstPageFull = firstItems.length >= pageSize;
  final trustServerTotal =
      totalCount > pageSize && all.length >= totalCount;
  if (trustServerTotal) {
    return AttendanceLoadResult(items: all, totalCount: totalCount);
  }

  int lastPage;
  if (totalCount > pageSize) {
    lastPage = (totalCount / pageSize).ceil();
    if (lastPage > maxPagesHardCap) {
      lastPage = maxPagesHardCap;
      truncated = true;
    }
  } else {
    lastPage = maxPagesHardCap;
    truncated = true;
  }
  if (firstPageFull && lastPage < 2) {
    lastPage = 2;
  }

  final batch = parallelPages.clamp(2, 6);
  var done = false;

  for (var start = 2; start <= lastPage && !done; start += batch) {
    final end = (start + batch - 1) > lastPage ? lastPage : (start + batch - 1);
    onProgress?.call(
      'Đang tải log ${all.length}${totalCount > 0 ? ' / $totalCount' : ''} (trang $start–$end)...',
    );
    final pages = List.generate(end - start + 1, (i) => start + i);
    final results = await Future.wait(pages.map(fetchPage));
    for (final result in results) {
      final pageItems = parsePage(result);
      if (pageItems.isEmpty) {
        done = true;
        break;
      }

      var newOnPage = 0;
      for (final a in pageItems) {
        if (seenIds.add(a.id)) newOnPage++;
      }
      if (newOnPage == 0) {
        done = true;
        break;
      }

      all.addAll(pageItems);
      if (pageItems.length < pageSize) {
        done = true;
        break;
      }
      final reportedComplete =
          totalCount > pageSize && all.length >= totalCount;
      if (reportedComplete) {
        done = true;
        break;
      }
    }
  }

  if (!done && lastPage >= maxPagesHardCap) truncated = true;

  return AttendanceLoadResult(
    items: all,
    truncated: truncated,
    totalCount: totalCount > 0 ? totalCount : null,
  );
}

/// Back-compat wrapper.
Future<List<Attendance>> loadAttendancesForPeriod(
  ApiService api, {
  required List<String> deviceIds,
  required DateTime fromDate,
  required DateTime toDate,
  int dayEndHour = 0,
  int dayEndMinute = 0,
  int pageSize = 1000,
  int parallelPages = 4,
  int maxPagesHardCap = 40,
  void Function(String message)? onProgress,
}) async {
  final r = await loadAttendancesForPeriodResult(
    api,
    deviceIds: deviceIds,
    fromDate: fromDate,
    toDate: toDate,
    dayEndHour: dayEndHour,
    dayEndMinute: dayEndMinute,
    pageSize: pageSize,
    parallelPages: parallelPages,
    maxPagesHardCap: maxPagesHardCap,
    onProgress: onProgress,
  );
  return r.items;
}

List<dynamic> parseLeaveItemsFromResponse(Map<String, dynamic> result) {
  if (result['isSuccess'] != true) return [];
  final data = result['data'];
  if (data is Map) return (data['items'] as List?) ?? [];
  if (data is List) return data;
  return [];
}

/// Tải đủ phiếu phép trong khoảng ngày (phân trang — tránh chỉ trang 1).
Future<List<dynamic>> loadLeavesForPeriod(
  ApiService api, {
  required String fromDate,
  required String toDate,
  String? status,
  String? employeeId,
  int pageSize = 500,
  int maxPages = 20,
}) async {
  final all = <dynamic>[];
  for (var page = 1; page <= maxPages; page++) {
    final res = await api.getAllLeaves(
      page: page,
      pageSize: pageSize,
      fromDate: fromDate,
      toDate: toDate,
      status: status,
      employeeId: employeeId,
    );
    final items = parseLeaveItemsFromResponse(res);
    if (items.isEmpty) break;
    all.addAll(items);

    final data = res['data'];
    final totalCount = data is Map
        ? (data['totalCount'] as num?)?.toInt() ?? 0
        : 0;
    if (totalCount > 0 && all.length >= totalCount) break;
    if (items.length < pageSize) break;
  }
  return all;
}

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
  if (dayAtts.isEmpty) return [];
  if (dayAtts.length == 1) {
    final a = dayAtts.first;
    if (a.attendanceState == 1) {
      return [SummaryDayPunchPair(checkOut: a)];
    }
    return [SummaryDayPunchPair(checkIn: a)];
  }

  // Luôn sort theo punchTime tăng dần, lẻ=Vào / chẵn=Ra (cặp 1–2, 3–4…).
  // Không ghép mọi CheckIn với Out đầu tiên sau đó — dễ 2 ca chồng (VD 07:07–13:04
  // trong khi 08:12–11:16 nằm giữa).
  final pairs = _pairsFromChronological(dayAtts);
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
