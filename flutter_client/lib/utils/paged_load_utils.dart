/// Helpers for APIs returning [PagedResult] (items + totalCount).
List<Map<String, dynamic>> mapsFromPagedApiData(dynamic data) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (data is Map) {
    final items = data['items'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  }
  return [];
}

int totalCountFromPagedApiData(dynamic data, {int fallback = 0}) {
  if (data is Map) {
    return (data['totalCount'] as num?)?.toInt() ?? fallback;
  }
  return fallback;
}

/// Tải đủ các trang (tránh chỉ 20–1000 bản ghi đầu).
Future<List<Map<String, dynamic>>> fetchAllPagedMaps(
  Future<Map<String, dynamic>> Function(int page, int pageSize) fetchPage, {
  int pageSize = 500,
  int maxPages = 40,
}) async {
  final all = <Map<String, dynamic>>[];
  for (var page = 1; page <= maxPages; page++) {
    final res = await fetchPage(page, pageSize);
    if (res['isSuccess'] != true) break;
    final items = mapsFromPagedApiData(res['data']);
    if (items.isEmpty) break;
    all.addAll(items);
    final tc = totalCountFromPagedApiData(res['data']);
    if (tc > 0 && all.length >= tc) break;
    if (items.length < pageSize) break;
  }
  return all;
}
