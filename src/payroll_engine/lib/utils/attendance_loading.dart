import '../models/attendance.dart';
import '../payroll_api.dart';

/// Mở rộng ngày bắt đầu tải thêm 1 ngày khi có giờ chốt ngày (ca qua đêm).
DateTime _fetchFromDate(DateTime rangeStart, {int dayEndHour = 0, int dayEndMinute = 0}) {
  final start = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  if (dayEndHour > 0 || dayEndMinute > 0) return start.subtract(const Duration(days: 1));
  return start;
}

DateTime _fetchToDate(DateTime rangeEnd, {int dayEndHour = 0, int dayEndMinute = 0}) {
  final end = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  if (dayEndHour > 0 || dayEndMinute > 0) return end.add(const Duration(days: 1));
  return end;
}

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
  PayrollApi api, {
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
    fetchFrom: _fetchFromDate(
      fromDate,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
    ),
    fetchTo: _fetchToDate(
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
  PayrollApi api, {
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

  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    onProgress?.call(
      'Đang tải tuần ${i + 1}/${chunks.length} '
      '(${chunk.start.day}/${chunk.start.month}–${chunk.end.day}/${chunk.end.month})...',
    );

    final fetchFrom = _fetchFromDate(
      chunk.start,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
    );
    final fetchTo = _fetchToDate(
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

    // Chỉ coi thiếu khi một tuần dừng sớm (lỗi mạng / hard cap trang).
    // Không cộng totalCount các tuần: fetchFrom/fetchTo cố ý chồng ~1–2 ngày
    // quanh day_end_time → tổng API bị đếm đôi trong khi log đã dedupe theo id.
    if (part.truncated) truncated = true;
  }

  onProgress?.call('Hoàn tất (${all.length} log)');

  return AttendanceLoadResult(
    items: all,
    truncated: truncated,
    // Never sum weekly API totalCounts — fetch windows intentionally overlap by
    // ~1–2 days when day_end_time is set, so the sum looks like "missing" logs
    // (e.g. 1648 unique / 2043 summed) even when every punch was loaded.
    // On real truncation, omit expected so the UI shows a generic reload hint.
    totalCount: truncated || all.isEmpty ? null : all.length,
  );
}

Future<AttendanceLoadResult> _loadAttendancesPagedRange(
  PayrollApi api, {
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
  PayrollApi api, {
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
  PayrollApi api, {
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

