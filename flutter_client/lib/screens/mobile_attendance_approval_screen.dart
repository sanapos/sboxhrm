import 'package:flutter/material.dart';
import '../widgets/app_scroll_safe.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../models/mobile_attendance.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/mobile_attendance_record_detail_sheet.dart';
import '../widgets/punch_photo_preview.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../utils/attendance_correction_privilege.dart';

class MobileAttendanceApprovalScreen extends StatefulWidget {
  /// Nhúng trong [AttendanceApprovalScreen] (TabBarView cha) — tránh NestedScrollView lồng nhau.
  final bool embeddedInParentTab;

  const MobileAttendanceApprovalScreen({
    super.key,
    this.embeddedInParentTab = false,
  });

  @override
  State<MobileAttendanceApprovalScreen> createState() =>
      _MobileAttendanceApprovalScreenState();
}

class _MobileAttendanceApprovalScreenState
    extends State<MobileAttendanceApprovalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  List<MobileAttendanceRecord> _pendingRecords = [];
  List<MobileAttendanceRecord> _approvedRecords = [];
  List<MobileAttendanceRecord> _rejectedRecords = [];
  int _currentPage = 1;
  final int _pageSize = 20;
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employeesList = [];

  List<MobileAttendanceRecord> get _filteredPendingRecords {
    if (_selectedBranchId == null) return _pendingRecords;
    final ids = _employeesList
        .where((e) => e['branchId']?.toString() == _selectedBranchId)
        .map((e) => e['id']?.toString() ?? '')
        .toSet();
    return _pendingRecords
        .where((r) => ids.contains(r.odooEmployeeId))
        .toList();
  }

  List<MobileAttendanceRecord> get _filteredApprovedRecords {
    if (_selectedBranchId == null) return _approvedRecords;
    final ids = _employeesList
        .where((e) => e['branchId']?.toString() == _selectedBranchId)
        .map((e) => e['id']?.toString() ?? '')
        .toSet();
    return _approvedRecords
        .where((r) => ids.contains(r.odooEmployeeId))
        .toList();
  }

  List<MobileAttendanceRecord> get _filteredRejectedRecords {
    if (_selectedBranchId == null) return _rejectedRecords;
    final ids = _employeesList
        .where((e) => e['branchId']?.toString() == _selectedBranchId)
        .map((e) => e['id']?.toString() ?? '')
        .toSet();
    return _rejectedRecords
        .where((r) => ids.contains(r.odooEmployeeId))
        .toList();
  }

  // Summary tab state
  DateTime _summaryFrom = DateTime.now().subtract(const Duration(days: 6));
  DateTime _summaryTo = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() => _currentPage = 1);
    });
    _loadData();
    _loadBranchData();
  }

  Future<void> _loadBranchData() async {
    try {
      final emps = await _apiService.getEmployeesForSelect(pageSize: 1000);
      if (mounted) {
        setState(() => _employeesList =
            emps.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
    try {
      final br = await _apiService.getBranchesForSelect();
      final bd = br['data'];
      if (bd is List && mounted) {
        setState(() => _branches =
            bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 30));
      final to = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final pendingResult = await _apiService.getPendingMobileAttendance();
      final historyResult = await _apiService.getMobileAttendanceHistory(
        fromDate: from,
        toDate: to,
      );

      if (mounted) {
        setState(() {
          if (pendingResult['isSuccess'] == true &&
              pendingResult['data'] != null) {
            final items = pendingResult['data'] is List
                ? pendingResult['data'] as List
                : (pendingResult['data']['items'] ?? []) as List;
            _pendingRecords = items
                .map((e) => MobileAttendanceRecord.fromJson(
                    e is Map<String, dynamic>
                        ? e
                        : Map<String, dynamic>.from(e)))
                .toList();
          } else {
            _pendingRecords = [];
          }

          if (historyResult['isSuccess'] == true &&
              historyResult['data'] != null) {
            final items = historyResult['data'] is List
                ? historyResult['data'] as List
                : (historyResult['data']['items'] ?? []) as List;
            final allRecords = items
                .map((e) => MobileAttendanceRecord.fromJson(
                    e is Map<String, dynamic>
                        ? e
                        : Map<String, dynamic>.from(e)))
                .toList();
            _approvedRecords = allRecords
                .where((r) =>
                    r.status == 'approved' || r.status == 'auto_approved')
                .toList();
            _rejectedRecords =
                allRecords.where((r) => r.status == 'rejected').toList();
          } else {
            _approvedRecords = [];
            _rejectedRecords = [];
          }
        });
      }

      final pendingOk = pendingResult['isSuccess'] == true;
      final historyOk = historyResult['isSuccess'] == true;
      if (mounted && (!pendingOk || !historyOk)) {
        final msg = !pendingOk && !historyOk
            ? (pendingResult['message'] ?? historyResult['message'] ?? '')
                .toString()
            : (!pendingOk
                ? pendingResult['message']?.toString()
                : historyResult['message']?.toString());
        appNotification.showError(
          title: 'Lỗi',
          message: msg != null && msg.isNotEmpty
              ? msg
              : 'Không thể tải dữ liệu chấm công mobile',
        );
      }
    } catch (e) {
      debugPrint('Error loading mobile attendance data: $e');
      if (mounted) {
        appNotification.showError(
            title: 'Lỗi', message: 'Không thể tải dữ liệu chấm công mobile');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  TabBar _buildApprovalTabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: HrmPageChrome.primaryNavy,
      unselectedLabelColor: const Color(0xFF71717A),
      indicatorColor: HrmPageChrome.primaryNavy,
      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      tabs: [
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pending_actions, size: 18),
              const SizedBox(width: 6),
              const Text('Chờ duyệt'),
              if (_filteredPendingRecords.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_filteredPendingRecords.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 18),
              SizedBox(width: 6),
              Text('Đã duyệt'),
            ],
          ),
        ),
        const Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cancel, size: 18),
              SizedBox(width: 6),
              Text('Từ chối'),
            ],
          ),
        ),
        const Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.table_chart, size: 18),
              SizedBox(width: 6),
              Text('Tổng hợp'),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabBarView = TabBarView(
      controller: _tabController,
      children: _isLoading
          ? List.generate(
              4,
              (_) => const Center(child: CircularProgressIndicator()),
            )
          : [
              _buildPendingTab(),
              _buildApprovedTab(),
              _buildRejectedTab(),
              _buildSummaryTab(),
            ],
    );

    final tabBarRow = Container(
      color: Colors.white,
      child: Row(
        children: [
          Expanded(child: _buildApprovalTabBar()),
          IconButton(
            tooltip: 'Bộ lọc',
            icon: const Icon(Icons.filter_list, color: Color(0xFF71717A)),
            onPressed: _showFilterDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tabBarRow,
        Expanded(child: tabBarView),
      ],
    );

    if (widget.embeddedInParentTab) {
      return ColoredBox(
        color: HrmPageChrome.background,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: body,
    );
  }

  Widget _buildPendingTab() {
    if (_filteredPendingRecords.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Không có yêu cầu chờ duyệt',
        subtitle:
            'Chấm công tự động duyệt nằm ở tab «Đã duyệt», không hiển thị ở đây',
      );
    }

    final totalCount = _filteredPendingRecords.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedRecords = _filteredPendingRecords.sublist(
        startIndex.clamp(0, totalCount), endIndex);

    Widget recordTile(int index) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
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
            child: _buildPendingDeckItem(paginatedRecords[index]),
          ),
        );

    final pager = totalPages > 1
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Hiển thị ${startIndex + 1}-$endIndex / $totalCount',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Row(children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: page > 1
                          ? () => setState(() => _currentPage--)
                          : null,
                      visualDensity: VisualDensity.compact),
                  Text('$page / $totalPages',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500)),
                  IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: page < totalPages
                          ? () => setState(() => _currentPage++)
                          : null,
                      visualDensity: VisualDensity.compact),
                ]),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Column(
      children: [
        _buildBulkActions(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: paginatedRecords.length,
            itemBuilder: (_, index) => recordTile(index),
          ),
        ),
        pager,
      ],
    );
  }

  Widget _buildBulkActions() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${_filteredPendingRecords.length} yêu cầu chờ duyệt',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF18181B),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canApproveMobileAttendance(
                  Provider.of<PermissionProvider>(context, listen: false)))
                OutlinedButton.icon(
                  onPressed: () => _bulkAction(false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Từ chối tất cả'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              const SizedBox(width: 8),
              if (canApproveMobileAttendance(
                  Provider.of<PermissionProvider>(context, listen: false)))
                FilledButton.icon(
                  onPressed: () => _bulkAction(true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Duyệt tất cả'),
                  style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openRecordDetail(
    MobileAttendanceRecord record, {
    Future<void> Function(MobileAttendanceRecord)? onApprove,
    Future<void> Function(MobileAttendanceRecord)? onReject,
  }) {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canApprove = canApproveMobileAttendance(perm) &&
        record.status == 'pending' &&
        onApprove != null &&
        onReject != null;
    final canManage = canEditMobileAttendanceRecord(perm) ||
        canDeleteMobileAttendanceRecord(perm);

    showMobileAttendanceRecordDetailSheet(
      context,
      record: record,
      apiService: _apiService,
      onApprove: canApprove ? () => onApprove(record) : null,
      onReject: canApprove ? () => onReject(record) : null,
      canManageRecord: canManage,
      canEditRecord: canEditMobileAttendanceRecord(perm),
      canDeleteRecord: canDeleteMobileAttendanceRecord(perm),
      onRecordChanged: _loadData,
    );
  }

  Widget _buildPendingDeckItem(MobileAttendanceRecord record) {
    final isCheckIn = record.punchType == 0;
    final time =
        '${record.punchTime.hour.toString().padLeft(2, '0')}:${record.punchTime.minute.toString().padLeft(2, '0')}';
    final date =
        '${record.punchTime.day}/${record.punchTime.month}/${record.punchTime.year}';
    return InkWell(
      onTap: () => _openRecordDetail(record, onApprove: _approveRecord, onReject: _rejectRecord),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            MobilePunchPhotoThumb(
              sitePhotoUrl: record.sitePhotoUrl,
              faceImageUrl: null,
              apiService: _apiService,
              sitePhotoOnly: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.employeeName,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF18181B)),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '$time · $date · ${record.punchTypeLabel} · ${record.formattedDistanceFromLocation} · ${record.faceMatchScore?.toStringAsFixed(0) ?? '0'}%',
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isCheckIn
                        ? HrmPageChrome.primaryNavy
                        : const Color(0xFFEF4444))
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(record.punchTypeLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isCheckIn
                          ? HrmPageChrome.primaryNavy
                          : const Color(0xFFEF4444))),
            ),
            const SizedBox(width: 8),
            if (canApproveMobileAttendance(
                Provider.of<PermissionProvider>(context, listen: false)))
              InkWell(
                onTap: () => _rejectRecord(record),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.close, size: 18, color: Color(0xFFEF4444))),
              ),
            const SizedBox(width: 4),
            if (canApproveMobileAttendance(
                Provider.of<PermissionProvider>(context, listen: false)))
              InkWell(
                onTap: () => _approveRecord(record),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.check, size: 18, color: HrmPageChrome.primaryNavy)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryDeckItem(MobileAttendanceRecord record, bool isApproved) {
    final isCheckIn = record.punchType == 0;
    final time =
        '${record.punchTime.hour.toString().padLeft(2, '0')}:${record.punchTime.minute.toString().padLeft(2, '0')}';
    final date = '${record.punchTime.day}/${record.punchTime.month}';
    return InkWell(
      onTap: () => _openRecordDetail(record),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            MobilePunchPhotoThumb(
              sitePhotoUrl: null,
              faceImageUrl: null,
              apiService: _apiService,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.employeeName,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF18181B)),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '$time · $date · ${record.punchTypeLabel} · ${record.approvedBy ?? 'N/A'}',
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isApproved
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444))
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isApproved
                    ? (record.status == 'auto_approved'
                        ? 'Tự động duyệt'
                        : 'Đã duyệt')
                    : 'Từ chối',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isApproved
                        ? (record.status == 'auto_approved'
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF22C55E))
                        : const Color(0xFFEF4444)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryListTab({
    required List<MobileAttendanceRecord> records,
    required bool isApproved,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    if (records.isEmpty) {
      return _buildEmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }

    final totalCount = records.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedRecords =
        records.sublist(startIndex.clamp(0, totalCount), endIndex);

    Widget recordTile(int index) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
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
            child: _buildHistoryDeckItem(paginatedRecords[index], isApproved),
          ),
        );

    final pager = totalPages > 1
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Hiển thị ${startIndex + 1}-$endIndex / $totalCount',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Row(children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: page > 1
                          ? () => setState(() => _currentPage--)
                          : null,
                      visualDensity: VisualDensity.compact),
                  Text('$page / $totalPages',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500)),
                  IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: page < totalPages
                          ? () => setState(() => _currentPage++)
                          : null,
                      visualDensity: VisualDensity.compact),
                ]),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: paginatedRecords.length,
            itemBuilder: (_, index) => recordTile(index),
          ),
        ),
        pager,
      ],
    );
  }

  Widget _buildApprovedTab() {
    return _buildHistoryListTab(
      records: _filteredApprovedRecords,
      isApproved: true,
      emptyIcon: Icons.check_circle,
      emptyTitle: 'Chưa có chấm công được duyệt',
      emptySubtitle:
          'Gồm duyệt thủ công và tự động duyệt (30 ngày gần nhất)',
    );
  }

  Widget _buildRejectedTab() {
    return _buildHistoryListTab(
      records: _filteredRejectedRecords,
      isApproved: false,
      emptyIcon: Icons.cancel,
      emptyTitle: 'Chưa có chấm công bị từ chối',
      emptySubtitle: 'Các chấm công bị từ chối sẽ hiển thị ở đây',
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF71717A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFA1A1AA),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveRecord(MobileAttendanceRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận duyệt'),
        content: Text(
            'Bạn có chắc muốn duyệt chấm công của ${record.employeeName}?\n\nSau khi duyệt, dữ liệu sẽ được thêm vào chấm công chi tiết.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: HrmPageChrome.primaryNavy,
            ),
            child: const Text('Duyệt'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final result = await _apiService.approveMobileAttendance(
          recordId: record.id,
          approved: true,
        );
        if (result['isSuccess'] == true) {
          await _loadData();
          if (!mounted) return;
          NotificationOverlayManager().showSuccess(
              title: 'Thành công',
              message: 'Đã duyệt và thêm vào chấm công chi tiết');
        } else {
          if (!mounted) return;
          appNotification.showError(
              title: 'Lỗi', message: result['message'] ?? 'Không thể duyệt');
        }
      } catch (e) {
        if (!mounted) return;
        appNotification.showError(title: 'Lỗi', message: 'Lỗi kết nối: $e');
      }
    }
  }

  Future<void> _rejectRecord(MobileAttendanceRecord record) async {
    final reasonController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Từ chối chấm công'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Từ chối chấm công của ${record.employeeName}'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Lý do từ chối',
                  hintText: 'Nhập lý do...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reasonController.text),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final apiResult = await _apiService.approveMobileAttendance(
          recordId: record.id,
          approved: false,
          rejectionReason: result.isNotEmpty ? result : 'Không đủ điều kiện',
        );
        if (apiResult['isSuccess'] == true) {
          await _loadData();
          if (!mounted) return;
          NotificationOverlayManager()
              .showInfo(title: 'Từ chối', message: 'Đã từ chối chấm công');
        } else {
          if (!mounted) return;
          appNotification.showError(
              title: 'Lỗi',
              message: apiResult['message'] ?? 'Không thể từ chối');
        }
      } catch (e) {
        if (!mounted) return;
        appNotification.showError(title: 'Lỗi', message: 'Lỗi kết nối: $e');
      }
    }
    reasonController.dispose();
  }

  void _bulkAction(bool approve) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(approve ? 'Duyệt tất cả' : 'Từ chối tất cả'),
        content: Text(
          approve
              ? 'Bạn có chắc muốn duyệt tất cả ${_pendingRecords.length} yêu cầu?\n\nTất cả sẽ được thêm vào chấm công chi tiết.'
              : 'Bạn có chắc muốn từ chối tất cả ${_pendingRecords.length} yêu cầu?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  approve ? HrmPageChrome.primaryNavy : const Color(0xFFEF4444),
            ),
            child: Text(approve ? 'Duyệt tất cả' : 'Từ chối tất cả'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final records = List<MobileAttendanceRecord>.from(_pendingRecords);
      int successCount = 0;
      int failCount = 0;

      for (var record in records) {
        try {
          final result = await _apiService.approveMobileAttendance(
            recordId: record.id,
            approved: approve,
            rejectionReason: approve ? null : 'Từ chối hàng loạt',
          );
          if (result['isSuccess'] == true) {
            successCount++;
          } else {
            failCount++;
          }
        } catch (_) {
          failCount++;
        }
      }

      await _loadData();

      if (!mounted) return;
      if (failCount > 0) {
        appNotification.showWarning(
          title: 'Hoàn tất',
          message: 'Thành công: $successCount, Thất bại: $failCount',
        );
      } else {
        if (approve) {
          NotificationOverlayManager().showSuccess(
              title: 'Thành công', message: 'Đã duyệt $successCount yêu cầu');
        } else {
          NotificationOverlayManager().showInfo(
              title: 'Từ chối', message: 'Đã từ chối $successCount yêu cầu');
        }
      }
    }
  }

  // ─── Summary tab helpers ──────────────────────────────────────────────

  List<DateTime> get _summaryDays {
    final days = <DateTime>[];
    var d = DateTime(_summaryFrom.year, _summaryFrom.month, _summaryFrom.day);
    final end = DateTime(_summaryTo.year, _summaryTo.month, _summaryTo.day);
    while (!d.isAfter(end)) {
      days.add(d);
      d = d.add(const Duration(days: 1));
    }
    return days;
  }

  List<String> get _summaryEmployees {
    final all = [..._approvedRecords, ..._pendingRecords, ..._rejectedRecords];
    final seen = <String>{};
    for (final r in all) {
      seen.add(r.employeeName);
    }
    return seen.toList()..sort();
  }

  // approved + auto_approved only
  List<MobileAttendanceRecord> get _summaryApproved => _approvedRecords
      .where((r) => r.status == 'approved' || r.status == 'auto_approved')
      .toList();

  /// Returns records for given employee & date (local date)
  List<MobileAttendanceRecord> _recordsFor(String emp, DateTime day) {
    return _summaryApproved.where((r) {
      final local = r.punchTime.toLocal();
      return r.employeeName == emp &&
          local.year == day.year &&
          local.month == day.month &&
          local.day == day.day;
    }).toList();
  }

  String _dayLabel(DateTime d) {
    const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final weekday = d.weekday; // 1=Mon … 7=Sun
    return '${days[weekday - 1]}\n${DateFormat('dd/MM').format(d)}';
  }

  Widget _buildSummaryTab() {
    final days = _summaryDays;
    final employees = _summaryEmployees;

    Widget dateRangeBar() => Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.date_range, size: 16, color: HrmPageChrome.primaryNavy),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                      initialDateRange:
                          DateTimeRange(start: _summaryFrom, end: _summaryTo),
                      locale: const Locale('vi'),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(
                          colorScheme: const ColorScheme.light(
                              primary: HrmPageChrome.primaryNavy),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setState(() {
                        _summaryFrom = picked.start;
                        _summaryTo = picked.end;
                      });
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${DateFormat('dd/MM/yyyy').format(_summaryFrom)} – ${DateFormat('dd/MM/yyyy').format(_summaryTo)}',
                      style: const TextStyle(
                          fontSize: 13,
                          color: HrmPageChrome.primaryNavy,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

    if (employees.isEmpty || days.isEmpty) {
      return Column(
        children: [
          dateRangeBar(),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.table_chart, size: 56, color: Color(0xFFE4E4E7)),
                  SizedBox(height: 12),
                  Text('Chưa có dữ liệu',
                      style: TextStyle(color: Color(0xFF71717A))),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // ── cell builders ──────────────────────────────────────────────────────
    Widget attendanceCell(String emp, DateTime day) {
      final recs = _recordsFor(emp, day);
      if (recs.isEmpty) {
        return const Center(
            child: Text('—',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13)));
      }
      final hasIn = recs.any((r) => r.punchType == 0);
      final hasOut = recs.any((r) => r.punchType == 1);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasIn)
              const Icon(Icons.login, size: 14, color: Color(0xFF22C55E)),
            if (hasOut)
              const Icon(Icons.logout, size: 14, color: Color(0xFF3B82F6)),
            if (!hasIn && !hasOut)
              const Icon(Icons.circle, size: 8, color: Color(0xFFF59E0B)),
          ],
        ),
      );
    }

    Widget hoursCell(String emp, DateTime day) {
      final recs = _recordsFor(emp, day);
      if (recs.isEmpty) {
        return const Center(
            child: Text('—',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13)));
      }
      final ins = recs
          .where((r) => r.punchType == 0)
          .map((r) => r.punchTime.toLocal())
          .toList()
        ..sort();
      final outs = recs
          .where((r) => r.punchType == 1)
          .map((r) => r.punchTime.toLocal())
          .toList()
        ..sort();
      if (ins.isEmpty || outs.isEmpty) {
        return Center(
          child: Text(
            ins.isNotEmpty
                ? 'V ${DateFormat('HH:mm').format(ins.first)}'
                : 'R ${DateFormat('HH:mm').format(outs.first)}',
            style: const TextStyle(fontSize: 10, color: Color(0xFFF59E0B)),
            textAlign: TextAlign.center,
          ),
        );
      }
      final diff = outs.last.difference(ins.first);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return Center(
        child: Text(
          '$h:${m.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: h >= 8
                ? const Color(0xFF22C55E)
                : (h >= 4 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
          ),
        ),
      );
    }

    const legend = Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 12,
        children: [
          _LegendItem(
              icon: Icons.login, color: Color(0xFF22C55E), label: 'Vào'),
          _LegendItem(
              icon: Icons.logout, color: Color(0xFF3B82F6), label: 'Ra'),
          _LegendItem(
              icon: Icons.circle,
              color: Color(0xFFF59E0B),
              label: 'Thiếu lượt'),
        ],
      ),
    );

    return Column(
      children: [
        dateRangeBar(),
        Container(color: Colors.white, child: legend),
        const Divider(height: 1),
        Expanded(
          child: _SyncScrollTables(
            days: days,
            employees: employees,
            dayLabel: _dayLabel,
            attendanceCellBuilder: attendanceCell,
            hoursCellBuilder: hoursCell,
          ),
        ),
      ],
    );
  }

  void _showFilterDialog() {
    showAppSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Lọc chi nhánh',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B))),
            const SizedBox(height: 16),
            if (_branches.isEmpty)
              const Text('Không có chi nhánh')
            else ...[
              ListTile(
                title: const Text('Tất cả chi nhánh'),
                leading: const Icon(Icons.all_inclusive),
                selected: _selectedBranchId == null,
                onTap: () {
                  setState(() => _selectedBranchId = null);
                  Navigator.pop(ctx);
                },
              ),
              ..._branches.map((b) => ListTile(
                    title: Text(b['name']?.toString() ?? ''),
                    leading: const Icon(Icons.account_tree_outlined),
                    selected: _selectedBranchId == b['id']?.toString(),
                    onTap: () {
                      setState(() => _selectedBranchId = b['id']?.toString());
                      Navigator.pop(ctx);
                    },
                  )),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ─── Legend item ──────────────────────────────────────────────────────────────
class _LegendItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _LegendItem(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF52525B))),
        ],
      );
}

// ─── Synchronised-scroll two-table widget ─────────────────────────────────────
class _SyncScrollTables extends StatefulWidget {
  final List<DateTime> days;
  final List<String> employees;
  final String Function(DateTime) dayLabel;
  final Widget Function(String, DateTime) attendanceCellBuilder;
  final Widget Function(String, DateTime) hoursCellBuilder;

  const _SyncScrollTables({
    required this.days,
    required this.employees,
    required this.dayLabel,
    required this.attendanceCellBuilder,
    required this.hoursCellBuilder,
  });

  @override
  State<_SyncScrollTables> createState() => _SyncScrollTablesState();
}

class _SyncScrollTablesState extends State<_SyncScrollTables> {
  late final ScrollController _attScroll;
  late final ScrollController _hrsScroll;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _attScroll = ScrollController();
    _hrsScroll = ScrollController();
    _attScroll.addListener(_syncFromAtt);
    _hrsScroll.addListener(_syncFromHrs);
  }

  void _syncFromAtt() {
    if (_syncing) return;
    _syncing = true;
    if (_hrsScroll.hasClients) _hrsScroll.jumpTo(_attScroll.offset);
    _syncing = false;
  }

  void _syncFromHrs() {
    if (_syncing) return;
    _syncing = true;
    if (_attScroll.hasClients) _attScroll.jumpTo(_hrsScroll.offset);
    _syncing = false;
  }

  @override
  void dispose() {
    _attScroll.removeListener(_syncFromAtt);
    _hrsScroll.removeListener(_syncFromHrs);
    _attScroll.dispose();
    _hrsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildTable(
            title: 'BẢNG ĐIỂM DANH',
            titleColor: const Color(0xFF16A34A),
            cellBuilder: widget.attendanceCellBuilder,
            scrollCtrl: _attScroll,
          ),
          const SizedBox(height: 8),
          _buildTable(
            title: 'BẢNG GIỜ LÀM',
            titleColor: const Color(0xFF2563EB),
            cellBuilder: widget.hoursCellBuilder,
            scrollCtrl: _hrsScroll,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTable({
    required String title,
    required Color titleColor,
    required Widget Function(String, DateTime) cellBuilder,
    required ScrollController scrollCtrl,
  }) {
    final days = widget.days;
    final employees = widget.employees;
    const empColW = 130.0;
    const dayColW = 64.0;
    const rowH = 44.0;
    const headerH = 52.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // section title bar
        Container(
          color: titleColor.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Container(
                width: 3,
                height: 14,
                color: titleColor,
                margin: const EdgeInsets.only(right: 6)),
            Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: titleColor)),
          ]),
        ),
        // main table: frozen col + horizontally scrollable body
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Frozen employee column ────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header cell
                  Container(
                    width: empColW,
                    height: headerH,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(
                      color: HrmPageChrome.primaryNavy,
                      border: Border(
                          right: BorderSide(color: Colors.white24, width: 1),
                          bottom:
                              BorderSide(color: Colors.white24, width: 0.5)),
                    ),
                    child: const Text('Nhân viên',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  // Employee name cells
                  ...employees.asMap().entries.map((e) {
                    final isEven = e.key.isEven;
                    return Container(
                      width: empColW,
                      height: rowH,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isEven ? const Color(0xFFF4F4F5) : Colors.white,
                        border: const Border(
                          right: BorderSide(color: Color(0xFFD4D4D8)),
                          bottom:
                              BorderSide(color: Color(0xFFE4E4E7), width: 0.5),
                        ),
                      ),
                      child: Text(e.value,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF18181B)),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2),
                    );
                  }),
                ],
              ),
              // ── Scrollable date area ───────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: dayColW * days.length,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Day header row
                        Row(
                          children: days.map((d) {
                            final isToday = d.year == DateTime.now().year &&
                                d.month == DateTime.now().month &&
                                d.day == DateTime.now().day;
                            return Container(
                              width: dayColW,
                              height: headerH,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isToday
                                    ? const Color(0xFF2563EB)
                                    : HrmPageChrome.primaryNavy,
                                border: const Border(
                                    right: BorderSide(
                                        color: Colors.white12, width: 0.5),
                                    bottom: BorderSide(
                                        color: Colors.white24, width: 0.5)),
                              ),
                              child: Text(
                                widget.dayLabel(d),
                                style: TextStyle(
                                  color: isToday
                                      ? Colors.yellow.shade200
                                      : Colors.white,
                                  fontSize: 10,
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }).toList(),
                        ),
                        // Data rows
                        ...employees.asMap().entries.map((entry) {
                          final emp = entry.value;
                          final isEven = entry.key.isEven;
                          return Row(
                            children: days
                                .map((d) => Container(
                                      width: dayColW,
                                      height: rowH,
                                      decoration: BoxDecoration(
                                        color: isEven
                                            ? const Color(0xFFF9F9F9)
                                            : Colors.white,
                                        border: const Border(
                                          right: BorderSide(
                                              color: Color(0xFFE4E4E7),
                                              width: 0.5),
                                          bottom: BorderSide(
                                              color: Color(0xFFE4E4E7),
                                              width: 0.5),
                                        ),
                                      ),
                                      child: cellBuilder(emp, d),
                                    ))
                                .toList(),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
