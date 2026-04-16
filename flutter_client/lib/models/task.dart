// ==========================================
// lib/models/task.dart
// Task Management Models - Quản lý công việc
// ==========================================

// ============ ENUMS ============
enum WorkTaskStatus { todo, inProgress, inReview, completed, cancelled, onHold }

enum TaskPriority { low, medium, high, urgent }

enum TaskType { task, bug, feature, improvement, meeting, other }

// ============ HELPER FUNCTIONS ============
String getTaskStatusLabel(WorkTaskStatus status) {
  switch (status) {
    case WorkTaskStatus.todo:
      return 'Chờ làm';
    case WorkTaskStatus.inProgress:
      return 'Đang làm';
    case WorkTaskStatus.inReview:
      return 'Đang xem xét';
    case WorkTaskStatus.completed:
      return 'Hoàn thành';
    case WorkTaskStatus.cancelled:
      return 'Đã hủy';
    case WorkTaskStatus.onHold:
      return 'Tạm hoãn';
  }
}

String getTaskStatusLabelEn(WorkTaskStatus status) {
  switch (status) {
    case WorkTaskStatus.todo:
      return 'To Do';
    case WorkTaskStatus.inProgress:
      return 'In Progress';
    case WorkTaskStatus.inReview:
      return 'In Review';
    case WorkTaskStatus.completed:
      return 'Completed';
    case WorkTaskStatus.cancelled:
      return 'Cancelled';
    case WorkTaskStatus.onHold:
      return 'On Hold';
  }
}

String getPriorityLabel(TaskPriority priority) {
  switch (priority) {
    case TaskPriority.low:
      return 'Thấp';
    case TaskPriority.medium:
      return 'Trung bình';
    case TaskPriority.high:
      return 'Cao';
    case TaskPriority.urgent:
      return 'Khẩn cấp';
  }
}

String getTaskTypeLabel(TaskType type) {
  switch (type) {
    case TaskType.task:
      return 'Công việc';
    case TaskType.bug:
      return 'Lỗi';
    case TaskType.feature:
      return 'Tính năng';
    case TaskType.improvement:
      return 'Cải tiến';
    case TaskType.meeting:
      return 'Cuộc họp';
    case TaskType.other:
      return 'Khác';
  }
}

WorkTaskStatus parseTaskStatus(dynamic value) {
  if (value == null) return WorkTaskStatus.todo;
  if (value is int) {
    return WorkTaskStatus.values[value.clamp(0, WorkTaskStatus.values.length - 1)];
  }
  if (value is String) {
    final lower = value.toLowerCase();
    switch (lower) {
      case 'todo':
        return WorkTaskStatus.todo;
      case 'inprogress':
        return WorkTaskStatus.inProgress;
      case 'inreview':
        return WorkTaskStatus.inReview;
      case 'completed':
        return WorkTaskStatus.completed;
      case 'cancelled':
        return WorkTaskStatus.cancelled;
      case 'onhold':
        return WorkTaskStatus.onHold;
    }
  }
  return WorkTaskStatus.todo;
}

TaskPriority parsePriority(dynamic value) {
  if (value == null) return TaskPriority.medium;
  if (value is int) {
    return TaskPriority.values[value.clamp(0, TaskPriority.values.length - 1)];
  }
  if (value is String) {
    final lower = value.toLowerCase();
    switch (lower) {
      case 'low':
        return TaskPriority.low;
      case 'medium':
        return TaskPriority.medium;
      case 'high':
        return TaskPriority.high;
      case 'urgent':
        return TaskPriority.urgent;
    }
  }
  return TaskPriority.medium;
}

TaskType parseTaskType(dynamic value) {
  if (value == null) return TaskType.task;
  if (value is int) {
    return TaskType.values[value.clamp(0, TaskType.values.length - 1)];
  }
  if (value is String) {
    final lower = value.toLowerCase();
    switch (lower) {
      case 'task':
        return TaskType.task;
      case 'bug':
        return TaskType.bug;
      case 'feature':
        return TaskType.feature;
      case 'improvement':
        return TaskType.improvement;
      case 'meeting':
        return TaskType.meeting;
      case 'other':
        return TaskType.other;
    }
  }
  return TaskType.task;
}

// ============ MODELS ============

class WorkTask {
  final String id;
  final String taskCode;
  final String title;
  final String? description;
  final TaskType taskType;
  final TaskPriority priority;
  final WorkTaskStatus status;
  final int progress;
  final String storeId;
  final String? storeName;
  final String assignedById;
  final String? assignedByName;
  final String? assigneeId;
  final String? assigneeName;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? actualStartDate;
  final DateTime? completedDate;
  final double? estimatedHours;
  final double? actualHours;
  final String? parentTaskId;
  final String? parentTaskTitle;
  final String? tags;
  final String? checklist;
  final String? completionNotes;
  final bool isOverdue;
  final int subTaskCount;
  final int completedSubTaskCount;
  final int commentCount;
  final int attachmentCount;
  final List<TaskAssignee>? assignees;
  final List<TaskComment>? comments;
  final List<TaskAttachment>? attachments;
  final List<WorkTask>? subTasks;
  final DateTime createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final bool isActive;

  WorkTask({
    required this.id,
    required this.taskCode,
    required this.title,
    this.description,
    required this.taskType,
    required this.priority,
    required this.status,
    required this.progress,
    required this.storeId,
    this.storeName,
    required this.assignedById,
    this.assignedByName,
    this.assigneeId,
    this.assigneeName,
    this.startDate,
    this.dueDate,
    this.actualStartDate,
    this.completedDate,
    this.estimatedHours,
    this.actualHours,
    this.parentTaskId,
    this.parentTaskTitle,
    this.tags,
    this.checklist,
    this.completionNotes,
    this.isOverdue = false,
    this.subTaskCount = 0,
    this.completedSubTaskCount = 0,
    this.commentCount = 0,
    this.attachmentCount = 0,
    this.assignees,
    this.comments,
    this.attachments,
    this.subTasks,
    required this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.isActive = true,
  });

  factory WorkTask.fromJson(Map<String, dynamic> json) {
    return WorkTask(
      id: json['id'] ?? '',
      taskCode: json['taskCode'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      taskType: parseTaskType(json['taskType']),
      priority: parsePriority(json['priority']),
      status: parseTaskStatus(json['status']),
      progress: json['progress'] ?? 0,
      storeId: json['storeId'] ?? '',
      storeName: json['storeName'],
      assignedById: json['assignedById'] ?? '',
      assignedByName: json['assignedByName'],
      assigneeId: json['assigneeId'],
      assigneeName: json['assigneeName'],
      startDate: json['startDate'] != null ? DateTime.tryParse(json['startDate']) : null,
      dueDate: json['dueDate'] != null ? DateTime.tryParse(json['dueDate']) : null,
      actualStartDate: json['actualStartDate'] != null ? DateTime.tryParse(json['actualStartDate']) : null,
      completedDate: json['completedDate'] != null ? DateTime.tryParse(json['completedDate']) : null,
      estimatedHours: json['estimatedHours']?.toDouble(),
      actualHours: json['actualHours']?.toDouble(),
      parentTaskId: json['parentTaskId'],
      parentTaskTitle: json['parentTaskTitle'],
      tags: json['tags'],
      checklist: json['checklist'],
      completionNotes: json['completionNotes'],
      isOverdue: json['isOverdue'] ?? (
        json['dueDate'] != null &&
        DateTime.tryParse(json['dueDate'])?.isBefore(DateTime.now()) == true &&
        parseTaskStatus(json['status']) != WorkTaskStatus.completed &&
        parseTaskStatus(json['status']) != WorkTaskStatus.cancelled
      ),
      subTaskCount: json['subTaskCount'] ?? 0,
      completedSubTaskCount: json['completedSubTaskCount'] ?? 0,
      commentCount: json['commentCount'] ?? 0,
      attachmentCount: json['attachmentCount'] ?? 0,
      assignees: json['assignees'] != null
          ? (json['assignees'] as List).map((e) => TaskAssignee.fromJson(e)).toList()
          : null,
      comments: json['comments'] != null
          ? (json['comments'] as List).map((e) => TaskComment.fromJson(e)).toList()
          : null,
      attachments: json['attachments'] != null
          ? (json['attachments'] as List).map((e) => TaskAttachment.fromJson(e)).toList()
          : null,
      subTasks: json['subTasks'] != null
          ? (json['subTasks'] as List).map((e) => WorkTask.fromJson(e)).toList()
          : null,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      createdBy: json['createdBy'],
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt']) : null,
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'taskCode': taskCode,
      'title': title,
      'description': description,
      'taskType': taskType.index,
      'priority': priority.index,
      'status': status.index,
      'progress': progress,
      'storeId': storeId,
      'assignedById': assignedById,
      'assigneeId': assigneeId,
      'startDate': startDate?.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'estimatedHours': estimatedHours,
      'actualHours': actualHours,
      'parentTaskId': parentTaskId,
      'tags': tags,
      'checklist': checklist,
      'completionNotes': completionNotes,
    };
  }

  // Helper getters
  List<String> get tagList {
    if (tags == null || tags!.isEmpty) return [];
    try {
      // Assuming tags is JSON array string
      return tags!.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } catch (e) {
      return [];
    }
  }

  double get subTaskProgress {
    if (subTaskCount == 0) return 0;
    return (completedSubTaskCount / subTaskCount * 100).roundToDouble();
  }

  bool get hasAssignees => assignees != null && assignees!.isNotEmpty;
  bool get hasSubTasks => subTaskCount > 0;
  bool get hasComments => commentCount > 0;
  bool get hasAttachments => attachmentCount > 0;
}

class TaskComment {
  final String id;
  final String taskId;
  final String userId;
  final String? userName;
  final String? userAvatar;
  final String content;
  final String? parentCommentId;
  final DateTime createdAt;
  final List<TaskComment>? replies;

  TaskComment({
    required this.id,
    required this.taskId,
    required this.userId,
    this.userName,
    this.userAvatar,
    required this.content,
    this.parentCommentId,
    required this.createdAt,
    this.replies,
  });

  factory TaskComment.fromJson(Map<String, dynamic> json) {
    return TaskComment(
      id: json['id'] ?? '',
      taskId: json['taskId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'],
      userAvatar: json['userAvatar'],
      content: json['content'] ?? '',
      parentCommentId: json['parentCommentId'],
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      replies: json['replies'] != null
          ? (json['replies'] as List).map((e) => TaskComment.fromJson(e)).toList()
          : null,
    );
  }
}

class TaskAttachment {
  final String id;
  final String taskId;
  final String uploadedById;
  final String? uploadedByName;
  final String fileName;
  final String filePath;
  final String? contentType;
  final int fileSize;
  final DateTime createdAt;

  TaskAttachment({
    required this.id,
    required this.taskId,
    required this.uploadedById,
    this.uploadedByName,
    required this.fileName,
    required this.filePath,
    this.contentType,
    required this.fileSize,
    required this.createdAt,
  });

  factory TaskAttachment.fromJson(Map<String, dynamic> json) {
    return TaskAttachment(
      id: json['id'] ?? '',
      taskId: json['taskId'] ?? '',
      uploadedById: json['uploadedById'] ?? '',
      uploadedByName: json['uploadedByName'],
      fileName: json['fileName'] ?? '',
      filePath: json['filePath'] ?? '',
      contentType: json['contentType'],
      fileSize: json['fileSize'] ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class TaskAssignee {
  final String id;
  final String taskId;
  final String employeeId;
  final String? employeeName;
  final String? employeeCode;
  final String? employeeAvatar;
  final String? role;
  final DateTime assignedAt;

  TaskAssignee({
    required this.id,
    required this.taskId,
    required this.employeeId,
    this.employeeName,
    this.employeeCode,
    this.employeeAvatar,
    this.role,
    required this.assignedAt,
  });

  factory TaskAssignee.fromJson(Map<String, dynamic> json) {
    return TaskAssignee(
      id: json['id'] ?? '',
      taskId: json['taskId'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'],
      employeeCode: json['employeeCode'],
      employeeAvatar: json['employeeAvatar'],
      role: json['role'],
      assignedAt: DateTime.tryParse(json['assignedAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class TaskHistory {
  final String id;
  final String taskId;
  final String userId;
  final String? userName;
  final String changeType;
  final String? oldValue;
  final String? newValue;
  final String? description;
  final DateTime createdAt;

  TaskHistory({
    required this.id,
    required this.taskId,
    required this.userId,
    this.userName,
    required this.changeType,
    this.oldValue,
    this.newValue,
    this.description,
    required this.createdAt,
  });

  factory TaskHistory.fromJson(Map<String, dynamic> json) {
    return TaskHistory(
      id: json['id'] ?? '',
      taskId: json['taskId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'],
      changeType: json['changeType'] ?? '',
      oldValue: json['oldValue'],
      newValue: json['newValue'],
      description: json['description'],
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class TaskStatistics {
  final int totalTasks;
  final int todoCount;
  final int inProgressCount;
  final int inReviewCount;
  final int completedCount;
  final int cancelledCount;
  final int onHoldCount;
  final int overdueCount;
  final double completionRate;
  final double averageProgress;
  final List<TasksByPriority>? byPriority;
  final List<TasksByType>? byType;
  final List<TasksByAssignee>? byAssignee;

  TaskStatistics({
    required this.totalTasks,
    required this.todoCount,
    required this.inProgressCount,
    required this.inReviewCount,
    required this.completedCount,
    required this.cancelledCount,
    required this.onHoldCount,
    required this.overdueCount,
    required this.completionRate,
    required this.averageProgress,
    this.byPriority,
    this.byType,
    this.byAssignee,
  });

  factory TaskStatistics.fromJson(Map<String, dynamic> json) {
    return TaskStatistics(
      totalTasks: json['totalTasks'] ?? 0,
      todoCount: json['todoCount'] ?? 0,
      inProgressCount: json['inProgressCount'] ?? 0,
      inReviewCount: json['inReviewCount'] ?? 0,
      completedCount: json['completedCount'] ?? 0,
      cancelledCount: json['cancelledCount'] ?? 0,
      onHoldCount: json['onHoldCount'] ?? 0,
      overdueCount: json['overdueCount'] ?? 0,
      completionRate: (json['completionRate'] ?? 0).toDouble(),
      averageProgress: (json['averageProgress'] ?? 0).toDouble(),
      byPriority: json['byPriority'] != null
          ? (json['byPriority'] as List).map((e) => TasksByPriority.fromJson(e)).toList()
          : null,
      byType: json['byType'] != null
          ? (json['byType'] as List).map((e) => TasksByType.fromJson(e)).toList()
          : null,
      byAssignee: json['byAssignee'] != null
          ? (json['byAssignee'] as List).map((e) => TasksByAssignee.fromJson(e)).toList()
          : null,
    );
  }
}

class TasksByPriority {
  final TaskPriority priority;
  final int count;

  TasksByPriority({required this.priority, required this.count});

  factory TasksByPriority.fromJson(Map<String, dynamic> json) {
    return TasksByPriority(
      priority: parsePriority(json['priority']),
      count: json['count'] ?? 0,
    );
  }
}

class TasksByType {
  final TaskType taskType;
  final int count;

  TasksByType({required this.taskType, required this.count});

  factory TasksByType.fromJson(Map<String, dynamic> json) {
    return TasksByType(
      taskType: parseTaskType(json['taskType']),
      count: json['count'] ?? 0,
    );
  }
}

class TasksByAssignee {
  final String employeeId;
  final String? employeeName;
  final int totalTasks;
  final int completedTasks;
  final int inProgressTasks;
  final int overdueTasks;

  TasksByAssignee({
    required this.employeeId,
    this.employeeName,
    required this.totalTasks,
    required this.completedTasks,
    required this.inProgressTasks,
    required this.overdueTasks,
  });

  factory TasksByAssignee.fromJson(Map<String, dynamic> json) {
    return TasksByAssignee(
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'],
      totalTasks: json['totalTasks'] ?? 0,
      completedTasks: json['completedTasks'] ?? 0,
      inProgressTasks: json['inProgressTasks'] ?? 0,
      overdueTasks: json['overdueTasks'] ?? 0,
    );
  }
}

class KanbanBoard {
  final List<KanbanColumn> columns;

  KanbanBoard({required this.columns});

  factory KanbanBoard.fromJson(Map<String, dynamic> json) {
    return KanbanBoard(
      columns: json['columns'] != null
          ? (json['columns'] as List).map((e) => KanbanColumn.fromJson(e)).toList()
          : [],
    );
  }
}

class KanbanColumn {
  final WorkTaskStatus status;
  final int taskCount;
  final List<WorkTask> tasks;

  KanbanColumn({required this.status, required this.taskCount, required this.tasks});

  factory KanbanColumn.fromJson(Map<String, dynamic> json) {
    return KanbanColumn(
      status: parseTaskStatus(json['status']),
      taskCount: json['taskCount'] ?? 0,
      tasks: json['tasks'] != null
          ? (json['tasks'] as List).map((e) => WorkTask.fromJson(e)).toList()
          : [],
    );
  }
}
