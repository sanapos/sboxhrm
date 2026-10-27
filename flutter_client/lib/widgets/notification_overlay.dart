import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_tr.dart';
import '../models/hrm.dart';
export '../models/hrm.dart' show NotificationType;
import '../utils/notification_sound.dart';
import '../utils/vietnamese_text_fix.dart';
import '../utils/pos_notify_focus.dart';

import './pos/pos_theme.dart';
import '../utils/pos_kds_alert.dart';

import '../theme/sbox_tokens.dart';
/// Nhóm toast in POS — luôn chỉ giữ 1 dòng trên màn thu ngân.
const kPosPrintNotifyKind = 'pos_print';

/// Toast nội bộ KDS (lỗi quyền / in) — vẫn hiện khi đang mở màn bếp.
const kPosKdsNotifyKind = 'pos_kds';

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

  /// Hiển thị thông báo popup.
  ///
  /// [relatedEntityType] = [kPosPrintNotifyKind]: thay thế mọi toast in cũ
  /// (màn bán hàng chỉ còn 1 dòng).
  void show({
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
    String? relatedEntityType,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onTap,
    bool playSound = true,
    bool? compact,
  }) {
    if (PosKdsAlert.isOpen && relatedEntityType != kPosKdsNotifyKind) {
      return;
    }
    // Viên gọn 1 dòng, không kêu: thành công + tiến trình in. Lỗi / cảnh báo / thiết bị /
    // chấm công / bếp KDS vẫn là thẻ góc phải có nút đóng.
    final isCompact = compact ??
        (relatedEntityType != 'Device' &&
            relatedEntityType != 'Attendance' &&
            relatedEntityType != kPosKdsNotifyKind &&
            (type == NotificationType.success ||
                (type == NotificationType.info &&
                    relatedEntityType == kPosPrintNotifyKind)));
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final item = NotificationOverlayItem(
      id: id,
      title: fixVietnameseMojibake(title),
      // Nội dung dài (danh sách mặt hàng, món…) không được che màn hình → rút gọn.
      message: fixVietnameseMojibake(PosNotifyFocus.clip(message, max: 140)),
      type: type,
      relatedEntityType: relatedEntityType,
      onTap: onTap,
      compact: isCompact,
    );

    if (relatedEntityType == kPosPrintNotifyKind) {
      _notifications.removeWhere(
        (n) => n.relatedEntityType == kPosPrintNotifyKind,
      );
    }

    _notifications.insert(0, item);
    // Màn thu ngân: tối đa 1 toast hiện — tránh chồng lệnh in.
    if (_notifications.length > 1) {
      _notifications.removeRange(1, _notifications.length);
    }
    _controller.add(_notifications);

    if (playSound && !isCompact) {
      NotificationSound().play();
    }

    Future.delayed(duration, () => remove(id));
  }

  /// Viên thông báo gọn 1 dòng (không kêu) — vd. «Món A: hết hàng».
  void showToast(
    String text, {
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(milliseconds: 2500),
  }) {
    show(
      title: text,
      message: '',
      type: type,
      duration: duration,
      playSound: false,
      compact: true,
    );
  }

  /// Helper: Hiển thị thông báo thành công (viên gọn, ~2,5 giây)
  void showSuccess({
    required String title,
    required String message,
    VoidCallback? onTap,
    String? relatedEntityType,
    Duration duration = const Duration(milliseconds: 2500),
  }) {
    show(
      title: title,
      message: message,
      type: NotificationType.success,
      onTap: onTap,
      relatedEntityType: relatedEntityType,
      duration: duration,
    );
  }

  /// Helper: Hiển thị thông báo lỗi
  void showError({
    required String title,
    required String message,
    VoidCallback? onTap,
    String? relatedEntityType,
    Duration duration = const Duration(seconds: 5),
  }) {
    show(
      title: title,
      message: message,
      type: NotificationType.error,
      onTap: onTap,
      relatedEntityType: relatedEntityType,
      duration: duration,
    );
  }

  /// Helper: Hiển thị thông báo cảnh báo
  void showWarning({
    required String title,
    required String message,
    VoidCallback? onTap,
    String? relatedEntityType,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      title: title,
      message: message,
      type: NotificationType.warning,
      onTap: onTap,
      relatedEntityType: relatedEntityType,
      duration: duration,
    );
  }

  /// Helper: Hiển thị thông báo thông tin
  void showInfo({
    required String title,
    required String message,
    VoidCallback? onTap,
    String? relatedEntityType,
  }) {
    show(
      title: title,
      message: message,
      type: NotificationType.info,
      onTap: onTap,
      relatedEntityType: relatedEntityType,
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
  /// Viên 1 dòng góc trái dưới (thành công / tiến trình in) thay cho thẻ góc phải.
  final bool compact;

  NotificationOverlayItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.relatedEntityType,
    this.onTap,
    this.compact = false,
  }) : createdAt = DateTime.now();
}

/// Widget hiển thị thông báo ở góc phải trên.
///
/// Dùng [Stack] (không insert [OverlayEntry]) vì widget này thường nằm trong
/// `MaterialApp.builder` — **ngoài** Overlay của Navigator, nên
/// `Overlay.maybeOf(context)` hay trả null → bấm «Kiểm tra kết nối» im lặng.
///
/// Gốc nằm ở `MaterialApp.builder` (trên mọi route). Bản lồng bên trong (khung trang chủ,
/// POS độc lập…) chỉ trả [child] — nếu không, màn đẩy toàn màn hình (Thiết lập in, Máy in
/// nội bộ…) che mất thông báo, còn khi cả hai cùng vẽ thì toast hiện đôi.
class NotificationOverlay extends StatefulWidget {
  final Widget child;
  final double extraTopInset;

  const NotificationOverlay({
    super.key,
    required this.child,
    this.extraTopInset = 0,
  });

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay> {
  final _manager = NotificationOverlayManager();

  @override
  Widget build(BuildContext context) {
    if (context.dependOnInheritedWidgetOfExactType<_NotificationOverlayScope>() != null) {
      return widget.child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _NotificationOverlayScope(child: widget.child),
        ValueListenableBuilder<bool>(
          valueListenable: PosKdsAlert.uiOpen,
          builder: (context, kdsOpen, _) {
            return StreamBuilder<List<NotificationOverlayItem>>(
          stream: _manager.stream,
          initialData: _manager.notifications,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <NotificationOverlayItem>[];
            if (items.isEmpty) return const SizedBox.shrink();
            final item = items.first;
            if (kdsOpen && item.relatedEntityType != kPosKdsNotifyKind) {
              return const SizedBox.shrink();
            }
            final screenWidth = MediaQuery.sizeOf(context).width;
            final isMobile = screenWidth < 600;
            if (item.compact) {
              // Màn rộng (thu ngân T1): góc trái dưới — vùng lưới món, không che giỏ
              // hàng, nút Thanh toán hay thanh trên. Điện thoại: trên cùng như cũ.
              final pad = MediaQuery.paddingOf(context);
              final pill = _CompactToast(
                // Cùng key cho chuỗi in (đang gửi → đã gửi → in xong): đổi chữ tại chỗ,
                // không trượt lại từng lần.
                key: ValueKey(item.relatedEntityType == kPosPrintNotifyKind
                    ? 'print'
                    : item.id),
                item: item,
                onDismiss: () => _manager.remove(item.id),
              );
              return isMobile
                  ? Positioned(
                      top: pad.top + widget.extraTopInset + 8,
                      left: 8,
                      right: 8,
                      child: Align(alignment: Alignment.topCenter, child: pill),
                    )
                  : Positioned(
                      left: 16,
                      bottom: pad.bottom + 16,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (screenWidth * 0.4).clamp(280.0, 480.0),
                        ),
                        child: pill,
                      ),
                    );
            }
            final top = MediaQuery.paddingOf(context).top +
                widget.extraTopInset +
                (isMobile ? 8.0 : 16.0);
            return Positioned(
              top: top,
              left: isMobile ? 8 : null,
              right: isMobile ? 8 : 16,
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: isMobile ? null : 380,
                  child: _NotificationCard(
                    key: ValueKey(item.id),
                    item: item,
                    onDismiss: () => _manager.remove(item.id),
                  ),
                ),
              ),
            );
          },
        );
          },
        ),
      ],
    );
  }
}

class _NotificationOverlayScope extends InheritedWidget {
  const _NotificationOverlayScope({required super.child});

  @override
  bool updateShouldNotify(_NotificationOverlayScope oldWidget) => false;
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
        return SboxColors.danger; // Màu đỏ - disconnect
      } else if (titleLower.contains('kết nối') ||
          titleLower.contains('phát hiện')) {
        return SboxColors.success; // Màu xanh - connect
      }
      return SboxColors.slate500; // Thiết bị khác
    }

    // Chấm công
    if (item.relatedEntityType == 'Attendance' ||
        item.type == NotificationType.attendanceCorrection ||
        item.title.toLowerCase().contains('chấm công')) {
      return const Color(0xFF2D5F8B); // Cyan
    }

    switch (item.type) {
      case NotificationType.success:
        return SboxColors.success; // Bright green
      case NotificationType.warning:
        return SboxColors.warning; // Bright amber
      case NotificationType.error:
        return SboxColors.danger; // Bright red
      case NotificationType.info:
      default:
        return PosTheme.kiotBlue; // Bright blue
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
            borderRadius: BorderRadius.circular(14),
            color: SboxColors.slate900,
            child: InkWell(
              onTap: () {
                widget.item.onTap?.call();
                _dismiss();
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
                ),
                // IntrinsicHeight: thanh màu giãn theo nội dung (lỗi dài 3–4 dòng).
                child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Color indicator
                    Container(
                      width: 4,
                      constraints: const BoxConstraints(minHeight: 72),
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
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_getIcon(), color: color, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              tr(widget.item.title),
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
                              tr(widget.item.message),
                              style: TextStyle(
                                fontSize: 13,
                                color: SboxColors.slate400,
                              ),
                              // Lỗi / cảnh báo thường kèm cách xử lý ở cuối câu — 2 dòng là cắt mất phần đó.
                              maxLines: widget.item.type == NotificationType.error ||
                                      widget.item.type == NotificationType.warning
                                  ? 4
                                  : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Close button
                    Center(
                      child: IconButton(
                      icon:
                          Icon(Icons.close, size: 18, color: SboxColors.slate500),
                      onPressed: _dismiss,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Viên thông báo gọn: icon + «Tiêu đề · nội dung» một dòng, chạm để đóng.
class _CompactToast extends StatelessWidget {
  const _CompactToast({super.key, required this.item, required this.onDismiss});

  final NotificationOverlayItem item;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (item.type) {
      NotificationType.success => (SboxColors.success, Icons.check_circle_rounded),
      NotificationType.warning => (SboxColors.warning, Icons.info_rounded),
      NotificationType.error => (SboxColors.danger, Icons.error_rounded),
      _ => (const Color(0xFF7CC4F8), Icons.sync_rounded),
    };
    final title = tr(item.title);
    final msg = tr(item.message).trim();
    return Material(
      color: SboxColors.slate900,
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          item.onTap?.call();
          onDismiss();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (msg.isNotEmpty)
                        TextSpan(
                          text: ' · $msg',
                          style: TextStyle(color: SboxColors.slate400),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
