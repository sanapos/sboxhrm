import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/hrm.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/notifications/notification_category_meta.dart';
import '../utils/notification_navigation.dart';
import '../utils/admin_navigation.dart';
import '../services/api_service.dart';
import '../services/system_notification_service.dart';
import '../services/signalr_service.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import 'notification_settings_screen.dart';
import 'notifications/notification_composer_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import '../widgets/hrm_page_chrome.dart';

import '../theme/sbox_tokens.dart';

class NotificationsScreen extends StatefulWidget {
  final bool adminPortalMode;
  final bool agentMode;

  const NotificationsScreen({
    super.key,
    this.adminPortalMode = false,
    this.agentMode = false,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _apiService = ApiService();
  final SignalRService _signalRService = SignalRService();

  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  int _unreadCount = 0;
  int _totalCount = 0;
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMore = true;
  int _loadSeq = 0;

  /// Read filter: null = all, true = unread, false = read
  bool? _readFilter;

  /// Lọc theo loại (CategoryCode) — lọc phía server, kèm số chưa đọc từng loại.
  String? _category;
  List<({String code, int total, int unread})> _categoryCounts = [];

  final _searchCtl = TextEditingController();
  Timer? _searchDebounce;
  bool _searchOpen = false;

  StreamSubscription? _notificationSubscription;
  StreamSubscription? _notificationReadSubscription;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('vi', timeago.ViMessages());
    if (widget.adminPortalMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final auth = Provider.of<AuthProvider>(context, listen: false);
        Provider.of<PermissionProvider>(context, listen: false).loadPermissions(role: auth.userRole);
      });
    }
    _loadData();
    _connectSignalR();
    _scrollController.addListener(_onScroll);
    // Reload khi có thay đổi từ bên ngoài (ví dụ: bấm notification hệ thống)
    ScreenRefreshNotifier.notifications.addListener(_onExternalRefresh);
  }

  void _onExternalRefresh() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.notifications.removeListener(_onExternalRefresh);
    _notificationSubscription?.cancel();
    _notificationReadSubscription?.cancel();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _connectSignalR() async {
    try {
      await _notificationSubscription?.cancel();
      await _notificationReadSubscription?.cancel();
      if (!_signalRService.isConnected) {
        await _signalRService.connect();
      }
      _notificationSubscription = _signalRService.onNewNotification.listen(_handleNewNotification);
      _notificationReadSubscription = _signalRService.onNotificationRead.listen(_handleNotificationRead);
    } catch (e) {
      debugPrint('Error connecting SignalR: $e');
    }
  }

  bool _matchesFilters(AppNotification n) {
    if (_readFilter == false && !n.isRead) return false;
    if (_category != null && (n.categoryCode ?? 'none').toLowerCase() != _category) return false;
    final q = _searchCtl.text.trim().toLowerCase();
    if (q.isNotEmpty &&
        !n.effectiveTitle.toLowerCase().contains(q) &&
        !n.effectiveMessage.toLowerCase().contains(q)) {
      return false;
    }
    return true;
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final notification = AppNotification.fromJson(data);
      if (!mounted) return;
      final exists = _notifications.any((n) => n.id == notification.id);
      setState(() {
        if (!notification.isRead) _unreadCount++;
        _bumpCategory(notification.categoryCode, total: 1, unread: notification.isRead ? 0 : 1);
        if (!exists && _matchesFilters(notification)) {
          _notifications.insert(0, notification);
          _totalCount++;
        }
      });
    } catch (e) {
      debugPrint('Error handling notification: $e');
    }
  }

  void _bumpCategory(String? code, {int total = 0, int unread = 0}) {
    final c = (code ?? 'none').toLowerCase();
    final i = _categoryCounts.indexWhere((x) => x.code == c);
    if (i == -1) {
      if (total > 0) _categoryCounts.add((code: c, total: total, unread: unread.clamp(0, total)));
      return;
    }
    final old = _categoryCounts[i];
    _categoryCounts[i] = (
      code: c,
      total: (old.total + total).clamp(0, 1 << 30),
      unread: (old.unread + unread).clamp(0, 1 << 30),
    );
  }

  /// Sự kiện đọc / bỏ đọc từ thiết bị khác (hoặc chính máy này).
  void _handleNotificationRead(Map<String, dynamic> data) {
    try {
      if (!mounted) return;
      final id = (data['id'] ?? data['Id'])?.toString();
      final readAll = data['all'] == true || data['All'] == true;
      final unread = data['unread'] == true;
      final category = data['category']?.toString();
      if (readAll || (category != null && category.isNotEmpty)) {
        // Đọc hết / đọc cả nhóm — tải lại cho đúng số liệu.
        _loadData(silent: true);
        ScreenRefreshNotifier.refreshNotificationCount();
        return;
      }
      if (id == null || id.isEmpty) return;
      final index = _notifications.indexWhere((n) => n.id == id);
      if (index != -1 && _notifications[index].isRead == unread) {
        setState(() => _applyRead(index, !unread));
      }
      ScreenRefreshNotifier.refreshNotificationCount();
    } catch (e) {
      debugPrint('Error handling notification-read: $e');
    }
  }

  void _applyRead(int index, bool read) {
    final old = _notifications[index];
    if (old.isRead == read) return;
    _notifications[index] = old.withRead(read);
    _unreadCount = (_unreadCount + (read ? -1 : 1)).clamp(0, 1 << 30);
    _bumpCategory(old.categoryCode, unread: read ? -1 : 1);
  }

  Future<void> _loadData({bool silent = false}) async {
    final seq = ++_loadSeq;
    if (!silent) setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getNotifications(
          page: 1,
          pageSize: _pageSize,
          isRead: _readFilter == null ? null : (_readFilter! ? false : true),
          category: _category,
          search: _searchCtl.text,
        ),
        _apiService.getNotificationSummary(),
        _apiService.getNotificationCategoryCounts(),
      ]);
      if (!mounted || seq != _loadSeq) return;
      final result = results[0], summary = results[1], counts = results[2];
      setState(() {
        _notifications = (result['items'] as List).map((json) => AppNotification.fromJson(json)).toList();
        _totalCount = result['totalCount'] ?? 0;
        _currentPage = 1;
        _hasMore = _notifications.length < _totalCount;
        _unreadCount = summary['unreadCount'] ?? 0;
        if (counts['isSuccess'] == true && counts['data'] is List) {
          _categoryCounts = [
            for (final c in counts['data'] as List)
              (
                code: (c['code']?.toString() ?? 'none').toLowerCase(),
                total: (c['total'] as num?)?.toInt() ?? 0,
                unread: (c['unread'] as num?)?.toInt() ?? 0,
              ),
          ];
        }
      });
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (mounted && !silent) {
        appNotification.showError(title: 'Lỗi', message: tr('Lỗi tải thông báo: $e'));
      }
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _apiService.getNotifications(
        page: _currentPage + 1,
        pageSize: _pageSize,
        isRead: _readFilter == null ? null : (_readFilter! ? false : true),
        category: _category,
        search: _searchCtl.text,
      );
      final newItems = (result['items'] as List).map((json) => AppNotification.fromJson(json)).toList();
      if (!mounted) return;
      setState(() {
        final ids = _notifications.map((n) => n.id).toSet();
        _notifications.addAll(newItems.where((n) => !ids.contains(n.id)));
        _currentPage++;
        _hasMore = newItems.isNotEmpty && _notifications.length < _totalCount;
      });
    } catch (e) {
      debugPrint('Error loading more: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _loadData(silent: true));
    setState(() {});
  }

  Future<void> _setRead(AppNotification n, bool read) async {
    final index = _notifications.indexWhere((x) => x.id == n.id);
    if (index == -1 || _notifications[index].isRead == read) return;
    setState(() => _applyRead(index, read)); // cập nhật ngay, lỗi thì hoàn lại
    final result =
        read ? await _apiService.markNotificationAsRead(n.id) : await _apiService.markNotificationAsUnread(n.id);
    if (!mounted) return;
    if (result['isSuccess'] != true) {
      final i = _notifications.indexWhere((x) => x.id == n.id);
      if (i != -1) setState(() => _applyRead(i, !read));
      appNotification.showError(title: 'Lỗi', message: result['message']?.toString() ?? 'Không cập nhật được');
      return;
    }
    // Đang lọc "Chưa đọc" / "Đã đọc" → bỏ khỏi danh sách khi không còn khớp
    if ((_readFilter == true && read) || (_readFilter == false && !read)) {
      setState(() {
        _notifications.removeWhere((x) => x.id == n.id);
        _totalCount = (_totalCount - 1).clamp(0, 1 << 30);
      });
    }
    ScreenRefreshNotifier.refreshNotificationCount();
  }

  Future<void> _markAllAsRead() async {
    final cat = _category;
    final result = cat != null
        ? await _apiService.markNotificationCategoryAsRead(cat)
        : await _apiService.markAllNotificationsAsRead();
    if (result['isSuccess'] == true) {
      await _loadData(silent: true);
      if (!mounted) return;
      ScreenRefreshNotifier.refreshNotificationCount();
      if (_unreadCount == 0) {
        await SystemNotificationService().cancelAll();
      }
      if (mounted) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: tr(cat != null
              ? 'Đã đọc hết nhóm «${NotificationCategoryMeta.of(cat).label}»'
              : 'Đã đánh dấu tất cả đã đọc'),
        );
      }
    } else if (mounted) {
      appNotification.showError(title: 'Lỗi', message: result['message']?.toString() ?? '');
    }
  }

  Future<bool> _deleteNotification(String id) async {
    final result = await _apiService.deleteNotification(id);
    if (result['isSuccess'] == true) {
      if (!mounted) return true;
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == id);
        if (index != -1) {
          final n = _notifications[index];
          if (!n.isRead) _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
          _bumpCategory(n.categoryCode, total: -1, unread: n.isRead ? 0 : -1);
          _notifications.removeAt(index);
          _totalCount--;
        }
      });
      ScreenRefreshNotifier.refreshNotificationCount();
      return true;
    } else {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể xóa');
      }
      return false;
    }
  }

  Future<void> _deleteAllNotifications() async {
    final onlyRead = _readFilter == false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr(onlyRead ? 'Xóa tất cả thông báo đã đọc?' : 'Xóa tất cả thông báo?')),
        content: Text(tr('Hành động này không thể hoàn tác.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(tr('Xóa tất cả')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final isReadParam = _readFilter == null ? null : (_readFilter! ? false : true);
    final result = await _apiService.deleteAllNotifications(isRead: isReadParam);
    if (result['isSuccess'] == true) {
      await _loadData();
      ScreenRefreshNotifier.refreshNotificationCount();
      if (mounted) {
        appNotification.showSuccess(title: 'Thành công', message: tr('Đã xóa thông báo'));
      }
    } else if (mounted) {
      appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể xóa');
    }
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(tr('Cài đặt thông báo'))),
        body: const NotificationSettingsScreen(),
      ),
    ));
  }

  Future<void> _openComposer() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationComposerScreen()));
    if (mounted) _loadData(silent: true);
  }

  bool get _canCompose {
    if (widget.adminPortalMode || widget.agentMode) return false;
    try {
      return Provider.of<PermissionProvider>(context, listen: false).canCreate('Notification') &&
          Provider.of<AuthProvider>(context, listen: false).userRole != 'Employee';
    } catch (_) {
      return false;
    }
  }

  // == Helpers ==

  Map<String, List<AppNotification>> _groupByDate(List<AppNotification> items) {
    final map = <String, List<AppNotification>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final n in items) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      String label;
      if (d == today) {
        label = 'Hôm nay';
      } else if (d == yesterday) {
        label = 'Hôm qua';
      } else if (now.difference(d).inDays < 7) {
        label = DateFormat('EEEE', 'vi').format(n.createdAt);
        label = label[0].toUpperCase() + label.substring(1);
      } else {
        label = DateFormat('dd/MM/yyyy').format(n.createdAt);
      }
      map.putIfAbsent(label, () => []).add(n);
    }
    return map;
  }

  IconData _getIcon(AppNotification n) {
    if (n.relatedEntityType == 'Device' || n.relatedEntityType == 'DeviceStatus') {
      final t = n.title.toLowerCase();
      if (t.contains('ngắt') || t.contains('mất') || t.contains('offline')) return Icons.wifi_off;
      if (t.contains('kết nối') || t.contains('online') || t.contains('phát hiện')) return Icons.wifi;
      return Icons.router;
    }
    if (n.relatedEntityType == 'Attendance' || n.relatedEntityType == 'NewAttendance') {
      return Icons.fingerprint;
    }
    switch (n.type) {
      case NotificationType.warning:
        return Icons.warning_amber;
      case NotificationType.error:
        return Icons.error_outline;
      case NotificationType.success:
        return Icons.check_circle_outline;
      case NotificationType.leaveRequest:
        return Icons.event_busy;
      case NotificationType.advanceRequest:
        return Icons.attach_money;
      case NotificationType.scheduleRegistration:
        return Icons.calendar_today;
      case NotificationType.payslip:
        return Icons.receipt_long;
      case NotificationType.system:
        return Icons.settings;
      case NotificationType.approvalRequired:
        return Icons.approval;
      case NotificationType.reminder:
        return Icons.alarm;
      case NotificationType.attendanceCorrection:
        return Icons.edit_calendar;
      default:
        if (n.categoryCode != null) return NotificationCategoryMeta.of(n.categoryCode).icon;
        return Icons.notifications_outlined;
    }
  }

  Color _getColor(AppNotification n) {
    if (n.relatedEntityType == 'Device' || n.relatedEntityType == 'DeviceStatus') {
      final t = n.title.toLowerCase();
      if (t.contains('ngắt') || t.contains('mất') || t.contains('offline')) return SboxColors.danger;
      return SboxColors.success;
    }
    switch (n.type) {
      case NotificationType.warning:
        return SboxColors.warning;
      case NotificationType.error:
        return SboxColors.danger;
      case NotificationType.success:
        return SboxColors.success;
      case NotificationType.approvalRequired:
        return SboxColors.danger;
      default:
        if (n.categoryCode != null) return NotificationCategoryMeta.of(n.categoryCode).color;
        if (n.relatedEntityType == 'Attendance' || n.relatedEntityType == 'NewAttendance') {
          return SboxColors.brand500;
        }
        return HrmPageChrome.chipMid;
    }
  }

  void _navigateToRelated(AppNotification notification) {
    navigateFromNotification(
      relatedEntityType: notification.relatedEntityType,
      relatedEntityId: notification.relatedEntityId,
      title: notification.title,
      categoryCode: notification.categoryCode,
      actionUrl: notification.actionUrl,
      adminPortalMode: widget.adminPortalMode || AdminNavigationNotifier.systemAdminReady.value,
      agentMode: widget.agentMode,
    );
  }

  // == Build ==

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(_notifications);
    final List<dynamic> flatItems = [];
    for (final key in grouped.keys) {
      flatItems.add(key);
      flatItems.addAll(grouped[key]!);
    }
    if (_hasMore) flatItems.add(null);

    final content = Container(
      color: SboxColors.slate100,
      child: HrmResponsiveListLayout(
        headerSections: [_buildHeader()],
        desktopBody: _buildNotificationsBody(flatItems),
        mobileSlivers: (_) => _notificationsMobileSlivers(flatItems),
      ),
    );

    if (!widget.adminPortalMode) return content;

    return Scaffold(
      backgroundColor: SboxColors.slate100,
      appBar: AppBar(title: Text(tr('Thông báo')), centerTitle: false),
      body: SafeArea(top: false, child: content),
    );
  }

  Widget _emptyState() {
    final filtered = _category != null || _searchCtl.text.trim().isNotEmpty;
    return EmptyState(
      icon: filtered
          ? Icons.filter_alt_off_rounded
          : (_readFilter == true ? Icons.mark_email_read : Icons.notifications_off),
      title: filtered
          ? 'Không có thông báo phù hợp'
          : (_readFilter == true ? 'Không có thông báo chưa đọc' : 'Không có thông báo'),
      description: filtered
          ? 'Thử bỏ bớt bộ lọc hoặc từ khoá tìm kiếm'
          : (_readFilter == true ? 'Bạn đã xem hết — tuyệt vời!' : 'Chưa có thông báo nào'),
    );
  }

  Widget _itemAt(List<dynamic> flatItems, int i) {
    final item = flatItems[i];
    if (item == null) return _loadMoreFooter();
    if (item is String) return _buildDateHeader(item);
    return _buildNotificationCard(item as AppNotification);
  }

  Widget _loadMoreFooter() => Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: _loadingMore
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : OutlinedButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                  label: Text(tr('Xem thêm (${_totalCount - _notifications.length})')),
                ),
        ),
      );

  Widget _buildNotificationsBody(List<dynamic> flatItems) {
    if (_isLoading && _notifications.isEmpty) return const LoadingWidget();
    if (_notifications.isEmpty) return _emptyState();
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemCount: flatItems.length,
        itemBuilder: (_, i) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: _itemAt(flatItems, i),
          ),
        ),
      ),
    );
  }

  List<Widget> _notificationsMobileSlivers(List<dynamic> flatItems) {
    if (_isLoading && _notifications.isEmpty) {
      return [HrmScrollSlivers.fillRemaining(child: const LoadingWidget())];
    }
    if (_notifications.isEmpty) {
      return [HrmScrollSlivers.fillRemaining(child: _emptyState())];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((_, i) => _itemAt(flatItems, i), childCount: flatItems.length),
        ),
      ),
    ];
  }

  // ── Đầu trang: tiêu đề + tìm kiếm + lọc đọc + nhóm loại ──
  Widget _buildHeader() {
    final unreadInCat = _category == null
        ? _unreadCount
        : _categoryCounts.where((c) => c.code == _category).fold<int>(0, (s, c) => s + c.unread);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (_searchOpen)
            Expanded(
              child: TextField(
                controller: _searchCtl,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('Tìm trong thông báo…'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _searchCtl.clear();
                      setState(() => _searchOpen = false);
                      _loadData(silent: true);
                    },
                  ),
                  filled: true,
                  fillColor: SboxColors.slate100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            )
          else ...[
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: tr('Thông báo'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
                  if (_unreadCount > 0)
                    TextSpan(
                      text: '  ${tr('$_unreadCount chưa đọc')}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SboxColors.danger),
                    ),
                ]),
              ),
            ),
            _headerIcon(Icons.search_rounded, 'Tìm kiếm', () => setState(() => _searchOpen = true)),
          ],
          if (unreadInCat > 0)
            _headerIcon(Icons.done_all_rounded, _category == null ? 'Đánh dấu tất cả đã đọc' : 'Đọc hết nhóm này',
                _markAllAsRead,
                color: SboxColors.brand500),
          PopupMenuButton<String>(
            tooltip: tr('Tuỳ chọn'),
            icon: const Icon(Icons.more_vert_rounded, color: SboxColors.slate600),
            onSelected: (v) {
              switch (v) {
                case 'settings':
                  _openSettings();
                case 'delete':
                  _deleteAllNotifications();
                case 'refresh':
                  _loadData();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                    dense: true, leading: const Icon(Icons.refresh_rounded), title: Text(tr('Tải lại'))),
              ),
              if (!widget.adminPortalMode)
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.tune_rounded),
                      title: Text(tr('Cài đặt thông báo')),
                      subtitle: Text(tr('Giờ yên lặng, nhóm nhận'))),
                ),
              if (_notifications.isNotEmpty)
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade400),
                    title: Text(tr(_readFilter == false ? 'Xoá tất cả đã đọc' : 'Xoá tất cả'),
                        style: TextStyle(color: Colors.red.shade400)),
                  ),
                ),
            ],
          ),
        ]),
        if (_canCompose)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _openComposer,
                icon: const Icon(Icons.campaign_rounded, size: 18),
                label: Text(tr('Gửi thông báo cho nhân viên')),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ),
          ),
        const SizedBox(height: 8),
        // Trạng thái đọc
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _readChip('Tất cả', null),
            const SizedBox(width: 6),
            _readChip('Chưa đọc', true, count: _unreadCount),
            const SizedBox(width: 6),
            _readChip('Đã đọc', false),
          ]),
        ),
        if (_categoryCounts.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _categoryChip(null),
              for (final c in _categoryCounts) _categoryChip(c),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _headerIcon(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) => IconButton(
        tooltip: tr(tooltip),
        onPressed: onTap,
        icon: Icon(icon, color: color ?? SboxColors.slate600),
      );

  Widget _readChip(String label, bool? value, {int? count}) {
    final active = _readFilter == value;
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      selected: active,
      showCheckmark: false,
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(tr(label), style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        if (count != null && count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: SboxColors.danger, borderRadius: BorderRadius.circular(10)),
            child: Text(count > 99 ? '99+' : '$count',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
      onSelected: (_) {
        setState(() => _readFilter = value);
        _loadData();
      },
    );
  }

  Widget _categoryChip(({String code, int total, int unread})? c) {
    final code = c?.code;
    final active = _category == code;
    final meta = code == null ? null : NotificationCategoryMeta.of(code);
    final color = meta?.color ?? SboxColors.brand500;
    final unread = c?.unread ?? 0;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () {
          setState(() => _category = active ? null : code);
          _loadData();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.12) : SboxColors.slate50,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: active ? color.withValues(alpha: 0.5) : SboxColors.slate200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(meta?.icon ?? Icons.apps_rounded, size: 15, color: active ? color : SboxColors.slate500),
            const SizedBox(width: 5),
            Text(tr(meta?.label ?? 'Mọi loại'),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? color : SboxColors.slate700)),
            if (unread > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Text(unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildDateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6, left: 4),
      child: Text(
        tr(label),
        style: const TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w700, color: SboxColors.slate500, letterSpacing: 0.3),
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification n) {
    final color = _getColor(n);
    final icon = _getIcon(n);
    final hasNav = canNavigateFromNotification(
      relatedEntityType: n.relatedEntityType,
      categoryCode: n.categoryCode,
      actionUrl: n.actionUrl,
      title: n.title,
    );
    final catLabel = (n.categoryLabel != null && n.categoryLabel!.isNotEmpty)
        ? n.categoryLabel!
        : (n.categoryCode != null ? NotificationCategoryMeta.of(n.categoryCode).label : null);

    final card = Material(
      color: n.isRead ? Colors.white : color.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (!n.isRead) unawaited(_setRead(n, true));
          _navigateToRelated(n);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: n.isRead ? SboxColors.slate200 : color.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: n.isRead ? SboxColors.slate100 : color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: n.isRead ? SboxColors.slate400 : color, size: 21),
              ),
              if (!n.isRead)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: SboxColors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (catLabel != null)
                    Flexible(
                      child: Text(tr(catLabel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: n.isRead ? SboxColors.slate400 : color)),
                    ),
                  if (catLabel != null)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text('·', style: TextStyle(fontSize: 11, color: SboxColors.slate400)),
                    ),
                  Text(tr(timeago.format(n.createdAt, locale: 'vi')),
                      style: const TextStyle(fontSize: 11, color: SboxColors.slate400)),
                ]),
                const SizedBox(height: 2),
                Text(
                  tr(n.effectiveTitle),
                  style: TextStyle(
                    fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                    fontSize: 14,
                    color: n.isRead ? SboxColors.slate600 : SboxColors.slate900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                _ExpandableText(
                  text: tr(n.effectiveMessage),
                  style: TextStyle(
                      fontSize: 13, height: 1.4, color: n.isRead ? SboxColors.slate500 : SboxColors.slate700),
                ),
                if (hasNav || (n.fromUserName ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      if ((n.fromUserName ?? '').isNotEmpty) ...[
                        const Icon(Icons.person_outline_rounded, size: 13, color: SboxColors.slate400),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(n.fromUserName!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (hasNav)
                        Text(tr('Xem chi tiết ›'),
                            style: const TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w700, color: SboxColors.brand500)),
                    ]),
                  ),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: tr('Tuỳ chọn'),
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const Icon(Icons.more_horiz_rounded, color: SboxColors.slate400),
              onSelected: (v) {
                if (v == 'read') _setRead(n, true);
                if (v == 'unread') _setRead(n, false);
                if (v == 'delete') _deleteNotification(n.id);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: n.isRead ? 'unread' : 'read',
                  child: ListTile(
                    dense: true,
                    leading: Icon(n.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined),
                    title: Text(tr(n.isRead ? 'Đánh dấu chưa đọc' : 'Đánh dấu đã đọc')),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
                    title: Text(tr('Xoá'), style: TextStyle(color: Colors.red.shade400)),
                  ),
                ),
              ],
            ),
          ]),
        ),
      ),
    );

    // Vuốt phải: đọc / chưa đọc · Vuốt trái: xoá
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Dismissible(
        key: Key('n_${n.id}'),
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          decoration: BoxDecoration(color: SboxColors.brand500, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(n.isRead ? Icons.mark_email_unread_rounded : Icons.mark_email_read_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Text(tr(n.isRead ? 'Chưa đọc' : 'Đã đọc'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ]),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            await _setRead(n, !n.isRead);
            return false; // giữ thẻ, chỉ đổi trạng thái
          }
          return _deleteNotification(n.id);
        },
        child: card,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expandable text widget — shows up to 3 lines with "Xem thêm" / "Thu gọn"
// ---------------------------------------------------------------------------
class _ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _ExpandableText({required this.text, required this.style});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: tr(widget.text), style: widget.style),
          maxLines: 3,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);

        final isOverflow = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(widget.text),
              style: widget.style,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (isOverflow || _expanded)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    tr(_expanded ? 'Thu gọn' : 'Xem thêm'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SboxColors.brand500),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
