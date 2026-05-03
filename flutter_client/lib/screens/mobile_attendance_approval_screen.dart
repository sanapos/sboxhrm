import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/mobile_attendance.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

class MobileAttendanceApprovalScreen extends StatefulWidget {
  const MobileAttendanceApprovalScreen({super.key});

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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load pending records
      final pendingResult = await _apiService.getPendingMobileAttendance();
      // Load history for approved/rejected
      final historyResult = await _apiService.getMobileAttendanceHistory();

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
          }
        });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: const Color(0xFF1E3A5F),
                    unselectedLabelColor: const Color(0xFF71717A),
                    indicatorColor: const Color(0xFF1E3A5F),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.pending_actions, size: 18),
                            const SizedBox(width: 6),
                            const Text('Chờ duyệt'),
                            if (_pendingRecords.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_pendingRecords.length}',
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
                  ),
                ),
                IconButton(
                  tooltip: 'Bộ lọc',
                  icon: const Icon(Icons.filter_list, color: Color(0xFF71717A)),
                  onPressed: _showFilterDialog,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPendingTab(),
                      _buildApprovedTab(),
                      _buildRejectedTab(),
                      _buildSummaryTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingTab() {
    if (_pendingRecords.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Không có yêu cầu chờ duyệt',
        subtitle: 'Tất cả chấm công đã được xử lý',
      );
    }

    final totalCount = _pendingRecords.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedRecords =
        _pendingRecords.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        _buildBulkActions(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: paginatedRecords.length,
            itemBuilder: (_, index) => Padding(
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
            ),
          ),
        ),
        if (totalPages > 1)
          Container(
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
          ),
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
            '${_pendingRecords.length} yêu cầu chờ duyệt',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF18181B),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (Provider.of<PermissionProvider>(context, listen: false)
                  .canApprove('MobileAttendanceApproval'))
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
              if (Provider.of<PermissionProvider>(context, listen: false)
                  .canApprove('MobileAttendanceApproval'))
                ElevatedButton.icon(
                  onPressed: () => _bulkAction(true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Duyệt tất cả'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 0,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDeckItem(MobileAttendanceRecord record) {
    final isCheckIn = record.punchType == 0;
    final time =
        '${record.punchTime.hour.toString().padLeft(2, '0')}:${record.punchTime.minute.toString().padLeft(2, '0')}';
    final date =
        '${record.punchTime.day}/${record.punchTime.month}/${record.punchTime.year}';
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(isCheckIn ? Icons.login : Icons.logout,
                  size: 18, color: const Color(0xFFF59E0B)),
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
                    '$time · $date · ${record.distanceFromLocation?.toInt() ?? 0}m · ${record.faceMatchScore?.toStringAsFixed(0) ?? '0'}%',
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
                        ? const Color(0xFF1E3A5F)
                        : const Color(0xFFEF4444))
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(isCheckIn ? 'Vào' : 'Ra',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isCheckIn
                          ? const Color(0xFF1E3A5F)
                          : const Color(0xFFEF4444))),
            ),
            const SizedBox(width: 8),
            if (Provider.of<PermissionProvider>(context, listen: false)
                .canApprove('MobileAttendanceApproval'))
              InkWell(
                onTap: () => _rejectRecord(record),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.close, size: 18, color: Color(0xFFEF4444))),
              ),
            const SizedBox(width: 4),
            if (Provider.of<PermissionProvider>(context, listen: false)
                .canApprove('MobileAttendanceApproval'))
              InkWell(
                onTap: () => _approveRecord(record),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.check, size: 18, color: Color(0xFF1E3A5F))),
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
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isApproved
                        ? const Color(0xFF1E3A5F)
                        : const Color(0xFFEF4444))
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(isApproved ? Icons.check : Icons.close,
                  size: 18,
                  color: isApproved
                      ? const Color(0xFF1E3A5F)
                      : const Color(0xFFEF4444)),
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
                    '$time · $date · ${isCheckIn ? 'Vào' : 'Ra'} · ${record.approvedBy ?? 'N/A'}',
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
                isApproved ? 'Đã duyệt' : 'Từ chối',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isApproved
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovedTab() {
    if (_approvedRecords.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle,
        title: 'Chưa có chấm công được duyệt',
        subtitle: 'Các chấm công đã duyệt sẽ hiển thị ở đây',
      );
    }

    final totalCount = _approvedRecords.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedRecords =
        _approvedRecords.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: paginatedRecords.length,
            itemBuilder: (_, index) => Padding(
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
                child: _buildHistoryDeckItem(paginatedRecords[index], true),
              ),
            ),
          ),
        ),
        if (totalPages > 1)
          Container(
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
          ),
      ],
    );
  }

  Widget _buildRejectedTab() {
    if (_rejectedRecords.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cancel,
        title: 'Chưa có chấm công bị từ chối',
        subtitle: 'Các chấm công bị từ chối sẽ hiển thị ở đây',
      );
    }

    final totalCount = _rejectedRecords.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedRecords =
        _rejectedRecords.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: paginatedRecords.length,
            itemBuilder: (_, index) => Padding(
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
                child: _buildHistoryDeckItem(paginatedRecords[index], false),
              ),
            ),
          ),
        ),
        if (totalPages > 1)
          Container(
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
          ),
      ],
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
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận duyệt'),
        content: Text(
            'Bạn có chắc muốn duyệt chấm công của ${record.employeeName}?\n\nSau khi duyệt, dữ liệu sẽ được thêm vào chấm công chi tiết.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
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
      builder: (context) => AlertDialog(
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
          ElevatedButton(
            onPressed: () => Navigator.pop(context, reasonController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
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
      builder: (context) => AlertDialog(
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
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  approve ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444),
              foregroundColor: Colors.white,
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
              const Icon(Icons.date_range, size: 16, color: Color(0xFF1E3A5F)),
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
                              primary: Color(0xFF1E3A5F)),
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
                          color: Color(0xFF1E3A5F),
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
      if (recs.isEmpty)
        return const Center(
            child: Text('—',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13)));
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

    // ── frozen-column table ─────────────────────────────────────────────────
    // Synchronise both tables' scroll positions with a shared notifier
    return Column(
      children: [
        dateRangeBar(),
        // Legend
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: const Wrap(
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
        ),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Bộ lọc',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Chức năng lọc đang phát triển...'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    const Text('Đóng', style: TextStyle(color: Colors.white)),
              ),
            ),
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
                      color: Color(0xFF1E3A5F),
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
                                    : const Color(0xFF1E3A5F),
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
