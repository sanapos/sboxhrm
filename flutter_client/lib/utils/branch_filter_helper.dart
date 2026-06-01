/// Helpers for branch-scoped filtering on the client (attendance logs, etc.).
class BranchFilterHelper {
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
        .where((e) {
          final bid = e['branchId']?.toString();
          return bid != null && bid.isNotEmpty && branchIds.contains(bid);
        })
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
      final bid = m['branchId']?.toString();
      if (bid == null || !branchIds.contains(bid)) continue;
      final id = m['id']?.toString();
      final userId = m['applicationUserId']?.toString();
      if (id != null && id.isNotEmpty) keys.add(id);
      if (userId != null && userId.isNotEmpty) keys.add(userId);
    }
    return keys;
  }
}
