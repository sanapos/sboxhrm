import '../models/department.dart';

/// Expand a parent department to include descendant department IDs/names.
class DepartmentFilterHelper {
  /// Hiện bộ lọc phòng ban khi có từ 2 phòng trở lên (1 phòng thì ẩn).
  static bool showDepartmentFilter(Iterable? departments) =>
      departments != null && departments.length >= 2;

  static String? _idOf(dynamic d) {
    if (d is Department) return d.id;
    if (d is DepartmentSelectDto) return d.id;
    if (d is DepartmentTreeNode) return d.id;
    if (d is Map) {
      return (d['id'] ?? d['Id'])?.toString();
    }
    return null;
  }

  static String? _parentIdOf(dynamic d) {
    if (d is Department) return d.parentId ?? d.parentDepartmentId;
    if (d is DepartmentSelectDto) return d.parentId;
    if (d is DepartmentTreeNode) return d.parentId;
    if (d is Map) {
      final parent = d['parentDepartmentId'] ??
          d['parentId'] ??
          d['ParentDepartmentId'] ??
          d['ParentId'];
      return parent?.toString();
    }
    return null;
  }

  static String? _nameOf(dynamic d) {
    if (d is Department) return d.name;
    if (d is DepartmentSelectDto) return d.name;
    if (d is DepartmentTreeNode) return d.name;
    if (d is Map) return d['name']?.toString() ?? d['Name']?.toString();
    return null;
  }

  /// Expands [rootDepartmentId] to include all descendant department IDs.
  static Set<String> expandDepartmentIds(
    String rootDepartmentId,
    Iterable departments, {
    bool includeChildren = true,
  }) {
    final result = <String>{rootDepartmentId};
    if (!includeChildren) return result;

    final childrenByParent = <String, List<String>>{};
    for (final d in departments) {
      final id = _idOf(d);
      final parent = _parentIdOf(d);
      if (id == null || id.isEmpty || parent == null || parent.isEmpty) {
        continue;
      }
      childrenByParent.putIfAbsent(parent, () => []).add(id);
    }

    final queue = List<String>.from(childrenByParent[rootDepartmentId] ?? const []);
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!result.add(current)) continue;
      final kids = childrenByParent[current];
      if (kids != null) queue.addAll(kids);
    }
    return result;
  }

  /// Walk nested [node.children] (preferred when the org tree is already loaded).
  static Set<String> expandFromTreeNode(
    DepartmentTreeNode node, {
    bool includeChildren = true,
  }) {
    final ids = <String>{node.id};
    if (!includeChildren) return ids;
    for (final child in node.children) {
      ids.addAll(expandFromTreeNode(child));
    }
    return ids;
  }

  /// Names of [rootName] plus all descendant departments (same-name roots included).
  static Set<String> expandDepartmentNames(
    String rootName,
    Iterable departments, {
    bool includeChildren = true,
  }) {
    final names = <String>{rootName};
    final roots = <String>[];
    for (final d in departments) {
      if (_nameOf(d) == rootName) {
        final id = _idOf(d);
        if (id != null && id.isNotEmpty) roots.add(id);
      }
    }
    if (roots.isEmpty) return names;

    final ids = <String>{};
    for (final id in roots) {
      ids.addAll(expandDepartmentIds(id, departments, includeChildren: includeChildren));
    }
    for (final d in departments) {
      final id = _idOf(d);
      final name = _nameOf(d);
      if (id != null && ids.contains(id) && name != null && name.isNotEmpty) {
        names.add(name.trim());
      }
    }
    return names;
  }

  static bool employeeMatchesDepartmentFilter({
    required String filterName,
    required Iterable departments,
    String? departmentName,
    String? departmentId,
  }) {
    if (filterName.isEmpty || filterName == 'Tất cả') return true;

    if (departmentId != null && departmentId.isNotEmpty) {
      final ids = <String>{};
      for (final d in departments) {
        if (_nameOf(d) == filterName) {
          final id = _idOf(d);
          if (id != null && id.isNotEmpty) {
            ids.addAll(expandDepartmentIds(id, departments));
          }
        }
      }
      if (ids.contains(departmentId)) return true;
    }

    final names = expandDepartmentNames(filterName, departments);
    return departmentName != null && names.contains(departmentName);
  }

  static bool _employeeInDepartments(
    Map<String, dynamic> m,
    Set<String> departmentIds,
    Set<String> departmentNames,
  ) {
    final nested = m['department'];
    final did = m['departmentId']?.toString() ??
        m['DepartmentId']?.toString() ??
        (nested is Map ? (nested['id'] ?? nested['Id'])?.toString() : null) ??
        '';
    if (did.isNotEmpty &&
        did != 'null' &&
        departmentIds.contains(did)) {
      return true;
    }
    final dname = m['departmentName']?.toString() ??
        m['DepartmentName']?.toString() ??
        (nested is Map
            ? (nested['name'] ?? nested['Name'])?.toString()
            : null) ??
        (nested is String ? nested : null) ??
        m['department']?.toString() ??
        m['Department']?.toString() ??
        '';
    return dname.isNotEmpty &&
        dname != 'null' &&
        departmentNames.contains(dname.trim());
  }

  static Set<String> _departmentNamesForIds(
    Iterable departments,
    Set<String> departmentIds,
  ) {
    final names = <String>{};
    for (final d in departments) {
      final id = _idOf(d);
      final name = _nameOf(d);
      if (id != null &&
          departmentIds.contains(id) &&
          name != null &&
          name.isNotEmpty) {
        names.add(name.trim());
      }
    }
    return names;
  }

  /// Employee profile id + application user id for report matching.
  static Set<String> employeeKeysForDepartments(
    Iterable employees,
    Set<String> departmentIds,
    Iterable departments,
  ) {
    final names = _departmentNamesForIds(departments, departmentIds);
    final keys = <String>{};
    for (final raw in employees) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (!_employeeInDepartments(m, departmentIds, names)) continue;
      final id = m['id']?.toString();
      final userId = m['applicationUserId']?.toString();
      if (id != null && id.isNotEmpty) keys.add(id);
      if (userId != null && userId.isNotEmpty) keys.add(userId);
    }
    return keys;
  }

  static Set<String> employeeCodesInDepartments(
    Iterable employees,
    Set<String> departmentIds,
    Iterable departments,
  ) {
    final names = _departmentNamesForIds(departments, departmentIds);
    final codes = <String>{};
    for (final raw in employees) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (!_employeeInDepartments(m, departmentIds, names)) continue;
      for (final field in const ['employeeCode', 'pin', 'Pin']) {
        final v = m[field]?.toString() ?? '';
        if (v.isNotEmpty && v != 'null') codes.add(v);
      }
    }
    return codes;
  }
}
