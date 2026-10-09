import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/task.dart';
import '../../models/task_v2.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'work_common.dart';

// ═════════════════ Tổng quan ═════════════════

class WorkOverviewView extends StatelessWidget {
  const WorkOverviewView({
    super.key,
    required this.insights,
    required this.tasks,
    required this.projects,
    required this.workload,
    required this.isManager,
    required this.onOpenTask,
    required this.onOpenProject,
    this.selectedProject,
  });

  final TaskInsightsV2? insights;
  final List<WorkTask> tasks;
  final List<TaskProjectV2> projects;
  final List<TaskWorkloadV2> workload;
  final bool isManager;
  final TaskProjectV2? selectedProject;
  final ValueChanged<WorkTask> onOpenTask;
  final ValueChanged<TaskProjectV2> onOpenProject;

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final urgent = tasks.where((t) => t.isOpen && (t.overdueNow || workDueLabel(t).tone == SboxTone.warning)).toList()
      ..sort((a, b) => (a.dueDate ?? DateTime(2100)).compareTo(b.dueDate ?? DateTime(2100)));
    final pending = tasks.where((t) => t.status == WorkTaskStatus.assigned || t.status == WorkTaskStatus.inReview).toList();
    final kpis = <SboxKpi>[
      SboxKpi(label: 'Việc đang mở', value: SboxFmt.number(i?.open ?? 0), icon: Icons.assignment_outlined,
          note: '${SboxFmt.number(i?.inProgress ?? 0)} đang làm'),
      SboxKpi(label: 'Quá hạn', value: SboxFmt.number(i?.overdue ?? 0), icon: Icons.schedule_rounded, tone: SboxTone.danger,
          note: '${SboxFmt.number(i?.dueToday ?? 0)} việc đến hạn hôm nay'),
      SboxKpi(label: 'Xong 14 ngày', value: SboxFmt.number(i?.completedInRange ?? 0), icon: Icons.task_alt_rounded,
          tone: SboxTone.success, current: i?.completedInRange, previous: i?.completedPrevRange, compareLabel: 'kỳ trước'),
      SboxKpi(label: 'Đúng hạn', value: SboxFmt.pct(i?.onTimeRate ?? 0), icon: Icons.verified_outlined, tone: SboxTone.violet,
          note: '${SboxFmt.number(i?.completedOnTime ?? 0)}/${SboxFmt.number(i?.completedInRange ?? 0)} việc xong'),
      if (isManager)
        SboxKpi(label: 'Chờ nhận, duyệt', value: SboxFmt.number((i?.pendingAcceptance ?? 0) + (i?.inReview ?? 0)),
            icon: Icons.pending_actions_rounded, tone: SboxTone.warning),
      SboxKpi(
          label: 'Thời gian xong TB',
          value: (i?.avgCycleHours ?? 0) >= 48 ? '${SboxFmt.number((i!.avgCycleHours / 24))} ngày' : '${SboxFmt.number(i?.avgCycleHours ?? 0)} giờ',
          icon: Icons.timer_outlined,
          tone: SboxTone.neutral,
          note: 'Từ lúc tạo đến lúc xong'),
    ];
    final statusSlices = <SboxSlice>[
      SboxSlice('Chờ nhận', (i?.pendingAcceptance ?? 0).toDouble(), color: SboxColors.warning),
      SboxSlice('Cần làm', (i?.byStatus['Todo'] ?? 0).toDouble(), color: SboxColors.slate400),
      SboxSlice('Đang làm', (i?.inProgress ?? 0).toDouble(), color: SboxColors.brand500),
      SboxSlice('Chờ duyệt', (i?.inReview ?? 0).toDouble(), color: SboxColors.violet),
      SboxSlice('Tạm hoãn', (i?.byStatus['OnHold'] ?? 0).toDouble(), color: SboxColors.slate300),
    ];
    final days = i?.byDay ?? const [];
    final activeProjects = projects.where((p) => p.status == TaskProjectStatus.active).toList()
      ..sort((a, b) => b.overdueCount.compareTo(a.overdueCount));

    return SboxInsightPanel(
      kpis: kpis,
      charts: [
        SboxChartCard(
          title: 'Việc mới và việc hoàn thành',
          subtitle: '14 ngày gần nhất',
          child: SboxBarChart(
            valueFormat: (v) => '${SboxFmt.number(v)} việc',
            axisFormat: (v) => SboxFmt.number(v),
            labels: [for (final d in days) sboxDayLabel(d.date)],
            series: [
              SboxSeries(name: 'Việc mới', values: [for (final d in days) d.created.toDouble()], color: SboxColors.slate300),
              SboxSeries(name: 'Xong đúng hạn', values: [for (final d in days) (d.completed - d.late).toDouble()], color: SboxColors.success),
              SboxSeries(name: 'Xong trễ', values: [for (final d in days) d.late.toDouble()], color: SboxColors.danger),
            ],
          ),
        ),
        SboxChartCard(
          title: 'Việc đang mở theo trạng thái',
          child: SboxDonutChart(
            valueFormat: (v) => '${SboxFmt.number(v)} việc',
            centerValue: SboxFmt.number(i?.open ?? 0),
            centerLabel: 'đang mở',
            slices: statusSlices,
          ),
        ),
        SboxChartCard(
          title: 'Cần chú ý',
          subtitle: urgent.isEmpty ? 'Không có việc quá hạn hay sắp đến hạn' : '${urgent.length} việc quá hạn hoặc đến hạn trong 1–2 ngày',
          child: urgent.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(children: [
                    Icon(Icons.check_circle_rounded, color: SboxColors.success),
                    SizedBox(width: 8),
                    Expanded(child: Text('Mọi việc đang đúng tiến độ')),
                  ]),
                )
              : Column(children: [
                  for (final t in urgent.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: WorkTaskCard(task: t, dense: true, showProject: selectedProject == null, onTap: () => onOpenTask(t)),
                    ),
                ]),
        ),
        if (selectedProject == null && activeProjects.isNotEmpty)
          SboxChartCard(
            title: 'Dự án đang chạy',
            subtitle: '${activeProjects.length} dự án · ưu tiên dự án có việc trễ',
            child: Column(children: [
              for (final p in activeProjects.take(6))
                InkWell(
                  onTap: () => onOpenProject(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: p.colorValue, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.text))),
                        if (p.overdueCount > 0) ...[
                          SboxStatusChip(label: '${p.overdueCount} trễ', tone: SboxTone.danger),
                          const SizedBox(width: 6),
                        ],
                        Text('${p.doneCount}/${p.taskCount}', style: SboxType.captionStyle()),
                      ]),
                      const SizedBox(height: 6),
                      WorkProgressBar(value: p.progress, color: p.colorValue, showLabel: true),
                    ]),
                  ),
                ),
            ]),
          )
        else if (selectedProject != null && selectedProject!.stages.isNotEmpty)
          SboxChartCard(
            title: 'Việc theo giai đoạn',
            child: SboxBarChart(
              valueFormat: (v) => '${SboxFmt.number(v)} việc',
              axisFormat: (v) => SboxFmt.number(v),
              labels: [for (final s in selectedProject!.stages) s.name],
              series: [
                SboxSeries(name: 'Việc', values: [
                  for (final s in selectedProject!.stages) tasks.where((t) => t.stageKey == s.key).length.toDouble(),
                ]),
              ],
            ),
          ),
        if (isManager && workload.isNotEmpty)
          SboxChartCard(
            title: 'Ai đang nhiều việc nhất',
            child: SboxRankList(
              valueFormat: (v) => '${SboxFmt.number(v)} việc',
              color: SboxColors.violet,
              items: [
                for (final w in workload)
                  SboxSlice(w.employeeName, w.open.toDouble(), caption: w.overdue > 0 ? '${w.overdue} trễ' : null),
              ],
            ),
          ),
        if (pending.isNotEmpty && isManager)
          SboxChartCard(
            title: 'Chờ nhân viên nhận / chờ bạn duyệt',
            child: Column(children: [
              for (final t in pending.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WorkTaskCard(task: t, dense: true, showProject: selectedProject == null, onTap: () => onOpenTask(t)),
                ),
            ]),
          ),
      ],
    );
  }
}

// ═════════════════ Bảng Kanban ═════════════════

/// Một cột Kanban: theo giai đoạn dự án hoặc theo trạng thái.
class WorkBoardColumn {
  const WorkBoardColumn({required this.id, required this.title, required this.color, required this.tasks, this.done = false});
  final String id;
  final String title;
  final Color color;
  final List<WorkTask> tasks;
  final bool done;
}

class WorkBoardView extends StatefulWidget {
  const WorkBoardView({
    super.key,
    required this.columns,
    required this.onOpenTask,
    required this.onMove,
    this.onAdd,
    this.showProject = false,
  });

  final List<WorkBoardColumn> columns;
  final ValueChanged<WorkTask> onOpenTask;
  /// Kéo thả việc sang cột khác.
  final Future<void> Function(WorkTask task, WorkBoardColumn to) onMove;
  final ValueChanged<WorkBoardColumn>? onAdd;
  final bool showProject;

  @override
  State<WorkBoardView> createState() => _WorkBoardViewState();
}

class _WorkBoardViewState extends State<WorkBoardView> {
  String? _hover;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = SboxBreakpoints.isMobile(context);
    final colW = mobile ? MediaQuery.sizeOf(context).width * 0.82 : 300.0;
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: !mobile,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.sm, SboxSpace.lg, SboxSpace.lg),
        itemCount: widget.columns.length,
        separatorBuilder: (_, __) => const SizedBox(width: SboxSpace.md),
        itemBuilder: (ctx, i) => SizedBox(width: colW, child: _column(widget.columns[i], mobile)),
      ),
    );
  }

  Widget _column(WorkBoardColumn c, bool mobile) {
    return DragTarget<WorkTask>(
      onWillAcceptWithDetails: (d) {
        final ok = !c.tasks.any((t) => t.id == d.data.id);
        if (ok) setState(() => _hover = c.id);
        return ok;
      },
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (d) {
        setState(() => _hover = null);
        widget.onMove(d.data, c);
      },
      builder: (ctx, cand, rej) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hover == c.id ? c.color.withValues(alpha: 0.08) : SboxColors.slate100.withValues(alpha: 0.6),
          borderRadius: SboxRadius.lgAll,
          border: Border.all(color: _hover == c.id ? c.color : Colors.transparent, width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 48,
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(tr(c.title), style: SboxType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: SboxColors.surface, borderRadius: SboxRadius.pillAll),
                child: Text('${c.tasks.length}', style: SboxType.captionStyle()),
              ),
              if (widget.onAdd != null && !c.done)
                IconButton(
                  tooltip: tr('Thêm việc vào cột này'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  onPressed: () => widget.onAdd!(c),
                ),
            ]),
          ),
          Expanded(
            child: c.tasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(tr('Kéo việc vào đây'), style: SboxType.captionStyle(SboxColors.textMuted)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: c.tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final t = c.tasks[i];
                      final card = WorkTaskCard(task: t, dense: true, showProject: widget.showProject, onTap: () => widget.onOpenTask(t));
                      final feedback = Material(
                        color: Colors.transparent,
                        elevation: 8,
                        child: SizedBox(width: 280, child: Opacity(opacity: 0.92, child: WorkTaskCard(task: t, dense: true))),
                      );
                      final ghost = Opacity(opacity: 0.35, child: card);
                      return mobile
                          ? LongPressDraggable<WorkTask>(data: t, feedback: feedback, childWhenDragging: ghost, child: card)
                          : Draggable<WorkTask>(data: t, feedback: feedback, childWhenDragging: ghost, child: card);
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════ Danh sách ═════════════════

class WorkListView extends StatelessWidget {
  const WorkListView({super.key, required this.tasks, required this.onOpenTask, this.stages = const [], this.showProject = true});
  final List<WorkTask> tasks;
  final ValueChanged<WorkTask> onOpenTask;
  final List<TaskStageV2> stages;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final stageName = {for (final s in stages) s.key: s};
    int dueOrder(WorkTask t) => t.dueDate?.millisecondsSinceEpoch ?? 1 << 52;
    if (SboxBreakpoints.isMobile(context)) return _compact(stageName);
    return SboxDataTable<WorkTask>(
      rows: tasks,
      pageSize: 25,
      onRowTap: onOpenTask,
      emptyTitle: 'Không có công việc',
      emptyMessage: 'Đổi bộ lọc hoặc tạo việc mới.',
      columns: [
        SboxColumn<WorkTask>(
          label: 'Công việc',
          primary: true,
          flex: 4,
          minWidth: 220,
          cell: (t) => Row(children: [
            Icon(workTypeIcon(t.taskType), size: 18, color: SboxColors.slate400),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.text).copyWith(fontWeight: FontWeight.w600)),
                Text(t.taskCode, style: SboxType.captionStyle()),
              ]),
            ),
          ]),
          sortValue: (t) => t.title,
        ),
        if (showProject)
          SboxColumn<WorkTask>(label: 'Dự án', flex: 2, hideOnMobile: true, text: (t) => t.projectName ?? '—', sortValue: (t) => t.projectName ?? ''),
        SboxColumn<WorkTask>(
          label: stages.isEmpty ? 'Trạng thái' : 'Giai đoạn',
          flex: 2,
          minWidth: 130,
          cell: (t) {
            final s = stageName[t.stageKey];
            return Align(
              alignment: Alignment.centerLeft,
              child: s != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: s.colorValue.withValues(alpha: 0.12), borderRadius: SboxRadius.pillAll),
                      child: Text(tr(s.name), style: SboxType.captionStyle(s.colorValue).copyWith(fontWeight: FontWeight.w600)),
                    )
                  : SboxStatusChip(label: getTaskStatusLabel(t.status), tone: workStatusTone(t.status), dot: true),
            );
          },
          sortValue: (t) => t.status.index,
        ),
        SboxColumn<WorkTask>(
          label: 'Người làm',
          flex: 2,
          minWidth: 120,
          hideOnMobile: true,
          cell: (t) => Align(alignment: Alignment.centerLeft, child: WorkAvatarStack(names: t.peopleNames)),
          sortValue: (t) => t.peopleNames.isEmpty ? '' : t.peopleNames.first,
        ),
        SboxColumn<WorkTask>(
          label: 'Hạn',
          flex: 2,
          minWidth: 110,
          cell: (t) {
            final d = workDueLabel(t);
            return Text(tr(d.text), style: SboxType.smallStyle(d.tone == SboxTone.neutral ? SboxColors.textSecondary : d.tone.fg));
          },
          sortValue: dueOrder,
        ),
        SboxColumn<WorkTask>(
          label: 'Tiến độ',
          flex: 2,
          minWidth: 120,
          cell: (t) => WorkProgressBar(value: t.progress, showLabel: true),
          sortValue: (t) => t.progress,
        ),
      ],
    );
  }
}

extension on WorkListView {
  /// Điện thoại: mỗi việc 2 dòng (tên · trạng thái / hạn / %) thay cho thẻ bảng 5 dòng.
  Widget _compact(Map<String, TaskStageV2> stageName) {
    if (tasks.isEmpty) {
      return const SboxEmptyState(icon: Icons.inbox_outlined, title: 'Không có công việc', message: 'Đổi bộ lọc hoặc tạo việc mới.');
    }
    return SboxCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < tasks.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _compactRow(tasks[i], stageName[tasks[i].stageKey]),
        ],
      ]),
    );
  }

  Widget _compactRow(WorkTask t, TaskStageV2? stage) {
    final due = workDueLabel(t);
    final dueColor = due.tone == SboxTone.neutral ? SboxColors.textMuted : due.tone.fg;
    return InkWell(
      onTap: () => onOpenTask(t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Icon(workTypeIcon(t.taskType), size: 20, color: SboxColors.slate400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SboxType.smallStyle(t.isDone ? SboxColors.textMuted : SboxColors.text).copyWith(
                      fontWeight: FontWeight.w600, decoration: t.isDone ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 4),
              Row(children: [
                Flexible(
                  child: stage != null
                      ? Text(tr(stage.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SboxType.captionStyle(stage.colorValue).copyWith(fontWeight: FontWeight.w600))
                      : Text(tr(getTaskStatusLabel(t.status)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SboxType.captionStyle(workStatusTone(t.status) == SboxTone.neutral
                                  ? SboxColors.textSecondary
                                  : workStatusTone(t.status).fg)
                              .copyWith(fontWeight: FontWeight.w600)),
                ),
                // «Hoàn thành · Đã xong» lặp ý → bỏ chữ hạn khi việc đã xong mà không có ngày xong.
                if (!(t.isDone && t.completedDate == null)) ...[
                  Text('  ·  ', style: SboxType.captionStyle(SboxColors.slate300)),
                  Text(tr(due.text), maxLines: 1, style: SboxType.captionStyle(dueColor)),
                ],
                if (showProject && t.projectName != null) ...[
                  Text('  ·  ', style: SboxType.captionStyle(SboxColors.slate300)),
                  Flexible(child: Text(t.projectName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.captionStyle())),
                ],
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: t.progress.clamp(0, 100) / 100,
                strokeWidth: 3.5,
                backgroundColor: SboxColors.slate100,
                valueColor: AlwaysStoppedAnimation(t.progress >= 100 ? SboxColors.success : SboxColors.brand500),
              ),
              Text('${t.progress}%', style: SboxType.captionStyle(SboxColors.text).copyWith(fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════ Tiến độ (Gantt) ═════════════════

class WorkGanttView extends StatefulWidget {
  const WorkGanttView({super.key, required this.items, required this.onOpen, this.stages = const []});
  final List<TaskTimelineItemV2> items;
  final ValueChanged<String> onOpen;
  final List<TaskStageV2> stages;

  @override
  State<WorkGanttView> createState() => _WorkGanttViewState();
}

class _WorkGanttViewState extends State<WorkGanttView> {
  final _h = ScrollController();
  static const _row = 40.0;
  double _dayW = 32;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    var start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
    var end = DateTime(now.year, now.month, now.day).add(const Duration(days: 21));
    for (final i in widget.items) {
      if (i.barStart.isBefore(start)) start = DateTime(i.barStart.year, i.barStart.month, i.barStart.day);
      if (i.barEnd.isAfter(end)) end = DateTime(i.barEnd.year, i.barEnd.month, i.barEnd.day);
    }
    if (end.difference(start).inDays > 180) end = start.add(const Duration(days: 180));
    return (start, end.add(const Duration(days: 1)));
  }

  void _scrollToToday() {
    if (!_h.hasClients) return;
    final (start, _) = _range;
    final x = DateTime.now().difference(start).inHours / 24 * _dayW - 3 * _dayW;
    _h.jumpTo(x.clamp(0, _h.position.maxScrollExtent));
  }

  Color _barColor(TaskTimelineItemV2 i) {
    if (i.status == WorkTaskStatus.completed) return SboxColors.success;
    if (i.overdue) return SboxColors.danger;
    final st = widget.stages.where((s) => s.key == i.stageKey).firstOrNull;
    if (st != null) return st.colorValue;
    return switch (i.status) {
      WorkTaskStatus.inProgress => SboxColors.brand500,
      WorkTaskStatus.inReview => SboxColors.violet,
      WorkTaskStatus.assigned => SboxColors.warning,
      _ => SboxColors.slate400,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SboxEmptyState(
        icon: Icons.view_timeline_outlined,
        title: 'Chưa có việc có ngày bắt đầu / hạn chót',
        message: 'Đặt ngày bắt đầu và hạn chót cho công việc để xem dòng thời gian.',
      );
    }
    final (start, end) = _range;
    final days = end.difference(start).inDays;
    final mobile = SboxBreakpoints.isMobile(context);
    final nameW = mobile ? 132.0 : 260.0;
    final totalW = days * _dayW;
    final today = DateTime.now();
    final todayX = today.difference(start).inMinutes / 1440 * _dayW;
    final items = [...widget.items]..sort((a, b) => a.barStart.compareTo(b.barStart));

    Widget header() => SizedBox(
          height: 44,
          child: Stack(children: [
            for (var d = 0; d < days; d++)
              Positioned(
                left: d * _dayW,
                top: 0,
                width: _dayW,
                height: 44,
                child: () {
                  final date = start.add(Duration(days: d));
                  final weekend = date.weekday >= 6;
                  final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
                  return Container(
                    decoration: BoxDecoration(
                      color: isToday ? SboxColors.brand50 : (weekend ? SboxColors.slate50 : null),
                      border: const Border(left: BorderSide(color: SboxColors.divider)),
                    ),
                    alignment: Alignment.center,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (date.day == 1 || d == 0)
                        Text('T${date.month}', style: SboxType.captionStyle(SboxColors.brand700).copyWith(fontSize: 10)),
                      Text('${date.day}',
                          style: SboxType.captionStyle(isToday ? SboxColors.brand700 : SboxColors.textSecondary)
                              .copyWith(fontWeight: isToday ? FontWeight.w700 : FontWeight.w500)),
                    ]),
                  );
                }(),
              ),
          ]),
        );

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(SboxSpace.lg, 0, SboxSpace.lg, SboxSpace.sm),
        child: Row(children: [
          const SboxLegend(items: [
            (label: 'Đang làm', color: SboxColors.brand500),
            (label: 'Quá hạn', color: SboxColors.danger),
            (label: 'Hoàn thành', color: SboxColors.success),
          ]),
          const Spacer(),
          IconButton(tooltip: tr('Thu nhỏ'), onPressed: () => setState(() => _dayW = math.max(14, _dayW - 6)), icon: const Icon(Icons.zoom_out)),
          IconButton(tooltip: tr('Phóng to'), onPressed: () => setState(() => _dayW = math.min(72, _dayW + 6)), icon: const Icon(Icons.zoom_in)),
          TextButton(onPressed: _scrollToToday, child: Text(tr('Hôm nay'))),
        ]),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(SboxSpace.lg, 0, SboxSpace.lg, SboxSpace.lg),
          decoration: BoxDecoration(color: SboxColors.surface, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: nameW,
                child: Column(children: [
                  Container(
                    height: 44,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SboxColors.border))),
                    child: Text(tr('Công việc'), style: SboxType.captionStyle()),
                  ),
                  for (final i in items)
                    InkWell(
                      onTap: () => widget.onOpen(i.id),
                      child: Container(
                        height: _row,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SboxColors.divider))),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.text)),
                              if (!mobile && i.assigneeName != null)
                                Text(i.assigneeName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.captionStyle()),
                            ]),
                          ),
                          if (i.blockedBy.isNotEmpty) const Icon(Icons.link_rounded, size: 14, color: SboxColors.slate400),
                        ]),
                      ),
                    ),
                ]),
              ),
              const VerticalDivider(width: 1, color: SboxColors.border),
              Expanded(
                child: SingleChildScrollView(
                  controller: _h,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalW,
                    child: Stack(children: [
                      Column(children: [
                        Container(
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SboxColors.border))),
                          child: header(),
                        ),
                        for (final i in items)
                          SizedBox(
                            height: _row,
                            child: Stack(children: [
                              Positioned.fill(
                                child: Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SboxColors.divider)))),
                              ),
                              () {
                                final left = i.barStart.difference(start).inMinutes / 1440 * _dayW;
                                final w = math.max(_dayW * 0.35, i.barEnd.difference(i.barStart).inMinutes / 1440 * _dayW);
                                final c = _barColor(i);
                                return Positioned(
                                  left: left,
                                  width: w,
                                  top: 9,
                                  height: _row - 18,
                                  child: Tooltip(
                                    message: '${i.title}\n${workDate(i.barStart)} → ${workDate(i.dueDate)} · ${i.progress}%',
                                    child: InkWell(
                                      onTap: () => widget.onOpen(i.id),
                                      child: Container(
                                        decoration: BoxDecoration(color: c.withValues(alpha: 0.22), borderRadius: SboxRadius.smAll, border: Border.all(color: c)),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: (i.status == WorkTaskStatus.completed ? 100 : i.progress).clamp(0, 100) / 100,
                                          child: Container(decoration: BoxDecoration(color: c, borderRadius: SboxRadius.smAll)),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }(),
                            ]),
                          ),
                      ]),
                      if (todayX >= 0 && todayX <= totalW)
                        Positioned(left: todayX, top: 0, bottom: 0, child: Container(width: 2, color: SboxColors.danger.withValues(alpha: 0.7))),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ═════════════════ Nhân sự (tải việc) ═════════════════

class WorkWorkloadView extends StatelessWidget {
  const WorkWorkloadView({super.key, required this.rows});
  final List<TaskWorkloadV2> rows;

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]..sort((a, b) => b.open.compareTo(a.open));
    final top = sorted.take(12).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SboxInsightPanel(
        kpis: [
          SboxKpi(label: 'Nhân viên có việc', value: SboxFmt.number(rows.length), icon: Icons.groups_2_outlined),
          SboxKpi(
              label: 'Người có việc trễ',
              value: SboxFmt.number(rows.where((r) => r.overdue > 0).length),
              icon: Icons.person_off_outlined,
              tone: SboxTone.danger),
          SboxKpi(
              label: 'Đúng hạn chung',
              value: SboxFmt.pct(() {
                final done = rows.fold<int>(0, (a, r) => a + r.completedInRange);
                final ok = rows.fold<int>(0, (a, r) => a + r.completedOnTime);
                return done == 0 ? 0 : ok * 100 / done;
              }()),
              icon: Icons.verified_outlined,
              tone: SboxTone.success,
              note: '30 ngày gần nhất'),
          SboxKpi(
              label: 'Giờ việc đang mở',
              value: '${SboxFmt.number(rows.fold<double>(0, (a, r) => a + r.openEstimatedHours))} giờ',
              icon: Icons.timer_outlined,
              tone: SboxTone.neutral),
        ],
        charts: [
          SboxChartCard(
            title: 'Việc đang mở theo người',
            subtitle: 'Cột đỏ = quá hạn',
            wide: true,
            child: SboxBarChart(
              stacked: true,
              valueFormat: (v) => '${SboxFmt.number(v)} việc',
              axisFormat: (v) => SboxFmt.number(v),
              labels: [for (final r in top) r.employeeName.split(' ').last],
              series: [
                SboxSeries(name: 'Đúng tiến độ', values: [for (final r in top) (r.open - r.overdue).toDouble()], color: SboxColors.brand500),
                SboxSeries(name: 'Quá hạn', values: [for (final r in top) r.overdue.toDouble()], color: SboxColors.danger),
              ],
            ),
          ),
        ],
      ),
      SboxDataTable<TaskWorkloadV2>(
        rows: sorted,
        pageSize: 20,
        emptyTitle: 'Chưa có nhân viên nào được giao việc',
        columns: [
          SboxColumn(label: 'Nhân viên', primary: true, flex: 3, text: (r) => r.employeeName, sortValue: (r) => r.employeeName),
          SboxColumn(label: 'Đang mở', numeric: true, text: (r) => '${r.open}', sortValue: (r) => r.open),
          SboxColumn(label: 'Đang làm', numeric: true, hideOnMobile: true, text: (r) => '${r.inProgress}', sortValue: (r) => r.inProgress),
          SboxColumn(
            label: 'Quá hạn',
            numeric: true,
            cell: (r) => Text('${r.overdue}',
                textAlign: TextAlign.right,
                style: SboxType.smallStyle(r.overdue > 0 ? SboxColors.dangerText : SboxColors.textSecondary)
                    .copyWith(fontWeight: r.overdue > 0 ? FontWeight.w700 : null)),
            sortValue: (r) => r.overdue,
          ),
          SboxColumn(label: 'Sắp đến hạn', numeric: true, hideOnMobile: true, text: (r) => '${r.dueSoon}', sortValue: (r) => r.dueSoon),
          SboxColumn(label: 'Xong (30 ngày)', numeric: true, text: (r) => '${r.completedInRange}', sortValue: (r) => r.completedInRange),
          SboxColumn(label: 'Đúng hạn', numeric: true, text: (r) => SboxFmt.pct(r.onTimeRate), sortValue: (r) => r.onTimeRate),
          SboxColumn(label: 'Giờ ước tính', numeric: true, hideOnMobile: true, text: (r) => SboxFmt.number(r.openEstimatedHours), sortValue: (r) => r.openEstimatedHours),
        ],
      ),
    ]);
  }
}

// ═════════════════ Hôm nay (nhân viên, điện thoại) ═════════════════

class WorkTodayView extends StatelessWidget {
  const WorkTodayView({super.key, required this.tasks, required this.onOpenTask, this.header});
  final List<WorkTask> tasks;
  final ValueChanged<WorkTask> onOpenTask;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final endToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final open = tasks.where((t) => t.isOpen).toList()
      ..sort((a, b) => (a.dueDate ?? DateTime(2100)).compareTo(b.dueDate ?? DateTime(2100)));
    final waiting = open.where((t) => t.status == WorkTaskStatus.assigned).toList();
    final rest = open.where((t) => t.status != WorkTaskStatus.assigned).toList();
    final overdue = rest.where((t) => t.overdueNow).toList();
    final today = rest.where((t) => !t.overdueNow && t.dueDate != null && !t.dueDate!.isAfter(endToday)).toList();
    final doing = rest.where((t) => !overdue.contains(t) && !today.contains(t) && t.status == WorkTaskStatus.inProgress).toList();
    final later = rest.where((t) => !overdue.contains(t) && !today.contains(t) && !doing.contains(t)).toList();
    final doneToday = tasks
        .where((t) => t.isDone && t.completedDate != null && !t.completedDate!.isBefore(DateTime(now.year, now.month, now.day)))
        .toList();

    Widget section(String title, List<WorkTask> list, SboxTone tone, IconData icon) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: SboxSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 18, color: tone.solid),
            const SizedBox(width: 6),
            Text(tr(title), style: SboxType.titleSmStyle(tone == SboxTone.neutral ? SboxColors.text : tone.fg)),
            const SizedBox(width: 6),
            SboxStatusChip(label: '${list.length}', tone: tone),
          ]),
          const SizedBox(height: SboxSpace.sm),
          for (final t in list)
            Padding(
              padding: const EdgeInsets.only(bottom: SboxSpace.sm),
              child: WorkTaskCard(task: t, showProject: true, onTap: () => onOpenTask(t)),
            ),
        ]),
      );
    }

    final total = open.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (header != null) header!,
      SboxCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Hôm nay bạn có'), style: SboxType.smallStyle()),
              Text(tr('$total việc cần làm'), style: SboxType.headlineStyle()),
              const SizedBox(height: 4),
              Text(
                tr([
                  if (overdue.isNotEmpty) '${overdue.length} quá hạn',
                  if (waiting.isNotEmpty) '${waiting.length} chờ nhận',
                  '${doneToday.length} đã xong hôm nay',
                ].join(' · ')),
                style: SboxType.captionStyle(overdue.isNotEmpty ? SboxColors.dangerText : SboxColors.textMuted),
              ),
            ]),
          ),
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: (doneToday.length + total) == 0 ? 0 : doneToday.length / (doneToday.length + total),
                strokeWidth: 7,
                backgroundColor: SboxColors.slate100,
                valueColor: const AlwaysStoppedAnimation(SboxColors.success),
              ),
              Text('${doneToday.length}/${doneToday.length + total}', style: SboxType.captionStyle(SboxColors.text).copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: SboxSpace.lg),
      if (total == 0 && doneToday.isEmpty)
        const SboxEmptyState(icon: Icons.celebration_outlined, title: 'Không có việc nào', message: 'Bạn đã xử lý hết công việc được giao.'),
      section('Chờ bạn nhận', waiting, SboxTone.warning, Icons.inbox_outlined),
      section('Quá hạn', overdue, SboxTone.danger, Icons.schedule_rounded),
      section('Đến hạn hôm nay', today, SboxTone.brand, Icons.today_outlined),
      section('Đang làm', doing, SboxTone.violet, Icons.play_circle_outline),
      section('Sắp tới', later, SboxTone.neutral, Icons.upcoming_outlined),
      section('Đã xong hôm nay', doneToday, SboxTone.success, Icons.task_alt_rounded),
    ]);
  }
}
