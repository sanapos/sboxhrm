// Công việc v2: dự án, giai đoạn theo ngành, checklist có ảnh, gói ngành, thống kê.
import 'dart:convert';

import 'package:flutter/material.dart';

import 'task.dart';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse('$v');
List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

/// Màu từ chuỗi #RRGGBB (mặc định xanh SBOX).
Color hexColor(String? hex, [Color fallback = const Color(0xFF158DC0)]) {
  final h = (hex ?? '').replaceFirst('#', '');
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

String colorHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class TaskStageV2 {
  TaskStageV2({required this.key, required this.name, this.color, this.done = false});
  String key;
  String name;
  String? color;
  bool done;

  factory TaskStageV2.fromJson(Map<String, dynamic> j) => TaskStageV2(
        key: '${j['key'] ?? ''}',
        name: '${j['name'] ?? ''}',
        color: j['color']?.toString(),
        done: j['done'] == true,
      );

  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'color': color, 'done': done};

  Color get colorValue => hexColor(color);
}

enum TaskProjectStatus { active, onHold, completed, cancelled, archived }

String taskProjectStatusLabel(TaskProjectStatus s) => switch (s) {
      TaskProjectStatus.active => 'Đang thực hiện',
      TaskProjectStatus.onHold => 'Tạm dừng',
      TaskProjectStatus.completed => 'Hoàn thành',
      TaskProjectStatus.cancelled => 'Đã hủy',
      TaskProjectStatus.archived => 'Lưu trữ',
    };

class TaskProjectV2 {
  TaskProjectV2({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.industryKey,
    this.color,
    this.status = TaskProjectStatus.active,
    this.ownerEmployeeId,
    this.ownerName,
    this.customerName,
    this.customerPhone,
    this.address,
    this.budget,
    this.startDate,
    this.dueDate,
    this.stages = const [],
    this.taskCount = 0,
    this.doneCount = 0,
    this.inProgressCount = 0,
    this.overdueCount = 0,
    this.progress = 0,
    this.isOverdue = false,
    this.stageCounts = const {},
  });

  final String id;
  final String code;
  final String name;
  final String? description;
  final String? industryKey;
  final String? color;
  final TaskProjectStatus status;
  final String? ownerEmployeeId;
  final String? ownerName;
  final String? customerName;
  final String? customerPhone;
  final String? address;
  final double? budget;
  final DateTime? startDate;
  final DateTime? dueDate;
  final List<TaskStageV2> stages;
  final int taskCount;
  final int doneCount;
  final int inProgressCount;
  final int overdueCount;
  final int progress;
  final bool isOverdue;
  final Map<String, int> stageCounts;

  Color get colorValue => hexColor(color);

  factory TaskProjectV2.fromJson(Map<String, dynamic> j) => TaskProjectV2(
        id: '${j['id']}',
        code: '${j['code'] ?? ''}',
        name: '${j['name'] ?? ''}',
        description: j['description'],
        industryKey: j['industryKey'],
        color: j['color'],
        status: TaskProjectStatus.values[_i(j['status']).clamp(0, TaskProjectStatus.values.length - 1)],
        ownerEmployeeId: j['ownerEmployeeId']?.toString(),
        ownerName: j['ownerName'],
        customerName: j['customerName'],
        customerPhone: j['customerPhone'],
        address: j['address'],
        budget: j['budget'] == null ? null : _d(j['budget']),
        startDate: _dt(j['startDate']),
        dueDate: _dt(j['dueDate']),
        stages: _maps(j['stages']).map(TaskStageV2.fromJson).toList(),
        taskCount: _i(j['taskCount']),
        doneCount: _i(j['doneCount']),
        inProgressCount: _i(j['inProgressCount']),
        overdueCount: _i(j['overdueCount']),
        progress: _i(j['progress']),
        isOverdue: j['isOverdue'] == true,
        stageCounts: j['stageCounts'] is Map
            ? (j['stageCounts'] as Map).map((k, v) => MapEntry('$k', _i(v)))
            : const {},
      );
}

class TaskChecklistItemV2 {
  TaskChecklistItemV2({
    required this.id,
    required this.text,
    this.done = false,
    this.requirePhoto = false,
    this.photoUrl,
    this.note,
    this.doneBy,
    this.doneAt,
  });

  String id;
  String text;
  bool done;
  bool requirePhoto;
  String? photoUrl;
  String? note;
  String? doneBy;
  DateTime? doneAt;

  factory TaskChecklistItemV2.fromJson(Map<String, dynamic> j, int index) => TaskChecklistItemV2(
        id: '${j['id'] ?? 'c${index + 1}'}',
        text: '${j['text'] ?? j['title'] ?? j['name'] ?? ''}',
        done: j['done'] == true || j['isDone'] == true || j['completed'] == true,
        requirePhoto: j['requirePhoto'] == true,
        photoUrl: j['photoUrl'],
        note: j['note'],
        doneBy: j['doneBy'],
        doneAt: _dt(j['doneAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        'requirePhoto': requirePhoto,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (note != null) 'note': note,
        if (doneBy != null) 'doneBy': doneBy,
        if (doneAt != null) 'doneAt': doneAt!.toIso8601String(),
      };

  /// Đọc checklist (định dạng mới hoặc mảng chuỗi cũ).
  static List<TaskChecklistItemV2> parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final v = jsonDecode(raw);
      if (v is! List) return [];
      final out = <TaskChecklistItemV2>[];
      for (var i = 0; i < v.length; i++) {
        final e = v[i];
        if (e is String && e.trim().isNotEmpty) {
          out.add(TaskChecklistItemV2(id: 'c${i + 1}', text: e.trim()));
        } else if (e is Map) {
          final it = TaskChecklistItemV2.fromJson(Map<String, dynamic>.from(e), i);
          if (it.text.trim().isNotEmpty) out.add(it);
        }
      }
      return out;
    } catch (_) {
      return raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList()
          .asMap()
          .entries
          .map((e) => TaskChecklistItemV2(id: 'c${e.key + 1}', text: e.value))
          .toList();
    }
  }

  static String encode(List<TaskChecklistItemV2> items) => jsonEncode(items.map((e) => e.toJson()).toList());
}

extension WorkTaskV2X on WorkTask {
  List<TaskChecklistItemV2> get checklistItems => TaskChecklistItemV2.parse(checklist);
  bool get isDone => status == WorkTaskStatus.completed;
  bool get isOpen => status != WorkTaskStatus.completed && status != WorkTaskStatus.cancelled;
  bool get overdueNow => isOpen && dueDate != null && dueDate!.isBefore(DateTime.now());

  /// Tên người làm: người chính + người phụ.
  List<String> get peopleNames {
    final names = <String>[
      if (assigneeName != null && assigneeName!.trim().isNotEmpty) assigneeName!.trim(),
    ];
    for (final a in assignees ?? const <TaskAssignee>[]) {
      final n = a.employeeName?.trim();
      if (n != null && n.isNotEmpty && !names.contains(n)) names.add(n);
    }
    return names;
  }
}

class TaskPackTemplateV2 {
  TaskPackTemplateV2.fromJson(Map<String, dynamic> j)
      : name = '${j['name'] ?? ''}',
        taskType = parseTaskType(j['taskType']),
        stageKey = j['stageKey'],
        estimatedHours = j['estimatedHours'] == null ? null : _d(j['estimatedHours']),
        checklist = (j['checklist'] is List ? (j['checklist'] as List).map((e) => '$e').toList() : <String>[]),
        photoItems = _i(j['photoItems']),
        recurrenceType = _i(j['recurrenceType']),
        recurrenceDays = j['recurrenceDays'],
        recurrenceTime = j['recurrenceTime'];

  final String name;
  final TaskType taskType;
  final String? stageKey;
  final double? estimatedHours;
  final List<String> checklist;
  final int photoItems;
  final int recurrenceType;
  final String? recurrenceDays;
  final String? recurrenceTime;
}

class TaskIndustryPackV2 {
  TaskIndustryPackV2.fromJson(Map<String, dynamic> j)
      : key = '${j['key']}',
        name = '${j['name'] ?? ''}',
        icon = '${j['icon'] ?? ''}',
        description = '${j['description'] ?? ''}',
        projectLabel = '${j['projectLabel'] ?? 'Dự án'}',
        color = '${j['color'] ?? ''}',
        stages = _maps(j['stages']).map(TaskStageV2.fromJson).toList(),
        templates = _maps(j['templates']).map(TaskPackTemplateV2.fromJson).toList(),
        installedTemplates = _i(j['installedTemplates']),
        taskLabel = '${j['taskLabel'] ?? 'Công việc'}',
        featured = j['featured'] == true;

  final String key;
  final String name;
  final String icon;
  final String description;
  final String projectLabel;
  final String color;
  final List<TaskStageV2> stages;
  final List<TaskPackTemplateV2> templates;
  final int installedTemplates;

  /// Tên gọi việc theo ngành (Hạng mục / Phiếu dịch vụ / Cơ hội…).
  final String taskLabel;

  /// Gói ưu tiên (F&B, Xây dựng, Bán lẻ, Dịch vụ, Quản lý sale).
  final bool featured;

  bool get installed => installedTemplates > 0;
  int get recurringCount => templates.where((t) => t.recurrenceType != 0).length;

  IconData get iconData => switch (key) {
        'interior' || 'construction' => Icons.construction_outlined,
        'service' => Icons.home_repair_service_outlined,
        'sales' => Icons.trending_up_outlined,
        'repair' => Icons.build_outlined,
        'spa' => Icons.spa_outlined,
        'fnb' => Icons.restaurant_outlined,
        'retail' => Icons.storefront_outlined,
        'logistics' => Icons.local_shipping_outlined,
        'manufacturing' => Icons.precision_manufacturing_outlined,
        'hotel' => Icons.hotel_outlined,
        'office' => Icons.work_outline,
        _ => Icons.category_outlined,
      };
}

/// Lịch lặp của mẫu việc.
String recurrenceLabel(int type, String? days, String? time) {
  const wd = ['', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  final at = time == null || time.isEmpty ? '' : ' lúc $time';
  switch (type) {
    case 1:
      return 'Hằng ngày$at';
    case 2:
      final list = (days ?? '')
          .split(',')
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .where((d) => d >= 1 && d <= 7)
          .map((d) => wd[d])
          .join(', ');
      return 'Hằng tuần ${list.isEmpty ? '' : '($list)'}$at'.replaceAll('  ', ' ');
    case 3:
      final list = (days ?? '').split(',').map((e) => e.trim() == '0' ? 'cuối tháng' : 'ngày ${e.trim()}').join(', ');
      return 'Hằng tháng ($list)$at';
    default:
      return 'Không lặp';
  }
}

class TaskTemplateV2 {
  TaskTemplateV2.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        name = '${j['name'] ?? ''}',
        title = '${j['title'] ?? ''}',
        description = j['description'],
        taskType = parseTaskType(j['taskType']),
        priority = parsePriority(j['priority']),
        estimatedHours = j['estimatedHours'] == null ? null : _d(j['estimatedHours']),
        checklist = j['checklist'],
        industryKey = j['industryKey'],
        stageKey = j['stageKey'],
        projectId = j['projectId']?.toString(),
        recurrenceType = _i(j['recurrenceType']),
        recurrenceDays = j['recurrenceDays'],
        recurrenceTime = j['recurrenceTime'],
        dueAfterHours = j['dueAfterHours'] == null ? null : _i(j['dueAfterHours']),
        defaultAssigneeIds = (j['defaultAssigneeIds'] is List)
            ? (j['defaultAssigneeIds'] as List).map((e) => '$e').toList()
            : <String>[],
        nextRunAt = _dt(j['nextRunAt']),
        lastRunAt = _dt(j['lastRunAt']),
        formSchema = j['formSchema'],
        pieceRate = j['pieceRate'] == null ? null : _d(j['pieceRate']),
        assignOnShift = j['assignOnShift'] == true,
        requireCheckIn = j['requireCheckIn'] == true;

  /// Biểu mẫu riêng (JSON), tiền khoán, giao theo ca, bắt buộc check-in.
  final String? formSchema;
  final double? pieceRate;
  final bool assignOnShift;
  final bool requireCheckIn;

  int get formFieldCount => TaskFormFieldV2.parse(formSchema).length;

  final String id;
  final String name;
  final String title;
  final String? description;
  final TaskType taskType;
  final TaskPriority priority;
  final double? estimatedHours;
  final String? checklist;
  final String? industryKey;
  final String? stageKey;
  final String? projectId;
  final int recurrenceType;
  final String? recurrenceDays;
  final String? recurrenceTime;
  final int? dueAfterHours;
  final List<String> defaultAssigneeIds;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;

  int get checklistCount => TaskChecklistItemV2.parse(checklist).length;
}

class TaskWorkloadV2 {
  TaskWorkloadV2.fromJson(Map<String, dynamic> j)
      : employeeId = '${j['employeeId']}',
        employeeName = '${j['employeeName'] ?? '—'}',
        employeeCode = j['employeeCode'],
        open = _i(j['open']),
        inProgress = _i(j['inProgress']),
        overdue = _i(j['overdue']),
        dueSoon = _i(j['dueSoon']),
        completedInRange = _i(j['completedInRange']),
        completedOnTime = _i(j['completedOnTime']),
        onTimeRate = _d(j['onTimeRate']),
        openEstimatedHours = _d(j['openEstimatedHours']);

  final String employeeId;
  final String employeeName;
  final String? employeeCode;
  final int open;
  final int inProgress;
  final int overdue;
  final int dueSoon;
  final int completedInRange;
  final int completedOnTime;
  final double onTimeRate;
  final double openEstimatedHours;
}

class TaskTimelineItemV2 {
  TaskTimelineItemV2.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        taskCode = '${j['taskCode'] ?? ''}',
        title = '${j['title'] ?? ''}',
        status = parseTaskStatus(j['status']),
        priority = parsePriority(j['priority']),
        progress = _i(j['progress']),
        startDate = _dt(j['startDate']),
        dueDate = _dt(j['dueDate']),
        completedDate = _dt(j['completedDate']),
        createdAt = _dt(j['createdAt']) ?? DateTime.now(),
        stageKey = j['stageKey'],
        projectId = j['projectId']?.toString(),
        projectName = j['projectName'],
        assigneeName = j['assigneeName'],
        blockedBy = (j['blockedBy'] is List) ? (j['blockedBy'] as List).map((e) => '$e').toList() : <String>[];

  final String id;
  final String taskCode;
  final String title;
  final WorkTaskStatus status;
  final TaskPriority priority;
  final int progress;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? completedDate;
  final DateTime createdAt;
  final String? stageKey;
  final String? projectId;
  final String? projectName;
  final String? assigneeName;
  final List<String> blockedBy;

  DateTime get barStart => startDate ?? createdAt;
  DateTime get barEnd {
    final end = dueDate ?? completedDate ?? barStart.add(const Duration(days: 1));
    return end.isBefore(barStart) ? barStart.add(const Duration(hours: 4)) : end;
  }

  bool get overdue =>
      status != WorkTaskStatus.completed && status != WorkTaskStatus.cancelled && dueDate != null && dueDate!.isBefore(DateTime.now());
}

class TaskInsightsV2 {
  TaskInsightsV2.fromJson(Map<String, dynamic> j)
      : total = _i(j['total']),
        open = _i(j['open']),
        inProgress = _i(j['inProgress']),
        pendingAcceptance = _i(j['pendingAcceptance']),
        inReview = _i(j['inReview']),
        overdue = _i(j['overdue']),
        dueToday = _i(j['dueToday']),
        completedInRange = _i(j['completedInRange']),
        completedOnTime = _i(j['completedOnTime']),
        onTimeRate = _d(j['onTimeRate']),
        avgCycleHours = _d(j['avgCycleHours']),
        completedPrevRange = _i(j['completedPrevRange']),
        activeProjects = _i(j['activeProjects']),
        byDay = _maps(j['byDay'])
            .map((d) => (
                  date: _dt(d['date']) ?? DateTime.now(),
                  created: _i(d['created']),
                  completed: _i(d['completed']),
                  late: _i(d['completedLate']),
                ))
            .toList(),
        byStatus = j['byStatus'] is Map ? (j['byStatus'] as Map).map((k, v) => MapEntry('$k', _i(v))) : const {},
        byType = j['byType'] is Map ? (j['byType'] as Map).map((k, v) => MapEntry('$k', _i(v))) : const {};

  final int total;
  final int open;
  final int inProgress;
  final int pendingAcceptance;
  final int inReview;
  final int overdue;
  final int dueToday;
  final int completedInRange;
  final int completedOnTime;
  final double onTimeRate;
  final double avgCycleHours;
  final int completedPrevRange;
  final int activeProjects;
  final List<({DateTime date, int created, int completed, int late})> byDay;
  final Map<String, int> byStatus;
  final Map<String, int> byType;
}


/// Một trường biểu mẫu riêng của loại việc.
/// type: text / textarea / number / money / select / date / phone / checkbox / photo / signature / rating.
class TaskFormFieldV2 {
  TaskFormFieldV2({
    this.key = '',
    required this.label,
    this.type = 'text',
    this.required = false,
    this.options = const [],
    this.unit,
    this.hint,
  });

  TaskFormFieldV2.fromJson(Map<String, dynamic> j)
      : key = '${j['key'] ?? ''}',
        label = '${j['label'] ?? ''}',
        type = '${j['type'] ?? 'text'}',
        required = j['required'] == true,
        options = (j['options'] is List) ? (j['options'] as List).map((e) => '$e').toList() : const [],
        unit = j['unit'],
        hint = j['hint'];

  String key;
  String label;
  String type;
  bool required;
  List<String> options;
  String? unit;
  String? hint;

  static const types = <String, String>{
    'text': 'Chữ ngắn',
    'textarea': 'Đoạn văn',
    'number': 'Số',
    'money': 'Số tiền',
    'select': 'Chọn một',
    'date': 'Ngày',
    'phone': 'Số điện thoại',
    'checkbox': 'Có / không',
    'photo': 'Ảnh',
    'signature': 'Chữ ký',
    'rating': 'Chấm sao (1–5)',
  };

  Map<String, dynamic> toJson() => {
        if (key.isNotEmpty) 'key': key,
        'label': label,
        'type': type,
        'required': required,
        if (type == 'select') 'options': options,
        if (unit != null && unit!.isNotEmpty) 'unit': unit,
        if (hint != null && hint!.isNotEmpty) 'hint': hint,
      };

  static List<TaskFormFieldV2> parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final d = jsonDecode(raw);
      if (d is! List) return [];
      return d.whereType<Map>().map((e) => TaskFormFieldV2.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  static String? encode(List<TaskFormFieldV2> fields) =>
      fields.isEmpty ? null : jsonEncode(fields.map((f) => f.toJson()).toList());

  static Map<String, String> parseValues(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return {};
      return d.map((k, v) => MapEntry('$k', v == null ? '' : '$v'));
    } catch (_) {
      return {};
    }
  }
}

/// Thiết lập Công việc của cửa hàng.
class TaskWorkspaceV2 {
  TaskWorkspaceV2.fromJson(Map<String, dynamic> j)
      : industryKey = j['industryKey'],
        industryName = j['industryName'],
        projectLabel = '${j['projectLabel'] ?? 'Dự án'}',
        taskLabel = '${j['taskLabel'] ?? 'Công việc'}',
        photoStorage = '${j['photoStorage'] ?? 'server'}',
        driveConfigured = j['driveConfigured'] == true,
        driveConnected = j['driveConnected'] == true,
        driveAccountEmail = j['driveAccountEmail'],
        driveConnectedAt = _dt(j['driveConnectedAt']),
        driveLastError = j['driveLastError'],
        checkInRadiusM = _i(j['checkInRadiusM'] ?? 300),
        onboarded = j['onboarded'] == true;

  TaskWorkspaceV2.empty()
      : industryKey = null,
        industryName = null,
        projectLabel = 'Dự án',
        taskLabel = 'Công việc',
        photoStorage = 'server',
        driveConfigured = false,
        driveConnected = false,
        driveAccountEmail = null,
        driveConnectedAt = null,
        driveLastError = null,
        checkInRadiusM = 300,
        onboarded = false;

  final String? industryKey;
  final String? industryName;
  final String projectLabel;
  final String taskLabel;
  final String photoStorage;
  final bool driveConfigured;
  final bool driveConnected;
  final String? driveAccountEmail;
  final DateTime? driveConnectedAt;
  final String? driveLastError;
  final int checkInRadiusM;
  final bool onboarded;
}

class TaskMediaV2 {
  TaskMediaV2.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        fileName = '${j['fileName'] ?? ''}',
        contentType = j['contentType'],
        category = '${j['category'] ?? 'report'}',
        checklistItemId = j['checklistItemId'],
        caption = j['caption'],
        storageKind = '${j['storageKind'] ?? 'server'}',
        url = '${j['url'] ?? ''}',
        uploadedByName = j['uploadedByName'],
        createdAt = _dt(j['createdAt']),
        warning = j['warning'];

  final String id;
  final String fileName;
  final String? contentType;
  final String category;
  final String? checklistItemId;
  final String? caption;
  final String storageKind;
  final String url;
  final String? uploadedByName;
  final DateTime? createdAt;
  final String? warning;

  bool get isImage => (contentType ?? '').startsWith('image/');

  String get categoryLabel => switch (category) {
        'before' => 'Trước',
        'after' => 'Sau',
        'signature' => 'Chữ ký',
        'checklist' => 'Checklist',
        'comment' => 'Trao đổi',
        'form' => 'Biểu mẫu',
        'file' => 'Tài liệu',
        _ => 'Báo cáo',
      };
}

class TaskTimeLogV2 {
  TaskTimeLogV2.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        employeeName = j['employeeName'],
        startAt = _dt(j['startAt']),
        endAt = _dt(j['endAt']),
        startDistanceM = j['startDistanceM'] == null ? null : _i(j['startDistanceM']),
        hours = _d(j['hours']),
        note = j['note'];

  final String id;
  final String? employeeName;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? startDistanceM;
  final double hours;
  final String? note;

  bool get open => endAt == null;
}

class TaskPersonStatV2 {
  TaskPersonStatV2.fromJson(Map<String, dynamic> j)
      : employeeId = '${j['employeeId']}',
        employeeName = '${j['employeeName'] ?? '—'}',
        total = _i(j['total']),
        completed = _i(j['completed']),
        overdue = _i(j['overdue']),
        rework = _i(j['rework']),
        onTimeRate = _d(j['onTimeRate']),
        avgQuality = j['avgQuality'] == null ? null : _d(j['avgQuality']),
        loggedHours = _d(j['loggedHours']),
        pieceRateTotal = _d(j['pieceRateTotal']);

  final String employeeId;
  final String employeeName;
  final int total;
  final int completed;
  final int overdue;
  final int rework;
  final double onTimeRate;
  final double? avgQuality;
  final double loggedHours;
  final double pieceRateTotal;
}

class TaskDashboardV2 {
  TaskDashboardV2.fromJson(Map<String, dynamic> j)
      : total = _i(j['total']),
        completed = _i(j['completed']),
        overdue = _i(j['overdue']),
        onTimeRate = _d(j['onTimeRate']),
        reworkRate = _d(j['reworkRate']),
        avgCycleHours = _d(j['avgCycleHours']),
        avgQuality = j['avgQuality'] == null ? null : _d(j['avgQuality']),
        avgCustomerRating = j['avgCustomerRating'] == null ? null : _d(j['avgCustomerRating']),
        checkInRate = _d(j['checkInRate']),
        pieceRateTotal = _d(j['pieceRateTotal']),
        people = _maps(j['people']).map(TaskPersonStatV2.fromJson).toList();

  final int total;
  final int completed;
  final int overdue;
  final double onTimeRate;
  final double reworkRate;
  final double avgCycleHours;
  final double? avgQuality;
  final double? avgCustomerRating;
  final double checkInRate;
  final double pieceRateTotal;
  final List<TaskPersonStatV2> people;
}
