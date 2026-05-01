import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';

/// SuperAdmin – tab "Thông báo / Broadcast" (Phase 1).
class AnnouncementsTab extends StatefulWidget {
  const AnnouncementsTab({super.key});

  @override
  State<AnnouncementsTab> createState() => AnnouncementsTabState();
}

class AnnouncementsTabState extends State<AnnouncementsTab> {
  final _api = ApiService();
  final _df = DateFormat('dd/MM/yyyy HH:mm');

  List<Map<String, dynamic>> announcements = [];
  bool _loading = false;
  String? _error;

  static const _kindLabels = {
    0: 'Tin chung',
    1: 'Bảo trì',
    2: 'Nâng cấp',
    3: 'Gia hạn',
    4: 'Marketing',
  };
  static const _statusLabels = {
    0: 'Nháp',
    1: 'Đã lên lịch',
    2: 'Đang gửi',
    3: 'Đã gửi',
    4: 'Đã huỷ',
    5: 'Lỗi',
  };
  static const _severityLabels = {
    0: 'Info',
    1: 'Success',
    2: 'Warning',
    3: 'Critical'
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.listSystemAnnouncements(pageSize: 100);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      announcements =
          List<Map<String, dynamic>>.from(res['data'] as List? ?? const []);
      _error = null;
    } else {
      _error = res['message']?.toString() ?? 'Lỗi tải dữ liệu';
    }
    setState(() => _loading = false);
  }

  Color _kindColor(int kind) => switch (kind) {
        1 => AdminHelpers.warning, // maintenance
        2 => AdminHelpers.info, // upgrade
        3 => AdminHelpers.danger, // renewal
        4 => Colors.purple, // marketing
        _ => AdminHelpers.primary,
      };

  IconData _kindIcon(int kind) => switch (kind) {
        1 => Icons.build_circle_outlined,
        2 => Icons.system_update_alt,
        3 => Icons.event_repeat,
        4 => Icons.campaign,
        _ => Icons.notifications_active,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Thông báo hệ thống (${announcements.length})',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh)),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AdminHelpers.primary,
                    foregroundColor: Colors.white),
                onPressed: () => _openCreateDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Tạo thông báo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Quick action chips
          Wrap(spacing: 8, runSpacing: 8, children: [
            _quickChip('Bảo trì hệ thống', Icons.build_circle_outlined,
                AdminHelpers.warning,
                kind: 1, severity: 2),
            _quickChip('Nâng cấp phiên bản', Icons.system_update_alt,
                AdminHelpers.info,
                kind: 2, severity: 0),
            _quickChip('Nhắc gia hạn', Icons.event_repeat, AdminHelpers.danger,
                kind: 3, severity: 2, licenseStatus: 'expiring_soon'),
            _quickChip('Khuyến mãi', Icons.campaign, Colors.purple,
                kind: 4, severity: 1),
          ]),
          const SizedBox(height: 12),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.red[50],
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : announcements.isEmpty
                    ? AdminHelpers.emptyState(
                        Icons.notifications_off, 'Chưa có thông báo nào')
                    : ListView.separated(
                        itemCount: announcements.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _buildItem(announcements[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _quickChip(String label, IconData icon, Color color,
      {required int kind, required int severity, String? licenseStatus}) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      onPressed: () => _openCreateDialog(
          presetKind: kind,
          presetSeverity: severity,
          presetLicenseStatus: licenseStatus),
    );
  }

  Widget _buildItem(Map<String, dynamic> a) {
    final kind =
        AdminHelpers.parseEnumInt(a['kind'], AdminHelpers.announcementKindMap);
    final status = AdminHelpers.parseEnumInt(
        a['status'], AdminHelpers.announcementStatusMap);
    final severity = AdminHelpers.parseEnumInt(
        a['severity'], AdminHelpers.announcementSeverityMap);
    final color = _kindColor(kind);
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
                  child: Icon(_kindIcon(kind), color: color, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a['title']?.toString() ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      AdminHelpers.statusChip(_kindLabels[kind] ?? '?', color),
                      AdminHelpers.statusChip(
                          _severityLabels[severity] ?? '?',
                          severity == 3
                              ? AdminHelpers.danger
                              : severity == 2
                                  ? AdminHelpers.warning
                                  : AdminHelpers.info),
                      AdminHelpers.statusChip(
                          _statusLabels[status] ?? '?',
                          status == 3
                              ? AdminHelpers.success
                              : status == 5
                                  ? AdminHelpers.danger
                                  : AdminHelpers.primary),
                    ]),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _onAction(v, a),
                itemBuilder: (_) => [
                  if (status != 3 && status != 4)
                    const PopupMenuItem(
                        value: 'send', child: Text('📤 Gửi ngay')),
                  const PopupMenuItem(
                      value: 'stats', child: Text('📊 Thống kê')),
                  const PopupMenuItem(
                      value: 'resend', child: Text('🔁 Gửi lại lỗi')),
                  const PopupMenuItem(value: 'cancel', child: Text('🚫 Huỷ')),
                  const PopupMenuItem(
                      value: 'delete',
                      child:
                          Text('🗑️ Xoá', style: TextStyle(color: Colors.red))),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            Text(a['content']?.toString() ?? '',
                maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.people, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text('${a['recipientCount'] ?? 0} người nhận',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              const SizedBox(width: 12),
              Icon(Icons.check_circle, size: 14, color: AdminHelpers.success),
              const SizedBox(width: 4),
              Text('${a['deliveredCount'] ?? 0} đã gửi',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              const SizedBox(width: 12),
              Icon(Icons.visibility, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text('${a['seenCount'] ?? 0} xem',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              const Spacer(),
              if (a['createdAt'] != null)
                Text(_df.format(DateTime.parse(a['createdAt']).toLocal()),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _onAction(String action, Map<String, dynamic> a) async {
    final id = a['id'] as String;
    Map<String, dynamic> res;
    switch (action) {
      case 'send':
        res = await _api.sendSystemAnnouncement(id);
        break;
      case 'resend':
        res = await _api.resendFailedAnnouncement(id);
        break;
      case 'cancel':
        res = await _api.cancelSystemAnnouncement(id);
        break;
      case 'delete':
        final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                      title: const Text('Xoá thông báo?'),
                      content: const Text(
                          'Hành động không thể hoàn tác. Bạn có chắc?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Huỷ')),
                        ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Xoá')),
                      ],
                    )) ??
            false;
        if (!ok) return;
        res = await _api.deleteSystemAnnouncement(id);
        break;
      case 'stats':
        await _showStats(id);
        return;
      default:
        return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['isSuccess'] == true
            ? 'Thành công'
            : (res['message']?.toString() ?? 'Lỗi'))));
    _load();
  }

  Future<void> _showStats(String id) async {
    final res = await _api.getAnnouncementStats(id);
    if (!mounted) return;
    final data = res['data'] as Map<String, dynamic>?;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Thống kê delivery'),
        content: data == null
            ? const Text('Không có dữ liệu')
            : SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statRow('👥 Người nhận', data['recipients']),
                    _statRow('✅ Đã gửi', data['delivered']),
                    _statRow('👁️ Đã xem', data['seen']),
                    _statRow('🖱️ Click action', data['clicked']),
                    _statRow('🤝 Đã xác nhận', data['acked']),
                    _statRow('🚫 Đã ẩn', data['dismissed']),
                    _statRow('❌ Lỗi', data['failed']),
                  ],
                ),
              ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng')),
        ],
      ),
    );
  }

  Widget _statRow(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      );

  Future<void> _openCreateDialog({
    int presetKind = 0,
    int presetSeverity = 0,
    String? presetLicenseStatus,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => _CreateAnnouncementDialog(
        api: _api,
        presetKind: presetKind,
        presetSeverity: presetSeverity,
        presetLicenseStatus: presetLicenseStatus,
        onCreated: _load,
      ),
    );
  }
}

class _CreateAnnouncementDialog extends StatefulWidget {
  final ApiService api;
  final int presetKind;
  final int presetSeverity;
  final String? presetLicenseStatus;
  final VoidCallback onCreated;

  const _CreateAnnouncementDialog({
    required this.api,
    required this.presetKind,
    required this.presetSeverity,
    required this.presetLicenseStatus,
    required this.onCreated,
  });

  @override
  State<_CreateAnnouncementDialog> createState() =>
      _CreateAnnouncementDialogState();
}

class _CreateAnnouncementDialogState extends State<_CreateAnnouncementDialog> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  final _actionUrl = TextEditingController();
  final _actionLabel = TextEditingController();

  late int _kind;
  late int _severity;
  late String? _licenseStatus;
  bool _channelInApp = true;
  bool _channelBanner = true;
  bool _channelEmail = false;
  bool _requireAck = false;
  bool _allowDismiss = true;
  bool _sendNow = true;
  DateTime? _expiresAt;
  String _audienceMode = 'all'; // all | role | license
  final Set<String> _selectedRoles = {'Admin', 'Manager'};

  int _previewCount = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.presetKind;
    _severity = widget.presetSeverity;
    _licenseStatus = widget.presetLicenseStatus;
    if (_licenseStatus != null) _audienceMode = 'license';

    _title = TextEditingController(text: _defaultTitle());
    _content = TextEditingController(text: _defaultContent());
    _previewAudience();
  }

  String _defaultTitle() => switch (_kind) {
        1 => '🔧 Lịch bảo trì hệ thống',
        2 => '🆙 Phiên bản mới đã sẵn sàng',
        3 => '⏰ Nhắc gia hạn dịch vụ',
        4 => '🎁 Khuyến mãi đặc biệt',
        _ => '',
      };

  String _defaultContent() => switch (_kind) {
        1 =>
          'Hệ thống sẽ bảo trì từ ... đến ... Vui lòng lưu công việc trước thời điểm trên.',
        2 =>
          'Phiên bản mới đã được phát hành với nhiều cải tiến. Vui lòng cập nhật ứng dụng.',
        3 =>
          'Gói dịch vụ của bạn sắp hết hạn. Vui lòng liên hệ để gia hạn sớm.',
        4 =>
          'Ưu đãi đặc biệt dành cho cửa hàng của bạn — liên hệ ngay để biết chi tiết.',
        _ => '',
      };

  Future<void> _previewAudience() async {
    final res = await widget.api.previewAnnouncementAudience(_audienceJson());
    if (!mounted) return;
    final data = res['data'] as Map<String, dynamic>?;
    setState(() => _previewCount = (data?['totalUsers'] as int?) ?? 0);
  }

  Map<String, dynamic> _audienceJson() {
    switch (_audienceMode) {
      case 'role':
        return {
          'allUsers': false,
          'roles': _selectedRoles.toList(),
        };
      case 'license':
        return {
          'allUsers': false,
          'licenseStatus': _licenseStatus ?? 'expiring_soon',
        };
      default:
        return {'allUsers': true};
    }
  }

  int _channelMask() {
    var m = 0;
    if (_channelInApp) m |= 1;
    if (_channelBanner) m |= 2;
    if (_channelEmail) m |= 4;
    return m == 0 ? 1 : m;
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tiêu đề và nội dung không được trống')));
      return;
    }
    setState(() => _loading = true);
    final body = {
      'title': _title.text.trim(),
      'content': _content.text.trim(),
      'kind': _kind,
      'severity': _severity,
      'channels': _channelMask(),
      'audience': _audienceJson(),
      'expiresAt': _expiresAt?.toUtc().toIso8601String(),
      'requireAck': _requireAck,
      'allowDismiss': _allowDismiss,
      'actionUrl':
          _actionUrl.text.trim().isEmpty ? null : _actionUrl.text.trim(),
      'actionLabel':
          _actionLabel.text.trim().isEmpty ? null : _actionLabel.text.trim(),
      'sendNow': _sendNow,
    };
    final res = await widget.api.createSystemAnnouncement(body);
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['isSuccess'] == true
            ? (_sendNow ? 'Đã gửi thông báo' : 'Đã lưu thông báo')
            : (res['message']?.toString() ?? 'Lỗi'))));
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tạo thông báo hệ thống'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: _kind,
                decoration: const InputDecoration(labelText: 'Loại'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Tin chung')),
                  DropdownMenuItem(value: 1, child: Text('Bảo trì')),
                  DropdownMenuItem(value: 2, child: Text('Nâng cấp')),
                  DropdownMenuItem(value: 3, child: Text('Gia hạn')),
                  DropdownMenuItem(value: 4, child: Text('Marketing')),
                ],
                onChanged: (v) => setState(() {
                  _kind = v ?? 0;
                  _title.text = _defaultTitle();
                  _content.text = _defaultContent();
                }),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _severity,
                decoration: const InputDecoration(labelText: 'Mức độ'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Thông tin')),
                  DropdownMenuItem(value: 1, child: Text('Thành công')),
                  DropdownMenuItem(value: 2, child: Text('Cảnh báo')),
                  DropdownMenuItem(value: 3, child: Text('Nghiêm trọng')),
                ],
                onChanged: (v) => setState(() => _severity = v ?? 0),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Tiêu đề *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _content,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Nội dung *', alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextField(
                  controller: _actionUrl,
                  decoration: const InputDecoration(
                      labelText: 'URL hành động (tuỳ chọn)'),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                  controller: _actionLabel,
                  decoration:
                      const InputDecoration(labelText: 'Nhãn nút hành động'),
                )),
              ]),
              const Divider(height: 24),
              const Text('Kênh phát',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(children: [
                FilterChip(
                    label: const Text('Trong ứng dụng'),
                    selected: _channelInApp,
                    onSelected: (v) => setState(() => _channelInApp = v)),
                const SizedBox(width: 6),
                FilterChip(
                    label: const Text('Banner'),
                    selected: _channelBanner,
                    onSelected: (v) => setState(() => _channelBanner = v)),
                const SizedBox(width: 6),
                FilterChip(
                    label: const Text('Email (P3)'),
                    selected: _channelEmail,
                    onSelected: (v) => setState(() => _channelEmail = v)),
              ]),
              const Divider(height: 24),
              const Text('Đối tượng nhận',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              RadioListTile<String>(
                  dense: true,
                  value: 'all',
                  groupValue: _audienceMode,
                  title: const Text('Tất cả người dùng'),
                  onChanged: (v) {
                    setState(() => _audienceMode = v!);
                    _previewAudience();
                  }),
              RadioListTile<String>(
                  dense: true,
                  value: 'role',
                  groupValue: _audienceMode,
                  title: const Text('Theo vai trò'),
                  onChanged: (v) {
                    setState(() => _audienceMode = v!);
                    _previewAudience();
                  }),
              if (_audienceMode == 'role')
                Wrap(
                  spacing: 6,
                  children: [
                    'SuperAdmin',
                    'Admin',
                    'Manager',
                    'Employee',
                    'User',
                    'Agent',
                  ].map((r) {
                    final sel = _selectedRoles.contains(r);
                    return FilterChip(
                      label: Text(r),
                      selected: sel,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedRoles.add(r);
                          } else {
                            _selectedRoles.remove(r);
                          }
                        });
                        _previewAudience();
                      },
                    );
                  }).toList(),
                ),
              RadioListTile<String>(
                  dense: true,
                  value: 'license',
                  groupValue: _audienceMode,
                  title: const Text('Theo trạng thái license'),
                  onChanged: (v) {
                    setState(() {
                      _audienceMode = v!;
                      _licenseStatus ??= 'expiring_soon';
                    });
                    _previewAudience();
                  }),
              if (_audienceMode == 'license')
                DropdownButtonFormField<String>(
                  value: _licenseStatus ?? 'expiring_soon',
                  items: const [
                    DropdownMenuItem(
                        value: 'expiring_soon',
                        child: Text('Sắp hết hạn (≤30 ngày)')),
                    DropdownMenuItem(
                        value: 'expired', child: Text('Đã hết hạn')),
                    DropdownMenuItem(
                        value: 'active', child: Text('Đang hoạt động')),
                  ],
                  onChanged: (v) {
                    setState(() => _licenseStatus = v);
                    _previewAudience();
                  },
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AdminHelpers.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.people, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text('Số người nhận dự kiến: $_previewCount')),
                  TextButton(
                      onPressed: _previewAudience,
                      child: const Text('Tính lại')),
                ]),
              ),
              const Divider(height: 24),
              SwitchListTile(
                  dense: true,
                  title: const Text('Yêu cầu xác nhận đã đọc (popup chặn)'),
                  value: _requireAck,
                  onChanged: (v) => setState(() => _requireAck = v)),
              SwitchListTile(
                  dense: true,
                  title: const Text('Cho phép user ẩn banner'),
                  value: _allowDismiss,
                  onChanged: (v) => setState(() => _allowDismiss = v)),
              SwitchListTile(
                  dense: true,
                  title: const Text('Gửi ngay'),
                  value: _sendNow,
                  onChanged: (v) => setState(() => _sendNow = v)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_expiresAt == null
                    ? 'Không đặt hạn hiển thị banner'
                    : 'Hết hiệu lực: ${DateFormat('dd/MM/yyyy HH:mm').format(_expiresAt!.toLocal())}'),
                trailing: TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)));
                    if (d != null) {
                      setState(() => _expiresAt =
                          d.add(const Duration(hours: 23, minutes: 59)));
                    }
                  },
                  child: const Text('Chọn'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context),
            child: const Text('Huỷ')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AdminHelpers.primary,
              foregroundColor: Colors.white),
          onPressed: _loading ? null : _submit,
          child: Text(_loading
              ? 'Đang xử lý...'
              : _sendNow
                  ? 'Gửi'
                  : 'Lưu nháp'),
        ),
      ],
    );
  }
}
