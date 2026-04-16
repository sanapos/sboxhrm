import 'dart:async';
import 'package:flutter/material.dart';
import '../models/hrm.dart';
import '../utils/notification_sound.dart';

/// Global key để truy cập NotificationOverlay từ bất kỳ đâu
class NotificationOverlayManager {
  static final NotificationOverlayManager _instance =
      NotificationOverlayManager._internal();
  factory NotificationOverlayManager() => _instance;
  NotificationOverlayManager._internal();

  final List<NotificationOverlayItem> _notifications = [];
  final _controller = StreamController<List<NotificationOverlayItem>>.broadcast();

  Stream<List<NotificationOverlayItem>> get stream => _controller.stream;
  List<NotificationOverlayItem> get notifications =>
      List.unmodifiable(_notifications);

  /// Hiển thị thông báo popup
  void show({
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
    String? relatedEntityType,
    Duration duration = const Duration(seconds: 2),
    VoidCallback? onTap,
  }) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final item = NotificationOverlayItem(
      id: id,
      title: title,
      message: message,
      type: type,
      relatedEntityType: relatedEntityType,
      onTap: onTap,
    );

    _notifications.insert(0, item);
    _controller.add(_notifications);

    // Phát âm thanh thông báo
    NotificationSound().play();

    // Auto remove sau duration
    Future.delayed(duration, () => remove(id));
  }

  /// Helper: Hiển thị thông báo thành công
  void showSuccess(
      {required String title, required String message, VoidCallback? onTap}) {
    show(
      title: title,
      message: message,
      type: NotificationType.success,
      onTap: onTap,
    );
  }

  /// Helper: Hiển thị thông báo lỗi
  void showError(
      {required String title, required String message, VoidCallback? onTap}) {
    show(
      title: title,
      message: message,
      type: NotificationType.error,
      onTap: onTap,
    );
  }

  /// Helper: Hiển thị thông báo cảnh báo
  void showWarning(
      {required String title, required String message, VoidCallback? onTap}) {
    show(
      title: title,
      message: message,
      type: NotificationType.warning,
      onTap: onTap,
    );
  }

  /// Helper: Hiển thị thông báo thông tin
  void showInfo(
      {required String title, required String message, VoidCallback? onTap}) {
    show(
      title: title,
      message: message,
      type: NotificationType.info,
      onTap: onTap,
    );
  }

  /// Xóa thông báo theo id
  void remove(String id) {
    _notifications.removeWhere((n) => n.id == id);
    _controller.add(_notifications);
  }

  /// Xóa tất cả thông báo
  void clear() {
    _notifications.clear();
    _controller.add(_notifications);
  }

  void dispose() {
    _controller.close();
  }
}

/// Global instance để sử dụng từ bất kỳ đâu
final appNotification = NotificationOverlayManager();

class NotificationOverlayItem {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final String? relatedEntityType; // For device notifications
  final VoidCallback? onTap;
  final DateTime createdAt;

  NotificationOverlayItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.relatedEntityType,
    this.onTap,
  }) : createdAt = DateTime.now();
}

/// Widget hiển thị thông báo overlay ở góc phải trên
class NotificationOverlay extends StatefulWidget {
  final Widget child;

  const NotificationOverlay({super.key, required this.child});

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay> {
  final _manager = NotificationOverlayManager();
  StreamSubscription? _subscription;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _subscription = _manager.stream.listen((items) {
      _updateOverlay(items);
    });
    // Khởi tạo overlay sau frame đầu tiên
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateOverlay(_manager.notifications);
    });
  }

  void _updateOverlay(List<NotificationOverlayItem> items) {
    if (!mounted) return;
    _overlayEntry?.remove();
    _overlayEntry = null;

    if (items.isNotEmpty) {
      _overlayEntry = OverlayEntry(
        builder: (context) {
          final screenWidth = MediaQuery.of(context).size.width;
          final isMobile = screenWidth < 600;
          return Positioned(
            top: MediaQuery.of(context).padding.top + (isMobile ? 8 : 16),
            left: isMobile ? 8 : null,
            right: isMobile ? 8 : 16,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: isMobile ? null : 380,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: items
                      .take(5)
                      .map((item) => _NotificationCard(
                            key: ValueKey(item.id),
                            item: item,
                            onDismiss: () => _manager.remove(item.id),
                          ))
                      .toList(),
                ),
              ),
            ),
          );
        },
      );
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _NotificationCard extends StatefulWidget {
  final NotificationOverlayItem item;
  final VoidCallback onDismiss;

  const _NotificationCard({
    super.key,
    required this.item,
    required this.onDismiss,
  });

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  Color _getColor() {
    final item = widget.item;

    // Thiết bị kết nối/ngắt kết nối
    if (item.relatedEntityType == 'Device') {
      final titleLower = item.title.toLowerCase();
      if (titleLower.contains('ngắt') || titleLower.contains('mất')) {
        return const Color(0xFFEF4444); // Màu đỏ - disconnect
      } else if (titleLower.contains('kết nối') ||
          titleLower.contains('phát hiện')) {
        return const Color(0xFF22C55E); // Màu xanh - connect
      }
      return const Color(0xFF71717A); // Thiết bị khác
    }

    // Chấm công
    if (item.relatedEntityType == 'Attendance' ||
        item.type == NotificationType.attendanceCorrection ||
        item.title.toLowerCase().contains('chấm công')) {
      return const Color(0xFF2D5F8B); // Cyan
    }

    switch (item.type) {
      case NotificationType.success:
        return const Color(0xFF22C55E); // Bright green
      case NotificationType.warning:
        return const Color(0xFFF59E0B); // Bright amber
      case NotificationType.error:
        return const Color(0xFFEF4444); // Bright red
      case NotificationType.info:
      default:
        return const Color(0xFF1E3A5F); // Bright blue
    }
  }

  IconData _getIcon() {
    final item = widget.item;

    // Thiết bị kết nối/ngắt kết nối
    if (item.relatedEntityType == 'Device') {
      final titleLower = item.title.toLowerCase();
      if (titleLower.contains('ngắt') || titleLower.contains('mất')) {
        return Icons.wifi_off; // Disconnect
      } else if (titleLower.contains('kết nối') ||
          titleLower.contains('phát hiện')) {
        return Icons.wifi; // Connect
      }
      return Icons.devices; // Thiết bị khác
    }

    // Chấm công
    if (item.relatedEntityType == 'Attendance' ||
        item.type == NotificationType.attendanceCorrection ||
        item.title.toLowerCase().contains('chấm công')) {
      return Icons.access_time; // Icon đồng hồ
    }

    switch (item.type) {
      case NotificationType.success:
        return Icons.check_circle;
      case NotificationType.warning:
        return Icons.warning;
      case NotificationType.error:
        return Icons.error;
      case NotificationType.info:
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: const Color(0xFF18181B),
            child: InkWell(
              onTap: () {
                widget.item.onTap?.call();
                _dismiss();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
                ),
                child: Row(
                  children: [
                    // Color indicator
                    Container(
                      width: 4,
                      height: 72,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_getIcon(), color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.item.message,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[400],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Close button
                    IconButton(
                      icon:
                          Icon(Icons.close, size: 18, color: Colors.grey[500]),
                      onPressed: _dismiss,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
