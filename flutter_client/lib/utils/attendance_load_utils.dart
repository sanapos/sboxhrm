import '../models/attendance.dart';
import '../services/api_service.dart';
import 'attendance_date_range_presets.dart';

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

  bool get isIncomplete =>
      truncated || (totalCount != null && totalCount! > items.length);
}

int _readPageTotalCount(Map<String, dynamic> page) {
  final v = page['totalCount'] ?? page['TotalCount'];
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

List<Attendance> _parseAttendancePage(Map<String, dynamic> result) {
  final items = (result['items'] as List?) ?? [];
  return items
      .map((a) => Attendance.fromJson(a as Map<String, dynamic>))
      .toList();
}

/// Chia khoảng ngày làm việc thành các tuần (7 ngày) để tránh trang 1000 log.
List<({DateTime start, DateTime end})> _calendarWeekChunks(
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final chunks = <({DateTime start, DateTime end})>[];
  var cur = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final end = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  while (!cur.isAfter(end)) {
    var chunkEnd = cur.add(const Duration(days: 6));
    if (chunkEnd.isAfter(end)) chunkEnd = end;
    chunks.add((start: cur, end: chunkEnd));
    cur = chunkEnd.add(const Duration(days: 1));
  }
  return chunks;
}

/// Loads attendance rows for a period (paginated). Extends [fromDate] by one
/// calendar day when [dayEndHour]/[dayEndMinute] > 0 so overnight punches map to
/// the correct logical work day.
///
/// Khoảng >= 14 ngày: tải theo tuần (ổn định với ~30 NV). Ngắn hơn: phân trang
/// tuần tự, luôn gọi thêm trang khi trang 1 đủ [pageSize].
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
  final rangeStart = DateTime(fromDate.year, fromDate.month, fromDate.day);
  final rangeEnd = DateTime(toDate.year, toDate.month, toDate.day);
  final spanDays = rangeEnd.difference(rangeStart).inDays + 1;

  if (spanDays >= 14) {
    return _loadAttendancesByWeekChunks(
      api,
      deviceIds: deviceIds,
      fromDate: fromDate,
      toDate: toDate,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
      pageSize: pageSize,
      maxPagesHardCap: maxPagesHardCap,
      onProgress: onProgress,
    );
  }

  return _loadAttendancesPagedRange(
    api,
    deviceIds: deviceIds,
    fetchFrom: AttendanceDateRangePresets.fetchFromDate(
      fromDate,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
    ),
    fetchTo: AttendanceDateRangePresets.fetchToDate(
      toDate,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
    ),
    pageSize: pageSize,
    parallelPages: parallelPages,
    maxPagesHardCap: maxPagesHardCap,
    onProgress: onProgress,
  );
}

Future<AttendanceLoadResult> _loadAttendancesByWeekChunks(
  ApiService api, {
  required List<String> deviceIds,
  required DateTime fromDate,
  required DateTime toDate,
  required int dayEndHour,
  required int dayEndMinute,
  required int pageSize,
  required int maxPagesHardCap,
  void Function(String message)? onProgress,
}) async {
  final rangeStart = DateTime(fromDate.year, fromDate.month, fromDate.day);
  final rangeEnd = DateTime(toDate.year, toDate.month, toDate.day);
  final chunks = _calendarWeekChunks(rangeStart, rangeEnd);

  final all = <Attendance>[];
  final seenIds = <String>{};
  var truncated = false;
  var totalReported = 0;

  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    onProgress?.call(
      'Đang tải tuần ${i + 1}/${chunks.length} '
      '(${chunk.start.day}/${chunk.start.month}–${chunk.end.day}/${chunk.end.month})...',
    );

    final fetchFrom = AttendanceDateRangePresets.fetchFromDate(
      chunk.start,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
    );
    final fetchTo = AttendanceDateRangePresets.fetchToDate(
      chunk.end,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
    );

    final part = await _loadAttendancesPagedRange(
      api,
      deviceIds: deviceIds,
      fetchFrom: fetchFrom,
      fetchTo: fetchTo,
      pageSize: pageSize,
      parallelPages: 2,
      maxPagesHardCap: maxPagesHardCap,
      onProgress: null,
      seenIds: seenIds,
      mergeInto: all,
    );

    if (part.truncated) truncated = true;
    if (part.totalCount != null) totalReported += part.totalCount!;
  }

  onProgress?.call('Hoàn tất (${all.length} log)');

  final expected = totalReported > 0 ? totalReported : null;
  if (expected != null && all.length < expected) truncated = true;

  return AttendanceLoadResult(
    items: all,
    truncated: truncated,
    totalCount: expected,
  );
}

Future<AttendanceLoadResult> _loadAttendancesPagedRange(
  ApiService api, {
  required List<String> deviceIds,
  required DateTime fetchFrom,
  required DateTime fetchTo,
  required int pageSize,
  required int parallelPages,
  required int maxPagesHardCap,
  void Function(String message)? onProgress,
  Set<String>? seenIds,
  List<Attendance>? mergeInto,
}) async {
  Future<Map<String, dynamic>> fetchPage(int page) => api.getAttendances(
        deviceIds: deviceIds,
        fromDate: fetchFrom,
        toDate: fetchTo,
        page: page,
        pageSize: pageSize,
      );

  final all = mergeInto ?? <Attendance>[];
  final ids = seenIds ?? <String>{};
  var truncated = false;

  onProgress?.call('Đang tải trang 1...');
  final first = await fetchPage(1);
  final firstItems = _parseAttendancePage(first);
  if (firstItems.isEmpty) {
    return AttendanceLoadResult(
      items: all,
      totalCount: _readPageTotalCount(first) > 0 ? _readPageTotalCount(first) : null,
    );
  }

  for (final a in firstItems) {
    if (ids.add(a.id)) all.add(a);
  }
  final totalCount = _readPageTotalCount(first);

  if (firstItems.length < pageSize) {
    return AttendanceLoadResult(
      items: all,
      totalCount: totalCount > 0 ? totalCount : all.length,
    );
  }

  // Trang 1 đủ pageSize — bắt buộc thử trang 2+ (Trường Phát ~1756 log/tháng).
  var lastPage = totalCount > pageSize
      ? (totalCount / pageSize).ceil()
      : maxPagesHardCap;
  if (lastPage < 2) lastPage = 2;
  if (lastPage > maxPagesHardCap) {
    lastPage = maxPagesHardCap;
    truncated = true;
  }

  var page = 2;
  while (page <= lastPage) {
    onProgress?.call(
      'Đang tải log ${all.length}${totalCount > 0 ? ' / $totalCount' : ''} (trang $page)...',
    );

    Map<String, dynamic> result;
    try {
      result = await fetchPage(page);
    } catch (_) {
      truncated = true;
      break;
    }

    final pageItems = _parseAttendancePage(result);
    if (pageItems.isEmpty) {
      if (totalCount > 0 && all.length < totalCount && page == 2) {
        truncated = true;
      }
      break;
    }

    var newOnPage = 0;
    for (final a in pageItems) {
      if (ids.add(a.id)) {
        all.add(a);
        newOnPage++;
      }
    }

    if (newOnPage == 0 && pageItems.isNotEmpty) {
      // Trùng ID — thử trang kế tiếp một lần (pagination lệch).
      page++;
      continue;
    }

    if (pageItems.length < pageSize) break;
    if (totalCount > 0 && all.length >= totalCount) break;

    page++;
  }

  if (totalCount > 0 && all.length < totalCount) truncated = true;
  if (page > lastPage && all.length < (totalCount > 0 ? totalCount : all.length + 1)) {
    truncated = true;
  }

  return AttendanceLoadResult(
    items: all,
    truncated: truncated,
    totalCount: totalCount > 0 ? totalCount : null,
  );
}

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
  final workAtts = Attendance.withoutTravel(dayAtts);
  if (workAtts.isEmpty) return [];
  if (workAtts.length == 1) {
    final a = workAtts.first;
    if (a.attendanceState == 1) {
      return [SummaryDayPunchPair(checkOut: a)];
    }
    return [SummaryDayPunchPair(checkIn: a)];
  }

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
