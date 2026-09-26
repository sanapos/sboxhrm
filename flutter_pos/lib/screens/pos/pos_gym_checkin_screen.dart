import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../utils/file_saver.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';

/// Gym: hội viên check-in bằng máy chấm công (vân tay / khuôn mặt / thẻ) hoặc tại quầy.
/// Tách biệt chấm công nhân viên — hội viên có PIN riêng (9xxxxxxx), lượt quét ghi vào lượt tập,
/// trừ 1 buổi / ngày (thẻ thời gian chỉ kiểm tra hạn).
class PosGymCheckInScreen extends StatefulWidget {
  const PosGymCheckInScreen({super.key});

  @override
  State<PosGymCheckInScreen> createState() => _PosGymCheckInScreenState();
}

class _PosGymCheckInScreenState extends State<PosGymCheckInScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Check-in hội viên')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: tr('Lượt tập')),
            Tab(text: tr('Hội viên trên máy')),
            Tab(text: tr('Tổng hợp')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_VisitsTab(), _MembersTab(), _ReportTab()],
      ),
    );
  }
}

final _hm = DateFormat('HH:mm');
final _dmy = DateFormat('dd/MM/yyyy');

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

String _duration(int minutes) {
  if (minutes < 60) return '$minutes phút';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h giờ' : '$h giờ $m phút';
}

/// "Thẻ tháng · HSD 20/10/2026" / "Gói 10 buổi · còn 3 · HSD …" / "Chưa có thẻ / gói".
String _packageText(Map m) {
  final name = m['packageName']?.toString();
  if (name == null || name.isEmpty) return tr('Chưa có thẻ / gói');
  final exp = _date(m['expiresAt']);
  final remain = (m['remainingSessions'] as num?)?.toInt();
  final parts = <String>[name];
  if (m['unlimited'] != true && remain != null) parts.add('còn $remain buổi');
  if (exp != null) parts.add('HSD ${_dmy.format(exp)}');
  return parts.join(' · ');
}

bool _packageWarn(Map m) {
  final exp = _date(m['expiresAt']);
  final remain = (m['remainingSessions'] as num?)?.toInt();
  if ((m['packageName'] ?? '').toString().isEmpty) return true;
  if (exp != null && exp.difference(DateTime.now()).inDays < 7) return true;
  return m['unlimited'] != true && remain != null && remain <= 2;
}

/// Chọn khách hàng POS (tìm theo tên / SĐT).
Future<Map<String, dynamic>?> _pickCustomer(BuildContext context) {
  return showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _CustomerPickerDialog());
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog();

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final res = await _api.getPosCustomers(search: q, pageSize: 30);
    if (!mounted) return;
    final data = res['data'];
    setState(() {
      _loading = false;
      _items = data is Map
          ? ((data['items'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Chọn khách hàng')),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Tên hoặc số điện thoại'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(child: Text(tr('Không tìm thấy khách')))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final c = _items[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.person_outline),
                              title: Text(c['name']?.toString() ?? ''),
                              subtitle: Text(c['phone']?.toString() ?? ''),
                              onTap: () => Navigator.pop(context, c),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng')))],
    );
  }
}

// ── Tab 1: lượt tập trong ngày (tự làm mới 10 giây) ─────────────────────────

class _VisitsTab extends StatefulWidget {
  const _VisitsTab();

  @override
  State<_VisitsTab> createState() => _VisitsTabState();
}

class _VisitsTabState extends State<_VisitsTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  DateTime _day = DateTime.now();
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  String? _error;
  Timer? _timer;
  String _filter = 'all';

  bool get _isToday {
    final n = DateTime.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _isToday) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await _api.getGymVisits(from: _day, to: _day);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
        _error = null;
      } else if (!silent) {
        _error = res['message']?.toString() ?? tr('Không tải được lượt tập');
      }
    });
  }

  Future<void> _manualCheckIn() async {
    final c = await _pickCustomer(context);
    if (c == null || !mounted) return;
    final res = await _api.gymCheckIn(c['id'].toString());
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final v = res['data'] is Map ? res['data'] as Map : const {};
      final ok = v['status'] == 'Ok';
      final msg = '${c['name']} · ${v['note'] ?? _packageText(v)}';
      ok
          ? NotificationOverlayManager().showSuccess(title: 'Đã check-in', message: msg)
          : NotificationOverlayManager().showWarning(title: 'Check-in — cần kiểm tra', message: msg);
      _load();
    } else {
      NotificationOverlayManager()
          .showError(title: 'Không check-in được', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _checkOut(Map v) async {
    final res = await _api.gymCheckOut(v['id'].toString());
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Không cho ra được', message: res['message']?.toString() ?? '');
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final all = ((_data['items'] as List?) ?? []).whereType<Map>().toList();
    final items = switch (_filter) {
      'inside' => all.where((v) => v['checkOutAt'] == null).toList(),
      'warn' => all.where((v) => v['status'] != 'Ok').toList(),
      _ => all,
    };
    return Scaffold(
      backgroundColor: PosTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _manualCheckIn,
        icon: const Icon(Icons.how_to_reg),
        label: Text(tr('Check-in tại quầy')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.today, size: 18),
                  label: Text(_isToday ? tr('Hôm nay') : _dmy.format(_day)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _day,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (d == null) return;
                    _day = d;
                    _load();
                  },
                ),
                const Spacer(),
                if (_isToday)
                  Text(tr('Tự cập nhật 10 giây'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _stat('Đang tập', _data['inside'], Colors.green.shade700, 'inside'),
                _stat('Lượt tập', _data['total'], PosTheme.kiotBlue, 'all'),
                _stat('Hội viên', _data['customers'], Colors.indigo, null),
                _stat('Cần kiểm tra', _data['warnings'], Colors.red.shade700, 'warn'),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading && all.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    tr('Chưa có lượt tập.\nHội viên quét vân tay / khuôn mặt / thẻ trên máy chấm công '
                        'sẽ hiện ở đây.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              )
            else
              for (final v in items) _visitTile(v),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, dynamic value, Color color, String? filter) {
    final selected = filter != null && _filter == filter;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: filter == null ? null : () => setState(() => _filter = filter),
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : PosTheme.border, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(label), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            Text('${(value as num?)?.toInt() ?? 0}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _visitTile(Map v) {
    final inAt = _date(v['checkInAt']);
    final outAt = _date(v['checkOutAt']);
    final ok = v['status'] == 'Ok';
    final inside = outAt == null;
    final minutes = (v['durationMinutes'] as num?)?.toInt() ??
        (inAt == null ? 0 : DateTime.now().difference(inAt).inMinutes);
    final color = !ok ? Colors.red.shade700 : (inside ? Colors.green.shade700 : Colors.grey.shade600);
    final timeText = inside
        ? 'Vào ${inAt == null ? '' : _hm.format(inAt)} · đang tập ${_duration(minutes)}'
        : 'Vào ${inAt == null ? '' : _hm.format(inAt)} · Ra ${_hm.format(outAt)} · ${_duration(minutes)}';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: ok ? PosTheme.border : Colors.red.shade200),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(ok ? (inside ? Icons.fitness_center : Icons.logout) : Icons.warning_amber, color: color),
        ),
        title: Text(v['customerName']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(timeText)),
            Text(
              tr([
                _packageText(v),
                if (v['sessionDeducted'] == true) 'đã trừ 1 buổi',
                if ((v['deviceName'] ?? '').toString().isNotEmpty) v['deviceName'],
              ].join(' · ')),
              style: TextStyle(fontSize: 12, color: _packageWarn(v) ? Colors.orange.shade800 : Colors.grey.shade700),
            ),
            if (!ok || (v['note'] ?? '').toString().isNotEmpty)
              Text(tr(v['note']?.toString() ?? ''),
                  style: TextStyle(fontSize: 12, color: ok ? Colors.grey.shade700 : Colors.red.shade700,
                      fontWeight: ok ? FontWeight.normal : FontWeight.w700)),
          ],
        ),
        isThreeLine: true,
        trailing: inside && _isToday
            ? TextButton(onPressed: () => _checkOut(v), child: Text(tr('Cho ra')))
            : null,
      ),
    );
  }
}

// ── Tab 2: hội viên trên máy chấm công ──────────────────────────────────────

class _MembersTab extends StatefulWidget {
  const _MembersTab();

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getGymMembers(search: _search);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is List) {
        _items = (res['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _error = null;
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được hội viên');
      }
    });
  }

  Future<void> _add() async {
    final customer = await _pickCustomer(context);
    if (customer == null || !mounted) return;
    final devices = (await _api.getDevices(storeOnly: true)).whereType<Map>().toList();
    if (!mounted) return;
    if (devices.isEmpty) {
      NotificationOverlayManager()
          .showError(title: 'Chưa có máy chấm công', message: tr('Cửa hàng chưa có máy chấm công nào'));
      return;
    }
    final picked = <String>{if (devices.length == 1) devices.first['id'].toString()};
    final cardCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Đăng ký lên máy: ${customer['name']}')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Chọn máy hội viên sẽ quét (cửa ra vào / quầy lễ tân):'),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                for (final d in devices)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: picked.contains(d['id'].toString()),
                    title: Text(d['deviceName']?.toString() ?? ''),
                    subtitle: Text(d['location']?.toString() ?? d['serialNumber']?.toString() ?? ''),
                    onChanged: (v) => setD(() => v == true
                        ? picked.add(d['id'].toString())
                        : picked.remove(d['id'].toString())),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: cardCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('Số thẻ từ (nếu dùng thẻ)'),
                    helperText: tr('Sau khi đăng ký: lấy vân tay / khuôn mặt ngay trên máy.'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(
              onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: Text(tr('Đăng ký')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.addGymMember(customer['id'].toString(), picked.toList(), cardNumber: cardCtrl.text);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã đăng ký lên máy',
          message: tr('Bấm "Lấy vân tay" hoặc "Lấy khuôn mặt" để khách đăng ký sinh trắc học trên máy.'));
      _load();
    } else {
      NotificationOverlayManager()
          .showError(title: 'Không đăng ký được', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _enroll(Map m, bool face) async {
    final deviceId = m['deviceId'].toString();
    final pin = m['pin'].toString();
    final res = face
        ? await _api.enrollFaceWithResponse(deviceId, pin)
        : await _api.enrollFingerprintWithResponse(deviceId, pin, 0);
    if (!mounted) return;
    if (res?['isSuccess'] == true) {
      NotificationOverlayManager().showInfo(
          title: face ? 'Đang lấy khuôn mặt' : 'Đang lấy vân tay',
          message: tr('Mời ${m['customerName']} ${face ? 'nhìn vào camera' : 'đặt ngón tay 3 lần'} trên máy ${m['deviceName']}.'));
    } else {
      NotificationOverlayManager()
          .showError(title: 'Không gửi được lệnh', message: res?['message']?.toString() ?? '');
    }
  }

  Future<void> _remove(Map m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Gỡ hội viên khỏi máy?')),
        content: Text(tr('${m['customerName']} sẽ không quét được trên máy ${m['deviceName']}. '
            'Lịch sử lượt tập vẫn giữ.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Gỡ'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.removeGymMember(m['id'].toString());
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Không gỡ được', message: res['message']?.toString() ?? '');
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: PosTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: Text(tr('Đăng ký hội viên lên máy')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Tìm tên, SĐT, PIN'),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) {
                _search = v;
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
            ),
            const SizedBox(height: 10),
            if (_loading && _items.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr('Chưa có hội viên nào trên máy.\n'
                      'Bấm "Đăng ký hội viên lên máy", chọn khách và máy, rồi lấy vân tay / khuôn mặt.\n'
                      'Hội viên có mã PIN riêng, không lẫn vào chấm công nhân viên.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              )
            else
              for (final m in _items) _memberTile(m),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(Map m) {
    final fp = (m['fingerprintCount'] as num?)?.toInt() ?? 0;
    final face = (m['faceCount'] as num?)?.toInt() ?? 0;
    final last = _date(m['lastVisitAt']);
    final online = m['deviceOnline'] == true;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: PosTheme.border),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: PosTheme.kiotBlueLight,
          child: Icon(fp + face > 0 || (m['cardNumber'] ?? '').toString().isNotEmpty
              ? Icons.fingerprint
              : Icons.person_outline, color: PosTheme.kiotBlue),
        ),
        title: Text('${m['customerName']}${(m['phone'] ?? '').toString().isEmpty ? '' : ' · ${m['phone']}'}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.circle, size: 8, color: online ? Colors.green : Colors.grey),
              const SizedBox(width: 4),
              Flexible(
                child: Text(tr('${m['deviceName']} · PIN ${m['pin']} · '
                    '${fp > 0 ? '$fp vân tay' : 'chưa vân tay'} · ${face > 0 ? 'có khuôn mặt' : 'chưa khuôn mặt'}'
                    '${(m['cardNumber'] ?? '').toString().isEmpty ? '' : ' · thẻ ${m['cardNumber']}'}'),
                    style: const TextStyle(fontSize: 12)),
              ),
            ]),
            Text(
              tr('${_packageText(m)}${last == null ? '' : ' · tập gần nhất ${_dmy.format(last)}'}'),
              style: TextStyle(fontSize: 12, color: _packageWarn(m) ? Colors.orange.shade800 : Colors.grey.shade700),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'fp') _enroll(m, false);
            if (v == 'face') _enroll(m, true);
            if (v == 'remove') _remove(m);
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'fp', child: Text(tr('Lấy vân tay trên máy'))),
            PopupMenuItem(value: 'face', child: Text(tr('Lấy khuôn mặt trên máy'))),
            PopupMenuItem(value: 'remove', child: Text(tr('Gỡ khỏi máy'))),
          ],
        ),
      ),
    );
  }
}

// ── Tab 3: tổng hợp theo hội viên ───────────────────────────────────────────

class _ReportTab extends StatefulWidget {
  const _ReportTab();

  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  late DateTime _from;
  late DateTime _to;
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _from = DateTime(n.year, n.month, 1);
    _to = DateTime(n.year, n.month, n.day);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getGymReport(from: _from, to: _to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
        _error = null;
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được báo cáo');
      }
    });
  }

  Future<void> _excel() async {
    final res = await _api.downloadGymReportExcel(from: _from, to: _to);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Không xuất được Excel', message: res['message']?.toString() ?? '');
      return;
    }
    await saveAndOpenFileBytes(
      List<int>.from(res['data'] as List),
      'luot_tap_hoi_vien.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = ((_data['items'] as List?) ?? []).whereType<Map>().toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 18),
                label: Text('${_dmy.format(_from)} – ${_dmy.format(_to)}'),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDateRange: DateTimeRange(start: _from, end: _to),
                  );
                  if (r == null) return;
                  _from = r.start;
                  _to = r.end;
                  _load();
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: tr('Xuất Excel'),
                onPressed: _loading ? null : _excel,
                icon: const Icon(Icons.table_view_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('${_data['totalVisits'] ?? 0} lượt · ${_data['members'] ?? 0} hội viên · '
                '${_data['totalHours'] ?? 0} giờ tập'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_loading && items.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else if (items.isEmpty)
            Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(tr('Không có lượt tập trong kỳ'))))
          else
            Card(
              elevation: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  headingRowHeight: 36,
                  columns: [
                    for (final h in ['Hội viên', 'SĐT', 'Lượt', 'Ngày tập', 'Tổng giờ', 'TB phút', 'Cảnh báo',
                      'Lần cuối', 'Thẻ / gói', 'Còn lại', 'Hết hạn'])
                      DataColumn(label: Text(tr(h))),
                  ],
                  rows: [
                    for (final r in items)
                      DataRow(cells: [
                        DataCell(Text('${r['customerName'] ?? ''}')),
                        DataCell(Text('${r['phone'] ?? ''}')),
                        DataCell(Text('${r['visits'] ?? 0}')),
                        DataCell(Text('${r['days'] ?? 0}')),
                        DataCell(Text('${r['totalHours'] ?? 0}')),
                        DataCell(Text('${r['avgMinutes'] ?? 0}')),
                        DataCell(Text('${r['warnings'] ?? 0}',
                            style: TextStyle(color: (r['warnings'] ?? 0) > 0 ? Colors.red.shade700 : null))),
                        DataCell(Text('${r['lastVisit'] ?? ''}')),
                        DataCell(Text('${r['package'] ?? ''}')),
                        DataCell(Text('${r['remaining'] ?? ''}')),
                        DataCell(Text('${r['expiresAt'] ?? ''}')),
                      ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
