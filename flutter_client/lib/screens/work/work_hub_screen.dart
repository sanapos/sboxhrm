import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/employee.dart';
import '../../models/task.dart';
import '../../models/task_v2.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../task_management_screen.dart';
import 'work_common.dart';
import 'work_projects.dart';
import 'work_task_detail.dart';
import 'work_task_editor.dart';
import 'work_views.dart';

/// Bộ lọc phạm vi: tất cả / của tôi / không thuộc dự án / một dự án.
const _kAll = '__all';
const _kMine = '__mine';
const _kLoose = '__loose';

enum WorkView { today, overview, board, list, timeline, people }

/// Công việc v2: dự án theo ngành, bảng giai đoạn kéo thả, Gantt, tải việc, checklist có ảnh.
class WorkHubScreen extends StatefulWidget {
  const WorkHubScreen({super.key, this.debugViewer, this.initialView, this.initialProjectId});

  /// Kiểm thử: bỏ qua đăng nhập / tra nhân viên.
  final WorkViewer? debugViewer;
  final WorkView? initialView;
  /// Mở sẵn một dự án (liên kết sâu / kiểm thử).
  final String? initialProjectId;

  @override
  State<WorkHubScreen> createState() => _WorkHubScreenState();
}

class _WorkHubScreenState extends State<WorkHubScreen> {
  final _api = ApiService();
  final _search = TextEditingController();
  WorkViewer _viewer = const WorkViewer(isManager: false);
  bool _ready = false;
  bool _loading = true;
  WorkView _view = WorkView.overview;
  String _scope = _kAll;
  WorkTaskStatus? _statusFilter;
  bool _overdueOnly = false;

  List<TaskProjectV2> _projects = [];
  List<WorkTask> _tasks = [];
  TaskInsightsV2? _insights;
  List<TaskWorkloadV2> _workload = [];
  List<TaskTimelineItemV2> _timeline = [];
  List<WorkPerson> _people = [];
  List<TaskTemplateV2> _templates = [];
  List<TaskIndustryPackV2> _packs = [];
  int _seq = 0;
  Timer? _debounce;

  TaskProjectV2? get _project => _projects.where((p) => p.id == _scope).firstOrNull;

  @override
  void initState() {
    super.initState();
    NavigationNotifier.notificationHighlightId.addListener(_consumeHighlight);
    _init();
  }

  @override
  void dispose() {
    NavigationNotifier.notificationHighlightId.removeListener(_consumeHighlight);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (widget.debugViewer != null) {
      _viewer = widget.debugViewer!;
    } else {
      final role = context.read<AuthProvider>().userRole;
      String? empId;
      final me = await _api.getMyEmployee();
      if (me['isSuccess'] == true && me['data'] is Map) {
        final d = me['data'] as Map;
        empId = (d['id'] ?? d['Id'])?.toString();
      }
      _viewer = WorkViewer(isManager: StoreRoleHelper.isManagerOrAbove(role), employeeId: empId);
    }
    if (!_viewer.isManager) _scope = _kMine;
    if (widget.initialProjectId != null) _scope = widget.initialProjectId!;
    _view = widget.initialView ?? (_viewer.isManager ? WorkView.overview : WorkView.today);
    _ready = true;
    await Future.wait([_loadProjects(), _loadPeople(), _loadTemplates()]);
    await _load();
    _consumeHighlight();
  }

  void _consumeHighlight() {
    final id = NavigationNotifier.notificationHighlightId.value;
    if (!_ready || id == null || id.isEmpty || NavigationNotifier.currentModuleCode.value != 'Task') return;
    NavigationNotifier.notificationHighlightId.value = null;
    NavigationNotifier.taskOpenComments.value = false;
    _openTaskId(id);
  }

  // ─── Tải dữ liệu ──────────────────────────────────────────────

  Future<void> _loadProjects() async {
    final r = await _api.getTaskProjects();
    if (!mounted) return;
    setState(() => _projects = r['data'] is List
        ? (r['data'] as List).whereType<Map>().map((e) => TaskProjectV2.fromJson(Map<String, dynamic>.from(e))).toList()
        : []);
  }

  Future<void> _loadPeople() async {
    if (!_viewer.isManager) return;
    final list = await _api.getEmployeesForSelect(pageSize: 500);
    if (!mounted) return;
    setState(() => _people = list.whereType<Map>().map((e) => WorkPerson.fromEmployee(Employee.fromJson(Map<String, dynamic>.from(e)))).toList()
      ..sort((a, b) => a.name.compareTo(b.name)));
  }

  Future<void> _loadTemplates() async {
    if (!_viewer.isManager) return;
    final r = await _api.getTaskTemplatesV2();
    if (!mounted) return;
    setState(() => _templates = r['data'] is List
        ? (r['data'] as List).whereType<Map>().map((e) => TaskTemplateV2.fromJson(Map<String, dynamic>.from(e))).toList()
        : []);
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final projectId = _project?.id;
    final mine = _scope == _kMine;
    final now = DateTime.now();
    final futures = <String, Future<Map<String, dynamic>>>{
      'tasks': _api.getTasksV2(
        projectId: projectId,
        noProject: _scope == _kLoose,
        onlyAssignedToMe: mine,
        search: _search.text.trim(),
        status: _statusFilter?.index,
        isOverdue: _overdueOnly,
        pageSize: 300,
      ),
      if (_view == WorkView.overview)
        'insights': _api.getTaskInsights(projectId: projectId, onlyMine: mine, from: now.subtract(const Duration(days: 13)), to: now),
      if (_viewer.isManager && (_view == WorkView.overview || _view == WorkView.people))
        'workload': _api.getTaskWorkload(projectId: projectId),
      if (_view == WorkView.timeline) 'timeline': _api.getTaskTimeline(projectId: projectId),
    };
    final keys = futures.keys.toList();
    final values = await Future.wait(futures.values);
    if (!mounted || seq != _seq) return;
    final r = {for (var i = 0; i < keys.length; i++) keys[i]: values[i]};
    List<Map<String, dynamic>> items(Map<String, dynamic>? res) {
      final d = res?['data'];
      final list = d is Map ? d['items'] : d;
      return list is List ? list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
    }

    setState(() {
      _loading = false;
      _tasks = items(r['tasks']).map(WorkTask.fromJson).where((t) => t.status != WorkTaskStatus.cancelled).toList();
      if (r['insights']?['data'] is Map) {
        _insights = TaskInsightsV2.fromJson(Map<String, dynamic>.from(r['insights']!['data'] as Map));
      }
      if (r.containsKey('workload')) _workload = items(r['workload']).map(TaskWorkloadV2.fromJson).toList();
      if (r.containsKey('timeline')) {
        _timeline = items(r['timeline']).map(TaskTimelineItemV2.fromJson).toList();
        if (mine && _viewer.employeeId != null) {
          final ids = _tasks.map((t) => t.id).toSet();
          _timeline = _timeline.where((t) => ids.contains(t.id)).toList();
        }
      }
    });
  }

  Future<void> _refreshAll() async {
    await _loadProjects();
    await _load();
  }

  void _setScope(String s) {
    if (_scope == s) return;
    setState(() => _scope = s);
    _load();
  }

  void _setView(WorkView v) {
    if (_view == v) return;
    setState(() {
      _view = v;
      // «Hôm nay» là danh sách việc của chính mình.
      if (v == WorkView.today) _scope = _kMine;
    });
    _load();
  }

  // ─── Điều hướng ───────────────────────────────────────────────

  Future<void> _openTaskId(String id) async {
    final changed = await showWorkTaskDetail(context, taskId: id, viewer: _viewer, onEdit: _viewer.isManager ? _editTask : null);
    if (changed) _refreshAll();
  }

  Future<void> _editTask(WorkTask t) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WorkTaskEditorPage(task: t, projects: _projects, people: _people, templates: _templates),
    ));
  }

  Future<void> _createTask({String? stageKey}) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WorkTaskEditorPage(
        projects: _projects,
        people: _people,
        templates: _templates,
        initialProjectId: _project?.id,
        initialStageKey: stageKey,
      ),
    ));
    if (ok == true) _refreshAll();
  }

  Future<void> _ensurePacks() async {
    if (_packs.isNotEmpty) return;
    final r = await _api.getTaskIndustryPacks();
    if (r['data'] is List) {
      _packs = (r['data'] as List).whereType<Map>().map((e) => TaskIndustryPackV2.fromJson(Map<String, dynamic>.from(e))).toList();
    }
  }

  Future<void> _editProject([TaskProjectV2? p]) async {
    await _ensurePacks();
    if (!mounted) return;
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WorkProjectEditorPage(project: p, packs: _packs, people: _people),
    ));
    if (ok == true) {
      await _loadProjects();
      if (p != null && !_projects.any((x) => x.id == p.id)) _scope = _kAll;
      _load();
    }
  }

  Future<void> _openPacks({int tab = 0}) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => WorkPacksPage(people: _people, initialTab: tab)));
    _packs = [];
    if (ok == true) {
      _loadTemplates();
      _load();
    }
  }

  void _openLegacy() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: Text(tr('Công việc (giao diện cũ)'))), body: const TaskManagementScreen()),
    ));
  }

  // ─── Bảng: cột + kéo thả ──────────────────────────────────────

  List<WorkBoardColumn> _columns() {
    final p = _project;
    if (p != null && p.stages.isNotEmpty) {
      return [
        for (final s in p.stages)
          WorkBoardColumn(
            id: s.key,
            title: s.name,
            color: s.colorValue,
            done: s.done,
            tasks: _tasks.where((t) => t.stageKey == s.key || (t.stageKey == null && s == p.stages.first)).toList(),
          ),
      ];
    }
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    WorkBoardColumn col(WorkTaskStatus s, Color c, {bool done = false}) => WorkBoardColumn(
          id: 'status_${s.index}',
          title: getTaskStatusLabel(s),
          color: c,
          done: done,
          tasks: _tasks.where((t) => t.status == s && (!done || (t.completedDate ?? t.updatedAt ?? t.createdAt).isAfter(cutoff))).toList(),
        );
    return [
      if (_viewer.isManager || _tasks.any((t) => t.status == WorkTaskStatus.assigned)) col(WorkTaskStatus.assigned, SboxColors.warning),
      col(WorkTaskStatus.todo, SboxColors.slate400),
      col(WorkTaskStatus.inProgress, SboxColors.brand500),
      col(WorkTaskStatus.inReview, SboxColors.violet),
      if (_tasks.any((t) => t.status == WorkTaskStatus.onHold)) col(WorkTaskStatus.onHold, SboxColors.slate300),
      col(WorkTaskStatus.completed, SboxColors.success, done: true),
    ];
  }

  Future<void> _move(WorkTask t, WorkBoardColumn to) async {
    final Map<String, dynamic> r;
    if (to.id.startsWith('status_')) {
      final status = WorkTaskStatus.values[int.parse(to.id.substring(7))];
      if (status == WorkTaskStatus.assigned) {
        workToast(context, 'Không thể kéo về «Chờ xác nhận»', error: true);
        return;
      }
      r = await _api.updateTaskStatus(t.id, {'status': status.index});
    } else {
      r = await _api.moveTaskStage(t.id, to.id);
    }
    if (!mounted) return;
    if (r['isSuccess'] != true) {
      workToast(context, '${r['message'] ?? 'Không chuyển được'}', error: true);
      return;
    }
    _load();
  }

  // ─── Giao diện ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mobile = SboxBreakpoints.isMobile(context);
    final pad = SboxSpace.pagePadding(MediaQuery.sizeOf(context).width);
    return ColoredBox(
      color: SboxColors.page,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: EdgeInsets.fromLTRB(pad, pad, pad, 0), child: _header(mobile)),
        const SizedBox(height: SboxSpace.md),
        _scopeStrip(pad),
        const SizedBox(height: SboxSpace.sm),
        Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: _viewTabs(mobile)),
        if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        Expanded(child: !_ready ? const SboxLoading() : _body(pad)),
      ]),
    );
  }

  Widget _header(bool mobile) {
    final p = _project;
    final subtitle = p != null
        ? [
            if ((p.customerName ?? '').isNotEmpty) p.customerName!,
            if ((p.address ?? '').isNotEmpty) p.address!,
            'Tiến độ ${p.progress}% · ${p.doneCount}/${p.taskCount} việc',
            if (p.dueDate != null) 'hạn ${workDate(p.dueDate)}',
          ].join(' · ')
        : (_viewer.isManager ? 'Giao việc, theo dõi tiến độ theo dự án và theo ngành' : 'Việc được giao cho bạn');
    return SboxPageHeader(
      title: p?.name ?? 'Công việc',
      subtitle: subtitle,
      actions: [
        if (_viewer.isManager) SboxButton(label: mobile ? 'Tạo việc' : 'Tạo công việc', icon: Icons.add_rounded, onPressed: () => _createTask()),
        if (p != null && _viewer.isManager)
          SboxButton.secondary(label: 'Sửa dự án', icon: Icons.edit_outlined, onPressed: () => _editProject(p)),
        PopupMenuButton<String>(
          tooltip: tr('Thêm'),
          onSelected: (v) => switch (v) {
            'project' => _editProject(),
            'packs' => _openPacks(),
            'templates' => _openPacks(tab: 1),
            'legacy' => _openLegacy(),
            _ => _refreshAll(),
          },
          itemBuilder: (_) => [
            if (_viewer.isManager) ...[
              PopupMenuItem(value: 'project', child: ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: Text(tr('Tạo dự án / công trình')))),
              PopupMenuItem(value: 'packs', child: ListTile(leading: const Icon(Icons.category_outlined), title: Text(tr('Gói theo ngành')))),
              PopupMenuItem(value: 'templates', child: ListTile(leading: const Icon(Icons.event_repeat_outlined), title: Text(tr('Mẫu việc và việc định kỳ')))),
            ],
            PopupMenuItem(value: 'refresh', child: ListTile(leading: const Icon(Icons.refresh_rounded), title: Text(tr('Tải lại')))),
            PopupMenuItem(value: 'legacy', child: ListTile(leading: const Icon(Icons.history_rounded), title: Text(tr('Giao diện cũ')))),
          ],
          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.more_vert_rounded)),
        ),
      ],
    );
  }

  Widget _scopeStrip(double pad) {
    Widget chip(String id, String label, {Color? color, int? progress, int? late}) {
      final sel = _scope == id;
      return Padding(
        padding: const EdgeInsets.only(right: SboxSpace.sm),
        child: Material(
          color: sel ? (color ?? SboxColors.brand600) : SboxColors.surface,
          shape: RoundedRectangleBorder(borderRadius: SboxRadius.pillAll, side: BorderSide(color: sel ? Colors.transparent : SboxColors.border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => _setScope(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (color != null && !sel) ...[
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                ],
                Text(tr(label), style: SboxType.smallStyle(sel ? Colors.white : SboxColors.text).copyWith(fontWeight: FontWeight.w600)),
                if (progress != null) ...[
                  const SizedBox(width: 6),
                  Text('$progress%', style: SboxType.captionStyle(sel ? Colors.white70 : SboxColors.textMuted)),
                ],
                if (late != null && late > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: sel ? Colors.white24 : SboxColors.dangerSoft, borderRadius: SboxRadius.pillAll),
                    child: Text('$late trễ', style: SboxType.captionStyle(sel ? Colors.white : SboxColors.dangerText).copyWith(fontSize: 11)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: pad), children: [
        if (_viewer.isManager) chip(_kAll, 'Tất cả việc'),
        chip(_kMine, 'Việc của tôi'),
        if (_viewer.isManager) chip(_kLoose, 'Việc lẻ'),
        for (final p in _projects) chip(p.id, p.name, color: p.colorValue, progress: p.progress, late: p.overdueCount),
        if (_viewer.isManager)
          Padding(
            padding: const EdgeInsets.only(right: SboxSpace.sm),
            child: ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: Text(tr(_projects.isEmpty ? 'Tạo dự án theo ngành' : 'Dự án mới')),
              onPressed: () => _editProject(),
            ),
          ),
      ]),
    );
  }

  Widget _viewTabs(bool mobile) {
    final views = <(WorkView, String, IconData)>[
      (WorkView.today, 'Hôm nay', Icons.today_outlined),
      if (_viewer.isManager) (WorkView.overview, 'Tổng quan', Icons.insights_outlined),
      (WorkView.board, 'Bảng', Icons.view_kanban_outlined),
      (WorkView.list, 'Danh sách', Icons.view_list_outlined),
      (WorkView.timeline, 'Tiến độ', Icons.view_timeline_outlined),
      if (_viewer.isManager) (WorkView.people, 'Nhân sự', Icons.groups_2_outlined),
    ];
    final tabs = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final v in views)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: _view == v.$1 ? SboxColors.brand700 : SboxColors.textSecondary,
                backgroundColor: _view == v.$1 ? SboxColors.brand50 : null,
                shape: const RoundedRectangleBorder(borderRadius: SboxRadius.mdAll),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _setView(v.$1),
              icon: Icon(v.$3, size: 18),
              label: Text(tr(v.$2), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
    if (_view == WorkView.overview || _view == WorkView.people || _view == WorkView.today) return tabs;
    final filters = Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: mobile ? 150 : 240,
        height: 36,
        child: TextField(
          controller: _search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: tr('Tìm việc'),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
          },
        ),
      ),
      const SizedBox(width: 6),
      if (_view == WorkView.list)
        SboxFilterChip<WorkTaskStatus?>(
          label: 'Trạng thái',
          value: _statusFilter,
          options: {
            null: 'Mọi trạng thái',
            for (final s in WorkTaskStatus.values.where((s) => s != WorkTaskStatus.cancelled)) s: getTaskStatusLabel(s),
          },
          onChanged: (v) {
            setState(() => _statusFilter = v);
            _load();
          },
        ),
      const SizedBox(width: 6),
      FilterChip(
        label: Text(tr('Quá hạn')),
        selected: _overdueOnly,
        onSelected: (v) {
          setState(() => _overdueOnly = v);
          _load();
        },
      ),
    ]);
    if (mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tabs,
        const SizedBox(height: 6),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: filters),
        const SizedBox(height: 6),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [Expanded(child: tabs), filters]),
    );
  }

  Widget _body(double pad) {
    if (!_loading && _tasks.isEmpty && _projects.isEmpty && _viewer.isManager && _scope == _kAll && _search.text.isEmpty) {
      return _welcome();
    }
    final p = _project;
    switch (_view) {
      case WorkView.today:
        return RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(padding: EdgeInsets.fromLTRB(pad, SboxSpace.sm, pad, pad + SboxSpace.xl), children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: WorkTodayView(tasks: _tasks, onOpenTask: (t) => _openTaskId(t.id)),
              ),
            ),
          ]),
        );
      case WorkView.overview:
        return RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(padding: EdgeInsets.fromLTRB(pad, SboxSpace.sm, pad, pad + SboxSpace.xl), children: [
            WorkOverviewView(
              insights: _insights,
              tasks: _tasks,
              projects: _projects,
              workload: _workload,
              isManager: _viewer.isManager,
              selectedProject: p,
              onOpenTask: (t) => _openTaskId(t.id),
              onOpenProject: (x) => _setScope(x.id),
            ),
          ]),
        );
      case WorkView.board:
        return WorkBoardView(
          columns: _columns(),
          showProject: p == null,
          onOpenTask: (t) => _openTaskId(t.id),
          onMove: _move,
          onAdd: _viewer.isManager ? (c) => _createTask(stageKey: c.id.startsWith('status_') ? null : c.id) : null,
        );
      case WorkView.list:
        return RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(padding: EdgeInsets.fromLTRB(pad, SboxSpace.sm, pad, pad + SboxSpace.xl), children: [
            WorkListView(tasks: _tasks, stages: p?.stages ?? const [], showProject: p == null, onOpenTask: (t) => _openTaskId(t.id)),
          ]),
        );
      case WorkView.timeline:
        return WorkGanttView(items: _timeline, stages: p?.stages ?? const [], onOpen: _openTaskId);
      case WorkView.people:
        return RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(padding: EdgeInsets.fromLTRB(pad, SboxSpace.sm, pad, pad + SboxSpace.xl), children: [
            WorkWorkloadView(rows: _workload),
          ]),
        );
    }
  }

  Widget _welcome() {
    return ListView(padding: const EdgeInsets.all(SboxSpace.xl), children: [
      SboxEmptyState(
        icon: Icons.rocket_launch_outlined,
        title: 'Bắt đầu quản lý công việc',
        message: 'Chọn ngành để có sẵn quy trình, mẫu việc có checklist và việc định kỳ — hoặc tạo việc đầu tiên.',
        action: Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, alignment: WrapAlignment.center, children: [
          SboxButton(label: 'Chọn gói theo ngành', icon: Icons.category_outlined, onPressed: () => _openPacks()),
          SboxButton.secondary(label: 'Tạo công việc', icon: Icons.add_rounded, onPressed: () => _createTask()),
        ]),
      ),
    ]);
  }
}
