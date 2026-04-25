import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';

/// SuperAdmin – Tab quản lý nội dung: Điều khoản, Chính sách, Trợ giúp + Báo lỗi
class ContentPagesTab extends StatefulWidget {
  const ContentPagesTab({super.key});
  @override
  State<ContentPagesTab> createState() => ContentPagesTabState();
}

class ContentPagesTabState extends State<ContentPagesTab>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _df = DateFormat('dd/MM/yyyy HH:mm');
  late final TabController _sub;

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _sub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AdminHelpers.bgLight,
          child: TabBar(
            controller: _sub,
            tabs: const [
              Tab(icon: Icon(Icons.description_outlined), text: 'Nội dung trang'),
              Tab(icon: Icon(Icons.bug_report_outlined), text: 'Báo lỗi & Góp ý'),
            ],
            labelColor: AdminHelpers.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AdminHelpers.primary,
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _sub,
            children: const [
              _PagesSubTab(),
              _BugReportsSubTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Sub-tab 1: Content Pages
// ═══════════════════════════════════════════════════════════════
class _PagesSubTab extends StatefulWidget {
  const _PagesSubTab();
  @override
  State<_PagesSubTab> createState() => _PagesSubTabState();
}

class _PagesSubTabState extends State<_PagesSubTab> {
  final _api = ApiService();
  List<Map<String, dynamic>> _pages = [];
  bool _loading = false;

  static const _pageTypes = [
    {'type': 'terms', 'label': 'Điều khoản sử dụng', 'icon': Icons.gavel, 'color': Color(0xFF0F2340)},
    {'type': 'privacy', 'label': 'Chính sách bảo mật', 'icon': Icons.security, 'color': Color(0xFF2D5F8B)},
    {'type': 'help', 'label': 'Trợ giúp', 'icon': Icons.help_outline, 'color': Color(0xFF059669)},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.adminGetAllAppPages();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      _pages = List<Map<String, dynamic>>.from(res['data'] as List? ?? []);
    }
    setState(() => _loading = false);
  }

  Map<String, dynamic>? _getPage(String type) {
    try { return _pages.firstWhere((p) => p['type'] == type); }
    catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Nội dung ứng dụng',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading) ...(_pageTypes.map((pt) {
            final page = _getPage(pt['type'] as String);
            final updatedAt = page?['updatedAt'];
            final icon = pt['icon'] as IconData;
            final color = pt['color'] as Color;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color),
                ),
                title: Text(pt['label'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: updatedAt != null
                    ? Text('Cập nhật: $updatedAt', style: const TextStyle(fontSize: 12))
                    : const Text('Chưa có nội dung', style: TextStyle(fontSize: 12, color: Colors.orange)),
                trailing: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: color, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Chỉnh sửa'),
                  onPressed: () => _openEditor(pt, page),
                ),
              ),
            );
          })),
        ],
      ),
    );
  }

  void _openEditor(Map<String, dynamic> pt, Map<String, dynamic>? page) {
    final titleCtrl = TextEditingController(
        text: page?['title'] as String? ?? pt['label'] as String);
    final contentCtrl = TextEditingController(text: page?['content'] as String? ?? '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: _PageEditorDialog(
            type: pt['type'] as String,
            label: pt['label'] as String,
            color: pt['color'] as Color,
            titleCtrl: titleCtrl,
            contentCtrl: contentCtrl,
            onSaved: _load,
          ),
        ),
      ),
    );
  }
}

class _PageEditorDialog extends StatefulWidget {
  final String type, label;
  final Color color;
  final TextEditingController titleCtrl, contentCtrl;
  final VoidCallback onSaved;
  const _PageEditorDialog({
    required this.type, required this.label, required this.color,
    required this.titleCtrl, required this.contentCtrl, required this.onSaved,
  });
  @override
  State<_PageEditorDialog> createState() => _PageEditorDialogState();
}

class _PageEditorDialogState extends State<_PageEditorDialog> {
  final _api = ApiService();
  bool _saving = false;

  Future<void> _save() async {
    if (widget.titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final res = await _api.adminUpsertAppPage(widget.type, {
      'title': widget.titleCtrl.text.trim(),
      'content': widget.contentCtrl.text,
      'isPublished': true,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      widget.onSaved();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã lưu ${widget.label}'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: ${res['message']}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(Icons.edit_document, color: widget.color),
            const SizedBox(width: 8),
            Expanded(child: Text('Chỉnh sửa: ${widget.label}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(height: 24),
          TextFormField(
            controller: widget.titleCtrl,
            decoration: const InputDecoration(
                labelText: 'Tiêu đề', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('Nội dung (Markdown hỗ trợ)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 380,
            child: TextField(
              controller: widget.contentCtrl,
              expands: true,
              maxLines: null,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '# Tiêu đề\n\n## Mục 1\n\nNội dung ở đây...'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: widget.color, foregroundColor: Colors.white),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: const Text('Lưu'),
            ),
          ]),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Sub-tab 2: Bug Reports
// ═══════════════════════════════════════════════════════════════
class _BugReportsSubTab extends StatefulWidget {
  const _BugReportsSubTab();
  @override
  State<_BugReportsSubTab> createState() => _BugReportsSubTabState();
}

class _BugReportsSubTabState extends State<_BugReportsSubTab> {
  final _api = ApiService();
  final _df = DateFormat('dd/MM/yyyy HH:mm');
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _loading = false;
  String _statusFilter = '';
  String _typeFilter = '';

  static const _statusColors = {
    'New': Color(0xFFEF4444),
    'InProgress': Color(0xFFF59E0B),
    'Resolved': Color(0xFF10B981),
    'Closed': Color(0xFF71717A),
  };
  static const _typeLabels = {
    'Bug': 'Lỗi',
    'Suggestion': 'Góp ý',
    'Other': 'Khác',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.adminGetAppBugReports(
      status: _statusFilter.isEmpty ? null : _statusFilter,
      type: _typeFilter.isEmpty ? null : _typeFilter,
      pageSize: 100,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'] as Map<String, dynamic>? ?? {};
      _items = List<Map<String, dynamic>>.from(data['items'] as List? ?? []);
      _total = (data['total'] as num?)?.toInt() ?? _items.length;
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('Báo lỗi & Góp ý ($_total)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 8),
          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterChip('Tất cả trạng thái', '', _statusFilter == '', () => setState(() { _statusFilter = ''; _load(); })),
              _filterChip('Mới', 'New', _statusFilter == 'New', () => setState(() { _statusFilter = 'New'; _load(); })),
              _filterChip('Đang xử lý', 'InProgress', _statusFilter == 'InProgress', () => setState(() { _statusFilter = 'InProgress'; _load(); })),
              _filterChip('Đã giải quyết', 'Resolved', _statusFilter == 'Resolved', () => setState(() { _statusFilter = 'Resolved'; _load(); })),
              const SizedBox(width: 12),
              _filterChip('Tất cả loại', '', _typeFilter == '', () => setState(() { _typeFilter = ''; _load(); })),
              _filterChip('Lỗi', 'Bug', _typeFilter == 'Bug', () => setState(() { _typeFilter = 'Bug'; _load(); })),
              _filterChip('Góp ý', 'Suggestion', _typeFilter == 'Suggestion', () => setState(() { _typeFilter = 'Suggestion'; _load(); })),
            ]),
          ),
          const SizedBox(height: 12),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _items.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Chưa có báo cáo nào', style: TextStyle(color: Colors.grey)))),
          if (!_loading && _items.isNotEmpty)
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _buildItem(_items[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String val, bool sel, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label),
          selected: sel,
          onSelected: (_) => onTap(),
          selectedColor: AdminHelpers.primary.withValues(alpha: 0.15),
        ),
      );

  Widget _buildItem(Map<String, dynamic> r) {
    final status = r['status'] as String? ?? 'New';
    final type = r['type'] as String? ?? 'Bug';
    final statusColor = _statusColors[status] ?? Colors.grey;
    final createdAt = r['createdAt'] as String?;
    DateTime? dt;
    try { dt = createdAt != null ? DateTime.parse(createdAt).toLocal() : null; } catch (_) {}

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: (type == 'Bug' ? Colors.red : type == 'Suggestion' ? Colors.blue : Colors.grey).withValues(alpha: 0.12),
        child: Icon(
          type == 'Bug' ? Icons.bug_report : type == 'Suggestion' ? Icons.lightbulb_outline : Icons.comment_outlined,
          color: type == 'Bug' ? Colors.red : type == 'Suggestion' ? Colors.blue : Colors.grey,
          size: 20,
        ),
      ),
      title: Row(children: [
        Expanded(child: Text(r['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(status, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
        ),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r['content'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Row(children: [
          Icon(Icons.person_outline, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 3),
          Text(r['userName'] as String? ?? 'Ẩn danh', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (r['storeName'] != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.store_outlined, size: 12, color: Colors.grey[500]),
            const SizedBox(width: 3),
            Text(r['storeName'] as String, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
          const Spacer(),
          if (dt != null) Text(_df.format(dt), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ]),
      ]),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) => _updateStatus(r['id'] as String, v),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'InProgress', child: Text('Đang xử lý')),
          PopupMenuItem(value: 'Resolved', child: Text('Đã giải quyết')),
          PopupMenuItem(value: 'Closed', child: Text('Đóng')),
        ],
      ),
      onTap: () => _showDetail(r),
    );
  }

  void _showDetail(Map<String, dynamic> r) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(r['title'] as String? ?? ''),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _detRow('Loại', _typeLabels[r['type']] ?? r['type'] ?? ''),
            _detRow('Người gửi', r['userName'] ?? 'Ẩn danh'),
            if (r['userEmail'] != null) _detRow('Email', r['userEmail']),
            if (r['storeName'] != null) _detRow('Cửa hàng', r['storeName']),
            if (r['appVersion'] != null) _detRow('Phiên bản', r['appVersion']),
            if (r['deviceInfo'] != null) _detRow('Thiết bị', r['deviceInfo']),
            const Divider(),
            const Text('Nội dung:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Text(r['content'] as String? ?? ''),
            ),
            if (r['adminNote'] != null && r['adminNote'] != '') ...[
              const Divider(),
              _detRow('Ghi chú xử lý', r['adminNote']),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
        ],
      ),
    );
  }

  Widget _detRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 90, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Future<void> _updateStatus(String id, String status) async {
    final res = await _api.adminUpdateAppBugReport(id, {'status': status});
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật trạng thái thành công'), backgroundColor: Colors.green),
      );
    }
  }
}
