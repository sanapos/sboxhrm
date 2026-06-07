import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';

/// SuperAdmin – tab "Marketing" (Phase 3): templates + campaigns đa kênh.
class MarketingTab extends StatefulWidget {
  const MarketingTab({super.key});

  @override
  State<MarketingTab> createState() => MarketingTabState();
}

class MarketingTabState extends State<MarketingTab>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _df = DateFormat('dd/MM/yyyy HH:mm');
  late TabController _inner;

  List<Map<String, dynamic>> templates = [];
  List<Map<String, dynamic>> campaigns = [];
  bool _loading = false;

  // Channel flags (must match backend [Flags] enum)
  static const int chInApp = 1;
  static const int chBanner = 2;
  static const int chEmail = 4;
  static const int chSms = 8;
  static const int chPush = 16;

  static const _campaignStatusLabels = {
    0: 'Nháp',
    1: 'Đã lên lịch',
    2: 'Đang chạy',
    3: 'Hoàn tất',
    4: 'Đã huỷ',
    5: 'Lỗi',
  };

  @override
  void initState() {
    super.initState();
    _inner = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _inner.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r1 = await _api.listNotificationTemplates();
    final r2 = await _api.listMarketingCampaigns();
    if (!mounted) return;
    if (r1['isSuccess'] == true) {
      templates = List<Map<String, dynamic>>.from(r1['data'] as List? ?? const []);
    }
    if (r2['isSuccess'] == true) {
      campaigns = List<Map<String, dynamic>>.from(r2['data'] as List? ?? const []);
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
              child: TabBar(
                controller: _inner,
                labelColor: AdminHelpers.primary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AdminHelpers.primary,
                tabs: [
                  Tab(text: 'Mẫu (${templates.length})'),
                  Tab(text: 'Chiến dịch (${campaigns.length})'),
                ],
              ),
            ),
            IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _inner,
                    children: [
                      _buildTemplatesTab(),
                      _buildCampaignsTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ============ Templates ============

  Widget _buildTemplatesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white),
            onPressed: _openCreateTemplate,
            icon: const Icon(Icons.add),
            label: const Text('Thêm mẫu'),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: templates.isEmpty
              ? AdminHelpers.emptyState(
                  Icons.article_outlined, 'Chưa có mẫu thông báo nào')
              : ListView.separated(
                  itemCount: templates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _templateItem(templates[i]),
                ),
        ),
      ],
    );
  }

  Widget _templateItem(Map<String, dynamic> t) {
    final isActive = t['isActive'] == true;
    final channels = AdminHelpers.parseEnumInt(
        t['channels'], AdminHelpers.notificationChannelMap);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor:
                      AdminHelpers.primary.withValues(alpha: 0.12),
                  child: const Icon(Icons.article,
                      color: AdminHelpers.primary)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['title']?.toString() ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      AdminHelpers.statusChip(
                          t['code']?.toString() ?? '', AdminHelpers.info),
                      AdminHelpers.statusChip(
                          isActive ? 'Bật' : 'Tắt',
                          isActive
                              ? AdminHelpers.success
                              : Colors.grey),
                      ..._channelChips(channels),
                    ]),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _onTemplateAction(v, t),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('✏️ Sửa')),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text('🗑️ Xoá',
                          style: TextStyle(color: Colors.red))),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            Text(t['body']?.toString() ?? '',
                maxLines: 3, overflow: TextOverflow.ellipsis),
            if ((t['variables'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text('Biến: ${(t['variables'] as List).join(", ")}',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _channelChips(int channels) {
    final out = <Widget>[];
    if (channels & chInApp != 0) {
      out.add(AdminHelpers.statusChip('In-App', AdminHelpers.info));
    }
    if (channels & chBanner != 0) {
      out.add(AdminHelpers.statusChip('Banner', AdminHelpers.warning));
    }
    if (channels & chEmail != 0) {
      out.add(AdminHelpers.statusChip('Email', AdminHelpers.primary));
    }
    if (channels & chSms != 0) {
      out.add(AdminHelpers.statusChip('SMS', AdminHelpers.success));
    }
    if (channels & chPush != 0) {
      out.add(AdminHelpers.statusChip('Push', AdminHelpers.danger));
    }
    return out;
  }

  Future<void> _onTemplateAction(String action, Map<String, dynamic> t) async {
    switch (action) {
      case 'edit':
        await _openCreateTemplate(initial: t);
        break;
      case 'delete':
        final ok = await _confirm('Xoá mẫu này?');
        if (!ok) return;
        final res = await _api.deleteNotificationTemplate(t['id'] as String);
        _toast(res);
        await _load();
        break;
    }
  }

  Future<void> _openCreateTemplate({Map<String, dynamic>? initial}) async {
    final code = TextEditingController(text: initial?['code']?.toString() ?? '');
    final title =
        TextEditingController(text: initial?['title']?.toString() ?? '');
    final body =
        TextEditingController(text: initial?['body']?.toString() ?? '');
    final vars = TextEditingController(
        text: ((initial?['variables'] as List?) ?? const [])
            .join(', '));
    final locale = TextEditingController(
        text: initial?['locale']?.toString() ?? 'vi-VN');
    int channels = AdminHelpers.parseEnumInt(
            initial?['channels'], AdminHelpers.notificationChannelMap) |
        (initial == null ? (chInApp | chBanner) : 0);
    if (channels == 0) channels = chInApp | chBanner;
    bool isActive = (initial?['isActive'] as bool?) ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => ScrollableAlertDialog(
          title: Text(initial == null ? 'Tạo mẫu mới' : 'Sửa mẫu'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AdminHelpers.dialogField(code, 'Mã (Code, duy nhất)',
                    Icons.qr_code),
                const SizedBox(height: 8),
                AdminHelpers.dialogField(title, 'Tiêu đề', Icons.title),
                const SizedBox(height: 8),
                TextField(
                  controller: body,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: 'Nội dung (hỗ trợ {variable})',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                AdminHelpers.dialogField(vars,
                    'Biến (CSV, vd: name, store)', Icons.code),
                const SizedBox(height: 8),
                AdminHelpers.dialogField(locale, 'Locale', Icons.language),
                const SizedBox(height: 8),
                _channelSelector(channels, (v) => setSt(() => channels = v)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đang bật'),
                  value: isActive,
                  onChanged: (v) => setSt(() => isActive = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Huỷ')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lưu')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final body2 = {
      'code': code.text.trim(),
      'title': title.text.trim(),
      'body': body.text,
      'variables': vars.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'channels': channels,
      'locale': locale.text.trim().isEmpty ? 'vi-VN' : locale.text.trim(),
      'isActive': isActive,
    };
    final res = initial == null
        ? await _api.createNotificationTemplate(body2)
        : await _api.updateNotificationTemplate(initial['id'] as String, body2);
    _toast(res);
    await _load();
  }

  // ============ Campaigns ============

  Widget _buildCampaignsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.success,
                foregroundColor: Colors.white),
            onPressed: _openCreateCampaign,
            icon: const Icon(Icons.campaign),
            label: const Text('Tạo chiến dịch'),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: campaigns.isEmpty
              ? AdminHelpers.emptyState(
                  Icons.local_offer_outlined, 'Chưa có chiến dịch nào')
              : ListView.separated(
                  itemCount: campaigns.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _campaignItem(campaigns[i]),
                ),
        ),
      ],
    );
  }

  Widget _campaignItem(Map<String, dynamic> c) {
    final status = AdminHelpers.parseEnumInt(
        c['status'], AdminHelpers.campaignStatusMap);
    final channels = AdminHelpers.parseEnumInt(
        c['channels'], AdminHelpers.notificationChannelMap);
    final schedule =
        DateTime.tryParse(c['scheduleAt']?.toString() ?? '')?.toLocal();
    final launched =
        DateTime.tryParse(c['launchedAt']?.toString() ?? '')?.toLocal();
    final statusColor = switch (status) {
      1 => AdminHelpers.info,
      2 => AdminHelpers.warning,
      3 => AdminHelpers.success,
      4 => Colors.grey,
      5 => AdminHelpers.danger,
      _ => Colors.blueGrey,
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                  child: Icon(Icons.local_offer, color: statusColor)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['name']?.toString() ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      AdminHelpers.statusChip(
                          _campaignStatusLabels[status] ?? '?', statusColor),
                      ..._channelChips(channels),
                    ]),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _onCampaignAction(v, c),
                itemBuilder: (_) {
                  final items = <PopupMenuEntry<String>>[];
                  if (status == 0 || status == 1) {
                    items.add(const PopupMenuItem(
                        value: 'launch', child: Text('🚀 Phóng ngay')));
                  }
                  if (status == 0 ||
                      status == 1 ||
                      status == 2) {
                    items.add(const PopupMenuItem(
                        value: 'cancel', child: Text('🛑 Huỷ')));
                  }
                  items.add(const PopupMenuItem(
                      value: 'delete',
                      child: Text('🗑️ Xoá',
                          style: TextStyle(color: Colors.red))));
                  return items;
                },
              ),
            ]),
            if ((c['description'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(c['description']!.toString(),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.people, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                  'Người nhận: ${c['recipientCount'] ?? 0}'
                  ' • Đã gửi: ${c['deliveredCount'] ?? 0}',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey[700])),
              const Spacer(),
              if (schedule != null)
                Text('Lịch: ${_df.format(schedule)}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[600])),
              if (launched != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('Phóng: ${_df.format(launched)}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[600])),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _onCampaignAction(String action, Map<String, dynamic> c) async {
    final id = c['id'] as String;
    Map<String, dynamic> res;
    switch (action) {
      case 'launch':
        final ok = await _confirm('Phóng chiến dịch ngay bây giờ?');
        if (!ok) return;
        res = await _api.launchMarketingCampaign(id);
        break;
      case 'cancel':
        final ok = await _confirm('Huỷ chiến dịch này?');
        if (!ok) return;
        res = await _api.cancelMarketingCampaign(id);
        break;
      case 'delete':
        final ok = await _confirm('Xoá chiến dịch này?');
        if (!ok) return;
        res = await _api.deleteMarketingCampaign(id);
        break;
      default:
        return;
    }
    _toast(res);
    await _load();
  }

  Future<void> _openCreateCampaign() async {
    final name = TextEditingController();
    final desc = TextEditingController();
    final customTitle = TextEditingController();
    final customBody = TextEditingController();
    final varsCtrl = TextEditingController(); // "key=value, key2=value2"
    final rolesCtrl = TextEditingController(); // CSV roles
    String? templateId;
    int channels = chInApp | chBanner;
    bool allUsers = true;
    bool launchNow = false;
    DateTime? scheduleAt;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => ScrollableAlertDialog(
          title: const Text('Tạo chiến dịch marketing'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AdminHelpers.dialogField(name, 'Tên chiến dịch', Icons.label),
                const SizedBox(height: 8),
                AdminHelpers.dialogField(
                    desc, 'Mô tả (tuỳ chọn)', Icons.notes),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: templateId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Mẫu (tuỳ chọn)',
                      border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— Không dùng mẫu —')),
                    ...templates.map((t) => DropdownMenuItem<String?>(
                          value: t['id'] as String,
                          child: Text(
                              '${t['code']} — ${t['title']}',
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setSt(() => templateId = v),
                ),
                const SizedBox(height: 8),
                AdminHelpers.dialogField(customTitle,
                    'Tiêu đề tuỳ biến (override)', Icons.title),
                const SizedBox(height: 8),
                TextField(
                  controller: customBody,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'Nội dung tuỳ biến (override, hỗ trợ {var})',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                AdminHelpers.dialogField(varsCtrl,
                    'Biến (key=value, key2=value2)', Icons.data_object),
                const SizedBox(height: 12),
                _channelSelector(channels, (v) => setSt(() => channels = v)),
                const Divider(),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Đối tượng nhận',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Toàn bộ người dùng'),
                  value: allUsers,
                  onChanged: (v) => setSt(() => allUsers = v),
                ),
                if (!allUsers)
                  AdminHelpers.dialogField(rolesCtrl,
                      'Vai trò (CSV: SuperAdmin,Admin,User)',
                      Icons.admin_panel_settings),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Phóng ngay sau khi tạo'),
                  value: launchNow,
                  onChanged: (v) => setSt(() {
                    launchNow = v;
                    if (v) scheduleAt = null;
                  }),
                ),
                if (!launchNow)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: Text(scheduleAt == null
                        ? 'Lịch gửi (tuỳ chọn)'
                        : _df.format(scheduleAt!)),
                    trailing: const Icon(Icons.edit),
                    onTap: () async {
                      final d = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 1)),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365)));
                      if (d == null) return;
                      final t = await showTimePicker(
                          // ignore: use_build_context_synchronously
                          context: ctx,
                          initialTime: TimeOfDay.now());
                      if (t == null) return;
                      setSt(() => scheduleAt = DateTime(
                          d.year, d.month, d.day, t.hour, t.minute));
                    },
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Huỷ')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lưu')),
          ],
        ),
      ),
    );

    if (saved != true) return;

    // Parse vars "k=v, k2=v2"
    final variables = <String, String>{};
    for (final part in varsCtrl.text.split(',')) {
      final s = part.trim();
      if (s.isEmpty) continue;
      final eq = s.indexOf('=');
      if (eq <= 0) continue;
      variables[s.substring(0, eq).trim()] = s.substring(eq + 1).trim();
    }

    final audience = <String, dynamic>{
      'allUsers': allUsers,
      if (!allUsers && rolesCtrl.text.trim().isNotEmpty)
        'roles': rolesCtrl.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
    };

    final body = <String, dynamic>{
      'name': name.text.trim(),
      if (desc.text.trim().isNotEmpty) 'description': desc.text.trim(),
      if (templateId != null) 'templateId': templateId,
      if (customTitle.text.trim().isNotEmpty)
        'customTitle': customTitle.text.trim(),
      if (customBody.text.trim().isNotEmpty)
        'customBody': customBody.text,
      if (variables.isNotEmpty) 'variables': variables,
      'audience': audience,
      'channels': channels,
      if (scheduleAt != null)
        'scheduleAt': scheduleAt!.toUtc().toIso8601String(),
      'launchNow': launchNow,
    };

    final res = await _api.createMarketingCampaign(body);
    _toast(res);
    await _load();
  }

  // ============ Helpers ============

  Widget _channelSelector(int value, ValueChanged<int> onChanged) {
    Widget cb(String label, int flag) => FilterChip(
          label: Text(label),
          selected: value & flag != 0,
          onSelected: (sel) =>
              onChanged(sel ? (value | flag) : (value & ~flag)),
        );
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        cb('In-App', chInApp),
        cb('Banner', chBanner),
        cb('Email', chEmail),
        cb('SMS', chSms),
        cb('Push', chPush),
      ]),
    );
  }

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ScrollableAlertDialog(
        title: const Text('Xác nhận'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ')),
          FilledButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK')),
        ],
      ),
    );
    return ok ?? false;
  }

  void _toast(Map<String, dynamic> res) {
    if (!mounted) return;
    final ok = res['isSuccess'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AdminHelpers.success : AdminHelpers.danger,
      content: Text(
          res['message']?.toString() ?? (ok ? 'Thành công' : 'Thất bại')),
    ));
  }
}
