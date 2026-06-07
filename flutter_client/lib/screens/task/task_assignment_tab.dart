import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../../models/task.dart';
import '../../services/api_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/hrm_page_chrome.dart';

/// Tab Phân công — dashboard giao việc cho quản lý / NV chờ xác nhận.
class TaskAssignmentTab extends StatefulWidget {
  final ApiService api;
  final String? branchId;
  final bool isManager;
  final void Function(WorkTask task) onOpenTask;
  final VoidCallback? onRefreshParent;

  const TaskAssignmentTab({
    super.key,
    required this.api,
    this.branchId,
    required this.isManager,
    required this.onOpenTask,
    this.onRefreshParent,
  });

  @override
  State<TaskAssignmentTab> createState() => _TaskAssignmentTabState();
}

class _TaskAssignmentTabState extends State<TaskAssignmentTab> {
  TaskAssignmentDashboard? _dashboard;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TaskAssignmentTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.api.getTaskAssignmentDashboard(
      branchId: widget.branchId,
    );
    if (!mounted) return;
    if (r['isSuccess'] == true && r['data'] != null) {
      setState(() {
        _dashboard = TaskAssignmentDashboard.fromJson(
            Map<String, dynamic>.from(r['data']));
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _accept(WorkTask task, {bool startNow = false}) async {
    final r = await widget.api.acceptTask(task.id, startImmediately: startNow);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      await _load();
      widget.onRefreshParent?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xác nhận nhận việc')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['message'] ?? 'Lỗi')),
      );
    }
  }

  Future<void> _reject(WorkTask task) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Từ chối nhận việc'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Lý do',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await widget.api.rejectTask(
      task.id,
      reasonCtrl.text.trim().isEmpty
          ? 'Từ chối nhận việc'
          : reasonCtrl.text.trim(),
    );
    reasonCtrl.dispose();
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      await _load();
      widget.onRefreshParent?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['message'] ?? 'Lỗi')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final d = _dashboard;
    if (d == null) {
      return Center(
        child: AppButton(label: 'Tải lại', onPressed: _load),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metricCard(
                  'Chờ tôi xác nhận', d.pendingAcceptanceCount, Colors.orange),
              if (widget.isManager) ...[
                _metricCard('Đã giao', d.assignedByMeCount, HrmPageChrome.primaryNavy),
                _metricCard(
                    'Quá hạn (đã giao)', d.overdueAssignedCount, Colors.red),
              ],
              _metricCard('Đang làm', d.myActiveCount, const Color(0xFF6366F1)),
            ],
          ),
          const SizedBox(height: 20),
          if (d.pendingAcceptance.isNotEmpty) ...[
            _sectionTitle('Chờ xác nhận nhận việc'),
            ...d.pendingAcceptance.map((t) => _taskTile(t, showActions: true)),
          ],
          if (widget.isManager && d.recentlyAssigned.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle('Giao gần đây'),
            ...d.recentlyAssigned.map((t) => _taskTile(t)),
          ],
          if (widget.isManager &&
              d.workloadByAssignee != null &&
              d.workloadByAssignee!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle('Tải công việc theo nhân viên'),
            ...d.workloadByAssignee!.map(_workloadRow),
          ],
        ],
      ),
    );
  }

  Widget _metricCard(String label, int value, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
          const SizedBox(height: 6),
          Text('$value',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: HrmPageChrome.primaryNavy)),
      );

  Widget _taskTile(WorkTask t, {bool showActions = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            '${t.taskCode} · ${getTaskStatusLabel(t.status)}${t.assigneeName != null ? ' · ${t.assigneeName}' : ''}'),
        trailing: showActions
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Nhận việc',
                    icon: const Icon(Icons.check_circle_outline,
                        color: HrmPageChrome.primaryNavy),
                    onPressed: () => _accept(t),
                  ),
                  IconButton(
                    tooltip: 'Từ chối',
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _reject(t),
                  ),
                ],
              )
            : null,
        onTap: () => widget.onOpenTask(t),
      ),
    );
  }

  Widget _workloadRow(TasksByAssignee a) {
    final rate = a.totalTasks > 0
        ? (a.completedTasks / a.totalTasks * 100).round()
        : 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(a.employeeName ?? '—'),
        subtitle: Text(
            'Tổng ${a.totalTasks} · Đang làm ${a.inProgressTasks} · Quá hạn ${a.overdueTasks}'),
        trailing: Text('$rate%',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
