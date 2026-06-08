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

  // Attendance: message often "Name\nTime · Device"
  if (_isAttendance(categoryCode, entityType) && rawMessage.contains('\n')) {
    final lines = rawMessage.split('\n');
    final employee = lines.first.trim();
    final detail = lines.length > 1 ? lines.sublist(1).join('\n').trim() : rawMessage;
    return NotificationDisplay(
      title: 'Chấm công · $employee',
      body: detail,
      senderName: employee,
      categoryLabel: 'Chấm công',
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
