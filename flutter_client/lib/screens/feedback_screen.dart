import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/app_scroll_safe.dart';
import '../widgets/ai_assist_sheet.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/navigation_notifier.dart';
import 'feedback_detail_screen.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_fab_clearance.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';

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
  List<Map<String, dynamic>> _senders = [];
  bool _isLoading = true;
  String? _filterStatus;
  String? _filterCategory;
  String? _filterSenderId;
  /// null = tất cả; 'general' = hòm thư chung; còn lại = id người nhận
  String? _filterRecipientKey;
  DateTime? _fromDate;
  DateTime? _toDate;
  VoidCallback? _highlightListener;

  // Mobile UI state
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

  bool _isFeedbackManager() {
    final role =
        Provider.of<AuthProvider>(context, listen: false).userRole ?? '';
    final r = role.toLowerCase();
    return r == 'admin' ||
        r == 'director' ||
        r == 'manager' ||
        r == 'departmenthead' ||
        Provider.of<PermissionProvider>(context, listen: false)
            .canApprove('Feedback');
  }

  @override
  void initState() {
    super.initState();
    final preferInbox = NavigationNotifier.feedbackPreferInbox.value;
    final initialTab = preferInbox
        ? 1
        : (_isFeedbackManager() ? 1 : 0);
    _tabCtl = TabController(length: 2, vsync: this, initialIndex: initialTab);
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging) _reloadCurrentTab();
    });
    _highlightListener = () {
      if (NavigationNotifier.notificationHighlightId.value != null) {
        _consumeNotificationHighlight();
      }
    };
    NavigationNotifier.notificationHighlightId
        .addListener(_highlightListener!);
    _loadManagers();
    if (_isFeedbackManager()) _loadSenders();
    _loadBoth().then((_) {
      if (preferInbox) {
        NavigationNotifier.feedbackPreferInbox.value = false;
      }
      _consumeNotificationHighlight();
      if (NavigationNotifier.takePendingAiOpenCreate('feedback')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showCreateDialog();
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeNotificationHighlight();
    });
  }

  @override
  void dispose() {
    if (_highlightListener != null) {
      NavigationNotifier.notificationHighlightId
          .removeListener(_highlightListener!);
    }
    _tabCtl.dispose();
    super.dispose();
  }

  Future<void> _consumeNotificationHighlight() async {
    final id = NavigationNotifier.notificationHighlightId.value;
    if (id == null || id.isEmpty || !mounted) return;

    if (_myFeedbacks.isEmpty && _allFeedbacks.isEmpty) {
      await _loadBoth(showSpinner: false);
    }

    Map<String, dynamic>? fb;
    var isMine = false;
    for (final item in _myFeedbacks) {
      if (item['id']?.toString() == id) {
        fb = item;
        isMine = true;
        break;
      }
    }
    if (fb == null) {
      for (final item in _allFeedbacks) {
        if (item['id']?.toString() == id) {
          fb = item;
          break;
        }
      }
    }

    if (fb == null) {
      await _loadBoth(showSpinner: false);
      for (final item in _myFeedbacks) {
        if (item['id']?.toString() == id) {
          fb = item;
          isMine = true;
          break;
        }
      }
      if (fb == null) {
        for (final item in _allFeedbacks) {
          if (item['id']?.toString() == id) {
            fb = item;
            break;
          }
        }
      }
    }

    if (fb == null || !mounted) return;

    NavigationNotifier.notificationHighlightId.value = null;
    final targetTab = isMine ? 0 : 1;
    if (_tabCtl.index != targetTab) {
      _tabCtl.animateTo(targetTab);
    }
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    _openDetail(fb, isMine: isMine);
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

  Future<void> _loadSenders() async {
    try {
      final rows = await _apiService.getEmployeesForSelect(pageSize: 500);
      _senders = rows
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
        ..sort((a, b) {
          final na = _employeeDisplayName(a);
          final nb = _employeeDisplayName(b);
          return na.compareTo(nb);
        });
    } catch (e) {
      debugPrint('Load senders error: $e');
    }
  }

  String _employeeDisplayName(Map<String, dynamic> e) {
    final fn = '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
    if (fn.isNotEmpty) return fn;
    return e['fullName']?.toString() ?? e['name']?.toString() ?? '';
  }

  bool get _hasActiveFilters =>
      _filterStatus != null ||
      _filterCategory != null ||
      _filterSenderId != null ||
      _filterRecipientKey != null ||
      _fromDate != null ||
      _toDate != null;

  int get _activeFilterCount {
    var n = 0;
    if (_filterStatus != null) n++;
    if (_filterCategory != null) n++;
    if (_filterSenderId != null) n++;
    if (_filterRecipientKey != null) n++;
    if (_fromDate != null || _toDate != null) n++;
    return n;
  }

  void _showFilterSheet(bool showSenderFilter) {
    var status = _filterStatus;
    var category = _filterCategory;
    var senderId = _filterSenderId;
    var recipientKey = _filterRecipientKey;
    var fromDate = _fromDate;
    var toDate = _toDate;

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            16 + MediaQuery.of(ctx).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(tr('Bộ lọc'),
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (_hasActiveFilters)
                    TextButton(
                      onPressed: () {
                        setSheet(() {
                          status = null;
                          category = null;
                          senderId = null;
                          recipientKey = null;
                          fromDate = null;
                          toDate = null;
                        });
                      },
                      child: Text(tr('Xóa tất cả'),
                          style: TextStyle(color: Color(0xFFEF4444))),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildFilterDropdown(
                'Trạng thái',
                status,
                _statusLabels.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(tr(e.value))))
                    .toList(),
                (v) => setSheet(() => status = v),
              ),
              const SizedBox(height: 10),
              _buildFilterDropdown(
                'Phân loại',
                category,
                _categoryLabels.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(tr(e.value))))
                    .toList(),
                (v) => setSheet(() => category = v),
              ),
              if (showSenderFilter) ...[
                const SizedBox(height: 10),
                _buildEmployeeFilterDropdown(
                  'Người gửi',
                  senderId,
                  _senders,
                  (v) => setSheet(() => senderId = v),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('recipient-sheet-$recipientKey'),
                initialValue: recipientKey,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('Người nhận'),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                      value: null, child: Text(tr('Tất cả người nhận'))),
                  DropdownMenuItem(
                      value: 'general', child: Text(tr('Hòm thư chung'))),
                  ..._managers.map((m) {
                    final id = m['id']?.toString() ?? '';
                    final name = m['name']?.toString() ?? '';
                    return DropdownMenuItem(value: id, child: Text(tr(name)));
                  }),
                ],
                onChanged: (v) => setSheet(() => recipientKey = v),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: ctx,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: fromDate != null
                        ? DateTimeRange(
                            start: fromDate!,
                            end: toDate ?? fromDate!)
                        : null,
                    locale: appUiLocale(),
                  );
                  if (range != null) {
                    setSheet(() {
                      fromDate = range.start;
                      toDate = range.end;
                    });
                  }
                },
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  tr(fromDate != null
                      ? '${DateFormat('dd/MM/yy').format(fromDate!)} – ${DateFormat('dd/MM/yy').format(toDate ?? fromDate!)}'
                      : 'Thời gian gửi'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _filterStatus = status;
                    _filterCategory = category;
                    _filterSenderId = senderId;
                    _filterRecipientKey = recipientKey;
                    _fromDate = fromDate;
                    _toDate = toDate;
                  });
                  Navigator.pop(ctx);
                  _reloadCurrentTab();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy,
                ),
                child: Text(tr('Áp dụng')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _filterStatus = null;
      _filterCategory = null;
      _filterSenderId = null;
      _filterRecipientKey = null;
      _fromDate = null;
      _toDate = null;
    });
    _reloadCurrentTab();
  }

  ({
    String? senderEmployeeId,
    String? recipientEmployeeId,
    bool? generalMailboxOnly,
    DateTime? fromDate,
    DateTime? toDate,
  }) _filterQuery() {
    return (
      senderEmployeeId: _filterSenderId,
      recipientEmployeeId:
          _filterRecipientKey != null && _filterRecipientKey != 'general'
              ? _filterRecipientKey
              : null,
      generalMailboxOnly: _filterRecipientKey == 'general' ? true : null,
      fromDate: _fromDate,
      toDate: _toDate,
    );
  }

  Future<void> _fetchAll() async {
    final q = _filterQuery();
    final res = await _apiService.getFeedbacks(
      status: _filterStatus,
      category: _filterCategory,
      senderEmployeeId: q.senderEmployeeId,
      recipientEmployeeId: q.recipientEmployeeId,
      generalMailboxOnly: q.generalMailboxOnly,
      fromDate: q.fromDate,
      toDate: q.toDate,
    );
    if (res['isSuccess'] == true) {
      final data = res['data'];
      _allFeedbacks = List<Map<String, dynamic>>.from(data['items'] ?? []);
    } else if (mounted) {
      NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ??
              'Không thể tải danh sách phản hồi');
    }
  }

  Future<void> _fetchMy() async {
    final q = _filterQuery();
    final res = await _apiService.getMyFeedbacks(
      status: _filterStatus,
      category: _filterCategory,
      senderEmployeeId: q.senderEmployeeId,
      recipientEmployeeId: q.recipientEmployeeId,
      generalMailboxOnly: q.generalMailboxOnly,
      fromDate: q.fromDate,
      toDate: q.toDate,
    );
    if (res['isSuccess'] == true) {
      _myFeedbacks = List<Map<String, dynamic>>.from(res['data'] ?? []);
    } else if (mounted) {
      NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ??
              'Không thể tải phản hồi của bạn');
    }
  }

  Future<void> _loadBoth({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _isLoading = true);
    try {
      await Future.wait([_fetchMy(), _fetchAll()]);
    } catch (e) {
      debugPrint('Load feedback lists error: $e');
      if (mounted) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: tr('Không thể tải danh sách phản ánh'));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      await _fetchAll();
    } catch (e) {
      debugPrint('Load feedbacks error: $e');
      if (mounted) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: tr('Không thể tải danh sách phản hồi'));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMy() async {
    setState(() => _isLoading = true);
    try {
      await _fetchMy();
    } catch (e) {
      debugPrint('Load my feedbacks error: $e');
      if (mounted) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: tr('Không thể tải phản hồi của bạn'));
      }
    }
    if (mounted) setState(() => _isLoading = false);
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
    const primary = HrmPageChrome.primaryNavy;
    final hasActiveFilter = _hasActiveFilters;
    final showSenderFilter = _isFeedbackManager() && _senders.isNotEmpty;
    final canCreateFeedback = isMobile &&
        Provider.of<PermissionProvider>(context, listen: false)
            .canCreate('Feedback');

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      floatingActionButton: canCreateFeedback
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add),
              label: Text(tr('Gửi ý kiến')),
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 4,
            )
          : null,
      body: Column(
        children: [
          // ===== Compact action bar (mobile: hidden, nút lọc gộp vào TabBar) =====
          if (!isMobile)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Expanded(child: SizedBox()),
                  if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Feedback'))
                    FilledButton.icon(
                      onPressed: _showCreateDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr('Gửi ý kiến')),
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                ],
              ),
            ),
          // ===== TabBar + filter =====
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(right: isMobile ? 4 : 12),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabCtl,
                    labelColor: primary,
                    unselectedLabelColor: const Color(0xFF71717A),
                    indicatorColor: primary,
                    tabs: [
                      Tab(text: tr('Của tôi')),
                      Tab(text: tr('Hòm thư')),
                    ],
                  ),
                ),
                if (hasActiveFilter)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      label: Text(tr('$_activeFilterCount'),
                          style: const TextStyle(fontSize: 11)),
                      backgroundColor: primary.withValues(alpha: 0.1),
                      labelStyle: const TextStyle(color: primary),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                IconButton(
                  tooltip: tr('Bộ lọc'),
                  onPressed: () => _showFilterSheet(showSenderFilter),
                  icon: Badge(
                    isLabelVisible: hasActiveFilter,
                    smallSize: 8,
                    child: Icon(
                      hasActiveFilter
                          ? Icons.filter_list
                          : Icons.filter_list_outlined,
                      color: hasActiveFilter ? primary : const Color(0xFF71717A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ===== Content =====
          Expanded(
            child: TabBarView(
              controller: _tabCtl,
              children: [
                _buildFeedbackList(_myFeedbacks, isMine: true,
                    fabClearance: canCreateFeedback),
                _buildFeedbackList(_allFeedbacks, isMine: false,
                    fabClearance: canCreateFeedback),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _filterFieldWidth([double desktop = 180]) {
    if (!Responsive.isMobile(context)) return desktop;
    return MediaQuery.of(context).size.width - 28;
  }

  Widget _buildFilterDropdown(String label, String? value,
      List<DropdownMenuItem<String>> items, ValueChanged<String?> onChanged) {
    return SizedBox(
      width: _filterFieldWidth(),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        decoration: InputDecoration(
          labelText: tr(label),
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        items: [
          DropdownMenuItem<String>(value: null, child: Text(tr('Tất cả $label'))),
          ...items,
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildEmployeeFilterDropdown(
    String label,
    String? value,
    List<Map<String, dynamic>> employees,
    ValueChanged<String?> onChanged,
  ) {
    return SizedBox(
      width: _filterFieldWidth(200),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: tr(label),
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        items: [
          DropdownMenuItem<String>(
              value: null, child: Text(tr('Tất cả $label'))),
          ...employees.map((e) {
            final id = e['id']?.toString() ?? '';
            final name = _employeeDisplayName(e);
            final code = e['employeeCode']?.toString() ?? '';
            return DropdownMenuItem<String>(
              value: id,
              child: Text(
                tr(code.isNotEmpty ? '$name ($code)' : name),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFeedbackList(List<Map<String, dynamic>> list,
      {required bool isMine, bool fabClearance = false}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      final empty = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              tr(_hasActiveFilters
                  ? 'Không có phản ánh phù hợp bộ lọc'
                  : (isMine
                      ? 'Bạn chưa gửi phản ánh nào'
                      : 'Chưa có phản ánh nào')),
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
            if (_hasActiveFilters) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: _clearFilters, child: Text(tr('Xóa bộ lọc'))),
            ],
          ],
        ),
      );
      if (fabClearance) {
        return HrmFabClearance(
          fabVisible: true,
          extendedFab: true,
          child: empty,
        );
      }
      return empty;
    }

    return RefreshIndicator(
      onRefresh: () async => _reloadCurrentTab(),
      child: ListView.builder(
        padding: Responsive.fabListInsets(
          context,
          base: const EdgeInsets.all(16),
          extendedFab: fabClearance,
        ),
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
    final replyCount = fb['replyCount'] ?? 0;

    return GestureDetector(
      onTap: () => _openDetail(fb, isMine: isMine),
      child: Container(
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
                    size: 20, color: HrmPageChrome.primaryNavy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr(fb['title'] ?? ''),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Flexible(
                  child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_statusColors[status] ?? Colors.grey)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tr(_statusLabels[status] ?? status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _statusColors[status] ?? Colors.grey,
                    ),
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
            Text(tr(fb['content'] ?? ''),
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
                        Text(tr('${tr('Phản hồi')}${respondedByName != null ? ' từ $respondedByName' : ''}'),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF059669)),
                        ),
                        if (respondedAt != null) ...[
                          const Spacer(),
                          Text(
                            tr(DateFormat('dd/MM/yyyy HH:mm')
                                .format(respondedAt)),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(tr(response),
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
                // Reply count badge
                if (replyCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline, size: 14, color: Color(0xFF3B82F6)),
                        const SizedBox(width: 4),
                        Text(tr('$replyCount phản hồi'),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF3B82F6), fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openDetail(fb, isMine: isMine),
                  icon: const Icon(Icons.chat_outlined, size: 16),
                  label: Text(tr('Xem / Trả lời')),
                  style: TextButton.styleFrom(
                      foregroundColor: HrmPageChrome.primaryNavy),
                ),
                if (Provider.of<PermissionProvider>(context, listen: false)
                    .canDelete('Feedback'))
                  TextButton.icon(
                    onPressed: () => _confirmDelete(fb),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(tr('Xóa')),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444)),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),  // close GestureDetector
    );
  }

  void _openDetail(Map<String, dynamic> fb, {required bool isMine}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeedbackDetailScreen(
          feedbackId: fb['id']?.toString() ?? '',
          isMine: isMine,
        ),
      ),
    );
    // Reload after returning from detail
    _reloadCurrentTab();
  }

  Widget _metaChip(IconData icon, String label, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[500]),
        const SizedBox(width: 4),
        Text(tr(label),
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
              title: Text(tr('Gửi ẩn danh')),
              subtitle: Text(tr(isAnonymous
                  ? 'Danh tính sẽ được bảo mật'
                  : 'Người nhận sẽ biết bạn là ai')),
              value: isAnonymous,
              activeThumbColor: HrmPageChrome.primaryNavy,
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
              decoration: InputDecoration(
                  labelText: tr('Phân loại *'),
                  border: OutlineInputBorder()),
              items: _categoryLabels.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(tr(e.value))))
                  .toList(),
              onChanged: (v) =>
                  setDlgState(() => category = v ?? 'General'),
            ),
            const SizedBox(height: 12),
            // Gửi đến
            DropdownButtonFormField<String>(
              initialValue: recipientId,
              decoration: InputDecoration(
                  labelText: tr('Gửi đến'),
                  hintText: tr('Hòm thư chung (mặc định)'),
                  border: OutlineInputBorder()),
              items: [
                DropdownMenuItem<String>(
                    value: null,
                    child: Text(tr('📧 Hòm thư chung'))),
                ..._managers.map((m) {
                  final name = m['name'] ?? '';
                  final pos = m['position'] ?? '';
                  return DropdownMenuItem<String>(
                      value: m['id']?.toString(),
                      child: Text(
                          tr('$name${pos.isNotEmpty ? ' ($pos)' : ''}')));
                }),
              ],
              onChanged: (v) => setDlgState(() => recipientId = v),
            ),
            const SizedBox(height: 12),
            // Tiêu đề
            TextField(
              controller: titleCtl,
              decoration: InputDecoration(
                  labelText: tr('Tiêu đề *'),
                  border: const OutlineInputBorder(),
                  suffixIcon: AiAssistIconButton(
                    kind: 'feedback',
                    title: 'AI gợi ý tiêu đề',
                    targetController: titleCtl,
                    tooltip: tr('AI gợi ý tiêu đề'),
                    contextBuilder: () =>
                        'Phân loại: ${_categoryLabels[category] ?? category}. '
                        'Gợi ý 1 tiêu đề ngắn gọn (tối đa 100 ký tự) cho phản ánh này. '
                        'Chỉ trả về tiêu đề, không có dấu ngoặc kép, không giải thích.',
                  )),
              maxLength: 300,
            ),
            const SizedBox(height: 12),
            // Nội dung
            TextField(
              controller: contentCtl,
              decoration: InputDecoration(
                  labelText: tr('Nội dung *'),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                  suffixIcon: AiAssistIconButton(
                    kind: 'feedback',
                    title: 'AI soạn phản ánh',
                    targetController: contentCtl,
                    tooltip: tr('AI soạn phản ánh'),
                    contextBuilder: () =>
                        'Phân loại: ${_categoryLabels[category] ?? category}. '
                        '${titleCtl.text.trim().isNotEmpty ? 'Tiêu đề: ${titleCtl.text.trim()}. ' : ''}'
                        'Viết nội dung phản ánh/ý kiến đầy đủ, có đề xuất giải pháp.',
                  )),
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
            message: tr('Vui lòng nhập tiêu đề và nội dung'));
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
        if (_tabCtl.index != 0) _tabCtl.animateTo(0);
        _loadBoth();
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
                  title: Text(tr('Gửi phản ánh / Ý kiến'), overflow: TextOverflow.ellipsis, maxLines: 1),
                  backgroundColor: HrmPageChrome.primaryNavy,
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
                          child: Text(tr('Hủy')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => onSubmit(ctx),
                          style: FilledButton.styleFrom(
                              backgroundColor: HrmPageChrome.primaryNavy),
                          child: Text(tr('Gửi')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Gửi phản ánh / Ý kiến')),
            content: SizedBox(
              width: 500,
              child: buildFormContent(setDlgState),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Hủy'))),
              FilledButton(
                onPressed: () => onSubmit(ctx),
                style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy),
                child: Text(tr('Gửi')),
              ),
            ],
          );
        },
      ),
    );
  }

  // ignore: unused_element
  void _showRespondDialog(Map<String, dynamic> fb) {
    final responseCtl =
        TextEditingController(text: tr(fb['response'] ?? ''));
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
                  Text(tr(fb['title'] ?? ''),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(tr(fb['content'] ?? ''),
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF64748B))),
                  if (fb['isAnonymous'] == true)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(tr('🔒 Gửi ẩn danh'),
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
              decoration: InputDecoration(
                  labelText: tr('Trạng thái'),
                  border: OutlineInputBorder()),
              items: _statusLabels.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(tr(e.value))))
                  .toList(),
              onChanged: (v) =>
                  setDlgState(() => status = v ?? 'InProgress'),
            ),
            const SizedBox(height: 12),
            // Response
            TextField(
              controller: responseCtl,
              decoration: InputDecoration(
                  labelText: tr('Phản hồi *'),
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
            title: 'Lỗi', message: tr('Vui lòng nhập nội dung phản hồi'));
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
            title: 'Thành công', message: tr('Đã phản hồi'));
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
                  title: Text(tr('Phản hồi ý kiến')),
                  backgroundColor: HrmPageChrome.primaryNavy,
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
                          child: Text(tr('Hủy')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => onSubmit(ctx),
                          style: FilledButton.styleFrom(
                              backgroundColor: HrmPageChrome.primaryNavy),
                          child: Text(tr('Gửi phản hồi')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Phản hồi ý kiến')),
            content: SizedBox(
              width: 500,
              child: buildFormContent(setDlgState),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Hủy'))),
              FilledButton(
                onPressed: () => onSubmit(ctx),
                style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy),
                child: Text(tr('Gửi phản hồi')),
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
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Xác nhận xóa')),
        content: Text(tr('Xóa phản ánh này?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(tr('Xóa'))),
        ],
      ),
    );
    if (confirm == true) {
      final res =
          await _apiService.deleteFeedback(fb['id'].toString());
      if (res['isSuccess'] == true) {
        appNotification.showSuccess(title: 'Thành công', message: tr('Đã xóa'));
        _loadMy();
      } else {
        appNotification.showError(
            title: 'Lỗi', message: res['message'] ?? 'Không thể xóa');
      }
    }
  }
}
