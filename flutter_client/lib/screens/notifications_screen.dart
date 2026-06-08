import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/hrm.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import '../utils/notification_navigation.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _apiService = ApiService();
  final SignalRService _signalRService = SignalRService();

  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  int _unreadCount = 0;
  int _totalCount = 0;
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMore = true;

  /// Read filter: null = all, true = unread, false = read
  bool? _readFilter;

  /// Entity type filter: null = all
  String? _entityFilter;

  StreamSubscription? _notificationSubscription;
  StreamSubscription? _notificationReadSubscription;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('vi', timeago.ViMessages());
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
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _connectSignalR() async {
    try {
      // Cancel previous subscriptions before creating new ones
      await _notificationSubscription?.cancel();
      await _notificationReadSubscription?.cancel();

      if (!_signalRService.isConnected) {
        await _signalRService.connect();
      }
      _notificationSubscription =
          _signalRService.onNewNotification.listen(_handleNewNotification);
      _notificationReadSubscription =
          _signalRService.onNotificationRead.listen(_handleNotificationRead);
    } catch (e) {
      debugPrint('Error connecting SignalR: $e');
    }
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final notification = AppNotification.fromJson(data);
      // Dedup is enforced at the SignalRService layer, but keep a local guard
      // to protect against a paginated reload racing with a live event.
      final exists = _notifications.any((n) => n.id == notification.id);
      if (!exists) {
        if (!mounted) return;
        setState(() {
          _notifications.insert(0, notification);
          if (!notification.isRead) _unreadCount++;
          _totalCount++;
        });
      }
    } catch (e) {
      debugPrint('Error handling notification: $e');
    }
  }

  void _handleNotificationRead(Map<String, dynamic> data) {
    try {
      final id = (data['id'] ?? data['Id'])?.toString();
      if (id == null || id.isEmpty) return;
      final readAll = data['all'] == true || data['All'] == true;
      if (!mounted) return;
      setState(() {
        if (readAll) {
          _notifications = _notifications
              .map((n) => n.isRead
                  ? n
                  : AppNotification(
                      id: n.id,
                      userId: n.userId,
                      title: n.title,
                      message: n.message,
                      type: n.type,
                      isRead: true,
                      readAt: DateTime.now(),
                      actionUrl: n.actionUrl,
                      relatedEntityId: n.relatedEntityId,
                      relatedEntityType: n.relatedEntityType,
                      categoryCode: n.categoryCode,
                      createdAt: n.createdAt,
                    ))
              .toList();
          _unreadCount = 0;
        } else {
          final index = _notifications.indexWhere((n) => n.id == id);
          if (index != -1 && !_notifications[index].isRead) {
            final old = _notifications[index];
            _notifications[index] = AppNotification(
              id: old.id,
              userId: old.userId,
              title: old.title,
              message: old.message,
              type: old.type,
              isRead: true,
              readAt: DateTime.now(),
              actionUrl: old.actionUrl,
              relatedEntityId: old.relatedEntityId,
              relatedEntityType: old.relatedEntityType,
              categoryCode: old.categoryCode,
              createdAt: old.createdAt,
            );
            _unreadCount = (_unreadCount - 1).clamp(0, _totalCount);
          }
        }
      });
      ScreenRefreshNotifier.refreshNotificationCount();
    } catch (e) {
      debugPrint('Error handling notification-read: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.getNotifications(
        page: 1,
        pageSize: _pageSize,
        isRead: _readFilter == null ? null : (_readFilter! ? false : true),
      );
      final summary = await _apiService.getNotificationSummary();

      setState(() {
        _notifications = (result['items'] as List)
            .map((json) => AppNotification.fromJson(json))
            .toList();
        _totalCount = result['totalCount'] ?? 0;
        _currentPage = 1;
        _hasMore = _notifications.length < _totalCount;
        _unreadCount = summary['unreadCount'] ?? 0;
      });
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (mounted) {
        appNotification.showError(
            title: 'Lỗi', message: 'Lỗi tải thông báo: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.getNotifications(
        page: _currentPage + 1,
        pageSize: _pageSize,
        isRead: _readFilter == null ? null : (_readFilter! ? false : true),
      );
      final newItems = (result['items'] as List)
          .map((json) => AppNotification.fromJson(json))
          .toList();
      setState(() {
        _notifications.addAll(newItems);
        _currentPage++;
        _hasMore = _notifications.length < _totalCount;
      });
    } catch (e) {
      debugPrint('Error loading more: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(String id) async {
    final result = await _apiService.markNotificationAsRead(id);
    if (result['isSuccess'] == true) {
      if (mounted) {
        setState(() {
          final index = _notifications.indexWhere((n) => n.id == id);
          if (index != -1 && !_notifications[index].isRead) {
            final old = _notifications[index];
            _notifications[index] = AppNotification(
              id: old.id,
              userId: old.userId,
              title: old.title,
              message: old.message,
              type: old.type,
              isRead: true,
              readAt: DateTime.now(),
              actionUrl: old.actionUrl,
              relatedEntityId: old.relatedEntityId,
              relatedEntityType: old.relatedEntityType,
              categoryCode: old.categoryCode,
              createdAt: old.createdAt,
            );
            _unreadCount = (_unreadCount - 1).clamp(0, _totalCount);
          }
        });
      }
      ScreenRefreshNotifier.refreshNotificationCount();
    }
  }

  Future<void> _markAllAsRead() async {
    final result = await _apiService.markAllNotificationsAsRead();
    if (result['isSuccess'] == true) {
      final summary = await _apiService.getNotificationSummary();
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((n) => AppNotification(
                  id: n.id,
                  userId: n.userId,
                  title: n.title,
                  message: n.message,
                  type: n.type,
                  isRead: true,
                  readAt: DateTime.now(),
                  actionUrl: n.actionUrl,
                  relatedEntityId: n.relatedEntityId,
                  relatedEntityType: n.relatedEntityType,
                  categoryCode: n.categoryCode,
                  createdAt: n.createdAt,
                ))
            .toList();
        _unreadCount = summary['unreadCount'] ?? 0;
      });
      ScreenRefreshNotifier.refreshNotificationCount();
      if (mounted) {
        appNotification.showSuccess(
            title: 'Thành công', message: 'Đã đánh dấu tất cả đã đọc');
      }
    }
  }

  Future<bool> _deleteNotification(String id) async {
    final result = await _apiService.deleteNotification(id);
    if (result['isSuccess'] == true) {
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == id);
        if (index != -1) {
          if (!_notifications[index].isRead) {
            _unreadCount = (_unreadCount - 1).clamp(0, _totalCount);
          }
          _notifications.removeAt(index);
          _totalCount--;
        }
      });
      ScreenRefreshNotifier.refreshNotificationCount();
      return true;
    } else {
      if (mounted) {
        appNotification.showError(
            title: 'Lỗi', message: result['message'] ?? 'Không thể xóa');
      }
      return false;
    }
  }

  Future<void> _deleteAllNotifications() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Xóa tất cả thông báo?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa tất cả'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final isReadParam =
        _readFilter == null ? null : (_readFilter! ? false : true);
    final result =
        await _apiService.deleteAllNotifications(isRead: isReadParam);
    if (result['isSuccess'] == true) {
      await _loadData();
      ScreenRefreshNotifier.refreshNotificationCount();
      if (mounted) {
        appNotification.showSuccess(
            title: 'Thành công', message: 'Đã xóa tất cả thông báo');
      }
    } else {
      if (mounted) {
        appNotification.showError(
            title: 'Lỗi', message: result['message'] ?? 'Không thể xóa');
      }
    }
  }

  // == Helpers ==

  List<AppNotification> get _filteredNotifications {
    if (_entityFilter == null) return _notifications;
    return _notifications.where((n) {
      final et = n.relatedEntityType?.toLowerCase() ?? '';
      if (_entityFilter == 'attendance') {
        return et == 'attendance' || et == 'newattendance';
      }
      if (_entityFilter == 'device') {
        return et == 'device' || et == 'devicestatus' || et == 'admsdevice';
      }
      return et != 'attendance' &&
          et != 'newattendance' &&
          et != 'device' &&
          et != 'devicestatus' &&
          et != 'admsdevice';
    }).toList();
  }

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
    if (n.relatedEntityType == 'Device' ||
        n.relatedEntityType == 'DeviceStatus') {
      final t = n.title.toLowerCase();
      if (t.contains('ngắt') || t.contains('mất') || t.contains('offline')) {
        return Icons.wifi_off;
      }
      if (t.contains('kết nối') ||
          t.contains('online') ||
          t.contains('phát hiện')) {
        return Icons.wifi;
      }
      return Icons.router;
    }
    if (n.relatedEntityType == 'Attendance' ||
        n.relatedEntityType == 'NewAttendance') {
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
        return Icons.notifications_outlined;
    }
  }

  Color _getColor(AppNotification n) {
    if (n.relatedEntityType == 'Device' ||
        n.relatedEntityType == 'DeviceStatus') {
      final t = n.title.toLowerCase();
      if (t.contains('ngắt') || t.contains('mất') || t.contains('offline')) {
        return const Color(0xFFEF4444);
      }
      return const Color(0xFF22C55E);
    }
    if (n.relatedEntityType == 'Attendance' ||
        n.relatedEntityType == 'NewAttendance') {
      return const Color(0xFF3B82F6);
    }
    switch (n.type) {
      case NotificationType.warning:
        return const Color(0xFFF59E0B);
      case NotificationType.error:
        return const Color(0xFFEF4444);
      case NotificationType.success:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF6366F1);
    }
  }

  void _navigateToRelated(AppNotification notification) {
    navigateFromNotification(
      relatedEntityType: notification.relatedEntityType,
      relatedEntityId: notification.relatedEntityId,
      title: notification.title,
      categoryCode: notification.categoryCode,
      actionUrl: notification.actionUrl,
    );
  }

  // == Build ==

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNotifications;
    final grouped = _groupByDate(filtered);
    final dateKeys = grouped.keys.toList();

    final List<dynamic> flatItems = [];
    for (final key in dateKeys) {
      flatItems.add(key);
      flatItems.addAll(grouped[key]!);
    }
    if (_hasMore) flatItems.add(null);

    return Container(
      color: const Color(0xFFF4F4F5),
      child: HrmResponsiveListLayout(
        headerSections: [_buildFilterBar()],
        desktopBody: _buildNotificationsBody(filtered, flatItems),
        mobileSlivers: (_) => _notificationsMobileSlivers(filtered, flatItems),
      ),
    );
  }

  Widget _buildNotificationsBody(List<AppNotification> filtered, List<dynamic> flatItems) {
    return _isLoading && _notifications.isEmpty
        ? const LoadingWidget()
        : filtered.isEmpty
            ? EmptyState(
                icon: _readFilter == true
                    ? Icons.mark_email_read
                    : Icons.notifications_off,
                title: _readFilter == true
                    ? 'Không có thông báo chưa đọc'
                    : 'Không có thông báo',
                description: _readFilter == true
                    ? 'Tất cả đã được đọc'
                    : 'Chưa có thông báo nào',
              )
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: flatItems.length,
                  itemBuilder: (_, i) {
                    final item = flatItems[i];
                    if (item == null) {
                      return const Center(
                          child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator()));
                    }
                    if (item is String) return _buildDateHeader(item);
                    return _buildNotificationCard(item as AppNotification);
                  },
                ),
              );
  }

  List<Widget> _notificationsMobileSlivers(
      List<AppNotification> filtered, List<dynamic> flatItems) {
    if (_isLoading && _notifications.isEmpty) {
      return [HrmScrollSlivers.fillRemaining(child: const LoadingWidget())];
    }
    if (filtered.isEmpty) {
      return [
        HrmScrollSlivers.fillRemaining(
          child: EmptyState(
            icon: _readFilter == true
                ? Icons.mark_email_read
                : Icons.notifications_off,
            title: _readFilter == true
                ? 'Không có thông báo chưa đọc'
                : 'Không có thông báo',
            description: _readFilter == true
                ? 'Tất cả đã được đọc'
                : 'Chưa có thông báo nào',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final item = flatItems[i];
              if (item == null) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator()));
              }
              if (item is String) return _buildDateHeader(item);
              return _buildNotificationCard(item as AppNotification);
            },
            childCount: flatItems.length,
          ),
        ),
      ),
    ];
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              _chip('Tất cả', _readFilter == null, () {
                setState(() => _readFilter = null);
                _loadData();
              }),
              const SizedBox(width: 6),
              _chip('Chưa đọc', _readFilter == true, () {
                setState(() => _readFilter = true);
                _loadData();
              }, count: _unreadCount, activeColor: const Color(0xFFEF4444)),
              const SizedBox(width: 6),
              _chip('Đã đọc', _readFilter == false, () {
                setState(() => _readFilter = false);
                _loadData();
              }, activeColor: const Color(0xFF22C55E)),
              Container(
                  width: 1,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: Colors.grey.shade300),
              _iconChip(
                  Icons.fingerprint,
                  'Chấm công',
                  _entityFilter == 'attendance',
                  () => setState(() => _entityFilter =
                      _entityFilter == 'attendance' ? null : 'attendance'),
                  activeColor: const Color(0xFF3B82F6)),
              const SizedBox(width: 6),
              _iconChip(
                  Icons.router,
                  'Thiết bị',
                  _entityFilter == 'device',
                  () => setState(() => _entityFilter =
                      _entityFilter == 'device' ? null : 'device'),
                  activeColor: const Color(0xFF22C55E)),
              const SizedBox(width: 6),
              _iconChip(
                  Icons.more_horiz,
                  'Khác',
                  _entityFilter == 'other',
                  () => setState(() => _entityFilter =
                      _entityFilter == 'other' ? null : 'other'),
                  activeColor: const Color(0xFF6366F1)),
              if (_unreadCount > 0 || _notifications.isNotEmpty) ...[
                Container(
                    width: 1,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: Colors.grey.shade300),
                if (_unreadCount > 0)
                  _actionIcon(
                      Icons.done_all, 'Đánh dấu đã đọc', _markAllAsRead),
                if (_notifications.isNotEmpty &&
                    Provider.of<PermissionProvider>(context, listen: false)
                        .canDelete('Notification')) ...[
                  const SizedBox(width: 4),
                  _actionIcon(Icons.delete_sweep_outlined, 'Xóa tất cả',
                      _deleteAllNotifications,
                      color: Colors.red.shade400),
                ],
              ],
            ]),
          ),
          Container(height: 1, color: Colors.grey.shade200),
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon, String tooltip, VoidCallback onTap,
      {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color ?? Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap,
      {int? count, Color? activeColor}) {
    final color = activeColor ?? Theme.of(context).primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color:
                  active ? color.withValues(alpha: 0.4) : Colors.grey.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? color : Colors.grey.shade600)),
          if (count != null && count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(10)),
              child: Text(count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _iconChip(IconData icon, String label, bool active, VoidCallback onTap,
      {Color? activeColor}) {
    final color = activeColor ?? Theme.of(context).primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color:
                  active ? color.withValues(alpha: 0.4) : Colors.grey.shade200),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: active ? color : Colors.grey.shade500),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? color : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  // == Expandable message text ==

  Widget _buildExpandableMessage(AppNotification n) {
    final style = TextStyle(
      fontSize: 13,
      height: 1.4,
      color: n.isRead ? Colors.grey.shade500 : Colors.grey.shade700,
    );
    return _ExpandableText(text: n.effectiveMessage, style: style);
  }

  Widget _buildDateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6, left: 4),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
            letterSpacing: 0.3),
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification n) {
    final color = _getColor(n);
    final icon = _getIcon(n);
    final canDelete = Provider.of<PermissionProvider>(context, listen: false)
        .canDelete('Notification');
    final hasNav = canNavigateFromNotification(
      relatedEntityType: n.relatedEntityType,
      categoryCode: n.categoryCode,
      actionUrl: n.actionUrl,
      title: n.title,
    );

    final card = Material(
      color: n.isRead ? Colors.white : color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (!n.isRead) await _markAsRead(n.id);
          _navigateToRelated(n);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: n.isRead
                  ? Colors.grey.shade200
                  : color.withValues(alpha: 0.25),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: n.isRead
                      ? Colors.grey.shade100
                      : color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    color: n.isRead ? Colors.grey.shade400 : color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (!n.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (n.categoryLabel != null &&
                                n.categoryLabel!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  n.categoryLabel!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: n.isRead
                                        ? Colors.grey.shade400
                                        : color,
                                  ),
                                ),
                              ),
                            Text(
                              n.effectiveTitle,
                              style: TextStyle(
                                fontWeight:
                                    n.isRead ? FontWeight.w500 : FontWeight.w700,
                                fontSize: 14,
                                color: n.isRead
                                    ? Colors.grey.shade600
                                    : Colors.grey.shade900,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (hasNav)
                        Icon(Icons.chevron_right,
                            size: 18, color: Colors.grey.shade400),
                    ]),
                    const SizedBox(height: 4),
                    _buildExpandableMessage(n),
                    const SizedBox(height: 6),
                    Text(
                      timeago.format(n.createdAt, locale: 'vi'),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: canDelete
          ? Dismissible(
              key: Key(n.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              confirmDismiss: (_) => _deleteNotification(n.id),
              child: card,
            )
          : card,
    );
  }
}

// ---------------------------------------------------------------------------
// Expandable text widget — shows up to 3 lines with "Xem thêm" / "Thu gọn"
// ---------------------------------------------------------------------------
class _ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _ExpandableText({
    required this.text,
    required this.style,
  });

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
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 3,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);

        final isOverflow = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
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
                    _expanded ? 'Thu gọn' : 'Xem thêm',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade500,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
