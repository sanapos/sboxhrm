import '../services/branch_session.dart';

/// Helpers for branch-scoped filtering on the client (attendance logs, etc.).
class BranchFilterHelper {
  /// Bộ lọc chi nhánh RIÊNG của từng màn hình. Khi cửa hàng dùng bộ chọn chi nhánh trên đầu app
  /// (chi nhánh đang làm việc = chi nhánh đang xem) thì ẩn — mọi màn hình lọc theo bộ chọn chung.
  static bool showBranchFilter(Iterable? branches) =>
      !BranchSession.instance.usesBranches && hasMultipleBranches(branches);

  /// Có từ 2 chi nhánh trở lên — dùng cho cột / nhóm theo chi nhánh, ô chọn chi nhánh khi nhập liệu.
  static bool hasMultipleBranches(Iterable? branches) =>
      branches != null && branches.length >= 2;

  /// Chi nhánh mặc định cho bộ lọc của màn hình = chi nhánh đang xem trên bộ chọn chung
  /// (null = tất cả / cửa hàng chưa dùng chi nhánh).
  static String? get viewBranchId => BranchSession.instance.viewBranchId;

  /// Dữ liệu cũ chưa gắn chi nhánh (nhân viên, chấm công, đơn từ…) được tính là của **trụ sở**
  /// — cùng quy ước với chứng từ POS phía máy chủ. Trước đây so sánh bằng nhau nên khi đang xem một
  /// chi nhánh (kể cả trụ sở), mọi nhân viên / chấm công cũ chưa gắn chi nhánh biến mất khỏi danh sách.
  /// Cửa hàng chưa có trụ sở → coi như khớp (không giấu dữ liệu).
  static bool branchMatches(String? itemBranchId, Set<String> branchIds) {
    final bid = itemBranchId?.trim();
    if (bid == null || bid.isEmpty || bid == 'null') {
      final hq = BranchSession.instance.headquarterId;
      return hq == null || hq.isEmpty || branchIds.contains(hq);
    }
    return branchIds.contains(bid);
  }

  /// [selectedBranchId] null = tất cả.
  static bool inBranch(String? itemBranchId, String? selectedBranchId) =>
      selectedBranchId == null || selectedBranchId.isEmpty || branchMatches(itemBranchId, {selectedBranchId});

  /// Expands [rootBranchId] ?? to include all descendant branch IDs.
  static Set<String> expandBranchIds(
    String rootBranchId,
    List<Map<String, dynamic>> branches, {
    bool includeChildren = true,
  }) {
    final result = <String>{rootBranchId};
    if (!includeChildren || branches.isEmpty) return result;

    final childrenByParent = <String, List<String>>{};
    for (final b in branches) {
      final id = b['id']?.toString();
      final parent = b['parentBranchId']?.toString();
      if (id == null || id.isEmpty || parent == null || parent.isEmpty) {
        continue;
      }
      childrenByParent.putIfAbsent(parent, () => []).add(id);
    }

    final queue = List<String>.from(childrenByParent[rootBranchId] ?? const []);
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!result.add(current)) continue;
      final kids = childrenByParent[current];
      if (kids != null) queue.addAll(kids);
    }
    return result;
  }

  static Set<String> employeeCodesInBranches(
    List<Map<String, dynamic>> employees,
    Set<String> branchIds,
  ) {
    return employees
        .where((e) => branchMatches(e['branchId']?.toString(), branchIds))
        .map((e) => e['employeeCode']?.toString() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet();
  }

  /// Employee profile id + application user id for payroll / payslip matching.
  static Set<String> employeeKeysForBranches(
    Iterable<dynamic> employees,
    Set<String> branchIds,
  ) {
    final keys = <String>{};
    for (final raw in employees) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw as Map);
      if (!branchMatches(m['branchId']?.toString(), branchIds)) continue;
      final id = m['id']?.toString();
      final userId = m['applicationUserId']?.toString();
      if (id != null && id.isNotEmpty) keys.add(id);
      if (userId != null && userId.isNotEmpty) keys.add(userId);
    }
    return keys;
  }
}
