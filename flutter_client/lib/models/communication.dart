/// Models for Internal Communication feature
library;

enum CommunicationType {
  news,
  announcement,
  event,
  policy,
  training,
  culture,
  recruitment,
  regulation,
  other,
}

enum CommunicationPriority {
  low,
  normal,
  high,
  urgent,
}

enum CommunicationStatus {
  draft,
  pendingApproval,
  published,
  archived,
  rejected,
}

enum ReactionType {
  like,
  love,
  celebrate,
  support,
  insightful,
}

class InternalCommunication {
  final String id;
  final String storeId;
  final String title;
  final String content;
  final String? summary;
  final String? thumbnailUrl;
  final List<String> attachedImages;
  final CommunicationType type;
  final String typeName;
  final CommunicationPriority priority;
  final String priorityName;
  final CommunicationStatus status;
  final String statusName;
  final String authorId;
  final String? authorName;
  final String? targetDepartmentId;
  final String? targetDepartmentName;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final bool isPinned;
  final bool isAiGenerated;
  final String? tags;
  final List<String> tagList;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool hasUserReacted;
  final ReactionType? userReactionType;

  InternalCommunication({
    required this.id,
    required this.storeId,
    required this.title,
    required this.content,
    this.summary,
    this.thumbnailUrl,
    this.attachedImages = const [],
    this.type = CommunicationType.news,
    this.typeName = 'News',
    this.priority = CommunicationPriority.normal,
    this.priorityName = 'Normal',
    this.status = CommunicationStatus.draft,
    this.statusName = 'Draft',
    required this.authorId,
    this.authorName,
    this.targetDepartmentId,
    this.targetDepartmentName,
    this.publishedAt,
    this.expiresAt,
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isPinned = false,
    this.isAiGenerated = false,
    this.tags,
    this.tagList = const [],
    required this.createdAt,
    this.updatedAt,
    this.hasUserReacted = false,
    this.userReactionType,
  });

  factory InternalCommunication.fromJson(Map<String, dynamic> json) {
    return InternalCommunication(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      summary: json['summary']?.toString(),
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      attachedImages: json['attachedImages'] != null
          ? List<String>.from(json['attachedImages'])
          : [],
      type: _parseType(json['type']),
      typeName: json['typeName']?.toString() ?? '',
      priority: _parsePriority(json['priority']),
      priorityName: json['priorityName']?.toString() ?? '',
      status: _parseStatus(json['status']),
      statusName: json['statusName']?.toString() ?? '',
      authorId: json['authorId']?.toString() ?? '',
      authorName: json['authorName']?.toString(),
      targetDepartmentId: json['targetDepartmentId']?.toString(),
      targetDepartmentName: json['targetDepartmentName']?.toString(),
      publishedAt: json['publishedAt'] != null
          ? DateTime.tryParse(json['publishedAt'].toString())
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
      viewCount: json['viewCount'] ?? 0,
      likeCount: json['likeCount'] ?? 0,
      commentCount: json['commentCount'] ?? 0,
      isPinned: json['isPinned'] ?? false,
      isAiGenerated: json['isAiGenerated'] ?? false,
      tags: json['tags']?.toString(),
      tagList: json['tagList'] != null
          ? List<String>.from(json['tagList'])
          : [],
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      hasUserReacted: json['hasUserReacted'] ?? false,
      userReactionType: json['userReactionType'] != null
          ? _parseReactionType(json['userReactionType'])
          : null,
    );
  }

  String get typeDisplay {
    switch (type) {
      case CommunicationType.news: return 'Tin tức';
      case CommunicationType.announcement: return 'Thông báo';
      case CommunicationType.event: return 'Sự kiện';
      case CommunicationType.policy: return 'Chính sách';
      case CommunicationType.training: return 'Đào tạo';
      case CommunicationType.culture: return 'Văn hóa';
      case CommunicationType.recruitment: return 'Tuyển dụng';
      case CommunicationType.regulation: return 'Nội quy';
      case CommunicationType.other: return 'Khác';
    }
  }

  String get priorityDisplay {
    switch (priority) {
      case CommunicationPriority.low: return 'Thấp';
      case CommunicationPriority.normal: return 'Bình thường';
      case CommunicationPriority.high: return 'Cao';
      case CommunicationPriority.urgent: return 'Khẩn cấp';
    }
  }

  String get statusDisplay {
    switch (status) {
      case CommunicationStatus.draft: return 'Nháp';
      case CommunicationStatus.pendingApproval: return 'Chờ duyệt';
      case CommunicationStatus.published: return 'Đã xuất bản';
      case CommunicationStatus.archived: return 'Lưu trữ';
      case CommunicationStatus.rejected: return 'Từ chối';
    }
  }

  static CommunicationType _parseType(dynamic value) {
    if (value is int) {
      switch (value) {
        case 0: return CommunicationType.news;
        case 1: return CommunicationType.announcement;
        case 2: return CommunicationType.event;
        case 3: return CommunicationType.policy;
        case 4: return CommunicationType.training;
        case 5: return CommunicationType.culture;
        case 6: return CommunicationType.recruitment;
        case 7: return CommunicationType.regulation;
        default: return CommunicationType.other;
      }
    }
    if (value is String) {
      return CommunicationType.values.firstWhere(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
        orElse: () => CommunicationType.news,
      );
    }
    return CommunicationType.news;
  }

  static CommunicationPriority _parsePriority(dynamic value) {
    if (value is int) {
      return CommunicationPriority.values[value.clamp(0, CommunicationPriority.values.length - 1)];
    }
    if (value is String) {
      return CommunicationPriority.values.firstWhere(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
        orElse: () => CommunicationPriority.normal,
      );
    }
    return CommunicationPriority.normal;
  }

  static CommunicationStatus _parseStatus(dynamic value) {
    if (value is int) {
      return CommunicationStatus.values[value.clamp(0, CommunicationStatus.values.length - 1)];
    }
    if (value is String) {
      return CommunicationStatus.values.firstWhere(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
        orElse: () => CommunicationStatus.draft,
      );
    }
    return CommunicationStatus.draft;
  }

  static ReactionType _parseReactionType(dynamic value) {
    if (value is int) {
      return ReactionType.values[value.clamp(0, ReactionType.values.length - 1)];
    }
    if (value is String) {
      return ReactionType.values.firstWhere(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
        orElse: () => ReactionType.like,
      );
    }
    return ReactionType.like;
  }
}

class CommunicationComment {
  final String id;
  final String communicationId;
  final String userId;
  final String? userName;
  final String content;
  final String? parentCommentId;
  final int likeCount;
  final DateTime createdAt;
  final List<CommunicationComment> replies;

  CommunicationComment({
    required this.id,
    required this.communicationId,
    required this.userId,
    this.userName,
    required this.content,
    this.parentCommentId,
    this.likeCount = 0,
    required this.createdAt,
    this.replies = const [],
  });

  factory CommunicationComment.fromJson(Map<String, dynamic> json) {
    return CommunicationComment(
      id: json['id']?.toString() ?? '',
      communicationId: json['communicationId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString(),
      content: json['content']?.toString() ?? '',
      parentCommentId: json['parentCommentId']?.toString(),
      likeCount: json['likeCount'] ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      replies: json['replies'] != null
          ? (json['replies'] as List).map((r) => CommunicationComment.fromJson(r)).toList()
          : [],
    );
  }
}

class AiGeneratedContent {
  final String title;
  final String content;
  final String? summary;
  final List<String> suggestedTags;
  final String prompt;

  AiGeneratedContent({
    required this.title,
    required this.content,
    this.summary,
    this.suggestedTags = const [],
    required this.prompt,
  });

  factory AiGeneratedContent.fromJson(Map<String, dynamic> json) {
    return AiGeneratedContent(
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      summary: json['summary']?.toString(),
      suggestedTags: json['suggestedTags'] != null
          ? List<String>.from(json['suggestedTags'])
          : [],
      prompt: json['prompt']?.toString() ?? '',
    );
  }
}
