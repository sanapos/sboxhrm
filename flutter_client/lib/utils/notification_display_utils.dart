/// Resolve user-facing notification title/body from API/SignalR/FCM payloads.
class NotificationDisplay {
  final String title;
  final String body;
  final String? senderName;
  final String? categoryLabel;

  const NotificationDisplay({
    required this.title,
    required this.body,
    this.senderName,
    this.categoryLabel,
  });
}

NotificationDisplay resolveNotificationDisplay(Map<String, dynamic> data) {
  final displayTitle = _nonEmpty(data['displayTitle']);
  final displayBody = _nonEmpty(data['displayBody']);
  final rawTitle = _nonEmpty(data['title']) ?? 'Thông báo mới';
  final rawMessage = _nonEmpty(data['message']) ?? '';
  final senderName = _nonEmpty(data['fromUserName']);
  final categoryLabel = _nonEmpty(data['categoryLabel']);
  final categoryCode = _nonEmpty(data['categoryCode']);
  final entityType = _nonEmpty(data['relatedEntityType']);
  final type = data['type'];

  if (displayTitle != null && displayBody != null) {
    if (_isAttendance(categoryCode, entityType)) {
      return _normalizeAttendanceDisplay(
        displayTitle: displayTitle,
        displayBody: displayBody,
        rawMessage: rawMessage,
        senderName: senderName,
      );
    }
    return NotificationDisplay(
      title: displayTitle,
      body: displayBody,
      senderName: senderName,
      categoryLabel: categoryLabel,
    );
  }

  final category = categoryLabel ??
      _categoryFromCode(categoryCode) ??
      _categoryFromEntity(entityType) ??
      _categoryFromType(type);

  if (_isAttendance(categoryCode, entityType)) {
    return _normalizeAttendanceDisplay(
      displayTitle: rawTitle,
      displayBody: rawMessage,
      rawMessage: rawMessage,
      senderName: senderName,
    );
  }

  if (senderName != null) {
    return NotificationDisplay(
      title: '$category · $senderName',
      body: _stripSenderPrefix(rawMessage, senderName).isNotEmpty
          ? _stripSenderPrefix(rawMessage, senderName)
          : rawMessage,
      senderName: senderName,
      categoryLabel: category,
    );
  }

  return NotificationDisplay(
    title: _isGenericTitle(rawTitle) ? category : rawTitle,
    body: rawMessage,
    categoryLabel: category,
  );
}

NotificationDisplay _normalizeAttendanceDisplay({
  required String displayTitle,
  required String displayBody,
  required String rawMessage,
  String? senderName,
}) {
  String employee;
  String detail;

  if (rawMessage.contains('\n')) {
    final lines = rawMessage.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    employee = lines.isNotEmpty ? lines.first : (senderName ?? 'Nhân viên');
    detail = lines.length > 1 ? lines.sublist(1).join('\n') : '';
  } else if (displayTitle.contains('·')) {
    final parts = displayTitle.split('·');
    employee = parts.length > 1 ? parts.sublist(1).join('·').trim() : (senderName ?? displayBody.trim());
    detail = displayBody.trim();
  } else {
    employee = senderName ?? displayBody.trim();
    detail = displayBody.trim();
    if (employee == detail) detail = '';
  }

  return NotificationDisplay(
    title: employee,
    body: _compactAttendanceDetail(detail),
    senderName: employee,
    categoryLabel: 'Chấm công',
  );
}

String compactAttendanceDetailForPush(String detail) => _compactAttendanceDetail(detail);

String _compactAttendanceDetail(String detail) {
  detail = detail.replaceAll('\n', ' ').trim();
  if (detail.isEmpty) return 'Chấm công';

  const taiMarker = ' tại ';
  final taiIdx = detail.indexOf(taiMarker);
  if (taiIdx >= 0) {
    final dashIdx = detail.indexOf(' - ');
    final timePart =
        dashIdx >= 0 ? detail.substring(0, dashIdx).trim() : detail.substring(0, taiIdx).trim();
    final branch = detail.substring(taiIdx + taiMarker.length).trim();
    if (branch.isNotEmpty) return '$timePart · $branch';
  }

  final sepIdx = detail.indexOf(' - ');
  if (sepIdx >= 0) {
    final timePart = detail.substring(0, sepIdx).trim();
    final rest = detail.substring(sepIdx + 3).trim();
    return rest.isEmpty ? timePart : '$timePart · $rest';
  }

  return detail;
}

String? _nonEmpty(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

bool _isAttendance(String? categoryCode, String? entityType) {
  final c = categoryCode?.toLowerCase();
  final e = entityType?.toLowerCase();
  return c == 'attendance' || e == 'attendance' || e == 'newattendance';
}

String _stripSenderPrefix(String message, String sender) {
  if (message.toLowerCase().startsWith(sender.toLowerCase())) {
    return message.substring(sender.length).trimLeftChars(': ·-\n\r');
  }
  return message;
}

extension on String {
  String trimLeftChars(String chars) {
    var i = 0;
    while (i < length && chars.contains(this[i])) {
      i++;
    }
    return substring(i);
  }
}

bool _isGenericTitle(String title) {
  const generic = {
    'thông báo',
    'thông báo mới',
    'chấm công',
    'đơn nghỉ phép mới',
    'đơn tăng ca mới',
    'yêu cầu chỉnh công mới',
    'yêu cầu ứng lương mới',
    'công việc mới',
    'công việc mới được giao',
  };
  return generic.contains(title.toLowerCase());
}

String? _categoryFromCode(String? code) {
  if (code == null) return null;
  const map = {
    'attendance': 'Chấm công',
    'leave': 'Nghỉ phép',
    'overtime': 'Tăng ca',
    'payroll': 'Lương',
    'task': 'Công việc',
    'approval': 'Phê duyệt',
    'device': 'Thiết bị',
    'hr': 'Nhân sự',
    'employee': 'Nhân sự',
    'transaction': 'Thu chi',
    'feedback': 'Phản hồi',
    'production': 'Sản lượng',
    'internal_comm': 'Truyền thông',
  };
  return map[code.toLowerCase()];
}

String? _categoryFromEntity(String? entityType) {
  if (entityType == null) return null;
  const map = {
    'leave': 'Nghỉ phép',
    'overtime': 'Tăng ca',
    'advancerequest': 'Ứng lương',
    'attendancecorrection': 'Chỉnh công',
    'worktask': 'Công việc',
    'attendance': 'Chấm công',
    'device': 'Thiết bị',
    'feedback': 'Phản hồi',
    'cashtransaction': 'Thu chi',
  };
  return map[entityType.toLowerCase()];
}

String _categoryFromType(dynamic type) {
  final intValue = type is int ? type : int.tryParse(type?.toString() ?? '') ?? 0;
  switch (intValue) {
    case 4:
      return 'Phê duyệt';
    case 2:
      return 'Cảnh báo';
    case 3:
      return 'Lỗi';
    case 5:
      return 'Nhắc nhở';
    default:
      return 'Thông báo';
  }
}
