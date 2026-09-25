import '../services/api_service.dart';
import 'paid_leave_schedule_utils.dart';

/// Tải đủ lịch làm việc trong kỳ (lặp trang) — một trang 1.000 dòng không đủ cho
/// cửa hàng đông nhân viên xếp cả tháng.
Future<List<Map<String, dynamic>>> loadAllWorkSchedules(
  ApiService api, {
  required DateTime fromDate,
  required DateTime toDate,
  bool mine = false,
  int pageSize = 1000,
  int maxPages = 30,
}) async {
  if (mine) {
    // Lịch của chính mình: một người, một kỳ — một trang là đủ.
    return extractWorkScheduleItems(await api.getMyWorkSchedules(
        fromDate: fromDate, toDate: toDate, pageSize: pageSize));
  }
  final all = <Map<String, dynamic>>[];
  for (var page = 1; page <= maxPages; page++) {
    final res = await api.getWorkSchedules(
        page: page, pageSize: pageSize, fromDate: fromDate, toDate: toDate);
    final items = extractWorkScheduleItems(res);
    all.addAll(items);
    if (items.length < pageSize) break;
  }
  return all;
}
