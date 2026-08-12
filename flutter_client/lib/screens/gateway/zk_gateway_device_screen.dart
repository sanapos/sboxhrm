import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/zk_gateway.dart';
import '../../services/zk_gateway_client.dart';
import '../../utils/file_saver.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import 'zk_gateway_widgets.dart';

/// Quản lý máy chấm công qua API LAN của ESP32 — thay trang web portal.
class ZkGatewayDeviceScreen extends StatefulWidget {
  const ZkGatewayDeviceScreen({
    super.key,
    required this.info,
  });

  final ZkGatewayInfo info;

  @override
  State<ZkGatewayDeviceScreen> createState() => _ZkGatewayDeviceScreenState();
}

class _ZkGatewayDeviceScreenState extends State<ZkGatewayDeviceScreen>
    with SingleTickerProviderStateMixin {
  final _client = ZkGatewayClient();
  late final TabController _tabs;

  List<ZkDeviceUser> _users = const [];
  bool _loadingUsers = true;
  String? _usersError;
  bool _busy = false;

  ZkDeviceAttlogPage? _attlog;
  bool _loadingAttlog = false;
  String? _attlogError;

  String? _enrollPin;
  int _enrollFid = 0;
  bool _enrollOverwrite = true;
  bool _enrolling = false;
  String _enrollMsg = '';
  double _enrollProgress = 0;
  Timer? _enrollTimer;

  int _unlockSeconds = 5;

  String get _ip => widget.info.ip;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && _tabs.index == 3 && _attlog == null) {
        _loadAttlog();
      }
    });
    _loadUsers();
  }

  @override
  void dispose() {
    _enrollTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<T?> _guardAuth<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ZkGatewayAuthException {
      if (!mounted) return null;
      appNotification.showError(
        title: tr('Gateway đang khóa'),
        message: tr('Quay lại màn chi tiết và nhập mật khẩu quản trị.'),
      );
      return null;
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loadingUsers = true;
      _usersError = null;
    });
    try {
      final list = await _client.fetchDeviceUsers(_ip);
      if (!mounted) return;
      list.sort((a, b) => a.pin.compareTo(b.pin));
      setState(() {
        _users = list;
        _loadingUsers = false;
        if (_enrollPin == null && list.isNotEmpty) {
          _enrollPin = list.first.pin;
        }
      });
    } on ZkGatewayAuthException {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
        _usersError = tr('Gateway đang khóa — mở khóa ở màn chi tiết');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
        _usersError = e is ZkGatewayException ? e.message : e.toString();
      });
    }
  }

  Future<void> _loadAttlog() async {
    setState(() {
      _loadingAttlog = true;
      _attlogError = null;
    });
    try {
      final page = await _client.fetchDeviceAttlog(_ip);
      if (!mounted) return;
      setState(() {
        _attlog = page;
        _loadingAttlog = false;
      });
    } on ZkGatewayAuthException {
      if (!mounted) return;
      setState(() {
        _loadingAttlog = false;
        _attlogError = tr('Gateway đang khóa — mở khóa ở màn chi tiết');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAttlog = false;
        _attlogError = e is ZkGatewayException ? e.message : e.toString();
      });
    }
  }

  Future<void> _editUser([ZkDeviceUser? existing]) async {
    final pinCtrl = TextEditingController(text: existing?.pin ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final cardCtrl = TextEditingController(
      text: (existing?.card ?? 0) > 0 ? '${existing!.card}' : '',
    );
    final isNew = existing == null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(isNew ? 'Thêm nhân viên trên máy' : 'Sửa nhân viên')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinCtrl,
                enabled: isNew,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Mã PIN')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: tr('Họ tên')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cardCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Số thẻ (tuỳ chọn)')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final pin = pinCtrl.text.trim();
    final name = nameCtrl.text.trim();
    if (pin.isEmpty) {
      appNotification.showError(title: tr('Thiếu PIN'), message: tr('Nhập mã PIN'));
      return;
    }

    setState(() => _busy = true);
    await _guardAuth(() async {
      await _client.saveDeviceUser(
        _ip,
        pin: pin,
        name: name.isEmpty ? pin : name,
        privilege: existing?.privilege ?? 0,
        card: int.tryParse(cardCtrl.text.trim()) ?? 0,
      );
      if (!mounted) return;
      appNotification.showSuccess(
        title: tr('Đã lưu'),
        message: name.isEmpty ? pin : name,
      );
      await _loadUsers();
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _deleteUser(ZkDeviceUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa nhân viên')),
        content: Text(tr('Xóa ${user.displayName} (PIN ${user.pin}) khỏi máy chấm công?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    await _guardAuth(() async {
      await _client.deleteDeviceUser(_ip, user.pin);
      if (!mounted) return;
      appNotification.showSuccess(title: tr('Đã xóa'), message: user.displayName);
      await _loadUsers();
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _deleteFinger(ZkDeviceUser user, {int? fid}) async {
    final label = fid == null
        ? tr('Xóa toàn bộ vân tay của ${user.displayName}?')
        : tr('Xóa mẫu ngón $fid của ${user.displayName}?');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa vân tay')),
        content: Text(label),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    await _guardAuth(() async {
      await _client.deleteDeviceFinger(_ip, pin: user.pin, fid: fid);
      if (!mounted) return;
      appNotification.showSuccess(title: tr('Đã xóa vân tay'), message: user.displayName);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _startEnroll() async {
    final pin = _enrollPin;
    if (pin == null || pin.isEmpty) {
      appNotification.showError(
        title: tr('Chưa chọn nhân viên'),
        message: tr('Chọn PIN trước khi đăng ký vân tay'),
      );
      return;
    }
    if (_enrolling) return;

    setState(() {
      _enrolling = true;
      _enrollProgress = 0.05;
      _enrollMsg = tr('Đang chờ quét vân tay trên máy...');
    });

    try {
      await _client.startDeviceEnroll(
        _ip,
        pin: pin,
        fid: _enrollFid,
        overwrite: _enrollOverwrite,
      );
    } on ZkGatewayAuthException {
      if (!mounted) return;
      setState(() {
        _enrolling = false;
        _enrollMsg = tr('Gateway đang khóa');
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enrolling = false;
        _enrollMsg = e is ZkGatewayException ? e.message : e.toString();
      });
      return;
    }

    var elapsed = 0;
    _enrollTimer?.cancel();
    _enrollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      elapsed += 2;
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _enrollProgress = (elapsed / 45).clamp(0.05, 0.95));
      try {
        final s = await _client.fetchDeviceEnrollStatus(_ip);
        if (!s.running) {
          t.cancel();
          if (!mounted) return;
          setState(() {
            _enrolling = false;
            _enrollProgress = 1;
            _enrollMsg = s.message.isNotEmpty
                ? s.message
                : (s.success ? tr('Thành công') : tr('Thất bại'));
          });
          if (s.success) {
            appNotification.showSuccess(
              title: tr('Đăng ký vân tay'),
              message: _enrollMsg,
            );
          } else if (s.failed) {
            appNotification.showError(
              title: tr('Đăng ký thất bại'),
              message: _enrollMsg,
            );
          }
        }
      } catch (_) {
        // Giữ polling đến hết ~45s.
        if (elapsed >= 48) {
          t.cancel();
          if (!mounted) return;
          setState(() {
            _enrolling = false;
            _enrollMsg = tr('Hết thời gian chờ phản hồi');
          });
        }
      }
    });
  }

  Future<void> _control(String action, {String? confirmTitle, String? confirmBody}) async {
    if (confirmTitle != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(confirmTitle)),
          content: Text(tr(confirmBody ?? '')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            ElevatedButton(
              style: action == 'factory_reset' || action == 'clear_attlog'
                  ? ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626))
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Xác nhận')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _busy = true);
    await _guardAuth(() async {
      final msg = await _client.deviceControl(
        _ip,
        action: action,
        seconds: _unlockSeconds,
      );
      if (!mounted) return;
      appNotification.showSuccess(title: tr('Đã gửi lệnh'), message: tr(msg));
      if (action == 'refresh') await _loadUsers();
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    await _guardAuth(() async {
      final bytes = await _client.downloadDeviceAttlogCsv(_ip);
      if (!mounted) return;
      await saveFileBytes(
        bytes,
        'cham-cong-${widget.info.serial.isNotEmpty ? widget.info.serial : _ip}.csv',
        'text/csv',
        category: 'attendance',
        sourceModule: 'zk_gateway',
      );
      appNotification.showSuccess(
        title: tr('Đã xuất CSV'),
        message: tr('${(bytes.length / 1024).round()} KB'),
      );
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          tr('Máy chấm công'),
          style: const TextStyle(
            color: HrmPageChrome.textDark,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        iconTheme: const IconThemeData(color: HrmPageChrome.textDark),
        bottom: TabBar(
          controller: _tabs,
          labelColor: HrmPageChrome.primaryNavy,
          unselectedLabelColor: HrmPageChrome.textMuted,
          indicatorColor: HrmPageChrome.primaryNavy,
          isScrollable: true,
          tabs: [
            Tab(text: tr('Nhân viên')),
            Tab(text: tr('Vân tay')),
            Tab(text: tr('Điều khiển')),
            Tab(text: tr('Chấm công')),
          ],
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _usersTab(),
          _enrollTab(),
          _controlTab(),
          _attlogTab(),
        ],
      ),
    );
  }

  Widget _usersTab() {
    if (_loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_usersError != null) {
      return _errorPane(_usersError!, onRetry: _loadUsers);
    }
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('${_users.length} nhân viên trên máy'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HrmPageChrome.textMuted,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _editUser(),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: Text(tr('Thêm')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_users.isEmpty)
            const GatewayNoteBox(
              text: 'Chưa có nhân viên trên máy. Bấm Thêm để tạo PIN mới.',
              icon: Icons.info_outline,
            )
          else
            for (final u in _users) ...[
              _userTile(u),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _userTile(ZkDeviceUser u) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        title: Text(
          u.displayName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
        subtitle: Text(
          'PIN ${u.pin}${u.card > 0 ? ' · thẻ ${u.card}' : ''}',
          style: const TextStyle(fontSize: 12.2, color: HrmPageChrome.textMuted),
        ),
        trailing: PopupMenuButton<String>(
          enabled: !_busy,
          onSelected: (v) {
            switch (v) {
              case 'edit':
                _editUser(u);
              case 'finger':
                _deleteFinger(u);
              case 'delete':
                _deleteUser(u);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
            PopupMenuItem(value: 'finger', child: Text(tr('Xóa hết vân tay'))),
            PopupMenuItem(value: 'delete', child: Text(tr('Xóa nhân viên'))),
          ],
        ),
      ),
    );
  }

  Widget _enrollTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Đăng ký vân tay'),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: HrmPageChrome.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: ValueKey('enroll-pin-${_enrollPin ?? "x"}-${_users.length}'),
                initialValue: _users.any((u) => u.pin == _enrollPin)
                    ? _enrollPin
                    : (_users.isNotEmpty ? _users.first.pin : null),
                decoration: InputDecoration(
                  labelText: tr('Nhân viên'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final u in _users)
                    DropdownMenuItem(
                      value: u.pin,
                      child: Text('${u.pin} — ${u.displayName}'),
                    ),
                ],
                onChanged: _enrolling
                    ? null
                    : (v) => setState(() => _enrollPin = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('enroll-fid-$_enrollFid'),
                initialValue: _enrollFid,
                decoration: InputDecoration(
                  labelText: tr('Ngón tay (fid 0–9)'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (var i = 0; i <= 9; i++)
                    DropdownMenuItem(value: i, child: Text(tr('Mẫu $i'))),
                ],
                onChanged: _enrolling
                    ? null
                    : (v) => setState(() => _enrollFid = v ?? 0),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Ghi đè mẫu cũ')),
                value: _enrollOverwrite,
                onChanged: _enrolling
                    ? null
                    : (v) => setState(() => _enrollOverwrite = v),
              ),
              const SizedBox(height: 8),
              if (_enrolling || _enrollProgress > 0) ...[
                LinearProgressIndicator(value: _enrollProgress),
                const SizedBox(height: 10),
              ],
              Text(
                _enrollMsg.isEmpty
                    ? tr('Chọn nhân viên và ngón tay, rồi đặt ngón lên máy khi đèn sáng (tối đa 45 giây).')
                    : _enrollMsg,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: HrmPageChrome.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: (_busy || _enrolling || _users.isEmpty) ? null : _startEnroll,
                icon: const Icon(Icons.fingerprint, size: 20),
                label: Text(tr(_enrolling ? 'Đang chờ quét...' : 'Bắt đầu đăng ký')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const GatewayNoteBox(
          text: 'Điện thoại và gateway phải cùng WiFi. Trong lúc đăng ký, đứng trước máy chấm công và đặt ngón tay theo hướng dẫn trên máy.',
          icon: Icons.info_outline,
        ),
      ],
    );
  }

  Widget _controlTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        _sectionCard(
          title: 'Mở cửa',
          children: [
            DropdownButtonFormField<int>(
              key: ValueKey('unlock-$_unlockSeconds'),
              initialValue: _unlockSeconds,
              decoration: InputDecoration(
                labelText: tr('Thời gian mở (giây)'),
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 3, child: Text('3')),
                DropdownMenuItem(value: 5, child: Text('5')),
                DropdownMenuItem(value: 10, child: Text('10')),
                DropdownMenuItem(value: 15, child: Text('15')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _unlockSeconds = v ?? 5),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : () => _control('unlock'),
              icon: const Icon(Icons.lock_open, size: 20),
              label: Text(tr('Mở cửa ngay')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Lệnh máy',
          children: [
            _ctrlBtn(
              icon: Icons.refresh,
              label: 'Làm mới dữ liệu trên máy',
              onTap: () => _control('refresh'),
            ),
            _ctrlBtn(
              icon: Icons.restart_alt,
              label: 'Khởi động lại máy chấm công',
              onTap: () => _control(
                'restart',
                confirmTitle: 'Khởi động lại máy?',
                confirmBody: 'Máy chấm công sẽ reboot. Gateway vẫn chạy.',
              ),
            ),
            _ctrlBtn(
              icon: Icons.delete_sweep_outlined,
              label: 'Xóa log chấm công trên máy',
              danger: true,
              onTap: () => _control(
                'clear_attlog',
                confirmTitle: 'Xóa toàn bộ log trên máy?',
                confirmBody: 'Nên đồng bộ lên máy chủ trước. Thao tác không hoàn tác trên máy.',
              ),
            ),
            _ctrlBtn(
              icon: Icons.warning_amber_rounded,
              label: 'Khôi phục xuất xưởng máy ZK',
              danger: true,
              last: true,
              onTap: () => _control(
                'factory_reset',
                confirmTitle: 'Khôi phục xuất xưởng máy ZK?',
                confirmBody:
                    'Xóa toàn bộ nhân viên, vân tay và log trên máy (CLEAR_DATA). '
                    'Mạch ESP / WiFi không bị đụng. Không thể hoàn tác.',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _attlogTab() {
    if (_loadingAttlog) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_attlogError != null) {
      return _errorPane(_attlogError!, onRetry: _loadAttlog);
    }
    final page = _attlog;
    if (page == null) {
      return Center(
        child: FilledButton(
          onPressed: _loadAttlog,
          child: Text(tr('Tải bản ghi trên máy')),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAttlog,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('${page.count} bản ghi${page.truncated ? " (đã cắt)" : ""}'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HrmPageChrome.textMuted,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _exportCsv,
                icon: const Icon(Icons.download, size: 18),
                label: Text(tr('CSV')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (page.items.isEmpty)
            const GatewayNoteBox(
              text: 'Không có bản ghi chấm công trên máy.',
              icon: Icons.info_outline,
            )
          else
            for (final row in page.items.reversed.take(200)) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.pin,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            row.time,
                            style: const TextStyle(
                              fontSize: 12,
                              color: HrmPageChrome.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          row.state,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          row.verify,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: HrmPageChrome.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(title),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: HrmPageChrome.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _ctrlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
    bool last = false,
  }) {
    final color = danger ? const Color(0xFFDC2626) : HrmPageChrome.primaryNavy;
    return Column(
      children: [
        InkWell(
          onTap: _busy ? null : onTap,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr(label),
                    style: TextStyle(
                      fontSize: 13.8,
                      fontWeight: FontWeight.w600,
                      color: danger ? color : HrmPageChrome.textDark,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
        if (!last) const Divider(height: 1),
      ],
    );
  }

  Widget _errorPane(String message, {required VoidCallback onRetry}) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFDC2626), height: 1.4),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: Text(tr('Thử lại'))),
        ),
      ],
    );
  }
}
