import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabCtl;

  List<Map<String, dynamic>> _allFeedbacks = [];
  List<Map<String, dynamic>> _myFeedbacks = [];
  List<Map<String, dynamic>> _managers = [];
  bool _isLoading = true;
  String? _filterStatus;
  String? _filterCategory;

  // Mobile UI state
  bool _showMobileFilters = false;

  static const _statusLabels = {
    'Pending': 'Chờ xử lý',
    'InProgress': 'Đang xử lý',
    'Resolved': 'Đã giải quyết',
    'Closed': 'Đã đóng',
  };
  static const _statusColors = {
    'Pending': Color(0xFFF59E0B),
    'InProgress': Color(0xFF3B82F6),
    'Resolved': Color(0xFF10B981),
    'Closed': Color(0xFF6B7280),
  };
  static const _categoryLabels = {
    'General': 'Chung',
    'Complaint': 'Khiếu nại',
    'Suggestion': 'Đề xuất',
    'Other': 'Khác',
  };
  static const _categoryIcons = {
    'General': Icons.chat_bubble_outline,
    'Complaint': Icons.report_problem_outlined,
    'Suggestion': Icons.lightbulb_outline,
    'Other': Icons.more_horiz,
  };

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 2, vsync: this);
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging) _reloadCurrentTab();
    });
    _loadManagers();
    _loadMy();
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  Future<void> _loadManagers() async {
    try {
      final res = await _apiService.getFeedbackManagers();
      if (res['isSuccess'] == true) {
        _managers = List<Map<String, dynamic>>.from(res['data'] ?? []);
      }
    } catch (e) {
      debugPrint('Load managers error: $e');
    }
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getFeedbacks(
        status: _filterStatus, category: _filterCategory,
      );
      if (res['isSuccess'] == true) {
        final data = res['data'];
        _allFeedbacks = List<Map<String, dynamic>>.from(data['items'] ?? []);
      }
    } catch (e) {
      debugPrint('Load feedbacks error: $e');
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể tải danh sách phản hồi');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadMy() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getMyFeedbacks();
      if (res['isSuccess'] == true) {
        _myFeedbacks = List<Map<String, dynamic>>.from(res['data'] ?? []);
      }
    } catch (e) {
      debugPrint('Load my feedbacks error: $e');
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể tải phản hồi của bạn');
    }
    setState(() => _isLoading = false);
  }

  void _reloadCurrentTab() {
    if (_tabCtl.index == 0) {
      _loadMy();
    } else {
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    const primary = Color(0xFF1E3A5F);
    final hasActiveFilter = _filterStatus != null || _filterCategory != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isMobile && Provider.of<PermissionProvider>(context, listen: false).canCreate('Feedback')
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add),
              label: const Text('Gửi ý kiến'),
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 4,
            )
          : null,
      body: Column(
        children: [
          // ===== Gradient header =====
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 24, vertical: isMobile ? 12 : 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primary, primary.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                    color: primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.feedback_outlined,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Phản ánh / Ý kiến',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                if (isMobile)
                  Stack(
                    children: [
                      IconButton(
                        icon: Icon(
                            _showMobileFilters
                                ? Icons.filter_list_off
                                : Icons.filter_list,
                            color: Colors.white),
                        onPressed: () => setState(
                            () => _showMobileFilters = !_showMobileFilters),
                      ),
                      if (hasActiveFilter)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF97316),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (!isMobile && Provider.of<PermissionProvider>(context, listen: false).canCreate('Feedback'))
                  FilledButton.icon(
                    onPressed: _showCreateDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Gửi ý kiến'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primary,
                      elevation: 0,
                    ),
                  ),
              ],
            ),
          ),
          // ===== Collapsible filters =====
          if (!isMobile || _showMobileFilters)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 14 : 24, vertical: 10),
              color: Colors.white,
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildFilterDropdown(
                    'Trạng thái',
                    _filterStatus,
                    _statusLabels.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    (v) {
                      setState(() => _filterStatus = v);
                      _reloadCurrentTab();
                    },
                  ),
                  _buildFilterDropdown(
                    'Phân loại',
                    _filterCategory,
                    _categoryLabels.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    (v) {
                      setState(() => _filterCategory = v);
                      _reloadCurrentTab();
                    },
                  ),
                ],
              ),
            ),
          // ===== TabBar =====
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtl,
              labelColor: primary,
              unselectedLabelColor: const Color(0xFF71717A),
              indicatorColor: primary,
              tabs: const [
                Tab(text: 'Của tôi'),
                Tab(text: 'Hòm thư'),
              ],
            ),
          ),
          // ===== Content =====
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabCtl,
                    children: [
                      _buildFeedbackList(_myFeedbacks, isMine: true),
                      _buildFeedbackList(_allFeedbacks, isMine: false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String? value,
      List<DropdownMenuItem<String>> items, ValueChanged<String?> onChanged) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        items: [
          DropdownMenuItem<String>(value: null, child: Text('Tất cả $label')),
          ...items,
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFeedbackList(List<Map<String, dynamic>> list,
      {required bool isMine}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              isMine ? 'Bạn chưa gửi phản ánh nào' : 'Chưa có phản ánh nào',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _reloadCurrentTab(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (ctx, i) => _buildFeedbackCard(list[i], isMine: isMine),
      ),
    );
  }

  Widget _buildFeedbackCard(Map<String, dynamic> fb,
      {required bool isMine}) {
    final status = fb['status'] ?? 'Pending';
    final category = fb['category'] ?? 'General';
    final isAnonymous = fb['isAnonymous'] == true;
    final createdAt =
        DateTime.tryParse(fb['createdAt'] ?? '') ?? DateTime.now();
    final response = fb['response'] as String?;
    final respondedByName = fb['respondedByName'] as String?;
    final respondedAt = fb['respondedAt'] != null
        ? DateTime.tryParse(fb['respondedAt'])
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(_categoryIcons[category] ?? Icons.chat_bubble_outline,
                    size: 20, color: const Color(0xFF1E3A5F)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(fb['title'] ?? '',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_statusColors[status] ?? Colors.grey)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusLabels[status] ?? status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _statusColors[status] ?? Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Meta info
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _metaChip(Icons.category_outlined,
                    _categoryLabels[category] ?? category),
                if (isAnonymous && !isMine)
                  _metaChip(Icons.visibility_off, 'Ẩn danh',
                      color: const Color(0xFFEF4444))
                else if (isAnonymous && isMine)
                  _metaChip(Icons.visibility_off, 'Ẩn danh (bạn gửi)',
                      color: const Color(0xFFEF4444))
                else if (fb['senderName'] != null)
                  _metaChip(Icons.person_outline, fb['senderName']),
                if (fb['recipientName'] != null)
                  _metaChip(Icons.send_outlined,
                      'Gửi: ${fb['recipientName']}')
                else
                  _metaChip(Icons.inbox_outlined, 'Hòm thư chung'),
                _metaChip(Icons.access_time,
                    DateFormat('dd/MM/yyyy HH:mm').format(createdAt)),
              ],
            ),
            const SizedBox(height: 10),
            // Content
            Text(fb['content'] ?? '',
                style: const TextStyle(fontSize: 14, height: 1.5)),
            // Response
            if (response != null && response.isNotEmpty) ...[
              const Divider(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.reply, size: 16,
                            color: Color(0xFF059669)),
                        const SizedBox(width: 6),
                        Text(
                          'Phản hồi${respondedByName != null ? ' từ $respondedByName' : ''}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF059669)),
                        ),
                        if (respondedAt != null) ...[
                          const Spacer(),
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm')
                                .format(respondedAt),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(response,
                        style: const TextStyle(fontSize: 14, height: 1.4)),
                  ],
                ),
              ),
            ],
            // Actions
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isMine && status == 'Pending' && Provider.of<PermissionProvider>(context, listen: false).canApprove('Feedback'))
                  TextButton.icon(
                    onPressed: () => _showRespondDialog(fb),
                    icon: const Icon(Icons.reply, size: 16),
                    label: const Text('Phản hồi'),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1E3A5F)),
                  ),
                if (!isMine && (status == 'Pending' || status == 'InProgress') && Provider.of<PermissionProvider>(context, listen: false).canApprove('Feedback'))
                  TextButton.icon(
                    onPressed: () => _showRespondDialog(fb),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Cập nhật'),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF3B82F6)),
                  ),
                if (isMine && status == 'Pending' && Provider.of<PermissionProvider>(context, listen: false).canDelete('Feedback'))
                  TextButton.icon(
                    onPressed: () => _confirmDelete(fb),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Xóa'),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[500]),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color ?? Colors.grey[600])),
      ],
    );
  }

  // =========== DIALOGS ===========

  void _showCreateDialog() {
    final titleCtl = TextEditingController();
    final contentCtl = TextEditingController();
    bool isAnonymous = false;
    String category = 'General';
    String? recipientId;

    Widget buildFormContent(StateSetter setDlgState) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ẩn danh toggle
            SwitchListTile(
              title: const Text('Gửi ẩn danh'),
              subtitle: Text(isAnonymous
                  ? 'Danh tính sẽ được bảo mật'
                  : 'Người nhận sẽ biết bạn là ai'),
              value: isAnonymous,
              activeThumbColor: const Color(0xFF1E3A5F),
              secondary: Icon(
                isAnonymous ? Icons.visibility_off : Icons.visibility,
                color:
                    isAnonymous ? const Color(0xFFEF4444) : Colors.grey,
              ),
              onChanged: (v) => setDlgState(() => isAnonymous = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            // Phân loại
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(
                  labelText: 'Phân loại *',
                  border: OutlineInputBorder()),
              items: _categoryLabels.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) =>
                  setDlgState(() => category = v ?? 'General'),
            ),
            const SizedBox(height: 12),
            // Gửi đến
            DropdownButtonFormField<String>(
              initialValue: recipientId,
              decoration: const InputDecoration(
                  labelText: 'Gửi đến',
                  hintText: 'Hòm thư chung (mặc định)',
                  border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String>(
                    value: null,
                    child: Text('📧 Hòm thư chung')),
                ..._managers.map((m) {
                  final name = m['name'] ?? '';
                  final pos = m['position'] ?? '';
                  return DropdownMenuItem<String>(
                      value: m['id']?.toString(),
                      child: Text(
                          '$name${pos.isNotEmpty ? ' ($pos)' : ''}'));
                }),
              ],
              onChanged: (v) => setDlgState(() => recipientId = v),
            ),
            const SizedBox(height: 12),
            // Tiêu đề
            TextField(
              controller: titleCtl,
              decoration: const InputDecoration(
                  labelText: 'Tiêu đề *',
                  border: OutlineInputBorder()),
              maxLength: 300,
            ),
            const SizedBox(height: 12),
            // Nội dung
            TextField(
              controller: contentCtl,
              decoration: const InputDecoration(
                  labelText: 'Nội dung *',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true),
              maxLines: 5,
              maxLength: 5000,
            ),
          ],
        ),
      );
    }

    void onSubmit(BuildContext ctx) async {
      if (titleCtl.text.trim().isEmpty ||
          contentCtl.text.trim().isEmpty) {
        appNotification.showError(
            title: 'Lỗi',
            message: 'Vui lòng nhập tiêu đề và nội dung');
        return;
      }
      final res = await _apiService.createFeedback({
        'title': titleCtl.text.trim(),
        'content': contentCtl.text.trim(),
        'category': category,
        'isAnonymous': isAnonymous,
        if (recipientId != null) 'recipientEmployeeId': recipientId,
      });
      if (res['isSuccess'] == true) {
        if (ctx.mounted) Navigator.pop(ctx);
        appNotification.showSuccess(
            title: 'Thành công',
            message:
                isAnonymous ? 'Đã gửi phản ánh ẩn danh' : 'Đã gửi phản ánh');
        _loadMy();
      } else {
        appNotification.showError(
            title: 'Lỗi',
            message: res['message'] ?? 'Không thể gửi');
      }
    }

    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Gửi phản ánh / Ý kiến', overflow: TextOverflow.ellipsis, maxLines: 1),
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                body: buildFormContent(setDlgState),
                bottomNavigationBar: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => onSubmit(ctx),
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A5F)),
                          child: const Text('Gửi'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            title: const Text('Gửi phản ánh / Ý kiến'),
            content: SizedBox(
              width: 500,
              child: buildFormContent(setDlgState),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy')),
              FilledButton(
                onPressed: () => onSubmit(ctx),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F)),
                child: const Text('Gửi'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRespondDialog(Map<String, dynamic> fb) {
    final responseCtl =
        TextEditingController(text: fb['response'] ?? '');
    String status = fb['status'] ?? 'InProgress';

    Widget buildFormContent(StateSetter setDlgState) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show original feedback
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fb['title'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(fb['content'] ?? '',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF64748B))),
                  if (fb['isAnonymous'] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('🔒 Gửi ẩn danh',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFFEF4444))),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Status
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(
                  labelText: 'Trạng thái',
                  border: OutlineInputBorder()),
              items: _statusLabels.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) =>
                  setDlgState(() => status = v ?? 'InProgress'),
            ),
            const SizedBox(height: 12),
            // Response
            TextField(
              controller: responseCtl,
              decoration: const InputDecoration(
                  labelText: 'Phản hồi *',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true),
              maxLines: 4,
              maxLength: 5000,
            ),
          ],
        ),
      );
    }

    void onSubmit(BuildContext ctx) async {
      if (responseCtl.text.trim().isEmpty) {
        appNotification.showError(
            title: 'Lỗi', message: 'Vui lòng nhập nội dung phản hồi');
        return;
      }
      final res = await _apiService.respondFeedback(
          fb['id'].toString(), {
        'response': responseCtl.text.trim(),
        'status': status,
      });
      if (res['isSuccess'] == true) {
        if (ctx.mounted) Navigator.pop(ctx);
        appNotification.showSuccess(
            title: 'Thành công', message: 'Đã phản hồi');
        _loadAll();
      } else {
        appNotification.showError(
            title: 'Lỗi',
            message: res['message'] ?? 'Không thể phản hồi');
      }
    }

    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Phản hồi ý kiến'),
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                body: buildFormContent(setDlgState),
                bottomNavigationBar: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => onSubmit(ctx),
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A5F)),
                          child: const Text('Gửi phản hồi'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            title: const Text('Phản hồi ý kiến'),
            content: SizedBox(
              width: 500,
              child: buildFormContent(setDlgState),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy')),
              FilledButton(
                onPressed: () => onSubmit(ctx),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F)),
                child: const Text('Gửi phản hồi'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> fb) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Xóa phản ánh này?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (confirm == true) {
      final res =
          await _apiService.deleteFeedback(fb['id'].toString());
      if (res['isSuccess'] == true) {
        appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa');
        _loadMy();
      } else {
        appNotification.showError(
            title: 'Lỗi', message: res['message'] ?? 'Không thể xóa');
      }
    }
  }
}
