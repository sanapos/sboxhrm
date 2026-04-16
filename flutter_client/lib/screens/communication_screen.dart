import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../utils/responsive_helper.dart';
import '../models/communication.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../widgets/rich_editor.dart';
import '../widgets/app_button.dart';
import '../widgets/notification_overlay.dart';
import '../utils/image_source_picker.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

class CommunicationScreen extends StatefulWidget {
  const CommunicationScreen({super.key});

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends State<CommunicationScreen> with TickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  // Data
  List<InternalCommunication> _communications = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = false;
  bool _statsLoading = false;
  String? _errorMessage;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  int _pageSize = 12;
  final List<int> _pageSizeOptions = [12, 24, 50, 100];

  // Filters
  final _searchCtrl = TextEditingController();
  String _searchTerm = '';
  int? _filterType;
  int? _filterPriority;
  int? _filterStatus = 2;
  String _sortBy = 'newest';
  String _viewMode = 'grid'; // grid or list

  // Mobile UI state
  bool _showMobileFilters = false;

  // Tab definitions: Dashboard + type categories
  final _tabs = <_TabDef>[
    const _TabDef('Dashboard', Icons.dashboard_rounded, null),
    const _TabDef('Tất cả', Icons.article_outlined, null),
    const _TabDef('Tin tức', Icons.newspaper, 0),
    const _TabDef('Thông báo', Icons.campaign, 1),
    const _TabDef('Nội quy', Icons.gavel, 7),
    const _TabDef('Đào tạo', Icons.school, 4),
    const _TabDef('Sự kiện', Icons.event, 2),
    const _TabDef('Chính sách', Icons.policy, 3),
  ];

  StreamSubscription? _commEventSub;
  Timer? _commEventDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadStats();
    _loadCommunications();
    // Listen for real-time communication events with debounce to avoid flood
    _commEventSub = SignalRService().onCommunicationEvent.listen((_) {
      _commEventDebounce?.cancel();
      _commEventDebounce = Timer(const Duration(milliseconds: 500), () {
        _loadCommunications();
        _loadStats();
      });
    });
  }

  @override
  void dispose() {
    _commEventDebounce?.cancel();
    _commEventSub?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final tab = _tabs[_tabController.index];
    if (_tabController.index == 0) {
      _loadStats();
      return;
    }
    setState(() {
      _filterType = tab.typeValue;
      _currentPage = 1;
    });
    _loadCommunications();
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final result = await _api.getCommunicationStats();
      if (result['isSuccess'] == true && result['data'] != null) {
        setState(() => _stats = result['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Load stats error: $e');
    }
    setState(() => _statsLoading = false);
  }

  Future<void> _loadCommunications() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final result = await _api.getCommunications(
        page: _currentPage,
        pageSize: _pageSize,
        type: _filterType,
        priority: _filterPriority,
        status: _filterStatus,
        searchTerm: _searchTerm.isNotEmpty ? _searchTerm : null,
        sortBy: switch (_sortBy) {
          'newest' => 'createdat',
          'oldest' => 'createdat',
          'most_viewed' => 'viewcount',
          'most_liked' => 'likecount',
          _ => null,
        },
        sortDescending: _sortBy != 'oldest',
      );
      if (result['isSuccess'] == true) {
        final data = result['data'];
        if (data is Map<String, dynamic>) {
          final items = data['items'] as List? ?? [];
          _communications = items.map((e) => InternalCommunication.fromJson(e as Map<String, dynamic>)).toList();
          _totalPages = data['totalPages'] ?? 1;
          _totalCount = data['totalItems'] ?? data['totalCount'] ?? (_totalPages * _pageSize);
        } else if (data is List) {
          _communications = data.map((e) => InternalCommunication.fromJson(e as Map<String, dynamic>)).toList();
        }
      } else {
        _errorMessage = result['message'] ?? 'Lỗi tải dữ liệu';
      }
    } catch (e) {
      _errorMessage = 'Lỗi: $e';
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<InternalCommunication> get _sortedComms {
    // Server already handles priority filter, sort, and pinned-first ordering.
    // Just return as-is from server response.
    return _communications;
  }

  Future<void> _toggleReaction(InternalCommunication comm) async {
    final reactionType = comm.hasUserReacted ? (comm.userReactionType?.index ?? 0) : 0;
    await _api.toggleCommunicationReaction(comm.id, {'reactionType': reactionType});
    _loadCommunications();
    _loadStats();
  }

  void _openCreateDialog({InternalCommunication? editing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateEditDialog(
        communication: editing,
        onSaved: () { _loadCommunications(); _loadStats(); },
      ),
    );
  }

  void _selectPost(InternalCommunication comm) {
    _showDetailDialog(comm);
  }

  void _showDetailDialog(InternalCommunication comm) {
    showDialog(
      context: context,
      barrierDismissible: true,
      useSafeArea: false,
      builder: (_) => Dialog.fullscreen(
        child: _CommunicationDetailPanel(
          communication: comm,
          onClose: () => Navigator.of(context).pop(),
          onEdit: () {
            Navigator.of(context).pop();
            _openCreateDialog(editing: comm);
          },
          onDelete: () {
            Navigator.of(context).pop();
            _deletePost(comm);
          },
          onPublish: () {
            Navigator.of(context).pop();
            _publishPost(comm);
          },
          onReactionToggled: () { _loadCommunications(); _loadStats(); },
        ),
      ),
    );
  }

  Future<void> _deletePost(InternalCommunication comm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa bài viết'),
        content: Text('Bạn có chắc muốn xóa "${comm.title}"?'),
        actions: [
          AppDialogActions.delete(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await _api.deleteCommunication(comm.id);
    if (mounted) {
      if (result['isSuccess'] == true) {
        _loadCommunications();
        _loadStats();
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xóa bài viết');
      } else {
        NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi');
      }
    }
  }

  Future<void> _publishPost(InternalCommunication comm) async {
    if (comm.status == CommunicationStatus.published) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xuất bản bài viết'),
        content: Text('Bạn có chắc muốn xuất bản "${comm.title}"?\nBài viết sẽ hiển thị cho toàn bộ nhân viên.'),
        actions: [
          AppDialogActions(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
            confirmLabel: 'Xuất bản',
            confirmVariant: AppButtonVariant.success,
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await _api.publishCommunication(comm.id);
    if (mounted) {
      if (result['isSuccess'] == true) {
        _loadCommunications();
        _loadStats();
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xuất bản thành công!');
      } else {
        NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi xuất bản');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          _buildHeader(theme),
          _buildTabBar(),
          Expanded(
            child: _tabController.index == 0
                ? _buildDashboard()
                : Column(
                    children: [
                      if (!Responsive.isMobile(context) || _showMobileFilters) _buildFilterBar(),
                      Expanded(child: _buildContent()),
                      if (_totalPages > 1 && !Responsive.isMobile(context)) _buildPagination(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ─── HEADER ──────────────────────────────────────────────
  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7), width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF0F2340)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Truyền thông nội bộ', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF18181B)), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          if (Responsive.isMobile(context)) ...[
            GestureDetector(
              onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _showMobileFilters ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18, color: const Color(0xFF1E3A5F)),
                    if (_searchTerm.isNotEmpty || _filterPriority != null || _filterStatus != 2 || _sortBy != 'newest')
                      Positioned(right: 0, top: 0, child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Communication'))
            IconButton(
              onPressed: () => _openCreateDialog(),
              icon: const Icon(Icons.add, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
            ),
          ] else
          if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Communication'))
          FilledButton.icon(
            onPressed: () => _openCreateDialog(),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Tạo bài mới'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB BAR ─────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7), width: 1)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: const Color(0xFF1E3A5F),
        indicatorWeight: 3,
        labelColor: const Color(0xFF1E3A5F),
        unselectedLabelColor: const Color(0xFFA1A1AA),
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        tabs: _tabs.map((t) => Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(t.icon, size: 18),
              const SizedBox(width: 8),
              Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        )).toList(),
      ),
    );
  }

  // ─── DASHBOARD ───────────────────────────────────────────
  Widget _buildDashboard() {
    if (_statsLoading) return const Center(child: CircularProgressIndicator());

    final totalPosts = _stats['totalPosts'] ?? 0;
    final publishedPosts = _stats['publishedPosts'] ?? 0;
    final draftPosts = _stats['draftPosts'] ?? 0;
    final totalViews = _stats['totalViews'] ?? 0;
    final totalLikes = _stats['totalLikes'] ?? 0;
    final totalComments = _stats['totalComments'] ?? 0;
    final typeDist = (_stats['typeDistribution'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats cards - 2 rows on narrow screens
          if (isNarrow) ...[
            if (Responsive.isMobile(context)) ...[
              // Mobile: 2 per row
              Row(children: [
                _statCard('Tổng bài viết', totalPosts.toString(), Icons.article, const Color(0xFF1E3A5F), const Color(0xFFE8F0FE)),
                const SizedBox(width: 8),
                _statCard('Đã xuất bản', publishedPosts.toString(), Icons.check_circle, const Color(0xFF059669), const Color(0xFFECFDF5)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _statCard('Bản nháp', draftPosts.toString(), Icons.edit_note, const Color(0xFFF59E0B), const Color(0xFFFFFBEB)),
                const SizedBox(width: 8),
                _statCard('Lượt xem', _formatNumber(totalViews), Icons.visibility, const Color(0xFF1E3A5F), const Color(0xFFEFF6FF)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _statCard('Lượt thích', _formatNumber(totalLikes), Icons.favorite, const Color(0xFFEF4444), const Color(0xFFFEF2F2)),
                const SizedBox(width: 8),
                _statCard('Bình luận', _formatNumber(totalComments), Icons.chat_bubble, const Color(0xFF0F2340), const Color(0xFFF5F3FF)),
              ]),
            ] else ...[
              Row(
                children: [
                  _statCard('Tổng bài viết', totalPosts.toString(), Icons.article, const Color(0xFF1E3A5F), const Color(0xFFE8F0FE)),
                  const SizedBox(width: 12),
                  _statCard('Đã xuất bản', publishedPosts.toString(), Icons.check_circle, const Color(0xFF059669), const Color(0xFFECFDF5)),
                  const SizedBox(width: 12),
                  _statCard('Bản nháp', draftPosts.toString(), Icons.edit_note, const Color(0xFFF59E0B), const Color(0xFFFFFBEB)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statCard('Tổng lượt xem', _formatNumber(totalViews), Icons.visibility, const Color(0xFF1E3A5F), const Color(0xFFEFF6FF)),
                  const SizedBox(width: 12),
                  _statCard('Lượt thích', _formatNumber(totalLikes), Icons.favorite, const Color(0xFFEF4444), const Color(0xFFFEF2F2)),
                  const SizedBox(width: 12),
                  _statCard('Bình luận', _formatNumber(totalComments), Icons.chat_bubble, const Color(0xFF0F2340), const Color(0xFFF5F3FF)),
                ],
              ),
            ],
          ] else
            Row(
              children: [
                _statCard('Tổng bài viết', totalPosts.toString(), Icons.article, const Color(0xFF1E3A5F), const Color(0xFFE8F0FE)),
                const SizedBox(width: 16),
                _statCard('Đã xuất bản', publishedPosts.toString(), Icons.check_circle, const Color(0xFF059669), const Color(0xFFECFDF5)),
                const SizedBox(width: 16),
                _statCard('Bản nháp', draftPosts.toString(), Icons.edit_note, const Color(0xFFF59E0B), const Color(0xFFFFFBEB)),
                const SizedBox(width: 16),
                _statCard('Tổng lượt xem', _formatNumber(totalViews), Icons.visibility, const Color(0xFF1E3A5F), const Color(0xFFEFF6FF)),
                const SizedBox(width: 16),
                _statCard('Lượt thích', _formatNumber(totalLikes), Icons.favorite, const Color(0xFFEF4444), const Color(0xFFFEF2F2)),
                const SizedBox(width: 16),
                _statCard('Bình luận', _formatNumber(totalComments), Icons.chat_bubble, const Color(0xFF0F2340), const Color(0xFFF5F3FF)),
              ],
            ),
          const SizedBox(height: 28),
          // Type distribution
          if (isNarrow) ...[
            _buildTypeDistribution(typeDist),
            const SizedBox(height: 20),
            _buildRecentPosts(),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildTypeDistribution(typeDist),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 3,
                  child: _buildRecentPosts(),
                ),
              ],
            ),
        ],
      ),
    );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E4E7)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)), overflow: TextOverflow.ellipsis, maxLines: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeDistribution(List<Map<String, dynamic>> dist) {
    final typeConfigs = {
      'News': ('Tin tức', Icons.newspaper, const Color(0xFF1E3A5F)),
      'Announcement': ('Thông báo', Icons.campaign, const Color(0xFFF59E0B)),
      'Event': ('Sự kiện', Icons.event, const Color(0xFF0F2340)),
      'Policy': ('Chính sách', Icons.policy, const Color(0xFF0F2340)),
      'Training': ('Đào tạo', Icons.school, const Color(0xFF22C55E)),
      'Culture': ('Văn hóa', Icons.diversity_3, const Color(0xFFEC4899)),
      'Recruitment': ('Tuyển dụng', Icons.person_add, const Color(0xFF1E3A5F)),
      'Regulation': ('Nội quy', Icons.gavel, const Color(0xFFEF4444)),
      'Other': ('Khác', Icons.article, const Color(0xFFA1A1AA)),
    };

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart, size: 20, color: Color(0xFF1E3A5F)),
              SizedBox(width: 8),
              Text('Phân bổ theo loại', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
            ],
          ),
          const SizedBox(height: 20),
          if (dist.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Chưa có dữ liệu', style: TextStyle(color: Color(0xFFA1A1AA)))))
          else
            ...dist.map((d) {
              final typeName = d['type']?.toString() ?? 'Other';
              final count = d['count'] ?? 0;
              final config = typeConfigs[typeName] ?? ('Khác', Icons.article, const Color(0xFFA1A1AA));
              final total = dist.fold<int>(0, (s, e) => s + ((e['count'] ?? 0) as int));
              final pct = total > 0 ? (count / total * 100) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: config.$3.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Icon(config.$2, size: 16, color: config.$3),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(config.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                              Text('$count bài  (${pct.toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: pct / 100,
                            backgroundColor: const Color(0xFFF1F5F9),
                            valueColor: AlwaysStoppedAnimation(config.$3),
                            borderRadius: BorderRadius.circular(4),
                            minHeight: 6,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecentPosts() {
    final recent = _communications.take(5).toList();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, size: 20, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              const Text('Bài viết gần đây', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
              const Spacer(),
              TextButton(
                onPressed: () { _tabController.animateTo(1); },
                child: const Text('Xem tất cả →', style: TextStyle(color: Color(0xFF1E3A5F), fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (recent.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Chưa có bài viết', style: TextStyle(color: Color(0xFFA1A1AA)))))
          else
            ...recent.map((c) => _recentPostItem(c)),
        ],
      ),
    );
  }

  Widget _recentPostItem(InternalCommunication c) {
    return InkWell(
      onTap: () => _selectPost(c),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _typeColor(c.type).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(c.type), color: _typeColor(c.type), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF18181B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(c.authorName ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                      const SizedBox(width: 8),
                      Text(DateFormat('dd/MM/yyyy').format(c.createdAt), style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('${c.viewCount}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(width: 10),
                Icon(Icons.favorite_border, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('${c.likeCount}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── FILTER BAR ──────────────────────────────────────────
  Widget _buildFilterBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final searchField = TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Tìm kiếm bài viết...',
            hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
            prefixIcon: const Icon(Icons.search, color: Color(0xFFA1A1AA)),
            suffixIcon: _searchTerm.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchCtrl.clear(); setState(() { _searchTerm = ''; _currentPage = 1; }); _loadCommunications(); })
                : null,
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onSubmitted: (v) { setState(() { _searchTerm = v; _currentPage = 1; }); _loadCommunications(); },
        );
        final priorityFilter = _filterDropdown<int?>(
          value: _filterPriority,
          hint: 'Ưu tiên',
          icon: Icons.flag_outlined,
          items: const [
            DropdownMenuItem(value: null, child: Text('Tất cả')),
            DropdownMenuItem(value: 0, child: Text('Thấp')),
            DropdownMenuItem(value: 1, child: Text('Bình thường')),
            DropdownMenuItem(value: 2, child: Text('🔥 Cao')),
            DropdownMenuItem(value: 3, child: Text('🚨 Khẩn cấp')),
          ],
          onChanged: (v) { setState(() { _filterPriority = v; _currentPage = 1; }); _loadCommunications(); },
        );
        final statusFilter = _filterDropdown<int?>(
          value: _filterStatus,
          hint: 'Trạng thái',
          icon: Icons.circle_outlined,
          items: const [
            DropdownMenuItem(value: null, child: Text('Tất cả')),
            DropdownMenuItem(value: 0, child: Text('Nháp')),
            DropdownMenuItem(value: 1, child: Text('Chờ duyệt')),
            DropdownMenuItem(value: 2, child: Text('Đã xuất bản')),
            DropdownMenuItem(value: 3, child: Text('Lưu trữ')),
            DropdownMenuItem(value: 4, child: Text('Từ chối')),
          ],
          onChanged: (v) { setState(() { _filterStatus = v; _currentPage = 1; }); _loadCommunications(); },
        );
        final sortFilter = _filterDropdown<String>(
          value: _sortBy,
          hint: 'Sắp xếp',
          icon: Icons.sort,
          items: const [
            DropdownMenuItem(value: 'newest', child: Text('Mới nhất')),
            DropdownMenuItem(value: 'oldest', child: Text('Cũ nhất')),
            DropdownMenuItem(value: 'most_viewed', child: Text('Xem nhiều nhất')),
            DropdownMenuItem(value: 'most_liked', child: Text('Thích nhiều nhất')),
          ],
          onChanged: (v) { setState(() { _sortBy = v ?? 'newest'; _currentPage = 1; }); _loadCommunications(); },
        );
        final viewToggle = Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE4E4E7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _viewModeBtn(Icons.grid_view_rounded, 'grid'),
              _viewModeBtn(Icons.view_list_rounded, 'list'),
            ],
          ),
        );

        if (isNarrow) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    priorityFilter,
                    statusFilter,
                    sortFilter,
                    viewToggle,
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(flex: 3, child: searchField),
              const SizedBox(width: 12),
              priorityFilter,
              const SizedBox(width: 12),
              statusFilter,
              const SizedBox(width: 12),
              sortFilter,
              const SizedBox(width: 12),
              viewToggle,
            ],
          ),
        );
      },
    );
  }

  Widget _filterDropdown<T>({T? value, required String hint, required IconData icon, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) {
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: hint,
          prefixIcon: Icon(icon, size: 18, color: const Color(0xFFA1A1AA)),
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          labelStyle: const TextStyle(fontSize: 13),
        ),
        items: items,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
        isExpanded: true,
      ),
    );
  }

  Widget _viewModeBtn(IconData icon, String mode) {
    final sel = _viewMode == mode;
    return InkWell(
      onTap: () => setState(() => _viewMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF1E3A5F) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: sel ? Colors.white : const Color(0xFFA1A1AA)),
      ),
    );
  }

  // ─── CONTENT ─────────────────────────────────────────────
  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF1E3A5F)));
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.red[700])),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _loadCommunications, icon: const Icon(Icons.refresh), label: const Text('Thử lại')),
          ],
        ),
      );
    }
    final items = _sortedComms;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
              child: const Icon(Icons.article_outlined, size: 48, color: Color(0xFFA1A1AA)),
            ),
            const SizedBox(height: 16),
            const Text('Chưa có bài viết nào', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF71717A))),
            const SizedBox(height: 8),
            const Text('Hãy tạo bài viết đầu tiên', style: TextStyle(fontSize: 13, color: Color(0xFFA1A1AA))),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _openCreateDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Tạo bài mới'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
            ),
          ],
        ),
      );
    }

    final isMobile = Responsive.isMobile(context);
    if (isMobile) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length,
        itemBuilder: (_, i) => Padding(
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
            child: _buildCommDeckItem(items[i]),
          ),
        ),
      );
    } else if (_viewMode == 'grid') {
      return GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.6,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildGridCard(items[i]),
      );
    } else {
      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildListCard(items[i]),
      );
    }
  }

  // ─── DECK ITEM (MOBILE) ─────────────────────────────────
  Widget _buildCommDeckItem(InternalCommunication c) {
    final typeLabel = _typeLabel(c.type);
    return InkWell(
      onTap: () => _selectPost(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _typeColor(c.type).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_typeIcon(c.type), color: _typeColor(c.type), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (c.isPinned) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.push_pin, size: 12, color: Color(0xFFEF6C00))),
                if (c.priority == CommunicationPriority.urgent) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.priority_high, size: 12, color: Colors.red)),
              ]),
              const SizedBox(height: 2),
              Text(
                [
                  typeLabel,
                  '${c.viewCount} xem',
                  '${c.likeCount} thích',
                  '${c.createdAt.day}/${c.createdAt.month}/${c.createdAt.year}',
                ].join(' · '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: c.status == CommunicationStatus.published ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(c.statusDisplay, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.status == CommunicationStatus.published ? const Color(0xFF059669) : const Color(0xFFF59E0B))),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  // ─── GRID CARD ───────────────────────────────────────────
  Widget _buildGridCard(InternalCommunication c) {
    final imageUrl = c.thumbnailUrl != null && c.thumbnailUrl!.isNotEmpty
        ? (c.thumbnailUrl!.startsWith('http') ? c.thumbnailUrl! : '${ApiService.baseUrl}${c.thumbnailUrl}')
        : null;

    return InkWell(
      onTap: () => _selectPost(c),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              child: imageUrl != null
                  ? CachedNetworkImage(imageUrl: imageUrl, height: 90, width: double.infinity, fit: BoxFit.cover,
                      placeholder: (_, __) => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      errorWidget: (_, __, ___) => _placeholderImage(c, 90))
                  : _placeholderImage(c, 90),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type + Priority badges
                    Row(
                      children: [
                        _typeBadge(c.type),
                        if (c.isPinned) ...[const SizedBox(width: 6), const Icon(Icons.push_pin, size: 14, color: Color(0xFFF59E0B))],
                        if (c.priority == CommunicationPriority.high || c.priority == CommunicationPriority.urgent) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.priority_high, size: 16, color: c.priority == CommunicationPriority.urgent ? Colors.red : Colors.orange),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Title
                    Text(c.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF18181B), height: 1.3),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (c.summary != null && c.summary!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(c.summary!, style: const TextStyle(fontSize: 12, color: Color(0xFF71717A), height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const Spacer(),
                    // Footer
                    Row(
                      children: [
                        if (c.authorName != null) ...[
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                            child: Text(c.authorName![0].toUpperCase(), style: const TextStyle(fontSize: 9, color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(c.authorName!, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)), overflow: TextOverflow.ellipsis)),
                        ],
                        const Spacer(),
                        _miniStat(Icons.visibility_outlined, c.viewCount),
                        const SizedBox(width: 8),
                        _miniStat(c.hasUserReacted ? Icons.favorite : Icons.favorite_border, c.likeCount, color: c.hasUserReacted ? Colors.red : null),
                        const SizedBox(width: 8),
                        _miniStat(Icons.chat_bubble_outline, c.commentCount),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── LIST CARD ───────────────────────────────────────────
  Widget _buildListCard(InternalCommunication c) {
    final imageUrl = c.thumbnailUrl != null && c.thumbnailUrl!.isNotEmpty
        ? (c.thumbnailUrl!.startsWith('http') ? c.thumbnailUrl! : '${ApiService.baseUrl}${c.thumbnailUrl}')
        : null;

    return InkWell(
      onTap: () => _selectPost(c),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl != null
                  ? CachedNetworkImage(imageUrl: imageUrl, width: 160, height: 140, fit: BoxFit.cover,
                      placeholder: (_, __) => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      errorWidget: (_, __, ___) => _placeholderImage(c, 140, width: 160))
                  : _placeholderImage(c, 140, width: 160),
            ),
            const SizedBox(width: 16),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _typeBadge(c.type),
                        if (c.isPinned) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(6)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.push_pin, size: 12, color: Color(0xFFF59E0B)),
                              SizedBox(width: 4),
                              Text('Ghim', style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ],
                        if (c.priority == CommunicationPriority.urgent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(6)),
                            child: const Text('Khẩn cấp', style: TextStyle(fontSize: 10, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                          ),
                        ],
                        const Spacer(),
                        PopupMenuButton<String>(
                          itemBuilder: (_) => [
                            if (Provider.of<PermissionProvider>(context, listen: false).canEdit('Communication'))
                            const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Chỉnh sửa')])),
                            if (c.status != CommunicationStatus.published)
                              const PopupMenuItem(value: 'publish', child: Row(children: [Icon(Icons.send, size: 16), SizedBox(width: 8), Text('Xuất bản')])),
                            if (Provider.of<PermissionProvider>(context, listen: false).canDelete('Communication'))
                            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Xóa', style: TextStyle(color: Colors.red))])),
                          ],
                          onSelected: (v) {
                            if (v == 'edit') _openCreateDialog(editing: c);
                            if (v == 'publish') _publishPost(c);
                            if (v == 'delete') _deletePost(c);
                          },
                          child: const Icon(Icons.more_horiz, size: 20, color: Color(0xFFA1A1AA)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(c.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF18181B)), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (c.summary != null) ...[
                      const SizedBox(height: 6),
                      Text(c.summary!, style: const TextStyle(fontSize: 13, color: Color(0xFF71717A), height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (c.authorName != null) ...[
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                            child: Text(c.authorName![0].toUpperCase(), style: const TextStyle(fontSize: 10, color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Text(c.authorName!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF52525B))),
                          const SizedBox(width: 12),
                        ],
                        Icon(Icons.access_time, size: 13, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(DateFormat('dd/MM/yyyy HH:mm').format(c.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        const Spacer(),
                        _miniStat(Icons.visibility_outlined, c.viewCount),
                        const SizedBox(width: 14),
                        InkWell(
                          onTap: () => _toggleReaction(c),
                          borderRadius: BorderRadius.circular(20),
                          child: _miniStat(c.hasUserReacted ? Icons.favorite : Icons.favorite_border, c.likeCount, color: c.hasUserReacted ? Colors.red : null),
                        ),
                        const SizedBox(width: 14),
                        _miniStat(Icons.chat_bubble_outline, c.commentCount),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── DETAIL PANEL (now shown as dialog) ──────────────────

  // ─── PAGINATION ──────────────────────────────────────────
  Widget _buildPagination() {
    final start = _totalCount > 0 ? (_currentPage - 1) * _pageSize + 1 : 0;
    final end = (_currentPage * _pageSize).clamp(0, _totalCount);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE4E4E7)))),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Hiển thị:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(width: 8),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _pageSize,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() { _pageSize = v; _currentPage = 1; });
                        _loadCommunications();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: _currentPage > 1 ? () { setState(() => _currentPage--); _loadCommunications(); } : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Trước'),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF71717A), side: const BorderSide(color: Color(0xFFE4E4E7))),
          ),
          Text('Hiển thị $start-$end / $_totalCount',
              style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF52525B))),
          OutlinedButton.icon(
            onPressed: _currentPage < _totalPages ? () { setState(() => _currentPage++); _loadCommunications(); } : null,
            icon: const Text('Sau'),
            label: const Icon(Icons.chevron_right, size: 18),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF71717A), side: const BorderSide(color: Color(0xFFE4E4E7))),
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────
  Widget _placeholderImage(InternalCommunication c, double height, {double? width}) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_typeColor(c.type).withValues(alpha: 0.08), _typeColor(c.type).withValues(alpha: 0.15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(_typeIcon(c.type), size: 36, color: _typeColor(c.type).withValues(alpha: 0.4))),
    );
  }

  Widget _typeBadge(CommunicationType type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _typeColor(type).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_typeIcon(type), size: 12, color: _typeColor(type)),
        const SizedBox(width: 4),
        Text(_typeLabel(type), style: TextStyle(fontSize: 10, color: _typeColor(type), fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _miniStat(IconData icon, int value, {Color? color}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color ?? const Color(0xFFA1A1AA)),
      const SizedBox(width: 3),
      Text('$value', style: TextStyle(fontSize: 11, color: color ?? const Color(0xFFA1A1AA))),
    ]);
  }

  String _formatNumber(dynamic n) {
    final num = (n is int) ? n : int.tryParse(n.toString()) ?? 0;
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return num.toString();
  }

  static IconData _typeIcon(CommunicationType t) => switch (t) {
    CommunicationType.news => Icons.newspaper,
    CommunicationType.announcement => Icons.campaign,
    CommunicationType.event => Icons.event,
    CommunicationType.policy => Icons.policy,
    CommunicationType.training => Icons.school,
    CommunicationType.culture => Icons.diversity_3,
    CommunicationType.recruitment => Icons.person_add,
    CommunicationType.regulation => Icons.gavel,
    CommunicationType.other => Icons.article,
  };

  static Color _typeColor(CommunicationType t) => switch (t) {
    CommunicationType.news => const Color(0xFF1E3A5F),
    CommunicationType.announcement => const Color(0xFFF59E0B),
    CommunicationType.event => const Color(0xFF0F2340),
    CommunicationType.policy => const Color(0xFF0F2340),
    CommunicationType.training => const Color(0xFF22C55E),
    CommunicationType.culture => const Color(0xFFEC4899),
    CommunicationType.recruitment => const Color(0xFF1E3A5F),
    CommunicationType.regulation => const Color(0xFFEF4444),
    CommunicationType.other => const Color(0xFFA1A1AA),
  };

  static String _typeLabel(CommunicationType t) => switch (t) {
    CommunicationType.news => 'Tin tức',
    CommunicationType.announcement => 'Thông báo',
    CommunicationType.event => 'Sự kiện',
    CommunicationType.policy => 'Chính sách',
    CommunicationType.training => 'Đào tạo',
    CommunicationType.culture => 'Văn hóa',
    CommunicationType.recruitment => 'Tuyển dụng',
    CommunicationType.regulation => 'Nội quy',
    CommunicationType.other => 'Khác',
  };
}

// ─── TAB DEFINITION ──────────────────────────────────────
class _TabDef {
  final String label;
  final IconData icon;
  final int? typeValue;
  const _TabDef(this.label, this.icon, this.typeValue);
}

// ═══════════════════════════════════════════════════════════
// DETAIL PANEL - Xem chi tiết + bình luận + phản ứng
// ═══════════════════════════════════════════════════════════
class _CommunicationDetailPanel extends StatefulWidget {
  final InternalCommunication communication;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPublish;
  final VoidCallback onReactionToggled;

  const _CommunicationDetailPanel({
    required this.communication,
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
    required this.onReactionToggled,
  });

  @override
  State<_CommunicationDetailPanel> createState() => _CommunicationDetailPanelState();
}

class _CommunicationDetailPanelState extends State<_CommunicationDetailPanel> {
  final ApiService _api = ApiService();
  late InternalCommunication _communication;
  bool _isTogglingReaction = false;
  List<CommunicationComment> _comments = [];
  bool _loadingComments = false;
  final _commentCtrl = TextEditingController();
  String? _replyToId;
  String? _replyToName;

  // Reactions
  static const _reactions = [
    (ReactionType.like, '👍', 'Thích'),
    (ReactionType.love, '❤️', 'Yêu thích'),
    (ReactionType.celebrate, '🎉', 'Chúc mừng'),
    (ReactionType.support, '💪', 'Ủng hộ'),
    (ReactionType.insightful, '💡', 'Hữu ích'),
  ];

  @override
  void initState() {
    super.initState();
    _communication = widget.communication;
    _loadDetail();
    _loadComments();
  }

  Future<void> _loadDetail() async {
    try {
      final result = await _api.getCommunicationDetail(widget.communication.id);
      if (result['isSuccess'] == true && result['data'] != null) {
        if (mounted) setState(() => _communication = InternalCommunication.fromJson(result['data'] as Map<String, dynamic>));
      }
    } catch (e) {
      debugPrint('Load detail error: $e');
    }
  }

  @override
  void didUpdateWidget(covariant _CommunicationDetailPanel old) {
    super.didUpdateWidget(old);
    if (old.communication.id != widget.communication.id) {
      _communication = widget.communication;
      _loadDetail();
      _loadComments();
      _replyToId = null;
      _replyToName = null;
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    try {
      final result = await _api.getCommunicationComments(widget.communication.id);
      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        if (data is Map<String, dynamic>) {
          final items = data['items'] as List? ?? [];
          _comments = items.map((e) => CommunicationComment.fromJson(e as Map<String, dynamic>)).toList();
        } else if (data is List) {
          _comments = data.map((e) => CommunicationComment.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('Load comments error: $e');
    }
    setState(() => _loadingComments = false);
  }

  Future<void> _addComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;
    if (content.length > 2000) {
      if (mounted) {
        NotificationOverlayManager().showWarning(title: 'Cảnh báo', message: 'Bình luận không được vượt quá 2000 ký tự');
      }
      return;
    }
    final data = <String, dynamic>{'content': content};
    if (_replyToId != null) data['parentCommentId'] = _replyToId;
    final result = await _api.addCommunicationComment(widget.communication.id, data);
    if (result['isSuccess'] == true) {
      _commentCtrl.clear();
      setState(() { _replyToId = null; _replyToName = null; });
      _loadComments();
      _loadDetail();
    } else if (mounted) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi gửi bình luận');
    }
  }

  Future<void> _toggleReaction(int reactionType) async {
    if (_isTogglingReaction) return;
    setState(() => _isTogglingReaction = true);
    try {
      await _api.toggleCommunicationReaction(widget.communication.id, {'reactionType': reactionType});
      await _loadDetail();
      widget.onReactionToggled();
    } finally {
      if (mounted) setState(() => _isTogglingReaction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _communication;
    final imageUrl = c.thumbnailUrl != null && c.thumbnailUrl!.isNotEmpty
        ? (c.thumbnailUrl!.startsWith('http') ? c.thumbnailUrl! : '${ApiService.baseUrl}${c.thumbnailUrl}')
        : null;

    return Column(
      children: [
        // Panel header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            boxShadow: [BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.arrow_back, size: 20),
                tooltip: 'Quay lại',
                style: IconButton.styleFrom(foregroundColor: const Color(0xFF52525B)),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.article, size: 20, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Chi tiết bài viết', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF18181B)))),
              IconButton(
                onPressed: widget.onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Chỉnh sửa',
                style: IconButton.styleFrom(foregroundColor: const Color(0xFF1E3A5F)),
              ),
              if (c.status != CommunicationStatus.published)
                IconButton(
                  onPressed: widget.onPublish,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  tooltip: 'Xuất bản',
                  style: IconButton.styleFrom(foregroundColor: const Color(0xFF22C55E)),
                ),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Xóa',
                style: IconButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Đóng',
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover image
                if (imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: CachedNetworkImage(imageUrl: imageUrl, width: double.infinity, fit: BoxFit.cover,
                          placeholder: (_, __) => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                          errorWidget: (_, __, ___) => const SizedBox.shrink()),
                    ),
                  ),
                if (imageUrl != null) const SizedBox(height: 24),

                // Type + Status badges
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _CommunicationScreenState._typeColor(c.type).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_CommunicationScreenState._typeIcon(c.type), size: 14, color: _CommunicationScreenState._typeColor(c.type)),
                        const SizedBox(width: 4),
                        Text(c.typeDisplay, style: TextStyle(fontSize: 12, color: _CommunicationScreenState._typeColor(c.type), fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: c.status == CommunicationStatus.published ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(c.statusDisplay,
                          style: TextStyle(fontSize: 12,
                              color: c.status == CommunicationStatus.published ? const Color(0xFF059669) : const Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600)),
                    ),
                    if (c.isPinned)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.push_pin, size: 13, color: Color(0xFFF59E0B)),
                          SizedBox(width: 4),
                          Text('Ghim', style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Title
                Text(c.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), height: 1.3, letterSpacing: -0.3)),
                const SizedBox(height: 12),

                // Author & Date
                Row(
                  children: [
                    if (c.authorName != null) ...[
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                        child: Text(c.authorName![0].toUpperCase(), style: const TextStyle(fontSize: 11, color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Text(c.authorName!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF52525B))),
                      const SizedBox(width: 12),
                    ],
                    Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(DateFormat('dd/MM/yyyy HH:mm').format(c.createdAt), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
                const SizedBox(height: 16),

                // Summary
                if (c.summary != null && c.summary!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.summarize, size: 16, color: Color(0xFF1E3A5F)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c.summary!, style: const TextStyle(fontSize: 13, color: Color(0xFF1D4ED8), fontStyle: FontStyle.italic, height: 1.4))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Content - full width, auto height for web-article reading experience
                SizedBox(
                  width: double.infinity,
                  child: HtmlContentView(html: c.content, minHeight: 100),
                ),
                const SizedBox(height: 12),

                // Tags
                if (c.tags != null && c.tags!.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: c.tags!.split(',').map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('#${t.trim()}', style: const TextStyle(fontSize: 11, color: Color(0xFF1E3A5F))),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Attached images
                if (c.attachedImages.isNotEmpty) ...[
                  const Text('Hình ảnh đính kèm', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF52525B))),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: c.attachedImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final url = c.attachedImages[i].startsWith('http') ? c.attachedImages[i] : '${ApiService.baseUrl}${c.attachedImages[i]}';
                        return GestureDetector(
                          onTap: () => showDialog(context: context, builder: (_) => Dialog(
                            backgroundColor: Colors.transparent,
                            child: Stack(alignment: Alignment.topRight, children: [
                              ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
                              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 28), style: IconButton.styleFrom(backgroundColor: Colors.black54)),
                            ]),
                          )),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(imageUrl: url, width: 80, height: 80, fit: BoxFit.cover, placeholder: (_, __) => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))), errorWidget: (_, __, ___) => Container(width: 80, height: 80, color: const Color(0xFFF1F5F9), child: const Icon(Icons.broken_image, color: Color(0xFFA1A1AA)))),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Stats row - views, likes, comments
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _detailStat(Icons.visibility_outlined, '${c.viewCount}', 'Lượt xem'),
                      _detailStat(Icons.favorite, '${c.likeCount}', 'Thích', color: Colors.red),
                      _detailStat(Icons.chat_bubble_outline, '${c.commentCount}', 'Bình luận'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const Divider(height: 24, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 16),

                // ── REACTIONS ──
                const Text('Tương tác', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _reactions.map((r) {
                    final isActive = c.hasUserReacted && c.userReactionType == r.$1;
                    return InkWell(
                      onTap: () => _toggleReaction(r.$1.index),
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFFE4E4E7)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(r.$2, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(r.$3, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFF71717A))),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                const Divider(height: 24, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 16),

                // ── COMMENTS ──
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF1E3A5F)),
                    const SizedBox(width: 8),
                    Text('Bình luận (${_comments.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 12),

                // Reply indicator
                if (_replyToName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.reply, size: 14, color: Color(0xFF1E3A5F)),
                        const SizedBox(width: 8),
                        Text('Trả lời $_replyToName', style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F))),
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() { _replyToId = null; _replyToName = null; }),
                          child: const Icon(Icons.close, size: 14, color: Color(0xFFA1A1AA)),
                        ),
                      ],
                    ),
                  ),

                // Comment input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        decoration: InputDecoration(
                          hintText: _replyToName != null ? 'Trả lời $_replyToName...' : 'Viết bình luận...',
                          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA1A1AA)),
                          filled: true,
                          fillColor: const Color(0xFFFAFAFA),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onSubmitted: (_) => _addComment(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        onPressed: _addComment,
                        icon: const Icon(Icons.send, size: 18, color: Colors.white),
                        tooltip: 'Gửi',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Comments list
                if (_loadingComments)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)))
                else if (_comments.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.chat_bubble_outline, size: 36, color: Color(0xFFCBD5E1)),
                      SizedBox(height: 8),
                      Text('Chưa có bình luận nào', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13)),
                      Text('Hãy là người đầu tiên bình luận!', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                    ]),
                  ))
                else
                  ..._comments.map((cm) => _commentWidget(cm, depth: 0)),
              ],
            ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _commentWidget(CommunicationComment cm, {int depth = 0}) {
    return Padding(
      padding: EdgeInsets.only(left: depth > 0 ? 24 : 0, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: depth > 0 ? 12 : 14,
                backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                child: Text(
                  (cm.userName ?? '?')[0].toUpperCase(),
                  style: TextStyle(fontSize: depth > 0 ? 9 : 11, color: const Color(0xFF1E3A5F), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(cm.userName ?? 'Ẩn danh', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                        const SizedBox(width: 8),
                        Text(_timeAgo(cm.createdAt), style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: depth > 0 ? const Color(0xFFFAFAFA) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(cm.content, style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.4)),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        InkWell(
                          onTap: () => setState(() { _replyToId = cm.id; _replyToName = cm.userName; }),
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: Text('Trả lời', style: TextStyle(fontSize: 11, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w500)),
                          ),
                        ),
                        if (cm.likeCount > 0) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.favorite, size: 12, color: Colors.red[300]),
                          const SizedBox(width: 2),
                          Text('${cm.likeCount}', style: TextStyle(fontSize: 11, color: Colors.red[300])),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Replies
          if (cm.replies.isNotEmpty)
            ...cm.replies.map((r) => _commentWidget(r, depth: depth + 1)),
        ],
      ),
    );
  }

  Widget _detailStat(IconData icon, String value, String label, {Color? color}) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color ?? const Color(0xFFA1A1AA)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color ?? const Color(0xFF374151))),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
      ],
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()} năm trước';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()} tháng trước';
    if (diff.inDays > 0) return '${diff.inDays} ngày trước';
    if (diff.inHours > 0) return '${diff.inHours} giờ trước';
    if (diff.inMinutes > 0) return '${diff.inMinutes} phút trước';
    return 'Vừa xong';
  }
}

// ═══════════════════════════════════════════════════════════
// CREATE / EDIT DIALOG
// ═══════════════════════════════════════════════════════════
class _CreateEditDialog extends StatefulWidget {
  final InternalCommunication? communication;
  final VoidCallback onSaved;

  const _CreateEditDialog({this.communication, required this.onSaved});

  @override
  State<_CreateEditDialog> createState() => _CreateEditDialogState();
}

class _CreateEditDialogState extends State<_CreateEditDialog> {
  final ApiService _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _richEditorCtrl = RichEditorController();
  final _summaryCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _aiPromptCtrl = TextEditingController();

  int _selectedType = 0;
  int _selectedPriority = 1;
  bool _isPinned = false;
  bool _publishImmediately = false;
  bool _isSubmitting = false;
  bool _isAiGenerating = false;
  String _aiTone = 'professional';
  String? _aiProvider;
  List<Map<String, dynamic>> _aiProviders = [];
  bool _aiAnyEnabled = false;
  String? _thumbnailUrl;
  List<String> _attachedImages = [];
  bool _isUploadingImage = false;

  bool get _isEditing => widget.communication != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final c = widget.communication!;
      _titleCtrl.text = c.title;
      _richEditorCtrl.html = c.content;
      _summaryCtrl.text = c.summary ?? '';
      _tagsCtrl.text = c.tags ?? '';
      _selectedType = c.type.index <= 7 ? c.type.index : 99;
      _selectedPriority = c.priority.index;
      _isPinned = c.isPinned;
      _thumbnailUrl = c.thumbnailUrl;
      _attachedImages = List<String>.from(c.attachedImages);
    }
    _loadAiProviders();
  }

  Future<void> _loadAiProviders() async {
    try {
      final result = await _api.getAiProviders();
      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        final providers = (data['providers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (mounted) {
          setState(() {
            _aiProviders = providers.where((p) => p['enabled'] == true && p['isConfigured'] == true).toList();
            _aiAnyEnabled = _aiProviders.isNotEmpty;
            if (_aiProviders.isNotEmpty && _aiProvider == null) {
              _aiProvider = _aiProviders.first['id'] as String?;
            }
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _richEditorCtrl.dispose();
    _summaryCtrl.dispose();
    _tagsCtrl.dispose();
    _aiPromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_richEditorCtrl.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập nội dung bài viết');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final data = {
        'title': _titleCtrl.text.trim(),
        'content': _richEditorCtrl.html.trim(),
        'summary': _summaryCtrl.text.trim().isNotEmpty ? _summaryCtrl.text.trim() : null,
        'type': _selectedType,
        'priority': _selectedPriority,
        'isPinned': _isPinned,
        'tags': _tagsCtrl.text.trim().isNotEmpty ? _tagsCtrl.text.trim() : null,
        'publishImmediately': _publishImmediately,
        'isAiGenerated': false,
        'thumbnailUrl': _thumbnailUrl,
        'attachedImages': _attachedImages.isNotEmpty ? _attachedImages : null,
      };

      final result = _isEditing
          ? await _api.updateCommunication(widget.communication!.id, data)
          : await _api.createCommunication(data);

      if (mounted) {
        if (result['isSuccess'] == true) {
          Navigator.pop(context);
          widget.onSaved();
          NotificationOverlayManager().showSuccess(title: 'Thành công', message: _isEditing ? 'Đã cập nhật thành công!' : 'Đã tạo bài truyền thông!');
        } else {
          NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi lưu bài viết');
        }
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickAndUploadImage({bool isThumbnail = false}) async {
    try {
      final images = await pickImagesWithCamera(
        context,
        allowMultiple: !isThumbnail,
      );
      if (images == null || images.isEmpty) return;
      setState(() => _isUploadingImage = true);

      const maxSizeBytes = 10 * 1024 * 1024; // 10MB
      const allowedExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

      for (final img in images) {
        // Client-side file size validation
        if (img.bytes.length > maxSizeBytes) {
          if (mounted) {
            NotificationOverlayManager().showWarning(title: 'Quá dung lượng', message: '${img.name}: Kích thước ảnh tối đa 10MB (hiện ${(img.bytes.length / 1024 / 1024).toStringAsFixed(1)}MB)');
          }
          continue;
        }

        // Client-side extension validation
        final ext = img.name.split('.').last.toLowerCase();
        if (!allowedExtensions.contains(ext)) {
          if (mounted) {
            NotificationOverlayManager().showWarning(title: 'Định dạng không hợp lệ', message: '${img.name}: Chỉ hỗ trợ định dạng JPEG, PNG, GIF, WebP');
          }
          continue;
        }

        final uploadResult = await _api.uploadCommunicationImage(img.bytes.toList(), img.name);
        if (uploadResult['isSuccess'] == true && uploadResult['data'] != null) {
          final imageUrl = uploadResult['data'].toString();
          setState(() {
            if (isThumbnail) { _thumbnailUrl = imageUrl; } else { _attachedImages.add(imageUrl); }
          });
        } else if (mounted) {
          NotificationOverlayManager().showError(title: 'Lỗi', message: uploadResult['message'] ?? 'Lỗi upload');
        }
      }
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _generateAi() async {
    if (_aiPromptCtrl.text.trim().isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập mô tả cho AI');
      return;
    }
    setState(() => _isAiGenerating = true);
    try {
      final result = await _api.generateAiCommunicationContent({
        'prompt': _aiPromptCtrl.text.trim(),
        'type': _selectedType,
        'tone': _aiTone,
        'maxLength': 3000,
        'language': 'vi',
        if (_aiProvider != null) 'provider': _aiProvider,
      });
      if (mounted && result['isSuccess'] == true) {
        final d = result['data'];
        if (d != null) {
          setState(() {
            _titleCtrl.text = d['title'] ?? _titleCtrl.text;
            _richEditorCtrl.html = d['content'] ?? _richEditorCtrl.html;
            if (d['summary'] != null) _summaryCtrl.text = d['summary'];
            if (d['suggestedTags'] != null) _tagsCtrl.text = (d['suggestedTags'] as List).join(', ');
          });
          NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'AI đã tạo nội dung!');
        }
      } else if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi AI');
      }
    } finally {
      if (mounted) setState(() => _isAiGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final dialogTitle = _isEditing ? 'Chỉnh sửa bài viết' : 'Tạo bài truyền thông mới';

    final bodyContent = SingleChildScrollView(
      padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
                      final leftContent = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _titleCtrl,
                              decoration: InputDecoration(
                                labelText: 'Tiêu đề *',
                                hintText: 'Nhập tiêu đề bài viết',
                                prefixIcon: const Icon(Icons.title),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập tiêu đề' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _summaryCtrl,
                              decoration: InputDecoration(
                                labelText: 'Tóm tắt',
                                hintText: 'Mô tả ngắn gọn...',
                                prefixIcon: const Icon(Icons.short_text),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            const Row(children: [
                              Icon(Icons.edit_document, size: 18, color: Color(0xFF1E3A5F)),
                              SizedBox(width: 8),
                              Text('Nội dung bài viết *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF374151))),
                            ]),
                            const SizedBox(height: 8),
                            RichEditor(
                              controller: _richEditorCtrl,
                              placeholder: 'Soạn nội dung bài viết tại đây...',
                              minHeight: 350,
                              onChanged: (_) {},
                              onImageUpload: (bytes, fileName) async {
                                final r = await _api.uploadCommunicationImage(bytes, fileName);
                                if (r['isSuccess'] == true && r['data'] != null) return r['data'].toString();
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _tagsCtrl,
                              decoration: InputDecoration(
                                labelText: 'Tags',
                                hintText: 'Nhập tags, cách nhau bằng dấu phẩy',
                                prefixIcon: const Icon(Icons.tag),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Image upload
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAFAFA),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE4E4E7)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    const Icon(Icons.image_outlined, color: Color(0xFF1E3A5F), size: 20),
                                    const SizedBox(width: 8),
                                    const Text('Hình ảnh', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF52525B))),
                                    const Spacer(),
                                    if (_isUploadingImage) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                  ]),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _isUploadingImage ? null : () => _pickAndUploadImage(isThumbnail: true),
                                        icon: const Icon(Icons.photo_camera, size: 18),
                                        label: Text(_thumbnailUrl != null ? 'Đổi ảnh bìa' : 'Chọn ảnh bìa'),
                                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1E3A5F), side: const BorderSide(color: Color(0xFF1E3A5F)), padding: const EdgeInsets.symmetric(vertical: 10)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _isUploadingImage ? null : () => _pickAndUploadImage(isThumbnail: false),
                                        icon: const Icon(Icons.add_photo_alternate, size: 18),
                                        label: const Text('Thêm ảnh'),
                                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF059669), side: const BorderSide(color: Color(0xFF059669)), padding: const EdgeInsets.symmetric(vertical: 10)),
                                      ),
                                    ),
                                  ]),
                                  if (_thumbnailUrl != null) ...[
                                    const SizedBox(height: 10),
                                    Stack(children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: CachedNetworkImage(imageUrl: '${ApiService.baseUrl}$_thumbnailUrl', height: 100, width: double.infinity, fit: BoxFit.cover,
                                            placeholder: (_, __) => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                                            errorWidget: (_, __, ___) => Container(height: 100, color: const Color(0xFFF1F5F9), child: const Center(child: Icon(Icons.broken_image, color: Color(0xFFA1A1AA))))),
                                      ),
                                      Positioned(top: 4, right: 4, child: InkWell(
                                        onTap: () => setState(() => _thumbnailUrl = null),
                                        child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 14)),
                                      )),
                                    ]),
                                  ],
                                  if (_attachedImages.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Wrap(spacing: 8, runSpacing: 8, children: _attachedImages.asMap().entries.map((e) =>
                                      Stack(children: [
                                        ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: '${ApiService.baseUrl}${e.value}', width: 70, height: 70, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 70, height: 70, color: const Color(0xFFF1F5F9), child: const Icon(Icons.broken_image, size: 18, color: Color(0xFFA1A1AA))))),
                                        Positioned(top: 2, right: 2, child: InkWell(onTap: () => setState(() => _attachedImages.removeAt(e.key)), child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 10)))),
                                      ]),
                                    ).toList()),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      final rightContent = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Loại bài viết', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              initialValue: _selectedType,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('📰 Tin tức')),
                                DropdownMenuItem(value: 1, child: Text('📢 Thông báo')),
                                DropdownMenuItem(value: 2, child: Text('🎉 Sự kiện')),
                                DropdownMenuItem(value: 3, child: Text('📋 Chính sách')),
                                DropdownMenuItem(value: 4, child: Text('🎓 Đào tạo')),
                                DropdownMenuItem(value: 5, child: Text('🏢 Văn hóa')),
                                DropdownMenuItem(value: 6, child: Text('👤 Tuyển dụng')),
                                DropdownMenuItem(value: 7, child: Text('📜 Nội quy')),
                                DropdownMenuItem(value: 99, child: Text('📦 Khác')),
                              ],
                              onChanged: (v) => setState(() => _selectedType = v ?? 0),
                            ),
                            const SizedBox(height: 16),
                            const Text('Mức độ ưu tiên', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              initialValue: _selectedPriority,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('Thấp')),
                                DropdownMenuItem(value: 1, child: Text('Bình thường')),
                                DropdownMenuItem(value: 2, child: Text('🔥 Cao')),
                                DropdownMenuItem(value: 3, child: Text('🚨 Khẩn cấp')),
                              ],
                              onChanged: (v) => setState(() => _selectedPriority = v ?? 1),
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              title: const Text('Ghim bài viết', style: TextStyle(fontSize: 14)),
                              subtitle: const Text('Hiển thị trên đầu danh sách', style: TextStyle(fontSize: 12)),
                              value: _isPinned,
                              onChanged: (v) => setState(() => _isPinned = v),
                              contentPadding: EdgeInsets.zero,
                              activeThumbColor: const Color(0xFF1E3A5F),
                            ),
                            if (!_isEditing)
                              SwitchListTile(
                                title: const Text('Xuất bản ngay', style: TextStyle(fontSize: 14)),
                                subtitle: const Text('Tự động xuất bản sau khi tạo', style: TextStyle(fontSize: 12)),
                                value: _publishImmediately,
                                onChanged: (v) => setState(() => _publishImmediately = v),
                                contentPadding: EdgeInsets.zero,
                                activeThumbColor: const Color(0xFF1E3A5F),
                              ),
                            const Divider(height: 32),
                            // AI Section - only show when at least one provider is enabled
                            if (_aiAnyEnabled)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [const Color(0xFF1E3A5F).withValues(alpha: 0.05), const Color(0xFF0F2340).withValues(alpha: 0.05)]),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(children: [
                                    Icon(Icons.auto_awesome, color: Color(0xFF1E3A5F), size: 20),
                                    SizedBox(width: 8),
                                    Text('Viết bài với AI', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
                                  ]),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _aiPromptCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Mô tả nội dung bạn muốn AI viết...\nVD: Viết nội quy sử dụng phòng họp',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      fillColor: Colors.white,
                                      filled: true,
                                    ),
                                    maxLines: 3,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      if (_aiProviders.length > 1)
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            initialValue: _aiProvider,
                                            decoration: InputDecoration(
                                              labelText: 'AI Provider',
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                              fillColor: Colors.white,
                                              filled: true,
                                            ),
                                            items: _aiProviders.map((p) {
                                              return DropdownMenuItem<String>(
                                                value: p['id'] as String,
                                                child: Text(p['name'] as String),
                                              );
                                            }).toList(),
                                            onChanged: (v) => setState(() => _aiProvider = v),
                                          ),
                                        ),
                                      if (_aiProviders.length > 1) const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _aiTone,
                                          decoration: InputDecoration(
                                            labelText: 'Giọng văn',
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                            fillColor: Colors.white,
                                            filled: true,
                                          ),
                                          items: const [
                                            DropdownMenuItem(value: 'professional', child: Text('Chuyên nghiệp')),
                                            DropdownMenuItem(value: 'friendly', child: Text('Thân thiện')),
                                            DropdownMenuItem(value: 'formal', child: Text('Trang trọng')),
                                            DropdownMenuItem(value: 'creative', child: Text('Sáng tạo')),
                                            DropdownMenuItem(value: 'inspirational', child: Text('Truyền cảm hứng')),
                                          ],
                                          onChanged: (v) => setState(() => _aiTone = v ?? 'professional'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: _isAiGenerating ? null : _generateAi,
                                      icon: _isAiGenerating
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.auto_awesome, size: 18),
                                      label: Text(_isAiGenerating ? 'Đang tạo...' : 'Tạo nội dung AI'),
                                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), padding: const EdgeInsets.symmetric(vertical: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );

                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            leftContent,
                            const SizedBox(height: 24),
                            rightContent,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: leftContent),
                          const SizedBox(width: 24),
                          Expanded(flex: 2, child: rightContent),
                        ],
                      );
                    },
                  ),
                );

    final actionButtons = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
          child: const Text('Hủy'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(_isEditing ? Icons.save : Icons.send, size: 18),
          label: Text(_isSubmitting ? 'Đang lưu...' : (_isEditing ? 'Cập nhật' : 'Tạo bài')),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
        ),
      ],
    );

    if (isMobile) {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Scaffold(
            appBar: AppBar(
              title: Text(dialogTitle),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Form(
              key: _formKey,
              child: bodyContent,
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.all(16),
              child: actionButtons,
            ),
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.78,
        height: MediaQuery.of(context).size.height * 0.92,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF0F2340)]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_isEditing ? Icons.edit : Icons.add, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(dialogTitle,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 24, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 16),
              Expanded(child: bodyContent),
              const SizedBox(height: 16),
              const Divider(height: 24, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 16),
              actionButtons,
            ],
          ),
        ),
      ),
    );
  }
}
