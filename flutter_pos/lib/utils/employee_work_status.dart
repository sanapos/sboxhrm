/// Trạng thái làm việc — khớp [EmployeeWorkStatus] trên server.
class EmployeeWorkStatusUtil {
  EmployeeWorkStatusUtil._();

  static const int active = 0;
  static const int resigned = 1;
  static const int onLeave = 2;
  static const int probation = 3;

  static const labels = [
    'Đang làm việc',
    'Đã nghỉ việc',
    'Nghỉ phép',
    'Đang thử việc',
  ];

  /// UI label → giá trị API (int enum).
  static int toApiValue(String displayLabel) {
    switch (displayLabel) {
      case 'Đã nghỉ việc':
        return resigned;
      case 'Nghỉ phép':
        return onLeave;
      case 'Đang thử việc':
        return probation;
      case 'Đang làm việc':
      default:
        return active;
    }
  }

  /// Giá trị API (string enum hoặc int) → nhãn hiển thị tiếng Việt.
  static String toDisplayLabel(String? raw) {
    if (raw == null || raw.isEmpty) return 'Đang làm việc';

    final normalized = raw.trim().toLowerCase().replaceAll(' ', '');
    switch (normalized) {
      case 'active':
      case '0':
        return 'Đang làm việc';
      case 'resigned':
      case '1':
        return 'Đã nghỉ việc';
      case 'onleave':
      case '2':
        return 'Nghỉ phép';
      case 'probation':
      case '3':
        return 'Đang thử việc';
    }

    final asInt = int.tryParse(raw);
    if (asInt != null) return _labelFromInt(asInt);

    return 'Đang làm việc';
  }

  static String _labelFromInt(int value) {
    switch (value) {
      case resigned:
        return 'Đã nghỉ việc';
      case onLeave:
        return 'Nghỉ phép';
      case probation:
        return 'Đang thử việc';
      case active:
      default:
        return 'Đang làm việc';
    }
  }

  /// Còn trong biên chế (chưa nghỉ việc hẳn).
  static bool isEmployed(String? raw) =>
      toDisplayLabel(raw) != 'Đã nghỉ việc';

  static bool isResigned(String? raw) =>
      toDisplayLabel(raw) == 'Đã nghỉ việc';

  static bool isSelectableMap(Map<String, dynamic> m, {String? keepEmployeeId}) {
    final id = m['id']?.toString() ?? '';
    if (keepEmployeeId != null &&
        keepEmployeeId.isNotEmpty &&
        id == keepEmployeeId) {
      return true;
    }
    return !isResigned(m['workStatus']?.toString());
  }

  static List<Map<String, dynamic>> filterSelectableMaps(
    Iterable<dynamic> list, {
    Iterable<String>? keepEmployeeIds,
  }) {
    final keep = keepEmployeeIds
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        const {};
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) {
          final id = m['id']?.toString() ?? '';
          if (keep.contains(id)) return true;
          return !isResigned(m['workStatus']?.toString());
        })
        .toList();
  }

  /// NV đã nghỉ việc xếp cuối; còn lại theo họ tên rồi mã NV.
  static int compareListOrder({
    required String? workStatusA,
    required String? workStatusB,
    required String nameA,
    required String nameB,
    required String codeA,
    required String codeB,
  }) {
    final aResigned = isResigned(workStatusA);
    final bResigned = isResigned(workStatusB);
    if (aResigned != bResigned) return aResigned ? 1 : -1;

    final byName = nameA.toLowerCase().compareTo(nameB.toLowerCase());
    if (byName != 0) return byName;
    return codeA.compareTo(codeB);
  }
}
