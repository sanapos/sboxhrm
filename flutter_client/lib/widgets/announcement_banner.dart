import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../screens/system_admin/system_admin_helpers.dart';
import '../utils/vietnamese_font.dart';

/// Top banner that polls active SuperAdmin announcements and lets the user
/// click action / acknowledge / dismiss.  Designed to be placed at the top
/// of the layout (above body content).
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key});

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  final _api = ApiService();
  Timer? _timer;
  List<Map<String, dynamic>> _items = [];
  final Set<String> _hidden = {};
  final Set<String> _seenSent = {};

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.getActiveAnnouncements();
      if (!mounted || res['isSuccess'] != true) return;
      final list =
          List<Map<String, dynamic>>.from(res['data'] as List? ?? const []);
      setState(() => _items = list);
      // Mark seen for newly displayed items (one-shot per session)
      for (final a in list) {
        final id = a['id']?.toString();
        if (id != null && !_seenSent.contains(id)) {
          _seenSent.add(id);
          _api.markAnnouncementSeen(id);
        }
      }
    } catch (_) {
      // Silent: banner is non-critical
    }
  }

  List<Map<String, dynamic>> get _visible =>
      _items.where((a) => !_hidden.contains(a['id']?.toString())).toList()
        ..sort((a, b) {
          final sa = AdminHelpers.parseEnumInt(
              a['severity'], AdminHelpers.announcementSeverityMap);
          final sb = AdminHelpers.parseEnumInt(
              b['severity'], AdminHelpers.announcementSeverityMap);
          return sb.compareTo(sa);
        });

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    if (visible.isEmpty) return const SizedBox.shrink();
    // Show only the top one — others remain queued, will appear when dismissed
    return _buildBanner(visible.first);
  }

  Color _color(int severity) => switch (severity) {
        3 => const Color(0xFFDC2626), // critical
        2 => const Color(0xFFEA580C), // warning
        1 => const Color(0xFF059669), // success
        _ => const Color(0xFF0891B2), // info
      };

  IconData _icon(int kind) => switch (kind) {
        1 => Icons.build_circle_outlined,
        2 => Icons.system_update_alt,
        3 => Icons.event_repeat,
        4 => Icons.local_offer,
        _ => Icons.campaign,
      };

  // Bỏ marker kỹ thuật `[RENEWAL-XXD-uuid]` khỏi text hiển thị (tương thích dữ liệu cũ).
  static final RegExp _markerRe =
      RegExp(r'\s*\[RENEWAL-\d+D-[0-9a-fA-F]{32}\]\s*');

  String _clean(String text) =>
      text.replaceAll(_markerRe, ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  /// Tính lại số ngày còn lại từ `expiresAt` (chính xác theo ngày hiện tại)
  /// và chuẩn hoá title cho thông báo gia hạn.
  String _formatRenewalTitle(Map<String, dynamic> a, String rawTitle) {
    final kind =
        AdminHelpers.parseEnumInt(a['kind'], AdminHelpers.announcementKindMap);
    if (kind != 3) return _clean(rawTitle); // chỉ áp dụng cho Renewal
    final expiresAtStr = a['expiresAt']?.toString();
    if (expiresAtStr == null || expiresAtStr.isEmpty) return _clean(rawTitle);
    final expiresAt = DateTime.tryParse(expiresAtStr);
    if (expiresAt == null) return _clean(rawTitle);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiresAt.year, expiresAt.month, expiresAt.day);
    final daysLeft = exp.difference(today).inDays;

    // Lấy phần tên cửa hàng: "⏰ <Name>: ..." → trích Name
    final cleaned = _clean(rawTitle);
    final m = RegExp(r'^[\u23F0\s]*([^:]+):').firstMatch(cleaned);
    final storeName = m != null ? m.group(1)!.trim() : 'Cửa hàng';

    if (daysLeft < 0) {
      return '⏰ $storeName: license đã hết hạn ${-daysLeft} ngày';
    }
    if (daysLeft == 0) {
      return '⏰ $storeName: license hết hạn hôm nay';
    }
    return '⏰ $storeName: license còn $daysLeft ngày';
  }

  Widget _buildBanner(Map<String, dynamic> a) {
    final id = a['id']?.toString() ?? '';
    final severity = AdminHelpers.parseEnumInt(
        a['severity'], AdminHelpers.announcementSeverityMap);
    final kind =
        AdminHelpers.parseEnumInt(a['kind'], AdminHelpers.announcementKindMap);
    final title = _formatRenewalTitle(a, a['title']?.toString() ?? '');
    final content = _clean(a['content']?.toString() ?? '');
    final actionUrl = a['actionUrl']?.toString();
    final actionLabel = a['actionLabel']?.toString();
    final requireAck = (a['requireAck'] as bool?) ?? false;
    final allowDismiss = (a['allowDismiss'] as bool?) ?? true;

    final color = _color(severity);

    return Material(
      color: color.withValues(alpha: 0.08),
      child: InkWell(
        onTap: () => _showDetail(a),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: color, width: 4),
              bottom: BorderSide(color: color.withValues(alpha: 0.2)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(_icon(kind), color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: vietnameseTextStyle(const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14))),
                  const SizedBox(height: 2),
                  Text(content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: vietnameseTextStyle(const TextStyle(fontSize: 12))),
                ],
              ),
            ),
            if (actionUrl != null && actionUrl.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: color),
                onPressed: () => _onAction(id, actionUrl),
                child: Text(
                    actionLabel?.isNotEmpty == true ? actionLabel! : 'Xem'),
              ),
            if (requireAck)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: color, foregroundColor: Colors.white),
                onPressed: () => _onAck(id),
                child: const Text('Đồng ý'),
              )
            else if (allowDismiss)
              IconButton(
                tooltip: 'Ẩn',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _onDismiss(id),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _onAction(String id, String url) async {
    _api.markAnnouncementClicked(id);
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _onAck(String id) async {
    await _api.markAnnouncementAcked(id);
    setState(() => _hidden.add(id));
  }

  Future<void> _onDismiss(String id) async {
    await _api.dismissAnnouncement(id);
    setState(() => _hidden.add(id));
  }

  Future<void> _showDetail(Map<String, dynamic> a) async {
    final id = a['id']?.toString() ?? '';
    final requireAck = (a['requireAck'] as bool?) ?? false;
    final allowDismiss = (a['allowDismiss'] as bool?) ?? true;
    final actionUrl = a['actionUrl']?.toString();
    final actionLabel = a['actionLabel']?.toString();
    await showDialog(
      context: context,
      barrierDismissible: !requireAck,
      builder: (_) => AlertDialog(
        title: Text(_formatRenewalTitle(a, a['title']?.toString() ?? '')),
        content: SingleChildScrollView(
          child: Text(_clean(a['content']?.toString() ?? '')),
        ),
        actions: [
          if (actionUrl != null && actionUrl.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _onAction(id, actionUrl);
              },
              child: Text(actionLabel?.isNotEmpty == true
                  ? actionLabel!
                  : 'Mở liên kết'),
            ),
          if (requireAck)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _onAck(id);
              },
              child: const Text('Tôi đã đọc'),
            )
          else
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (allowDismiss) _onDismiss(id);
              },
              child: const Text('Đóng'),
            ),
        ],
      ),
    );
  }
}
