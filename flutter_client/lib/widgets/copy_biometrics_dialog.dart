import 'dart:async';
import 'package:flutter/material.dart';
import '../models/device.dart';
import '../models/device_user.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/app_button.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Copy fingerprint / face templates from one attendance device to another.
class CopyBiometricsDialog extends StatefulWidget {
  final List<Device> devices;
  final List<DeviceUser> users;
  final String? initialSourceDeviceId;
  final String? preselectedUserId;
  final ApiService apiService;

  const CopyBiometricsDialog({
    super.key,
    required this.devices,
    required this.users,
    required this.apiService,
    this.initialSourceDeviceId,
    this.preselectedUserId,
  });

  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    required List<Device> devices,
    required List<DeviceUser> users,
    required ApiService apiService,
    String? initialSourceDeviceId,
    String? preselectedUserId,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CopyBiometricsDialog(
        devices: devices,
        users: users,
        apiService: apiService,
        initialSourceDeviceId: initialSourceDeviceId,
        preselectedUserId: preselectedUserId,
      ),
    );
  }

  @override
  State<CopyBiometricsDialog> createState() => _CopyBiometricsDialogState();
}

class _CopyBiometricsDialogState extends State<CopyBiometricsDialog> {
  late String _sourceId;
  String? _targetId;
  bool _copyAll = true;
  bool _includeFp = true;
  bool _includeFace = true;
  bool _submitting = false;
  bool _cancelled = false;
  String _status = '';
  String _search = '';
  late List<DeviceUser> _users;
  Timer? _userPoll;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _sourceId = widget.initialSourceDeviceId ??
        (widget.users.isNotEmpty
            ? widget.users.first.deviceId
            : widget.devices.first.id);
    if (widget.preselectedUserId != null) {
      _copyAll = false;
      _selectedIds.add(widget.preselectedUserId!);
      final pre = widget.users.where((u) => u.id == widget.preselectedUserId);
      if (pre.isNotEmpty) _sourceId = pre.first.deviceId;
    }
    final others = widget.devices.where((d) => d.id != _sourceId).toList();
    _targetId = others.isNotEmpty ? others.first.id : null;
    _users = List<DeviceUser>.from(widget.users);
    _userPoll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_submitting) _refreshUsers();
    });
    _refreshUsers();
  }

  @override
  void dispose() {
    _userPoll?.cancel();
    super.dispose();
  }

  Future<void> _refreshUsers() async {
    try {
      final ids = widget.devices.map((d) => d.id).toList();
      final data = await widget.apiService.getDeviceUsersByDeviceIds(ids);
      if (!mounted) return;
      setState(() {
        _users = data
            .whereType<Map>()
            .map((e) => DeviceUser.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
    } catch (_) {}
  }

  String _fpLine(DeviceUser u) {
    if (u.copyableFingerprintCount > 0) {
      return '${u.copyableFingerprintCount} vân tay sẵn sàng Copy · ${u.faceCount} KM';
    }
    if (u.fingerprintSyncing) {
      return 'Đang đồng bộ vân tay từ máy (15–60 giây) · ${u.faceCount} KM';
    }
    return '0 vân tay · ${u.faceCount} KM';
  }

  List<DeviceUser> get _sourceUsers {
    final q = _search.trim().toLowerCase();
    return _users.where((u) {
      if (u.deviceId != _sourceId) return false;
      if (q.isEmpty) return true;
      return u.pin.toLowerCase().contains(q) ||
          u.name.toLowerCase().contains(q) ||
          (u.employeeName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Map<String, dynamic>? _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

  bool _flag(Map<String, dynamic>? data, String a, String b) =>
      data != null && (data[a] == true || data[b] == true);

  int _int(Map<String, dynamic>? data, String a, String b) {
    final v = data?[a] ?? data?[b];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  Future<void> _submit() async {
    final targets = widget.devices.where((d) => d.id != _sourceId);
    final dest = (_targetId != null && targets.any((d) => d.id == _targetId))
        ? _targetId
        : (targets.isEmpty ? null : targets.first.id);
    if (dest == null) return;
    if (!_includeFp && !_includeFace) return;
    if (!_copyAll && _selectedIds.isEmpty) return;
    _cancelled = false;
    setState(() {
      _submitting = true;
      _status = 'Đang gửi sang máy đích…';
    });
    try {
      for (var attempt = 0; attempt < 10; attempt++) {
        if (!mounted || _cancelled) return;
        if (attempt > 0) {
          setState(() => _status =
              'Đã gửi tên. Đang lấy vân tay từ máy nguồn… (${attempt + 1}/10)\nKhông cần bấm lại.');
        }
        final result = await widget.apiService.copyBiometrics(
          sourceDeviceId: _sourceId,
          targetDeviceId: dest,
          sourceUserIds: _copyAll ? null : _selectedIds.toList(),
          includeFingerprints: _includeFp,
          includeFaces: _includeFace,
        );
        if (!mounted || _cancelled) return;
        if (result['isSuccess'] != true) {
          setState(() {
            _submitting = false;
            _status = '';
          });
          _showErr(result['message']?.toString() ?? 'Không copy được sinh trắc.');
          return;
        }
        final data = _asMap(result['data']);
        final waiting = _flag(data, 'autoRetry', 'AutoRetry') ||
            _flag(data, 'needsTemplateSync', 'NeedsTemplateSync') ||
            _flag(data, 'partialCopy', 'PartialCopy');
        final fpQueued = _int(data, 'fingerprintsQueued', 'FingerprintsQueued');
        final done = !waiting || fpQueued > 0 || !_includeFp;
        final msg = (data?['message'] ?? data?['Message'] ?? result['message'])
            ?.toString();
        if (done) {
          Navigator.pop(context, result);
          return;
        }
        setState(() => _status = msg?.isNotEmpty == true
            ? msg!
            : 'Đã gửi tên. Đang lấy vân tay từ máy nguồn…\nKhông cần bấm lại.');
        final waitSec = _int(data, 'retryAfterSeconds', 'RetryAfterSeconds');
        await Future<void>.delayed(Duration(seconds: waitSec > 0 ? waitSec : 8));
      }
      if (!mounted || _cancelled) return;
      setState(() {
        _submitting = false;
        _status =
            'Tên đã sang máy đích. Vân tay sẽ tự sang khi máy nguồn online — có thể đóng cửa sổ, không cần copy lần nữa. Nếu sau 2 phút máy đích vẫn chưa có vân tay, bấm Copy lại.';
      });
    } catch (e) {
      if (mounted && !_cancelled) {
        setState(() {
          _submitting = false;
          _status = '';
        });
        _showErr(e.toString());
      }
    }
  }

  void _showErr(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Lỗi')),
        content: Text(tr(msg)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final sourceUsers = _sourceUsers;
    final targets = widget.devices.where((d) => d.id != _sourceId).toList();
    final targetId = (_targetId != null && targets.any((d) => d.id == _targetId))
        ? _targetId
        : (targets.isEmpty ? null : targets.first.id);

    return Dialog(
      insetPadding: isMobile
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * (isMobile ? 1 : 0.9),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.fingerprint, color: Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr('Copy sinh trắc'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: tr('Làm mới số vân tay'),
                    onPressed: _submitting ? null : _refreshUsers,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    onPressed: () {
                      _cancelled = true;
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr('Bấm một lần. Vừa đăng ký xong thì đợi 15–60 giây cho file lên server (chữ “đang đồng bộ”) — không mất dữ liệu. Danh sách tự làm mới.'),
                style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_submitting)
                        const Padding(
                          padding: EdgeInsets.only(top: 2, right: 10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(top: 1, right: 8),
                          child: Icon(Icons.info_outline,
                              size: 18, color: Color(0xFF2563EB)),
                        ),
                      Expanded(
                        child: Text(
                          tr(_status),
                          style: const TextStyle(
                              fontSize: 13, height: 1.4, color: Color(0xFF1E3A8A)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey('src-$_sourceId'),
                        initialValue: _sourceId,
                        decoration: InputDecoration(
                          labelText: tr('Máy nguồn'),
                          prefixIcon: const Icon(Icons.upload),
                          border: const OutlineInputBorder(),
                        ),
                        items: widget.devices
                            .map((d) => DropdownMenuItem(
                                  value: d.id,
                                  child: Text(tr(
                                      '${d.deviceName}${d.isOnline ? '' : ' (offline)'}')),
                                ))
                            .toList(),
                        onChanged: _submitting
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() {
                                  _sourceId = v;
                                  _selectedIds.clear();
                                  if (_targetId == v) {
                                    final rest = widget.devices
                                        .where((d) => d.id != v);
                                    _targetId = rest.isEmpty
                                        ? null
                                        : rest.first.id;
                                  }
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('dst-$targetId'),
                        initialValue: targetId,
                        decoration: InputDecoration(
                          labelText: tr('Máy đích'),
                          prefixIcon: const Icon(Icons.download),
                          border: const OutlineInputBorder(),
                        ),
                        items: targets
                            .map((d) => DropdownMenuItem(
                                  value: d.id,
                                  child: Text(tr(
                                      '${d.deviceName}${d.isOnline ? '' : ' (offline)'}')),
                                ))
                            .toList(),
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _targetId = v),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: Text(tr('Vân tay')),
                            selected: _includeFp,
                            onSelected: _submitting
                                ? null
                                : (v) => setState(() => _includeFp = v),
                          ),
                          FilterChip(
                            label: Text(tr('Khuôn mặt')),
                            selected: _includeFace,
                            onSelected: _submitting
                                ? null
                                : (v) => setState(() => _includeFace = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      RadioListTile<bool>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr(
                            'Toàn bộ nhân viên trên máy nguồn (${_users.where((u) => u.deviceId == _sourceId).length})')),
                        value: true,
                        groupValue: _copyAll,
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _copyAll = v ?? true),
                      ),
                      RadioListTile<bool>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr(
                            'Chọn một số nhân viên${_copyAll ? '' : ' (${_selectedIds.length})'}')),
                        value: false,
                        groupValue: _copyAll,
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _copyAll = v ?? false),
                      ),
                      if (!_copyAll) ...[
                        TextField(
                          decoration: InputDecoration(
                            hintText: tr('Tìm PIN / tên...'),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: sourceUsers.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(tr('Không có nhân viên trên máy này.'),
                                      style: TextStyle(color: Colors.grey[600])),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: sourceUsers.length,
                                  itemBuilder: (ctx, i) {
                                    final u = sourceUsers[i];
                                    return CheckboxListTile(
                                      dense: true,
                                      value: _selectedIds.contains(u.id),
                                      onChanged: _submitting
                                          ? null
                                          : (v) {
                                              setState(() {
                                                if (v == true) {
                                                  _selectedIds.add(u.id);
                                                } else {
                                                  _selectedIds.remove(u.id);
                                                }
                                              });
                                            },
                                      title: Text(
                                          '${u.pin}  ${u.employeeName ?? u.name}'),
                                      subtitle: Text(_fpLine(u),
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: u.fingerprintSyncing
                                                  ? const Color(0xFFD97706)
                                                  : null)),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AppDialogActions(
                confirmLabel: 'Copy sang máy đích',
                confirmIcon: Icons.copy_all,
                isLoading: _submitting,
                onCancel: () {
                  _cancelled = true;
                  Navigator.pop(context);
                },
                onConfirm: (_submitting ||
                        targetId == null ||
                        (!_includeFp && !_includeFace) ||
                        (!_copyAll && _selectedIds.isEmpty))
                    ? null
                    : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
