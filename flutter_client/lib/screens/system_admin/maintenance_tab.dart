import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// SuperAdmin – tab "Bảo trì hệ thống" (Phase 2).
class MaintenanceTab extends StatefulWidget {
  const MaintenanceTab({super.key});

  @override
  State<MaintenanceTab> createState() => MaintenanceTabState();
}

class MaintenanceTabState extends State<MaintenanceTab> {
  final _api = ApiService();
  final _df = DateFormat('dd/MM/yyyy HH:mm');
  List<Map<String, dynamic>> windows = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.listMaintenanceWindows();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      windows = AdminHelpers.extractList(res['data']);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text(tr('Cửa sổ bảo trì (${windows.length})'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh)),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.warning,
                  foregroundColor: Colors.white),
              onPressed: _openCreate,
              icon: const Icon(Icons.build),
              label: Text(tr('Lên lịch bảo trì')),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : windows.isEmpty
                    ? AdminHelpers.emptyState(
                        Icons.handyman, 'Chưa có cửa sổ bảo trì nào')
                    : ListView.separated(
                        itemCount: windows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _item(windows[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _item(Map<String, dynamic> w) {
    final start = DateTime.tryParse(w['startAt']?.toString() ?? '')?.toLocal();
    final end = DateTime.tryParse(w['endAt']?.toString() ?? '')?.toLocal();
    final isActive = w['isActive'] == true;
    final now = DateTime.now();
    final inWindow = start != null &&
        end != null &&
        now.isAfter(start) &&
        now.isBefore(end);
    final color = inWindow && isActive
        ? AdminHelpers.danger
        : isActive
            ? AdminHelpers.warning
            : Colors.grey;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(Icons.build_circle, color: color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(w['title']?.toString() ?? ''),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      AdminHelpers.statusChip(
                          isActive ? 'Đang bật' : 'Đang tắt', color),
                      if (inWindow && isActive)
                        AdminHelpers.statusChip(
                            'ĐANG BẢO TRÌ', AdminHelpers.danger),
                      if (w['blockAccess'] == true)
                        AdminHelpers.statusChip(
                            'Chặn truy cập', AdminHelpers.danger),
                    ]),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _onAction(v, w),
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: isActive ? 'deactivate' : 'activate',
                      child: Text(tr(isActive ? '⏸️ Tắt' : '▶️ Bật'))),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text(tr('🗑️ Xoá'),
                          style: TextStyle(color: Colors.red))),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            Text(tr(w['message']?.toString() ?? ''),
                maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                  tr('${start != null ? _df.format(start) : "?"} → ${end != null ? _df.format(end) : "?"}'),
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey[700])),
              const Spacer(),
              if ((w['notifyBeforeMinutes'] as List?)?.isNotEmpty == true)
                Text(tr('${tr('Nhắc trước: ')}${(w['notifyBeforeMinutes'] as List).join(", ")} phút'),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _onAction(String action, Map<String, dynamic> w) async {
    final id = w['id'] as String;
    Map<String, dynamic> res;
    switch (action) {
      case 'activate':
        res = await _api.activateMaintenanceWindow(id);
        break;
      case 'deactivate':
        res = await _api.deactivateMaintenanceWindow(id);
        break;
      case 'delete':
        final ok = await showDialog<bool>(
                context: context,
                builder: (_) => ScrollableAlertDialog(
                      title: Text(tr('Xoá cửa sổ bảo trì?')),
                      content: Text(tr('Hành động không thể hoàn tác.')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(tr('Huỷ'))),
                        FilledButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(tr('Xoá'))),
                      ],
                    )) ??
            false;
        if (!ok) return;
        res = await _api.deleteMaintenanceWindow(id);
        break;
      default:
        return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(res['isSuccess'] == true
            ? 'Thành công'
            : (res['message']?.toString() ?? 'Lỗi')))));
    _load();
  }

  Future<void> _openCreate() async {
    final title = TextEditingController(text: tr('Bảo trì định kỳ'));
    final message = TextEditingController(
        text: tr('Hệ thống sẽ tạm dừng phục vụ để bảo trì. Vui lòng lưu công việc.'));
    // notifyCtrl lives outside StatefulBuilder to avoid re-creation on every setState
    final notifyCtrl = TextEditingController(text: tr('60,15,5'));
    DateTime start = DateTime.now().add(const Duration(hours: 2));
    DateTime end = start.add(const Duration(hours: 1));
    bool blockAccess = true;
    bool isActive = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return ScrollableAlertDialog(
          title: Text(tr('Lên lịch bảo trì')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: title,
                    decoration: InputDecoration(labelText: tr('Tiêu đề'))),
                const SizedBox(height: 8),
                TextField(
                    controller: message,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: tr('Mô tả'))),
                const SizedBox(height: 8),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Bắt đầu: ${_df.format(start)}')),
                    trailing: TextButton(
                      child: Text(tr('Chọn')),
                      onPressed: () async {
                        final d = await _pickDateTime(ctx, start);
                        if (d != null) {
                          setS(() {
                            start = d;
                            if (end.isBefore(start)) {
                              end = start.add(const Duration(hours: 1));
                            }
                          });
                        }
                      },
                    )),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Kết thúc: ${_df.format(end)}')),
                    trailing: TextButton(
                      child: Text(tr('Chọn')),
                      onPressed: () async {
                        final d = await _pickDateTime(ctx, end);
                        if (d != null) setS(() => end = d);
                      },
                    )),
                TextField(
                  decoration: InputDecoration(
                      labelText: tr('Nhắc trước (phút, CSV)'),
                      hintText: tr('VD: 60,15,5')),
                  controller: notifyCtrl,
                ),
                SwitchListTile(
                    dense: true,
                    title: Text(tr('Chặn truy cập user thường (trả 503)')),
                    value: blockAccess,
                    onChanged: (v) => setS(() => blockAccess = v)),
                SwitchListTile(
                    dense: true,
                    title: Text(tr('Bật ngay (active)')),
                    value: isActive,
                    onChanged: (v) => setS(() => isActive = v)),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Huỷ'))),
            FilledButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.warning,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (title.text.trim().isEmpty || message.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(tr('Nhập tiêu đề & mô tả'))));
                  return;
                }
                if (end.isBefore(start) || end.isAtSameMomentAs(start)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(tr('Thời gian kết thúc phải > bắt đầu'))));
                  return;
                }
                // Capture messenger before async gap to avoid BuildContext-across-await lint
                final messenger = ScaffoldMessenger.of(context);
                final res = await _api.createMaintenanceWindow({
                  'title': title.text.trim(),
                  'message': message.text.trim(),
                  'startAt': start.toUtc().toIso8601String(),
                  'endAt': end.toUtc().toIso8601String(),
                  'isActive': isActive,
                  'blockAccess': blockAccess,
                  'notifyBeforeMinutes': notifyCtrl.text
                      .split(',')
                      .map((e) => int.tryParse(e.trim()) ?? 0)
                      .where((x) => x > 0)
                      .toList(),
                });
                if (!context.mounted) return;
                Navigator.pop(ctx);
                messenger.showSnackBar(SnackBar(
                    content: Text(tr(res['isSuccess'] == true
                        ? 'Đã tạo cửa sổ bảo trì'
                        : (res['message']?.toString() ?? 'Lỗi')))));
                _load();
              },
              child: Text(tr('Lên lịch')),
            ),
          ],
        );
      }),
    ).then((_) {
      title.dispose();
      message.dispose();
      notifyCtrl.dispose();
    });
  }

  Future<DateTime?> _pickDateTime(BuildContext ctx, DateTime initial) async {
    final d = await showDatePicker(
        context: ctx,
        initialDate: initial,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null) return null;
    if (!ctx.mounted) return null;
    final t = await showTimePicker(
        context: ctx, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }
}
