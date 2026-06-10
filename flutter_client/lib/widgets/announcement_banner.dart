import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
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
  static const _renewalPhone = '0973024042';
  static const _renewalPhoneDisplay = '0973 024 042';

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

  static final RegExp _licenseExpiryInContentRe = RegExp(
    r'hết hạn vào\s*(\d{2})/(\d{2})/(\d{4})',
    caseSensitive: false,
  );

  /// Ngày hết hạn license (lịch VN), ưu tiên parse từ nội dung thông báo.
  DateTime? _licenseExpiryDate(Map<String, dynamic> a) {
    final content = a['content']?.toString() ?? '';
    final m = _licenseExpiryInContentRe.firstMatch(_clean(content));
    if (m != null) {
      return DateTime(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
      );
    }

    // Fallback: ExpiresAt trên server = ngày hết hạn license + 1 (ẩn banner)
    final expiresAtStr = a['expiresAt']?.toString();
    if (expiresAtStr == null || expiresAtStr.isEmpty) return null;
    final expiresAt = DateTime.tryParse(expiresAtStr);
    if (expiresAt == null) return null;
    final local = expiresAt.toLocal();
    return DateTime(local.year, local.month, local.day)
        .subtract(const Duration(days: 1));
  }

  int? _daysLeftForRenewal(Map<String, dynamic> a) {
    final exp = _licenseExpiryDate(a);
    if (exp == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return exp.difference(today).inDays;
  }

  String _storeNameFromTitle(String rawTitle) {
    final cleaned = _clean(rawTitle);
    final m = RegExp(r'^[\u23F0\s]*([^:]+):').firstMatch(cleaned);
    return m != null ? m.group(1)!.trim() : 'Cửa hàng';
  }

  /// Tính lại số ngày còn lại theo ngày hết hạn license trong content.
  String _formatRenewalTitle(Map<String, dynamic> a, String rawTitle) {
    final kind =
        AdminHelpers.parseEnumInt(a['kind'], AdminHelpers.announcementKindMap);
    if (kind != 3) return _clean(rawTitle);

    final daysLeft = _daysLeftForRenewal(a);
    final storeName = _storeNameFromTitle(rawTitle);
    if (daysLeft == null) return _clean(rawTitle);

    if (daysLeft < 0) {
      return '⏰ $storeName: license đã hết hạn ${-daysLeft} ngày';
    }
    if (daysLeft == 0) {
      return '⏰ $storeName: license hết hạn hôm nay';
    }
    return '⏰ $storeName: license còn $daysLeft ngày';
  }

  /// Bỏ dòng liên hệ trùng trong content (panel/dialog đã có nút Gọi/Zalo).
  String _formatRenewalContent(Map<String, dynamic> a) {
    final kind =
        AdminHelpers.parseEnumInt(a['kind'], AdminHelpers.announcementKindMap);
    var text = _clean(a['content']?.toString() ?? '');
    if (kind != 3) return text;

    final lines = text.split('\n');
    final kept = <String>[];
    for (final line in lines) {
      final lower = line.toLowerCase();
      final isContactLine = lower.contains('0973') ||
          lower.contains('zalo') ||
          lower.contains('gọi ngay') ||
          lower.contains('chat zalo') ||
          lower.contains('liên hệ gia hạn');
      if (!isContactLine) kept.add(line);
    }
    return kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  Widget _buildBanner(Map<String, dynamic> a) {
    final id = a['id']?.toString() ?? '';
    final severity = AdminHelpers.parseEnumInt(
        a['severity'], AdminHelpers.announcementSeverityMap);
    final kind =
        AdminHelpers.parseEnumInt(a['kind'], AdminHelpers.announcementKindMap);
    final title = _formatRenewalTitle(a, a['title']?.toString() ?? '');
    final content = _formatRenewalContent(a);
    final actionUrl = a['actionUrl']?.toString();
    final actionLabel = a['actionLabel']?.toString();
    final requireAck = (a['requireAck'] as bool?) ?? false;
    final allowDismiss = (a['allowDismiss'] as bool?) ?? true;
    // Gia hạn license: luôn cho khách tắt (kể cả bản ghi cũ AllowDismiss=false).
    final canDismiss = allowDismiss || kind == 3;

    final color = _color(severity);

    return Material(
      color: color.withValues(alpha: 0.08),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: color, width: 4),
            bottom: BorderSide(color: color.withValues(alpha: 0.2)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon(kind), color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => _showDetail(a),
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
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            vietnameseTextStyle(const TextStyle(fontSize: 12))),
                    if (actionUrl != null && actionUrl.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        actionLabel?.isNotEmpty == true
                            ? actionLabel!
                            : 'Xem chi tiết',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canDismiss)
                  IconButton(
                    tooltip: 'Tắt thông báo',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 36, minHeight: 36),
                    icon: Icon(Icons.close, size: 20, color: color),
                    onPressed: () => _onDismiss(id),
                  ),
                if (requireAck)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact),
                      onPressed: () => _onAck(id),
                      child: const Text('Đồng ý'),
                    ),
                  ),
              ],
            ),
          ],
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

  Future<void> _launchTel(String phone) async {
    final uri = Uri.parse('tel:+84${phone.startsWith('0') ? phone.substring(1) : phone}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchZalo(String phone) async {
    final uri = Uri.parse('https://zalo.me/$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _renewalContactPanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0891B2).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Liên hệ gia hạn ngay',
            style: vietnameseTextStyle(const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF0C4A6E),
            )),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _launchTel(_renewalPhone),
                icon: const Icon(Icons.phone_rounded, size: 18),
                label: Text('Gọi $_renewalPhoneDisplay'),
              ),
              OutlinedButton.icon(
                onPressed: () => _launchZalo(_renewalPhone),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Chat Zalo'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showDetail(Map<String, dynamic> a) async {
    final id = a['id']?.toString() ?? '';
    final kind =
        AdminHelpers.parseEnumInt(a['kind'], AdminHelpers.announcementKindMap);
    final isRenewal = kind == 3;
    final requireAck = (a['requireAck'] as bool?) ?? false;
    final allowDismiss = (a['allowDismiss'] as bool?) ?? true;
    final canDismiss = allowDismiss || isRenewal;
    final actionUrl = a['actionUrl']?.toString();
    final actionLabel = a['actionLabel']?.toString();
    await showDialog(
      context: context,
      barrierDismissible: !requireAck,
      builder: (_) => ScrollableAlertDialog(
        title: Text(_formatRenewalTitle(a, a['title']?.toString() ?? '')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_formatRenewalContent(a)),
              if (isRenewal) _renewalContactPanel(),
            ],
          ),
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
          else if (canDismiss)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _onDismiss(id);
              },
              child: const Text('Tắt thông báo'),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
        ],
      ),
    );
  }
}
