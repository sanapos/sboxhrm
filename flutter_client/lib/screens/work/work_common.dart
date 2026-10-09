import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/task.dart';
import '../../models/task_v2.dart';
import '../../services/api_service.dart';
import '../../utils/image_source_picker.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Tông màu SBOX theo trạng thái việc.
SboxTone workStatusTone(WorkTaskStatus s) => switch (s) {
      WorkTaskStatus.completed => SboxTone.success,
      WorkTaskStatus.inProgress => SboxTone.brand,
      WorkTaskStatus.inReview => SboxTone.violet,
      WorkTaskStatus.assigned => SboxTone.warning,
      WorkTaskStatus.onHold => SboxTone.neutral,
      WorkTaskStatus.cancelled => SboxTone.neutral,
      WorkTaskStatus.todo => SboxTone.neutral,
    };

SboxTone workPriorityTone(TaskPriority p) => switch (p) {
      TaskPriority.urgent => SboxTone.danger,
      TaskPriority.high => SboxTone.warning,
      TaskPriority.medium => SboxTone.brand,
      TaskPriority.low => SboxTone.neutral,
    };

String workPriorityLabel(TaskPriority p) => switch (p) {
      TaskPriority.urgent => 'Khẩn cấp',
      TaskPriority.high => 'Cao',
      TaskPriority.medium => 'Trung bình',
      TaskPriority.low => 'Thấp',
    };

IconData workTypeIcon(TaskType t) => switch (t) {
      TaskType.routine => Icons.repeat_rounded,
      TaskType.maintenance => Icons.build_circle_outlined,
      TaskType.installation => Icons.handyman_outlined,
      TaskType.inspection => Icons.fact_check_outlined,
      TaskType.delivery => Icons.local_shipping_outlined,
      TaskType.customerService => Icons.support_agent_outlined,
      TaskType.survey => Icons.straighten_outlined,
      TaskType.procurement => Icons.inventory_2_outlined,
      TaskType.meeting => Icons.groups_outlined,
      TaskType.bug => Icons.bug_report_outlined,
      _ => Icons.task_alt_rounded,
    };

String workDate(DateTime? d, {bool withTime = false}) {
  if (d == null) return '—';
  final l = d.isUtc ? d.toLocal() : d;
  final date = '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  if (!withTime || (l.hour == 0 && l.minute == 0)) return date;
  return '$date ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// «Trễ 2 ngày» / «Hôm nay 17:00» / «Còn 3 ngày».
({String text, SboxTone tone}) workDueLabel(WorkTask t) {
  final due = t.dueDate;
  if (due == null) return (text: 'Không hạn', tone: SboxTone.neutral);
  if (t.isDone) {
    return (text: t.completedDate == null ? 'Đã xong' : 'Xong ${workDate(t.completedDate)}', tone: SboxTone.success);
  }
  final l = due.isUtc ? due.toLocal() : due;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dd = DateTime(l.year, l.month, l.day);
  final days = dd.difference(today).inDays;
  final hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  if (l.isBefore(now)) {
    final late = now.difference(l);
    return (text: late.inDays >= 1 ? 'Trễ ${late.inDays} ngày' : 'Trễ ${late.inHours} giờ', tone: SboxTone.danger);
  }
  if (days == 0) return (text: 'Hôm nay $hm', tone: SboxTone.warning);
  if (days == 1) return (text: 'Mai $hm', tone: SboxTone.warning);
  return (text: 'Còn $days ngày', tone: SboxTone.neutral);
}

/// Chữ viết tắt tên (avatar).
String workInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return '${parts[parts.length - 2].characters.first}${parts.last.characters.first}'.toUpperCase();
}

class WorkAvatarStack extends StatelessWidget {
  const WorkAvatarStack({super.key, required this.names, this.size = 24, this.max = 3});
  final List<String> names;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return Text(tr('Chưa giao'), style: SboxType.captionStyle(SboxColors.textMuted));
    }
    final shown = names.take(max).toList();
    final extra = names.length - shown.length;
    return Tooltip(
      message: names.join(', '),
      child: SizedBox(
        height: size,
        width: size + (shown.length - 1 + (extra > 0 ? 1 : 0)) * size * 0.7,
        child: Stack(children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(left: i * size * 0.7, child: _dot(workInitials(shown[i]), SboxChartColors.at(shown[i].hashCode.abs() % 5))),
          if (extra > 0) Positioned(left: shown.length * size * 0.7, child: _dot('+$extra', SboxColors.slate400)),
        ]),
      ),
    );
  }

  Widget _dot(String text, Color c) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
        child: Text(text, style: TextStyle(color: Colors.white, fontSize: size * 0.38, fontWeight: FontWeight.w700)),
      );
}

/// Thanh tiến độ mảnh.
class WorkProgressBar extends StatelessWidget {
  const WorkProgressBar({super.key, required this.value, this.color, this.height = 6, this.showLabel = false});
  final int value;
  final Color? color;
  final double height;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final bar = ClipRRect(
      borderRadius: SboxRadius.pillAll,
      child: LinearProgressIndicator(
        value: (value.clamp(0, 100)) / 100,
        minHeight: height,
        backgroundColor: SboxColors.slate100,
        valueColor: AlwaysStoppedAnimation(color ?? (value >= 100 ? SboxColors.success : SboxColors.brand500)),
      ),
    );
    if (!showLabel) return bar;
    return Row(children: [
      Expanded(child: bar),
      const SizedBox(width: SboxSpace.sm),
      SizedBox(width: 38, child: Text('$value%', textAlign: TextAlign.right, style: SboxType.captionStyle(SboxColors.textSecondary))),
    ]);
  }
}

/// Thẻ việc dùng cho bảng Kanban và danh sách «Việc của tôi».
class WorkTaskCard extends StatelessWidget {
  const WorkTaskCard({super.key, required this.task, this.onTap, this.showProject = false, this.dense = false, this.footer});
  final WorkTask task;
  final VoidCallback? onTap;
  final bool showProject;
  final bool dense;
  /// Nút thao tác nhanh dưới thẻ (nhân viên: Nhận việc / Bắt đầu / Cập nhật % / Báo xong).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final due = workDueLabel(task);
    final items = task.checklistItems;
    final doneItems = items.where((i) => i.done).length;
    final overdue = task.overdueNow;
    return Material(
      color: SboxColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: SboxRadius.mdAll,
        side: BorderSide(color: overdue ? SboxColors.danger.withValues(alpha: 0.6) : SboxColors.border, width: overdue ? 1.2 : 1),
      ),
      child: InkWell(
        borderRadius: SboxRadius.mdAll,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(dense ? 10 : 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (showProject && task.projectName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: hexColor(task.projectColor), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(task.projectName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.captionStyle()),
                  ),
                ]),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(workTypeIcon(task.taskType), size: 16, color: SboxColors.slate500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SboxType.bodyStrong().copyWith(
                        decoration: task.isDone ? TextDecoration.lineThrough : null,
                        color: task.isDone ? SboxColors.textMuted : SboxColors.text)),
              ),
              if (task.priority.index >= TaskPriority.high.index)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.flag_rounded, size: 16, color: workPriorityTone(task.priority).solid),
                ),
            ]),
            if (items.isNotEmpty || task.progress > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: WorkProgressBar(value: task.progress, height: 5)),
                const SizedBox(width: 8),
                Text(items.isNotEmpty ? '$doneItems/${items.length}' : '${task.progress}%', style: SboxType.captionStyle()),
              ]),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Icon(overdue ? Icons.schedule_rounded : Icons.event_outlined, size: 14, color: due.tone == SboxTone.neutral ? SboxColors.slate400 : due.tone.solid),
              const SizedBox(width: 4),
              Text(tr(due.text), style: SboxType.captionStyle(due.tone == SboxTone.neutral ? SboxColors.textMuted : due.tone.fg)),
              if (task.commentCount > 0) ...[
                const SizedBox(width: 10),
                const Icon(Icons.chat_bubble_outline_rounded, size: 13, color: SboxColors.slate400),
                const SizedBox(width: 3),
                Text('${task.commentCount}', style: SboxType.captionStyle()),
              ],
              if (task.status == WorkTaskStatus.assigned) ...[
                const SizedBox(width: 8),
                SboxStatusChip(label: 'Chờ nhận', tone: SboxTone.warning),
              ],
              const Spacer(),
              WorkAvatarStack(names: task.peopleNames, size: 22),
            ]),
            if (footer != null) ...[const SizedBox(height: 10), footer!],
          ]),
        ),
      ),
    );
  }
}

/// Chụp / chọn ảnh rồi tải lên thư mục tasks. Trả về URL hoặc null.
Future<String?> workPickAndUploadPhoto(BuildContext context, ApiService api) async {
  final picked = await pickSingleImageWithCamera(context, maxEdge: 1600, jpegQuality: 80);
  if (picked == null) return null;
  final r = await api.uploadFile(picked.bytes, picked.name, folder: 'tasks');
  if (r['isSuccess'] == true && r['data'] != null) {
    final d = r['data'];
    final url = d is String ? d : (d['fileUrl'] ?? d['url'] ?? d['filePath']);
    return url?.toString();
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Không tải được ảnh: ${r['message'] ?? ''}'))));
  }
  return null;
}

/// URL ảnh đầy đủ (đường dẫn tương đối từ máy chủ).
String workImageUrl(String url) {
  if (url.startsWith('http')) return url;
  final base = ApiService.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}

void workToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(tr(message)),
    backgroundColor: error ? SboxColors.danger : null,
    behavior: SnackBarBehavior.floating,
  ));
}
