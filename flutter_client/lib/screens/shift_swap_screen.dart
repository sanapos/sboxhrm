import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';

class ShiftSwapScreen extends StatefulWidget {
  const ShiftSwapScreen({super.key});

  @override
  State<ShiftSwapScreen> createState() => _ShiftSwapScreenState();
}

class _ShiftSwapScreenState extends State<ShiftSwapScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  bool _isLoading = false;

  List<Map<String, dynamic>> _allSwaps = [];
  List<Map<String, dynamic>> _pendingForMe = [];
  List<Map<String, dynamic>> _pendingApproval = [];
  int _currentPage = 1;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      final results = await Future.wait([
        _apiService.getShiftSwaps(),
        _apiService.getShiftSwapsPendingForMe(),
        _apiService.getShiftSwapsPendingApproval(),
      ]);
      setState(() {
        if (results[0]['isSuccess'] == true) _allSwaps = List<Map<String, dynamic>>.from(results[0]['data'] ?? []);
        if (results[1]['isSuccess'] == true) _pendingForMe = List<Map<String, dynamic>>.from(results[1]['data'] ?? []);
        if (results[2]['isSuccess'] == true) _pendingApproval = List<Map<String, dynamic>>.from(results[2]['data'] ?? []);
      });
    } catch (e) {
      debugPrint('Error loading shift swaps: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF0F2340),
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: const Color(0xFF0F2340),
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Tất cả (${_allSwaps.length})'),
              Tab(text: 'Cần phản hồi (${_pendingForMe.length})'),
              Tab(text: 'Chờ duyệt (${_pendingApproval.length})'),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSwapList(_allSwaps, SwapAction.none),
                      _buildSwapList(_pendingForMe, SwapAction.respond),
                      _buildSwapList(_pendingApproval, SwapAction.approve),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Yêu cầu đổi ca'),
        backgroundColor: const Color(0xFF0F2340),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF0F2340), Color(0xFF9333EA)]),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.swap_horiz, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Đổi ca làm việc', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Yêu cầu & phê duyệt đổi ca', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwapList(List<Map<String, dynamic>> items, SwapAction action) {
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.swap_horiz, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Không có yêu cầu đổi ca', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ]),
      );
    }
    final isMobile = Responsive.isMobile(context);
    final totalCount = items.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = isMobile ? 0 : (page - 1) * _pageSize;
    final endIndex = isMobile ? totalCount : (page * _pageSize).clamp(0, totalCount);
    final paginatedItems = items.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
              child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: paginatedItems.length,
              itemBuilder: (ctx, i) => Padding(
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
                  child: _buildSwapDeckItem(paginatedItems[i], action),
                ),
              ),
            ),
          ),
        ),
        if (totalPages > 1 && !isMobile)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hiển thị ${startIndex + 1}-$endIndex / $totalCount',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: page > 1 ? () => setState(() => _currentPage--) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    Text('$page / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: page < totalPages ? () => setState(() => _currentPage++) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSwapDeckItem(Map<String, dynamic> swap, SwapAction action) {
    final status = swap['status']?.toString() ?? 'Pending';
    final statusColor = _getStatusColor(status);
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: const Color(0xFF0F2340).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.swap_horiz, color: Color(0xFF0F2340), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${swap['requesterName'] ?? 'Người YC'} ↔ ${swap['targetName'] ?? 'Người đổi'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      swap['requesterShift'] ?? swap['fromShiftName'] ?? '',
                      _formatDate(swap['requesterDate'] ?? swap['fromDate']),
                      '→',
                      swap['targetShift'] ?? swap['toShiftName'] ?? '',
                      _formatDate(swap['targetDate'] ?? swap['toDate']),
                    ].join(' '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(_getStatusText(status), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
            if (action == SwapAction.respond) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _respondToSwap(swap['id'], true),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.check_circle, size: 20, color: Color(0xFF1E3A5F))),
              ),
              InkWell(
                onTap: () => _respondToSwap(swap['id'], false),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.cancel, size: 20, color: Colors.red)),
              ),
            ],
            if (action == SwapAction.approve) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _approveSwap(swap['id']),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.approval, size: 20, color: Color(0xFF0F2340))),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return const Color(0xFF1E3A5F);
      case 'rejected': case 'declined': return const Color(0xFFEF4444);
      case 'accepted': return const Color(0xFF1E3A5F);
      default: return const Color(0xFFF59E0B);
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return 'Đã phê duyệt';
      case 'rejected': case 'declined': return 'Đã từ chối';
      case 'accepted': return 'Đã đồng ý';
      case 'pending': return 'Chờ phản hồi';
      default: return status;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(date.toString())); } catch (_) { return date.toString(); }
  }

  void _showCreateDialog() {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.swap_horiz, color: Color(0xFF0F2340)), SizedBox(width: 8), Text('Yêu cầu đổi ca')]),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: noteCtrl, decoration: InputDecoration(labelText: 'Ghi chú', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))), maxLines: 3),
              const SizedBox(height: 12),
              Text('Tính năng yêu cầu đổi ca sẽ cần chọn nhân viên muốn đổi và ca tương ứng.', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final data = {'note': noteCtrl.text};
              await _apiService.createShiftSwap(data);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F2340)),
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
  }

  Future<void> _respondToSwap(dynamic id, bool accept) async {
    await _apiService.respondToShiftSwap(id.toString(), {'accepted': accept});
    _loadData();
  }

  Future<void> _approveSwap(dynamic id) async {
    await _apiService.approveShiftSwap(id.toString());
    _loadData();
  }
}

enum SwapAction { none, respond, approve }
