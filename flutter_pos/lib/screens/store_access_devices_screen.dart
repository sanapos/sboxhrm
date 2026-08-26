import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Nhả slot thiết bị đăng nhập (web / app / POS) theo hạn mức gói.
class StoreAccessDevicesScreen extends StatefulWidget {
  const StoreAccessDevicesScreen({super.key});

  @override
  State<StoreAccessDevicesScreen> createState() =>
      _StoreAccessDevicesScreenState();
}

class _StoreAccessDevicesScreenState extends State<StoreAccessDevicesScreen> {
  final _api = ApiService();
  final _fmt = DateFormat('dd/MM/yyyy HH:mm');
  bool _loading = true;
  String? _error;
  int _used = 0;
  int _max = 0;
  bool _unlimited = true;
  List<Map<String, dynamic>> _items = [];
  String? _releasingId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getStoreAccessDevices();
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được danh sách thiết bị';
      });
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final raw = data['items'] ?? data['Items'];
    final items = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) items.add(Map<String, dynamic>.from(e));
      }
    }
    setState(() {
      _used = _asInt(data['used'] ?? data['Used']);
      _max = _asInt(data['max'] ?? data['Max']);
      _unlimited = data['unlimited'] == true || data['Unlimited'] == true || _max <= 0;
      _items = items;
      _loading = false;
    });
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  String _platformLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'web':
      case 'browser':
      case 'desktop':
        return 'Trình duyệt web';
      case 'pos':
        return 'Máy POS';
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      default:
        return raw.isEmpty ? 'Khác' : raw;
    }
  }

  IconData _platformIcon(String raw) {
    switch (raw.toLowerCase()) {
      case 'web':
      case 'browser':
      case 'desktop':
        return Icons.language;
      case 'pos':
        return Icons.point_of_sale;
      case 'ios':
        return Icons.phone_iphone;
      default:
        return Icons.smartphone;
    }
  }

  String _seenText(dynamic v) {
    if (v == null) return '—';
    final parsed = DateTime.tryParse(v.toString());
    if (parsed == null) return '—';
    return _fmt.format(parsed.toLocal());
  }

  Future<void> _release(Map<String, dynamic> row) async {
    final id = (row['id'] ?? row['Id'])?.toString();
    if (id == null || id.isEmpty) return;
    final isThis = row['isThisDevice'] == true || row['IsThisDevice'] == true;
    final name = (row['deviceName'] ?? row['DeviceName'])?.toString() ?? 'thiết bị';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Nhả thiết bị?')),
        content: Text(tr(isThis
            ? 'Đây là máy đang dùng. Nhả xong, lần đăng nhập tới sẽ chiếm lại 1 slot nếu còn chỗ.'
            : 'Gỡ «$name» khỏi hạn mức gói. Máy đó phải đăng nhập lại mới chiếm slot.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Nhả slot')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _releasingId = id);
    final res = await _api.releaseStoreAccessDevice(id);
    if (!mounted) return;
    setState(() => _releasingId = null);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã nhả thiết bị',
        message: tr('Slot đã trống — máy khác có thể đăng nhập.'),
      );
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Không nhả được',
        message: res['message']?.toString() ?? 'Thử lại',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<PermissionProvider>().canEditPosSetup() ||
        context.watch<PermissionProvider>().canEdit('SystemSettings') ||
        context.watch<PermissionProvider>().canEdit('UserManagement');
    final quota = _unlimited
        ? 'Đang dùng $_used máy · gói không giới hạn'
        : 'Đang dùng $_used / $_max máy theo gói';

    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          Text(
            tr('Mỗi điện thoại, trình duyệt hoặc máy POS đăng nhập chiếm 1 slot. '
                'Nhả máy không dùng để máy mới vào được khi gói có hạn mức.'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                tr(quota),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                tr('Chưa ghi nhận thiết bị đăng nhập.'),
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            ..._items.map((row) {
              final platform =
                  (row['platform'] ?? row['Platform'] ?? '').toString();
              final name =
                  (row['deviceName'] ?? row['DeviceName'])?.toString();
              final user =
                  (row['userName'] ?? row['UserName'])?.toString();
              final isThis =
                  row['isThisDevice'] == true || row['IsThisDevice'] == true;
              final id = (row['id'] ?? row['Id'])?.toString();
              final busy = id != null && id == _releasingId;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_platformIcon(platform), color: PosTheme.kiotBlue),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(name == null || name.isEmpty
                              ? _platformLabel(platform)
                              : '$name · ${_platformLabel(platform)}'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isThis)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            tr('Máy này'),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    tr('${user == null || user.isEmpty ? '—' : user}'
                        ' · ${_seenText(row['lastSeenAt'] ?? row['LastSeenAt'])}'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: !canEdit
                      ? null
                      : busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: tr('Nhả slot'),
                              icon: const Icon(Icons.link_off),
                              onPressed: () => _release(row),
                            ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
