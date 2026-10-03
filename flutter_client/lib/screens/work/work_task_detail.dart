import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/task.dart';
import '../../models/task_v2.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'work_common.dart';

/// Ai đang xem: để quyết định nút hành động.
class WorkViewer {
  const WorkViewer({required this.isManager, this.employeeId});
  final bool isManager;
  final String? employeeId;

  bool isParticipant(WorkTask t) =>
      employeeId != null &&
      (t.assigneeId == employeeId || (t.assignees ?? const []).any((a) => a.employeeId == employeeId));
}

/// Mở chi tiết việc: máy tính → khung bên phải; điện thoại → trang riêng.
/// Trả về true nếu việc đã thay đổi (để màn gọi tải lại).
Future<bool> showWorkTaskDetail(
  BuildContext context, {
  required String taskId,
  required WorkViewer viewer,
  Future<void> Function(WorkTask task)? onEdit,
}) async {
  final page = WorkTaskDetailPage(taskId: taskId, viewer: viewer, onEdit: onEdit);
  if (MediaQuery.sizeOf(context).width < SboxBreakpoints.tablet) {
    final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page));
    return r == true;
  }
  final r = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 12,
        child: SizedBox(width: 560, height: double.infinity, child: page),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
      child: FadeTransition(opacity: anim, child: child),
    ),
  );
  return r == true;
}

class WorkTaskDetailPage extends StatefulWidget {
  const WorkTaskDetailPage({super.key, required this.taskId, required this.viewer, this.onEdit});
  final String taskId;
  final WorkViewer viewer;
  final Future<void> Function(WorkTask task)? onEdit;

  @override
  State<WorkTaskDetailPage> createState() => _WorkTaskDetailPageState();
}

class _WorkTaskDetailPageState extends State<WorkTaskDetailPage> {
  final _api = ApiService();
  final _commentCtrl = TextEditingController();
  WorkTask? _task;
  List<TaskStageV2> _stages = const [];
  List<TaskHistory> _history = const [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _busyItem;
  final List<String> _commentPhotos = [];
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _api.getTaskById(widget.taskId);
    if (!mounted) return;
    if (r['isSuccess'] != true || r['data'] is! Map) {
      setState(() => _loading = false);
      return;
    }
    final t = WorkTask.fromJson(Map<String, dynamic>.from(r['data'] as Map));
    var stages = <TaskStageV2>[];
    if (t.projectId != null) {
      final p = await _api.getTaskProject(t.projectId!);
      if (p['isSuccess'] == true && p['data'] is Map) {
        stages = TaskProjectV2.fromJson(Map<String, dynamic>.from(p['data'] as Map)).stages;
      }
    }
    final h = await _api.getTaskHistory(t.id);
    if (!mounted) return;
    setState(() {
      _task = t;
      _stages = stages;
      _history = h['isSuccess'] == true && h['data'] is List
          ? (h['data'] as List).whereType<Map>().map((e) => TaskHistory.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [];
      _loading = false;
    });
  }

  void _applyResult(Map<String, dynamic> r, {String? ok}) {
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _changed = true;
      if (r['data'] is Map) {
        setState(() => _task = WorkTask.fromJson(Map<String, dynamic>.from(r['data'] as Map)));
      }
      if (ok != null) workToast(context, ok);
      _load();
    } else {
      workToast(context, '${r['message'] ?? 'Không thực hiện được'}', error: true);
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call, {String? ok}) async {
    setState(() => _busy = true);
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    _applyResult(r, ok: ok);
  }

  // ─── Hành động trạng thái ─────────────────────────────────────

  Future<void> _complete() async {
    final t = _task!;
    final open = t.checklistItems.where((i) => !i.done).length;
    if (open > 0) {
      final go = await SboxDialogs.confirm(
        context,
        title: 'Còn $open mục checklist chưa xong',
        message: 'Vẫn báo hoàn thành công việc này?',
        confirmLabel: 'Vẫn hoàn thành',
      );
      if (!go) return;
    }
    await _run(() => _api.updateTaskStatus(t.id, {'status': WorkTaskStatus.completed.index}), ok: 'Đã hoàn thành');
  }

  Future<void> _reject() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Từ chối nhận việc')),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: tr('Lý do'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Từ chối'))),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await _run(() => _api.rejectTask(_task!.id, reason), ok: 'Đã từ chối');
  }

  Future<void> _setProgress() async {
    var v = _task!.progress.toDouble();
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Cập nhật tiến độ')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${v.round()}%', style: SboxType.headlineStyle()),
            Slider(value: v, max: 100, divisions: 20, onChanged: (x) => set(() => v = x)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, v.round()), child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _run(() => _api.updateTaskProgress(_task!.id, {'progress': picked}), ok: 'Đã cập nhật tiến độ');
  }

  Future<void> _moveStage(TaskStageV2 s) async {
    if (_task!.stageKey == s.key) return;
    await _run(() => _api.moveTaskStage(_task!.id, s.key), ok: 'Đã chuyển sang «${s.name}»');
  }

  // ─── Checklist ─────────────────────────────────────────────────

  Future<void> _toggleItem(TaskChecklistItemV2 item, bool done) async {
    String? photo;
    if (done && item.requirePhoto && (item.photoUrl == null || item.photoUrl!.isEmpty)) {
      photo = await workPickAndUploadPhoto(context, _api);
      if (photo == null) return;
    }
    setState(() => _busyItem = item.id);
    final r = await _api.toggleTaskChecklistItem(_task!.id, item.id, done: done, photoUrl: photo);
    if (!mounted) return;
    setState(() => _busyItem = null);
    _applyResult(r);
  }

  Future<void> _attachItemPhoto(TaskChecklistItemV2 item) async {
    final photo = await workPickAndUploadPhoto(context, _api);
    if (photo == null || !mounted) return;
    setState(() => _busyItem = item.id);
    final r = await _api.toggleTaskChecklistItem(_task!.id, item.id, done: item.done, photoUrl: photo);
    if (!mounted) return;
    setState(() => _busyItem = null);
    _applyResult(r, ok: 'Đã thêm ảnh');
  }

  // ─── Bình luận ─────────────────────────────────────────────────

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty && _commentPhotos.isEmpty) return;
    await _run(() => _api.addTaskComment(_task!.id, {
          'content': text.isEmpty ? tr('Ảnh cập nhật') : text,
          'commentType': _commentPhotos.isEmpty ? 0 : 1,
          if (_commentPhotos.isNotEmpty) 'imageUrls': jsonEncode(_commentPhotos),
          if (_commentPhotos.isNotEmpty) 'progressSnapshot': _task!.progress,
        }));
    _commentCtrl.clear();
    setState(() => _commentPhotos.clear());
  }

  Future<void> _addCommentPhoto() async {
    final url = await workPickAndUploadPhoto(context, _api);
    if (url != null && mounted) setState(() => _commentPhotos.add(url));
  }

  // ─── Giao diện ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = _task;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: SboxColors.surface,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(_changed)),
          title: Text(t?.taskCode ?? tr('Công việc'), style: SboxType.titleSmStyle(SboxColors.textSecondary)),
          actions: [
            if (t != null && widget.onEdit != null && widget.viewer.isManager)
              IconButton(
                tooltip: tr('Sửa'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  await widget.onEdit!(t);
                  _changed = true;
                  _load();
                },
              ),
          ],
        ),
        body: _loading
            ? const SboxLoading()
            : t == null
                ? const SboxEmptyState(title: 'Không tải được công việc', message: 'Có thể việc đã bị xóa hoặc bạn không có quyền xem.')
                : Column(children: [
                    if (_busy) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
                        _header(t),
                        const SizedBox(height: SboxSpace.md),
                        _actions(t),
                        if (_stages.isNotEmpty) ...[const SizedBox(height: SboxSpace.lg), _stageStepper(t)],
                        const SizedBox(height: SboxSpace.lg),
                        _info(t),
                        const SizedBox(height: SboxSpace.lg),
                        _checklist(t),
                        if ((t.description ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: SboxSpace.lg),
                          SboxCard(title: 'Mô tả', child: SelectableText(t.description!, style: SboxType.bodyStyle())),
                        ],
                        const SizedBox(height: SboxSpace.lg),
                        _comments(t),
                        const SizedBox(height: SboxSpace.lg),
                        _historyCard(),
                        const SizedBox(height: SboxSpace.xxl),
                      ]),
                    ),
                  ]),
      ),
    );
  }

  Widget _header(WorkTask t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (t.projectName != null)
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: hexColor(t.projectColor), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(child: Text(t.projectName!, style: SboxType.smallStyle(), overflow: TextOverflow.ellipsis)),
        ]),
      const SizedBox(height: 4),
      Text(t.title, style: SboxType.titleStyle()),
      const SizedBox(height: SboxSpace.sm),
      Wrap(spacing: 6, runSpacing: 6, children: [
        SboxStatusChip(label: getTaskStatusLabel(t.status), tone: workStatusTone(t.status), dot: true),
        SboxStatusChip(label: workPriorityLabel(t.priority), tone: workPriorityTone(t.priority), icon: Icons.flag_outlined),
        SboxStatusChip(label: getTaskTypeLabel(t.taskType), icon: workTypeIcon(t.taskType)),
        if (t.overdueNow) SboxStatusChip(label: workDueLabel(t).text, tone: SboxTone.danger, icon: Icons.schedule_rounded),
      ]),
      const SizedBox(height: SboxSpace.md),
      Row(children: [
        Expanded(child: WorkProgressBar(value: t.progress, height: 8, showLabel: true)),
        if (t.progressMode == TaskProgressMode.manual && t.isOpen && (widget.viewer.isManager || widget.viewer.isParticipant(t)))
          TextButton(onPressed: _busy ? null : _setProgress, child: Text(tr('Cập nhật %'))),
      ]),
      Text(
        tr(switch (t.progressMode) {
          TaskProgressMode.checklist => 'Tiến độ tự tính theo checklist',
          TaskProgressMode.subTasks => 'Tiến độ tự tính theo việc con',
          TaskProgressMode.manual => 'Tiến độ do người làm cập nhật',
        }),
        style: SboxType.captionStyle(),
      ),
    ]);
  }

  Widget _actions(WorkTask t) {
    final mine = widget.viewer.isParticipant(t);
    final canAct = mine || widget.viewer.isManager;
    final buttons = <Widget>[];
    if (t.status == WorkTaskStatus.assigned && mine) {
      buttons.add(SboxButton(
          label: 'Nhận việc và bắt đầu',
          icon: Icons.play_arrow_rounded,
          onPressed: _busy ? null : () => _run(() => _api.acceptTask(t.id, startImmediately: true), ok: 'Đã nhận việc')));
      buttons.add(SboxButton.secondary(label: 'Từ chối', icon: Icons.block_rounded, onPressed: _busy ? null : _reject));
    } else if (canAct && (t.status == WorkTaskStatus.todo || t.status == WorkTaskStatus.onHold)) {
      buttons.add(SboxButton(
          label: 'Bắt đầu làm',
          icon: Icons.play_arrow_rounded,
          onPressed: _busy ? null : () => _run(() => _api.updateTaskStatus(t.id, {'status': WorkTaskStatus.inProgress.index}), ok: 'Đã bắt đầu')));
    }
    if (canAct && t.status == WorkTaskStatus.inProgress) {
      buttons.add(SboxButton.pay(label: 'Báo hoàn thành', icon: Icons.check_rounded, expand: false, onPressed: _busy ? null : _complete));
      if (!widget.viewer.isManager) {
        buttons.add(SboxButton.secondary(
            label: 'Gửi duyệt',
            icon: Icons.rate_review_outlined,
            onPressed: _busy ? null : () => _run(() => _api.updateTaskStatus(t.id, {'status': WorkTaskStatus.inReview.index}), ok: 'Đã gửi duyệt')));
      }
      buttons.add(SboxButton.ghost(
          label: 'Tạm hoãn',
          icon: Icons.pause_rounded,
          onPressed: _busy ? null : () => _run(() => _api.updateTaskStatus(t.id, {'status': WorkTaskStatus.onHold.index}))));
    }
    if (widget.viewer.isManager && t.status == WorkTaskStatus.inReview) {
      buttons.add(SboxButton.pay(label: 'Duyệt hoàn thành', icon: Icons.verified_outlined, expand: false, onPressed: _busy ? null : _complete));
      buttons.add(SboxButton.secondary(
          label: 'Yêu cầu làm lại',
          icon: Icons.replay_rounded,
          onPressed: _busy ? null : () => _run(() => _api.updateTaskStatus(t.id, {'status': WorkTaskStatus.inProgress.index}), ok: 'Đã trả lại')));
    }
    if (canAct && t.status == WorkTaskStatus.completed) {
      buttons.add(SboxButton.secondary(
          label: 'Mở lại',
          icon: Icons.undo_rounded,
          onPressed: _busy ? null : () => _run(() => _api.updateTaskStatus(t.id, {'status': WorkTaskStatus.inProgress.index}), ok: 'Đã mở lại')));
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: buttons);
  }

  Widget _stageStepper(WorkTask t) {
    final idx = _stages.indexWhere((s) => s.key == t.stageKey);
    final canMove = widget.viewer.isManager || widget.viewer.isParticipant(t);
    return SboxCard(
      title: 'Giai đoạn',
      subtitle: canMove ? 'Chạm để chuyển giai đoạn' : null,
      child: Wrap(
        spacing: 4,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < _stages.length; i++) ...[
            if (i > 0) Icon(Icons.chevron_right_rounded, size: 16, color: i <= idx ? _stages[i].colorValue : SboxColors.slate300),
            InkWell(
              borderRadius: SboxRadius.pillAll,
              onTap: canMove && !_busy ? () => _moveStage(_stages[i]) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: i == idx ? _stages[i].colorValue : (i < idx ? _stages[i].colorValue.withValues(alpha: 0.12) : SboxColors.surface),
                  borderRadius: SboxRadius.pillAll,
                  border: Border.all(color: i <= idx ? _stages[i].colorValue : SboxColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (i < idx) Icon(Icons.check_rounded, size: 14, color: _stages[i].colorValue),
                  if (i < idx) const SizedBox(width: 4),
                  Text(tr(_stages[i].name),
                      style: SboxType.captionStyle(i == idx ? Colors.white : (i < idx ? _stages[i].colorValue : SboxColors.textSecondary))
                          .copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _info(WorkTask t) {
    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: SboxColors.slate400),
            const SizedBox(width: SboxSpace.sm),
            SizedBox(width: 110, child: Text(tr(label), style: SboxType.smallStyle(SboxColors.textMuted))),
            Expanded(child: Text(value, style: SboxType.smallStyle(SboxColors.text))),
          ]),
        );
    return SboxCard(
      child: Column(children: [
        row(Icons.people_outline, 'Người làm', t.peopleNames.isEmpty ? tr('Chưa giao') : t.peopleNames.join(', ')),
        row(Icons.event_outlined, 'Hạn chót', '${workDate(t.dueDate, withTime: true)}  ·  ${tr(workDueLabel(t).text)}'),
        if (t.startDate != null) row(Icons.play_circle_outline, 'Bắt đầu', workDate(t.startDate, withTime: true)),
        if (t.estimatedHours != null) row(Icons.timer_outlined, 'Ước tính', '${SboxFmt.number(t.estimatedHours)} giờ'),
        if ((t.location ?? '').isNotEmpty) row(Icons.place_outlined, 'Địa điểm', t.location!),
        if ((t.assignedByName ?? '').isNotEmpty) row(Icons.person_pin_outlined, 'Giao bởi', t.assignedByName!),
      ]),
    );
  }

  Widget _checklist(WorkTask t) {
    final items = t.checklistItems;
    final canTick = t.isOpen && (widget.viewer.isManager || widget.viewer.isParticipant(t));
    final done = items.where((i) => i.done).length;
    return SboxCard(
      title: 'Checklist',
      subtitle: items.isEmpty ? 'Chưa có mục nào' : '$done/${items.length} mục · ${items.where((i) => i.requirePhoto).length} mục cần ảnh',
      child: items.isEmpty
          ? Text(tr('Quản lý có thể thêm checklist khi sửa công việc.'), style: SboxType.smallStyle(SboxColors.textMuted))
          : Column(children: [
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: _busyItem == it.id
                          ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2))
                          : Checkbox(
                              value: it.done,
                              onChanged: canTick && _busyItem == null ? (v) => _toggleItem(it, v == true) : null,
                            ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.text,
                              style: SboxType.bodyStyle(it.done ? SboxColors.textMuted : SboxColors.text)
                                  .copyWith(decoration: it.done ? TextDecoration.lineThrough : null)),
                          if (it.requirePhoto && !it.done && (it.photoUrl ?? '').isEmpty)
                            Text(tr('Cần chụp ảnh khi hoàn thành'), style: SboxType.captionStyle(SboxColors.warningText)),
                          if (it.done && it.doneBy != null)
                            Text('${it.doneBy} · ${workDate(it.doneAt, withTime: true)}', style: SboxType.captionStyle()),
                          if ((it.photoUrl ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: GestureDetector(
                                onTap: () => _openPhoto(it.photoUrl!),
                                child: ClipRRect(
                                  borderRadius: SboxRadius.smAll,
                                  child: Image.network(workImageUrl(it.photoUrl!),
                                      width: 96, height: 72, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                          width: 96, height: 72, color: SboxColors.slate100, child: const Icon(Icons.broken_image_outlined))),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    if (canTick)
                      IconButton(
                        tooltip: tr('Chụp / thêm ảnh'),
                        icon: Icon(Icons.photo_camera_outlined, color: it.requirePhoto ? SboxColors.warning : SboxColors.slate400, size: 20),
                        onPressed: _busyItem == null ? () => _attachItemPhoto(it) : null,
                      ),
                  ]),
                ),
            ]),
    );
  }

  void _openPhoto(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(child: Image.network(workImageUrl(url), fit: BoxFit.contain)),
      ),
    );
  }

  Widget _comments(WorkTask t) {
    final comments = [...(t.comments ?? const <TaskComment>[])]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    List<String> photos(TaskComment c) {
      try {
        final v = jsonDecode(c.imageUrls ?? '[]');
        return v is List ? v.map((e) => '$e').toList() : const [];
      } catch (_) {
        return const [];
      }
    }

    return SboxCard(
      title: 'Trao đổi',
      subtitle: comments.isEmpty ? 'Chưa có trao đổi' : '${comments.length} tin',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final c in comments)
          Padding(
            padding: const EdgeInsets.only(bottom: SboxSpace.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              WorkAvatarStack(names: [c.userName ?? '?'], size: 28, max: 1),
              const SizedBox(width: SboxSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(c.userName ?? '—', style: SboxType.smallStyle(SboxColors.text).copyWith(fontWeight: FontWeight.w600))),
                    const SizedBox(width: 6),
                    Text(workDate(c.createdAt, withTime: true), style: SboxType.captionStyle()),
                    if (c.progressSnapshot != null) ...[
                      const SizedBox(width: 6),
                      SboxStatusChip(label: '${c.progressSnapshot}%', tone: SboxTone.brand),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(c.content, style: SboxType.bodyStyle()),
                  if (photos(c).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final u in photos(c))
                          GestureDetector(
                            onTap: () => _openPhoto(u),
                            child: ClipRRect(
                              borderRadius: SboxRadius.smAll,
                              child: Image.network(workImageUrl(u), width: 80, height: 60, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(width: 80, height: 60, color: SboxColors.slate100)),
                            ),
                          ),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
        if (_commentPhotos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 6, children: [
              for (final u in _commentPhotos)
                Stack(children: [
                  ClipRRect(borderRadius: SboxRadius.smAll, child: Image.network(workImageUrl(u), width: 64, height: 48, fit: BoxFit.cover)),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () => setState(() => _commentPhotos.remove(u)),
                      child: Container(color: Colors.black54, child: const Icon(Icons.close, size: 14, color: Colors.white)),
                    ),
                  ),
                ]),
            ]),
          ),
        Row(children: [
          IconButton(tooltip: tr('Đính kèm ảnh'), onPressed: _busy ? null : _addCommentPhoto, icon: const Icon(Icons.add_a_photo_outlined)),
          Expanded(
            child: TextField(
              controller: _commentCtrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendComment(),
              decoration: InputDecoration(hintText: tr('Nhập trao đổi, báo cáo tiến độ…'), isDense: true),
            ),
          ),
          IconButton(tooltip: tr('Gửi'), onPressed: _busy ? null : _sendComment, icon: const Icon(Icons.send_rounded, color: SboxColors.brand600)),
        ]),
      ]),
    );
  }

  Widget _historyCard() {
    if (_history.isEmpty) return const SizedBox.shrink();
    final list = [..._history]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return SboxCard(
      title: 'Lịch sử',
      subtitle: '${list.length} thay đổi',
      trailing: TextButton(
        onPressed: () => setState(() => _showHistory = !_showHistory),
        child: Text(tr(_showHistory ? 'Thu gọn' : 'Xem')),
      ),
      child: !_showHistory
          ? const SizedBox.shrink()
          : Column(children: [
              for (final h in list.take(40))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 92, child: Text(workDate(h.createdAt, withTime: true), style: SboxType.captionStyle())),
                    Expanded(
                      child: Text(
                        [
                          h.userName,
                          h.description ?? _historyText(h),
                        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                        style: SboxType.smallStyle(),
                      ),
                    ),
                  ]),
                ),
            ]),
    );
  }

  String _historyText(TaskHistory h) {
    final label = switch (h.changeType) {
      'StatusChanged' => 'Đổi trạng thái',
      'StageChanged' => 'Chuyển giai đoạn',
      'ProgressUpdated' => 'Cập nhật tiến độ',
      'ChecklistUpdated' => 'Checklist',
      'AssigneeChanged' => 'Đổi người làm',
      'Created' => 'Tạo việc',
      _ => h.changeType,
    };
    final change = [h.oldValue, h.newValue].whereType<String>().where((s) => s.isNotEmpty).join(' → ');
    return change.isEmpty ? label : '$label: $change';
  }
}
