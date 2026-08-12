import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_tr.dart';
import '../models/hrm.dart';
import '../screens/main_layout.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../utils/notification_display_utils.dart';
import '../widgets/pos/pos_theme.dart';

/// Danh sách thông báo hệ thống cho app POS (độc lập, không phụ thuộc MainLayout HRM).
class PosNotificationsScreen extends StatefulWidget {
  const PosNotificationsScreen({super.key});

  @override
  State<PosNotificationsScreen> createState() => _PosNotificationsScreenState();
}

class _PosNotificationsScreenState extends State<PosNotificationsScreen> {
  final _api = ApiService();
  final _signalR = SignalRService();
  final _scroll = ScrollController();
  final _dt = DateFormat('dd/MM HH:mm');

  List<AppNotification> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  final int _pageSize = 20;
  bool _hasMore = true;
  int _unread = 0;
  bool? _unreadOnly;

  StreamSubscription? _newSub;
  StreamSubscription? _readSub;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    ScreenRefreshNotifier.notifications.addListener(_onExternalRefresh);
    _load(reset: true);
    _bindSignalR();
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.notifications.removeListener(_onExternalRefresh);
    _newSub?.cancel();
    _readSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onExternalRefresh() {
    if (mounted) _load(reset: true);
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _bindSignalR() async {
    try {
      await _newSub?.cancel();
      await _readSub?.cancel();
      if (!_signalR.isConnected) {
        await _signalR.connect();
      }
      _newSub = _signalR.onNewNotification.listen((data) {
        try {
          final n = AppNotification.fromJson(data);
          if (!mounted) return;
          if (_items.any((e) => e.id == n.id)) return;
          if (_unreadOnly == true && n.isRead) return;
          setState(() {
            _items.insert(0, n);
            if (!n.isRead) _unread++;
          });
        } catch (_) {}
      });
      _readSub = _signalR.onNotificationRead.listen((data) {
        final id = (data['id'] ?? data['Id'])?.toString();
        final all = data['all'] == true || data['All'] == true;
        if (!mounted) return;
        setState(() {
          if (all) {
            _items = _items
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
                        fromUserName: n.fromUserName,
                        categoryLabel: n.categoryLabel,
                        displayTitle: n.displayTitle,
                        displayBody: n.displayBody,
                        createdAt: n.createdAt,
                      ))
                .toList();
            _unread = 0;
          } else if (id != null && id.isNotEmpty) {
            final i = _items.indexWhere((n) => n.id == id);
            if (i >= 0 && !_items[i].isRead) {
              final old = _items[i];
              _items[i] = AppNotification(
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
                fromUserName: old.fromUserName,
                categoryLabel: old.categoryLabel,
                displayTitle: old.displayTitle,
                displayBody: old.displayBody,
                createdAt: old.createdAt,
              );
              _unread = (_unread - 1).clamp(0, 9999);
            }
          }
        });
        ScreenRefreshNotifier.refreshNotificationCount();
      });
    } catch (e) {
      debugPrint('PosNotifications SignalR: $e');
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    }
    try {
      final summary = await _api.getNotificationSummary();
      final unread = summary['unreadCount'];
      final result = await _api.getNotifications(
        page: 1,
        pageSize: _pageSize,
        isRead: _unreadOnly == null ? null : !_unreadOnly!,
      );
      if (!mounted) return;
      final raw = (result['items'] as List?) ?? const [];
      final items = raw
          .whereType<Map>()
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        _items = items;
        _unread = unread is int ? unread : int.tryParse('$unread') ?? 0;
        _page = 1;
        _hasMore = items.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final result = await _api.getNotifications(
        page: next,
        pageSize: _pageSize,
        isRead: _unreadOnly == null ? null : !_unreadOnly!,
      );
      if (!mounted) return;
      final raw = (result['items'] as List?) ?? const [];
      final more = raw
          .whereType<Map>()
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        _items = [..._items, ...more];
        _page = next;
        _hasMore = more.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _markAllRead() async {
    final res = await _api.markAllNotificationsAsRead();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _items = _items
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
                    fromUserName: n.fromUserName,
                    categoryLabel: n.categoryLabel,
                    displayTitle: n.displayTitle,
                    displayBody: n.displayBody,
                    createdAt: n.createdAt,
                  ))
            .toList();
        _unread = 0;
      });
      ScreenRefreshNotifier.refreshNotificationCount();
    }
  }

  Future<bool> _deleteOne(String id) async {
    final res = await _api.deleteNotification(id);
    if (!mounted) return false;
    if (res['isSuccess'] != true) return false;
    setState(() {
      final i = _items.indexWhere((n) => n.id == id);
      if (i >= 0) {
        if (!_items[i].isRead) _unread = (_unread - 1).clamp(0, 9999);
        _items.removeAt(i);
      }
    });
    ScreenRefreshNotifier.refreshNotificationCount();
    return true;
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa tất cả thông báo?')),
        content: Text(tr('Hành động này không thể hoàn tác.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(tr('Xóa tất cả')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final isReadParam =
        _unreadOnly == null ? null : (_unreadOnly! ? false : true);
    final res = await _api.deleteAllNotifications(isRead: isReadParam);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load(reset: true);
      ScreenRefreshNotifier.refreshNotificationCount();
    }
  }

  Future<void> _openItem(AppNotification n) async {
    if (!n.isRead && n.id.isNotEmpty) {
      unawaited(_api.markNotificationAsRead(n.id));
      setState(() {
        final i = _items.indexWhere((e) => e.id == n.id);
        if (i >= 0) {
          final old = _items[i];
          _items[i] = AppNotification(
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
            fromUserName: old.fromUserName,
            categoryLabel: old.categoryLabel,
            displayTitle: old.displayTitle,
            displayBody: old.displayBody,
            createdAt: old.createdAt,
          );
          _unread = (_unread - 1).clamp(0, 9999);
        }
      });
      ScreenRefreshNotifier.refreshNotificationCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        title: Text(tr('Thông báo')),
        actions: [
          if (_unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                tr('Đọc hết'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: tr('Xóa tất cả'),
              onPressed: _deleteAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(tr('Tất cả')),
                    selected: _unreadOnly == null,
                    onSelected: (_) {
                      setState(() => _unreadOnly = null);
                      _load(reset: true);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(tr('Chưa đọc$_unreadLabel')),
                    selected: _unreadOnly == true,
                    onSelected: (_) {
                      setState(() => _unreadOnly = true);
                      _load(reset: true);
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  String get _unreadLabel => _unread > 0 ? ' ($_unread)' : '';

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: PosTheme.kiotBlue));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr(_error!), style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _load(reset: true),
              child: Text(tr('Thử lại')),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(tr('Không có thông báo')));
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final n = _items[i];
          final display = resolveNotificationDisplay({
            'title': n.title,
            'message': n.message,
            'displayTitle': n.displayTitle,
            'displayBody': n.displayBody,
            'fromUserName': n.fromUserName,
            'categoryLabel': n.categoryLabel,
            'categoryCode': n.categoryCode,
            'relatedEntityType': n.relatedEntityType,
            'type': n.type.index,
          });
          final card = Material(
            color: n.isRead ? Colors.white : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openItem(n),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      n.isRead
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                      color: n.isRead
                          ? PosTheme.textSecondary
                          : PosTheme.kiotBlue,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            display.title,
                            style: TextStyle(
                              fontWeight:
                                  n.isRead ? FontWeight.w500 : FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (display.body.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              display.body,
                              style: const TextStyle(
                                fontSize: 13,
                                color: PosTheme.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            _dt.format(n.createdAt.toLocal()),
                            style: const TextStyle(
                              fontSize: 11,
                              color: PosTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Xóa'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.red.shade400,
                      ),
                      onPressed: () => unawaited(_deleteOne(n.id)),
                    ),
                  ],
                ),
              ),
            ),
          );
          return Dismissible(
            key: Key(n.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            confirmDismiss: (_) => _deleteOne(n.id),
            child: card,
          );
        },
      ),
    );
  }
}
