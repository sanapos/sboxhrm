// Truyền thông v2 — mạng xã hội nội bộ.
import 'package:flutter/material.dart';

int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// Enum từ API: máy chủ bật JsonStringEnumConverter → trả TÊN («Published», «Normal»), bản cũ trả SỐ.
/// Trước đây chỉ đọc số → mọi bài đã đăng bị hiểu là «Nháp» (0), mức độ 0, đăng / lưu xong app văng lỗi.
int _enum(dynamic v, Map<String, int> byName, {int fallback = 0}) {
  if (v is num) return v.toInt();
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return fallback;
  final n = int.tryParse(s);
  if (n != null) return n;
  final key = s.replaceAll('_', '').toLowerCase();
  for (final e in byName.entries) {
    if (e.key.toLowerCase() == key) return e.value;
  }
  return fallback;
}

const _statusNames = {'Draft': 0, 'PendingApproval': 1, 'Published': 2, 'Archived': 3, 'Rejected': 4, 'Scheduled': 5};
const _priorityNames = {'Low': 0, 'Normal': 1, 'High': 2, 'Urgent': 3};
const _typeNames = {
  'News': 0, 'Announcement': 1, 'Event': 2, 'Policy': 3, 'Training': 4, 'Culture': 5, 'Recruitment': 6, 'Regulation': 7, 'Other': 99,
};

/// Trạng thái bài từ dữ liệu API (tên hoặc số).
CommStatus commStatusOf(dynamic v) =>
    CommStatus.values[_enum(v, _statusNames).clamp(0, CommStatus.values.length - 1)];
DateTime? _dt(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse('$v');
  if (d == null) return null;
  // Máy chủ lưu UTC không kèm «Z».
  return d.isUtc ? d.toLocal() : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second).toLocal();
}

List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
List<String> _strs(dynamic v) => v is List ? v.map((e) => '$e').toList() : const [];

Color commColor(String? hex, [Color fallback = const Color(0xFF158DC0)]) {
  final h = (hex ?? '').replaceFirst('#', '');
  final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
  return v == null ? fallback : Color(0xFF000000 | v);
}

IconData commChannelIcon(String? icon) => switch (icon) {
      'home' => Icons.dynamic_feed_outlined,
      'campaign' => Icons.campaign_outlined,
      'gavel' => Icons.gavel_outlined,
      'badge' => Icons.badge_outlined,
      'event' => Icons.event_outlined,
      'school' => Icons.school_outlined,
      'celebration' => Icons.celebration_outlined,
      'folder' => Icons.folder_outlined,
      'store' => Icons.storefront_outlined,
      'groups' => Icons.groups_outlined,
      _ => Icons.forum_outlined,
    };

class CommChannel {
  CommChannel.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        key = j['key'],
        name = '${j['name'] ?? ''}',
        description = j['description'],
        icon = j['icon'],
        color = j['color'],
        postPolicy = _i(j['postPolicy']),
        requireApproval = j['requireApproval'] == true,
        branchId = j['branchId']?.toString(),
        departmentId = j['departmentId']?.toString(),
        sortOrder = _i(j['sortOrder']),
        isSystem = j['isSystem'] == true,
        canPost = j['canPost'] == true,
        unread = _i(j['unread']);

  final String id;
  final String? key;
  final String name;
  final String? description;
  final String? icon;
  final String? color;
  final int postPolicy;
  final bool requireApproval;
  final String? branchId;
  final String? departmentId;
  final int sortOrder;
  final bool isSystem;
  final bool canPost;
  final int unread;

  Color get colorValue => commColor(color);
  IconData get iconData => commChannelIcon(icon);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
        'postPolicy': postPolicy,
        'requireApproval': requireApproval,
        'branchId': branchId,
        'departmentId': departmentId,
        'sortOrder': sortOrder,
      };
}

class CommAttachment {
  CommAttachment({required this.url, required this.name, this.mime, this.size = 0, this.kind = 'other'});
  CommAttachment.fromJson(Map<String, dynamic> j)
      : url = '${j['url'] ?? ''}',
        name = '${j['name'] ?? ''}',
        mime = j['mime'],
        size = _i(j['size']),
        kind = '${j['kind'] ?? 'other'}';

  final String url;
  final String name;
  final String? mime;
  final int size;
  final String kind;

  Map<String, dynamic> toJson() => {'url': url, 'name': name, 'mime': mime, 'size': size, 'kind': kind};

  bool get isImage => kind == 'image';

  IconData get icon => switch (kind) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'word' => Icons.description_outlined,
        'excel' => Icons.table_chart_outlined,
        'powerpoint' => Icons.slideshow_outlined,
        'image' => Icons.image_outlined,
        'text' => Icons.article_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  Color get color => switch (kind) {
        'pdf' => const Color(0xFFDC2626),
        'word' => const Color(0xFF2563EB),
        'excel' => const Color(0xFF16A34A),
        'powerpoint' => const Color(0xFFEA580C),
        _ => const Color(0xFF64748B),
      };

  String get sizeLabel {
    if (size <= 0) return '';
    if (size >= 1024 * 1024) return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(size / 1024).round()} KB';
  }
}

class CommAudience {
  CommAudience({this.all = true, List<String>? branchIds, List<String>? departmentIds, List<String>? positions, List<String>? employeeIds})
      : branchIds = branchIds ?? [],
        departmentIds = departmentIds ?? [],
        positions = positions ?? [],
        employeeIds = employeeIds ?? [];

  factory CommAudience.fromJson(Map<String, dynamic>? j) => j == null
      ? CommAudience()
      : CommAudience(
          all: j['all'] != false,
          branchIds: _strs(j['branchIds']),
          departmentIds: _strs(j['departmentIds']),
          positions: _strs(j['positions']),
          employeeIds: _strs(j['employeeIds']),
        );

  bool all;
  List<String> branchIds;
  List<String> departmentIds;
  List<String> positions;
  List<String> employeeIds;

  bool get isEveryone => all || (branchIds.isEmpty && departmentIds.isEmpty && positions.isEmpty && employeeIds.isEmpty);

  Map<String, dynamic> toJson() => {
        'all': isEveryone,
        'branchIds': branchIds,
        'departmentIds': departmentIds,
        'positions': positions,
        'employeeIds': employeeIds,
      };
}

class CommPollOption {
  CommPollOption({required this.id, required this.text, this.votes = 0});
  String id;
  String text;
  int votes;
}

class CommPoll {
  CommPoll({required this.question, required this.options, this.multiple = false, this.anonymous = false, this.closesAt, this.closed = false, this.totalVoters = 0, List<String>? myVotes})
      : myVotes = myVotes ?? [];

  factory CommPoll.fromJson(Map<String, dynamic> j) => CommPoll(
        question: '${j['question'] ?? ''}',
        options: _maps(j['options']).map((o) => CommPollOption(id: '${o['id']}', text: '${o['text'] ?? ''}', votes: _i(o['votes']))).toList(),
        multiple: j['multiple'] == true,
        anonymous: j['anonymous'] == true,
        closesAt: _dt(j['closesAt']),
        closed: j['closed'] == true,
        totalVoters: _i(j['totalVoters']),
        myVotes: _strs(j['myVotes']),
      );

  String question;
  List<CommPollOption> options;
  bool multiple;
  bool anonymous;
  DateTime? closesAt;
  bool closed;
  int totalVoters;
  List<String> myVotes;

  int get totalVotes => options.fold(0, (a, o) => a + o.votes);

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': [for (final o in options) {'id': o.id, 'text': o.text}],
        'multiple': multiple,
        'anonymous': anonymous,
        'closesAt': closesAt?.toUtc().toIso8601String(),
      };
}

/// Loại cảm xúc (khớp enum ReactionType phía máy chủ).
const commReactions = <(int, String, String)>[
  (0, '👍', 'Thích'),
  (1, '❤️', 'Yêu thích'),
  (2, '🎉', 'Chúc mừng'),
  (3, '🤝', 'Ủng hộ'),
  (4, '💡', 'Hữu ích'),
];

enum CommStatus { draft, pendingApproval, published, archived, rejected, scheduled }

class CommPost {
  CommPost.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        channelId = j['channelId']?.toString(),
        channelName = j['channelName'],
        channelColor = j['channelColor'],
        type = _enum(j['type'], _typeNames),
        title = '${j['title'] ?? ''}',
        summary = j['summary'],
        contentHtml = '${j['contentHtml'] ?? ''}',
        contentFormat = j['contentFormat'],
        contentDelta = j['contentDelta'],
        thumbnailUrl = j['thumbnailUrl'],
        images = _strs(j['images']),
        attachments = _maps(j['attachments']).map(CommAttachment.fromJson).toList(),
        priority = _enum(j['priority'], _priorityNames, fallback: 1),
        status = commStatusOf(j['status']),
        authorId = '${j['authorId']}',
        authorName = j['authorName'],
        authorAvatar = j['authorAvatar'],
        publishedAt = _dt(j['publishedAt']),
        scheduledAt = _dt(j['scheduledAt']),
        createdAt = _dt(j['createdAt']) ?? DateTime.now(),
        isPinned = j['isPinned'] == true,
        requireAck = j['requireAck'] == true,
        ackDeadline = _dt(j['ackDeadline']),
        version = _i(j['version']),
        audience = j['audience'] is Map ? CommAudience.fromJson(Map<String, dynamic>.from(j['audience'] as Map)) : null,
        poll = j['poll'] is Map ? CommPoll.fromJson(Map<String, dynamic>.from(j['poll'] as Map)) : null,
        eventAt = _dt(j['eventAt']),
        eventLocation = j['eventLocation'],
        allowComments = j['allowComments'] != false,
        tags = j['tags'],
        isAiGenerated = j['isAiGenerated'] == true,
        views = _i(j['views']),
        reactionTotal = _i(j['reactionTotal']),
        reactions = j['reactions'] is Map ? (j['reactions'] as Map).map((k, v) => MapEntry(_i(k), _i(v))) : <int, int>{},
        comments = _i(j['comments']),
        ackCount = _i(j['ackCount']),
        audienceCount = _i(j['audienceCount']),
        myRead = j['myRead'] == true,
        myAcked = j['myAcked'] == true,
        myReaction = j['myReaction'] == null ? null : _i(j['myReaction']),
        mySaved = j['mySaved'] == true,
        canEdit = j['canEdit'] == true,
        canModerate = j['canModerate'] == true,
        latestComments = _maps(j['latestComments']).map(CommComment.fromJson).toList();

  final String id;
  final String? channelId;
  final String? channelName;
  final String? channelColor;
  final int type;
  final String title;
  final String? summary;
  final String contentHtml;
  final String? contentFormat;
  final String? contentDelta;
  final String? thumbnailUrl;
  final List<String> images;
  final List<CommAttachment> attachments;
  final int priority;
  CommStatus status;
  final String authorId;
  final String? authorName;
  final String? authorAvatar;
  final DateTime? publishedAt;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  bool isPinned;
  final bool requireAck;
  final DateTime? ackDeadline;
  final int version;
  final CommAudience? audience;
  final CommPoll? poll;
  final DateTime? eventAt;
  final String? eventLocation;
  final bool allowComments;
  final String? tags;
  final bool isAiGenerated;
  final int views;
  int reactionTotal;
  final Map<int, int> reactions;
  int comments;
  int ackCount;
  final int audienceCount;
  bool myRead;
  bool myAcked;
  int? myReaction;
  bool mySaved;
  final bool canEdit;
  final bool canModerate;
  /// Bình luận mới nhất (cũ → mới) hiện ngay dưới bài.
  final List<CommComment> latestComments;

  DateTime get when => publishedAt ?? createdAt;
  bool get urgent => priority >= 2;
  List<CommAttachment> get files => attachments.where((a) => !a.isImage).toList();
  List<String> get allImages => [...images, ...attachments.where((a) => a.isImage).map((a) => a.url)];
  List<String> get tagList => (tags ?? '').split(RegExp(r'[,;#]')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
}

class CommComment {
  CommComment.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        userId = '${j['userId']}',
        userName = j['userName'],
        avatar = j['avatar'],
        content = '${j['content'] ?? ''}',
        parentCommentId = j['parentCommentId']?.toString(),
        createdAt = _dt(j['createdAt']) ?? DateTime.now(),
        canDelete = j['canDelete'] == true,
        canEdit = j['canEdit'] == true,
        edited = j['edited'] == true,
        likeCount = _i(j['likeCount']),
        myLiked = j['myLiked'] == true,
        replyCount = _i(j['replyCount']);

  final String id;
  final String userId;
  final String? userName;
  final String? avatar;
  String content;
  final String? parentCommentId;
  final DateTime createdAt;
  final bool canDelete;
  final bool canEdit;
  bool edited;
  int likeCount;
  bool myLiked;
  int replyCount;
}

/// Người đã bày tỏ cảm xúc.
class CommReactor {
  CommReactor.fromJson(Map<String, dynamic> j)
      : userId = '${j['userId']}',
        name = '${j['name'] ?? ''}',
        avatar = j['avatar'],
        type = _i(j['type']);
  final String userId;
  final String name;
  final String? avatar;
  final int type;
}

/// Liên kết mở thẳng một bài trong ứng dụng web.
String commPostLink(String postId, {String? origin}) {
  final o = (origin ?? '').isNotEmpty && origin != 'null' ? origin! : const String.fromEnvironment('SITE_URL', defaultValue: 'https://sboxhrm.com');
  return '${o.replaceAll(RegExp(r'/+$'), '')}/?comm=$postId';
}

class CommBrief {
  CommBrief.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        title = '${j['title'] ?? ''}',
        at = _dt(j['at']),
        location = j['location'],
        deadline = _dt(j['deadline']);
  final String id;
  final String title;
  final DateTime? at;
  final String? location;
  final DateTime? deadline;
}

class CommSidebar {
  CommSidebar.fromJson(Map<String, dynamic> j)
      : requiredPending = _i(j['requiredPending']),
        required = _maps(j['required']).map(CommBrief.fromJson).toList(),
        openPolls = _i(j['openPolls']),
        events = _maps(j['events']).map(CommBrief.fromJson).toList(),
        birthdays = _maps(j['birthdays'])
            .map((b) => (name: '${b['name'] ?? ''}', date: DateTime.tryParse('${b['date']}') ?? DateTime.now(), photo: b['photoUrl'] as String?))
            .toList(),
        pendingApproval = _i(j['pendingApproval']);

  final int requiredPending;
  final List<CommBrief> required;
  final int openPolls;
  final List<CommBrief> events;
  final List<({String name, DateTime date, String? photo})> birthdays;
  final int pendingApproval;
}

class CommReader {
  CommReader.fromJson(Map<String, dynamic> j)
      : employeeId = '${j['employeeId']}',
        name = '${j['name'] ?? ''}',
        readAt = _dt(j['readAt']),
        ackAt = _dt(j['ackAt']),
        ackCurrent = j['ackCurrent'] == true;
  final String employeeId;
  final String name;
  final DateTime? readAt;
  final DateTime? ackAt;
  final bool ackCurrent;
}

class CommAiBlock {
  CommAiBlock(this.type, this.text);
  final String type;
  final String text;
}

class CommAiDraft {
  CommAiDraft.fromJson(Map<String, dynamic> j)
      : title = '${j['title'] ?? ''}',
        summary = '${j['summary'] ?? ''}',
        blocks = _maps(j['blocks']).map((b) => CommAiBlock('${b['type'] ?? 'p'}', '${b['text'] ?? ''}')).toList(),
        keyPoints = _strs(j['keyPoints']),
        faq = _maps(j['faq']).map((f) => (q: '${f['q'] ?? ''}', a: '${f['a'] ?? ''}')).toList(),
        tags = _strs(j['tags']),
        suggestedChannel = j['suggestedChannel'],
        suggestRequireAck = j['suggestRequireAck'] == true;

  final String title;
  final String summary;
  final List<CommAiBlock> blocks;
  final List<String> keyPoints;
  final List<({String q, String a})> faq;
  final List<String> tags;
  final String? suggestedChannel;
  final bool suggestRequireAck;
}

class CommPostStat {
  CommPostStat.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        title = '${j['title'] ?? ''}',
        channelName = j['channelName'],
        publishedAt = _dt(j['publishedAt']),
        audience = _i(j['audience']),
        read = _i(j['read']),
        acked = _i(j['acked']),
        requireAck = j['requireAck'] == true,
        reactions = _i(j['reactions']),
        comments = _i(j['comments']);
  final String id;
  final String title;
  final String? channelName;
  final DateTime? publishedAt;
  final int audience;
  final int read;
  final int acked;
  final bool requireAck;
  final int reactions;
  final int comments;

  double get readRate => audience == 0 ? 0 : read * 100 / audience;
}

String commTimeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.isNegative) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  if (diff.inMinutes < 1) return 'Vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút';
  if (diff.inHours < 24) return '${diff.inHours} giờ';
  if (diff.inDays < 7) return '${diff.inDays} ngày';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
