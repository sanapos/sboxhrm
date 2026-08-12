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
    final title = _isGenericTitle(rawTitle)
        ? '$category · $senderName'
        : rawTitle;
    final stripped = _stripSenderPrefix(rawMessage, senderName);
    var body = stripped.isNotEmpty ? stripped : rawMessage;
    if (body.isEmpty) body = rawTitle;
    if (!_isGenericTitle(rawTitle) &&
        body.isNotEmpty &&
        !body.toLowerCase().contains(senderName.toLowerCase())) {
      body = '$senderName: $body';
    }
    return NotificationDisplay(
      title: title,
      body: body,
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
    final lines = rawMessage
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    employee = lines.isNotEmpty ? lines.first : (senderName ?? 'Nhân viên');
    detail = lines.length > 1 ? lines.sublist(1).join('\n') : '';
  } else if (displayTitle.contains('·')) {
    final parts = displayTitle.split('·');
    employee = parts.length > 1
        ? parts.sublist(1).join('·').trim()
        : (senderName ?? displayBody.trim());
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

String _compactAttendanceDetail(String detail) {
  detail = detail.replaceAll('\n', ' ').trim();
  if (detail.isEmpty) return 'Chấm công';

  const taiMarker = ' tại ';
  final taiIdx = detail.indexOf(taiMarker);
  if (taiIdx >= 0) {
    final dashIdx = detail.indexOf(' - ');
    final timePart = dashIdx >= 0
        ? detail.substring(0, dashIdx).trim()
        : detail.substring(0, taiIdx).trim();
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
    return message.substring(sender.length).replaceFirst(RegExp(r'^[: ·\-\n\r]+'), '');
  }
  return message;
}

bool _isGenericTitle(String title) {
  const generic = {
    'thông báo',
    'thông báo mới',
    'thông báo hệ thống',
    'chấm công',
  };
  return generic.contains(title.toLowerCase());
}

String? _categoryFromCode(String? code) {
  if (code == null) return null;
  const map = {
    'attendance': 'Chấm công',
    'travel_attendance': 'Chấm đi đường',
    'leave': 'Nghỉ phép',
    'overtime': 'Tăng ca',
    'payroll': 'Lương',
    'task': 'Công việc',
    'approval': 'Phê duyệt',
    'device': 'Thiết bị',
    'hr': 'Nhân sự',
    'employee': 'Nhân sự',
    'system': 'Hệ thống',
    'transaction': 'Thu chi',
    'penalty': 'Phiếu phạt',
    'meal': 'Suất ăn',
    'business_trip': 'Công tác',
    'pos': 'POS',
    'shift': 'Ca làm việc',
    'feedback': 'Phản hồi',
    'production': 'Sản lượng',
    'kpi': 'KPI',
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
    'businesstripcase': 'Công tác',
    'businesstripexpense': 'Công tác',
    'penaltyticket': 'Phiếu phạt',
  };
  return map[entityType.toLowerCase()];
}

String _categoryFromType(dynamic type) {
  final intValue =
      type is int ? type : int.tryParse(type?.toString() ?? '') ?? 0;
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
