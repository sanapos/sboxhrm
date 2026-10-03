import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/page_top_actions.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../mobile_device_registration_screen.dart';

/// Đăng ký chấm công Mobile.
/// Quản lý: Cần duyệt (đăng ký mới + đổi máy) · Đã cấp quyền · Chưa đăng ký · Điện thoại của tôi.
/// Nhân viên: chỉ màn đăng ký điện thoại của mình.
class MobileDevicesHubScreen extends StatefulWidget {
  const MobileDevicesHubScreen({super.key, this.managerOverride, this.myPhone});

  /// Bỏ qua kiểm quyền (dùng cho test).
  final bool? managerOverride;

  /// Thay tab «Điện thoại của tôi» (dùng cho test).
  final Widget? myPhone;

  @override
  State<MobileDevicesHubScreen> createState() => _MobileDevicesHubScreenState();
}

class _MobileDevicesHubScreenState extends State<MobileDevicesHubScreen> with SingleTickerProviderStateMixin {
  late final bool _manager;
  TabController? _tabs;
  int _pending = 0;
  int _version = 0;

  bool _perm(bool Function(PermissionProvider p) f) {
    try {
      return f(Provider.of<PermissionProvider>(context, listen: false));
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _manager = widget.managerOverride ??
        _perm((p) => p.canApprove('MobileAttendanceApproval') || p.canApprove('AttendanceApproval'));
    if (_manager) _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _version++);

  @override
  Widget build(BuildContext context) {
    final myPhone = widget.myPhone ?? const MobileDeviceRegistrationScreen();
    if (!_manager) return myPhone;
    final narrow = MediaQuery.of(context).size.width < 700;
    // Điện thoại: biểu tượng trên, chữ ngắn dưới — 4 tab chia đều, không cắt chữ.
    Tab tab(IconData icon, String label, [int badge = 0]) => narrow
        ? Tab(
            height: 52,
            icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon, size: 20)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(tr(label), maxLines: 1, style: const TextStyle(fontSize: 12))),
          )
        : Tab(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(tr(label)),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: SboxColors.danger, borderRadius: BorderRadius.circular(99)),
                child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
        );
    return RegisterPageTopActions(
      actions: [HrmTopBarAction(icon: Icons.refresh_rounded, label: 'Làm mới', onPressed: _refresh)],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: Column(children: [
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabs,
              isScrollable: false,
              labelPadding: narrow ? const EdgeInsets.symmetric(horizontal: 2) : null,
              labelColor: SboxColors.brand700,
              unselectedLabelColor: SboxColors.slate500,
              indicatorColor: SboxColors.brand600,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: [
                tab(Icons.fact_check_rounded, 'Cần duyệt', _pending),
                tab(Icons.verified_user_rounded, narrow ? 'Đã cấp' : 'Đã cấp quyền'),
                tab(Icons.person_off_outlined, 'Chưa đăng ký'),
                tab(Icons.smartphone_rounded, narrow ? 'Máy của tôi' : 'Điện thoại của tôi'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                MdInboxView(key: ValueKey('inbox$_version'), onCount: (n) => setState(() => _pending = n), onChanged: _refresh),
                MdDevicesView(key: ValueKey('dev$_version')),
                MdUnregisteredView(key: ValueKey('un$_version')),
                myPhone,
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Dùng chung ─────────────────────────────────────────────────

String _ago(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays < 30) return '${diff.inDays} ngày trước';
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

void _toast(BuildContext context, String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(m)),
      backgroundColor: error ? SboxColors.danger : null,
      behavior: SnackBarBehavior.floating,
    ));

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photo, this.size = 40});
  final String name;
  final String? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).last.characters.first.toUpperCase();
    final hasPhoto = photo != null && photo!.isNotEmpty;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: SboxColors.brand50,
      foregroundImage: hasPhoto ? ApiService().storeImageProvider(photo!) : null,
      onForegroundImageError: hasPhoto ? (_, __) {} : null,
      child: Text(initials, style: TextStyle(color: SboxColors.brand700, fontWeight: FontWeight.w800, fontSize: size * 0.4)),
    );
  }
}

Widget _empSubtitle(Map e) {
  final parts = [e['employeeCode'], e['department'], e['branchName']]
      .whereType<Object>()
      .map((x) => '$x')
      .where((x) => x.isNotEmpty)
      .join(' · ');
  return Text(tr(parts), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: SboxColors.slate500));
}

List<Map<String, dynamic>> _rows(dynamic v) => [if (v is List) for (final x in v.whereType<Map>()) Map<String, dynamic>.from(x)];

// ─── Cần duyệt ─────────────────────────────────────────────────

class MdInboxView extends StatefulWidget {
  const MdInboxView({super.key, this.onCount, this.onChanged});
  final ValueChanged<int>? onCount;
  final VoidCallback? onChanged;

  @override
  State<MdInboxView> createState() => _MdInboxViewState();
}

class _MdInboxViewState extends State<MdInboxView> {
  final _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  final Set<String> _selected = {};
  final Set<String> _busy = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.getMobileDeviceInbox();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        _items = _rows((r['data'] as Map)['items']);
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Không tải được';
      }
      _selected.removeWhere((id) => !_items.any((i) => '${i['id']}' == id));
    });
    widget.onCount?.call(_items.length);
  }

  Future<bool> _decide(Map<String, dynamic> it, bool approve, {String? reason}) async {
    final id = '${it['id']}';
    setState(() => _busy.add(id));
    final r = it['kind'] == 'change'
        ? await _api.approveDeviceChange(requestId: id, approved: approve, rejectionReason: reason)
        : await _api.approveMobileDevice(deviceId: id, approved: approve, rejectionReason: reason);
    if (!mounted) return false;
    setState(() => _busy.remove(id));
    final ok = r['isSuccess'] == true;
    if (!ok) _toast(context, r['message']?.toString() ?? 'Không xử lý được', error: true);
    return ok;
  }

  Future<void> _approve(Map<String, dynamic> it) async {
    if (await _decide(it, true)) {
      if (!mounted) return;
      _toast(context, 'Đã duyệt điện thoại của ${(it['employee'] as Map?)?['employeeName'] ?? ''}');
      _load();
    }
  }

  Future<void> _reject(Map<String, dynamic> it) async {
    final reason = await showRejectReasonDialog(context, (it['employee'] as Map?)?['employeeName']?.toString() ?? '');
    if (reason == null) return;
    if (await _decide(it, false, reason: reason)) {
      if (!mounted) return;
      _toast(context, 'Đã từ chối, nhân viên nhận được lý do');
      _load();
    }
  }

  Future<void> _approveSelected() async {
    final list = _items.where((i) => _selected.contains('${i['id']}')).toList();
    var ok = 0;
    for (final it in list) {
      if (await _decide(it, true)) ok++;
    }
    if (!mounted) return;
    _toast(context, 'Đã duyệt $ok/${list.length} yêu cầu');
    _selected.clear();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SboxLoading(message: 'Đang tải yêu cầu…');
    if (_error != null) return SboxEmptyState(icon: Icons.cloud_off_rounded, title: 'Không tải được', message: _error);
    if (_items.isEmpty) {
      return const SboxEmptyState(
        icon: Icons.verified_rounded,
        title: 'Không có yêu cầu chờ duyệt',
        message: 'Đăng ký điện thoại mới và yêu cầu đổi máy của nhân viên sẽ hiện ở đây.',
      );
    }
    final wide = MediaQuery.of(context).size.width >= 900;
    return Column(children: [
      Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 8, wide ? 24 : 12, 8),
        child: Row(children: [
          Checkbox(
            value: _selected.isEmpty ? false : (_selected.length == _items.length ? true : null),
            tristate: true,
            onChanged: (_) => setState(() {
              if (_selected.length == _items.length) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(_items.map((i) => '${i['id']}'));
              }
            }),
          ),
          Expanded(
            child: Text(
              tr(_selected.isEmpty ? '${_items.length} yêu cầu chờ duyệt' : 'Đã chọn ${_selected.length}'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (_selected.isNotEmpty)
            SboxButton(label: 'Duyệt ${_selected.length} yêu cầu', icon: Icons.done_all_rounded, onPressed: _approveSelected),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 12, wide ? 24 : 12, 40),
            children: [
              for (final it in _items)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(it, wide)),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _card(Map<String, dynamic> it, bool wide) {
    final id = '${it['id']}';
    final e = Map<String, dynamic>.from((it['employee'] as Map?) ?? {});
    final isChange = it['kind'] == 'change';
    final faces = [for (final f in (it['faceImages'] as List? ?? const [])) '$f'];
    final locs = [for (final l in (it['locations'] as List? ?? const [])) '$l'];
    final busy = _busy.contains(id);
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Checkbox(
          value: _selected.contains(id),
          onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
        ),
        _Avatar(name: '${e['employeeName'] ?? ''}', photo: e['photoUrl']?.toString()),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('${e['employeeName'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            _empSubtitle(e),
          ]),
        ),
        SboxStatusChip(
          label: isChange ? 'Đổi máy' : 'Đăng ký mới',
          tone: isChange ? SboxTone.violet : SboxTone.brand,
          icon: isChange ? Icons.swap_horiz_rounded : Icons.fiber_new_rounded,
        ),
      ]),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Wrap(spacing: 16, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _info(Icons.smartphone_rounded,
              isChange ? '${it['oldDeviceName'] ?? '?'}  ›  ${it['deviceName'] ?? ''}' : '${it['deviceName'] ?? ''}'),
          if ('${it['deviceModel'] ?? ''}'.isNotEmpty) _info(Icons.memory_rounded, '${it['deviceModel']} ${it['osVersion'] ?? ''}'.trim()),
          _info(Icons.schedule_rounded, 'Gửi ${_ago(DateTime.tryParse('${it['requestedAt']}'))}'),
          if ('${it['wifiBssid'] ?? ''}'.isNotEmpty) _info(Icons.wifi_rounded, 'Wi-Fi ${it['wifiBssid']}'),
        ]),
      ),
      if (locs.isNotEmpty) ...[
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final l in locs) SboxStatusChip(label: l, icon: Icons.place_outlined),
          ]),
        ),
      ],
      if ('${it['reason'] ?? ''}'.isNotEmpty) ...[
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(tr('Lý do: ${it['reason']}'), style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
        ),
      ],
    ]);
    final facesRow = faces.isEmpty
        ? Text(tr('Không có ảnh khuôn mặt'), style: const TextStyle(fontSize: 12, color: SboxColors.slate400))
        : Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < faces.length; i++)
              InkWell(
                onTap: () => _showFaces(faces, i, '${e['employeeName'] ?? ''}', e['photoUrl']?.toString()),
                borderRadius: BorderRadius.circular(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 64,
                    height: 64,
                    color: SboxColors.slate100,
                    child: Image(
                      image: _api.storeImageProvider(faces[i]),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.face_rounded, color: SboxColors.slate400),
                    ),
                  ),
                ),
              ),
          ]);
    final actions = Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      SboxButton.secondary(label: 'Từ chối', icon: Icons.close_rounded, onPressed: busy ? null : () => _reject(it)),
      const SizedBox(width: 8),
      SboxButton(label: 'Duyệt', icon: Icons.check_rounded, loading: busy, onPressed: busy ? null : () => _approve(it)),
    ]);
    return SboxCard(
      padding: const EdgeInsets.fromLTRB(4, 12, 16, 14),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: info),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Align(alignment: Alignment.centerLeft, child: facesRow),
                  const SizedBox(height: 12),
                  actions,
                ]),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              info,
              const SizedBox(height: 10),
              Padding(padding: const EdgeInsets.only(left: 12), child: facesRow),
              const SizedBox(height: 12),
              actions,
            ]),
    );
  }

  Widget _info(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: SboxColors.slate400),
        const SizedBox(width: 4),
        Text(tr(text), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700)),
      ]);

  /// Xem ảnh đăng ký lớn, đặt cạnh ảnh hồ sơ để so khớp.
  void _showFaces(List<String> faces, int start, String name, String? profile) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        var i = start;
        return StatefulBuilder(builder: (ctx, set) {
          Widget img(String? path, String label) => Expanded(
                child: Column(children: [
                  AspectRatio(
                    aspectRatio: 3 / 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: SboxColors.slate100,
                        child: path == null || path.isEmpty
                            ? const Icon(Icons.person_outline_rounded, size: 48, color: SboxColors.slate400)
                            : Image(
                                image: _api.storeImageProvider(path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: SboxColors.slate400),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(tr(label), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                ]),
              );
          return AlertDialog(
            title: Text(tr('Ảnh khuôn mặt — $name')),
            content: SizedBox(
              width: 520,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  img(faces[i], 'Ảnh đăng ký ${i + 1}/${faces.length}'),
                  const SizedBox(width: 12),
                  img(profile, 'Ảnh hồ sơ'),
                ]),
                if (faces.length > 1)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(onPressed: i > 0 ? () => set(() => i--) : null, icon: const Icon(Icons.chevron_left_rounded)),
                    IconButton(
                        onPressed: i < faces.length - 1 ? () => set(() => i++) : null, icon: const Icon(Icons.chevron_right_rounded)),
                  ]),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng')))],
          );
        });
      },
    );
  }
}

/// Hỏi lý do từ chối (có lý do nhanh). null = hủy.
Future<String?> showRejectReasonDialog(BuildContext context, String name) {
  const quick = ['Ảnh khuôn mặt mờ / thiếu sáng', 'Không phải nhân viên', 'Sai điện thoại công ty cấp', 'Chọn sai địa điểm'];
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('Từ chối đăng ký của $name')),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final q in quick) ActionChip(label: Text(tr(q)), onPressed: () => set(() => c.text = q)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: tr('Lý do (nhân viên sẽ thấy)'),
                border: const OutlineInputBorder(),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(tr('Từ chối')),
          ),
        ],
      ),
    ),
  );
}

// ─── Đã cấp quyền ──────────────────────────────────────────────

class MdDevicesView extends StatefulWidget {
  const MdDevicesView({super.key});

  @override
  State<MdDevicesView> createState() => _MdDevicesViewState();
}

class _Flag {
  const _Flag(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;

  static const all = [
    _Flag('canUseFaceId', 'Khuôn mặt', Icons.face_retouching_natural_rounded),
    _Flag('canUseGps', 'Định vị', Icons.my_location_rounded),
    _Flag('allowOutsideCheckIn', 'Ngoài công ty', Icons.wrong_location_outlined),
    _Flag('requireOutsideReason', 'Bắt nhập lý do', Icons.edit_note_rounded),
    _Flag('allowTravelCheckIn', 'Công tác', Icons.luggage_outlined),
    _Flag('requirePhotoProof', 'Ảnh hiện trường', Icons.photo_camera_outlined),
  ];
}

class _MdDevicesViewState extends State<MdDevicesView> {
  final _api = ApiService();
  List<Map<String, dynamic>> _rowsData = [];
  final Set<String> _selected = {};
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.getMobileDevicesV2();
    if (!mounted) return;
    setState(() {
      _rowsData = _rows(r['data']);
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return _rowsData;
    return _rowsData.where((d) {
      final e = (d['employee'] as Map?) ?? {};
      return '${e['employeeName']} ${e['employeeCode']} ${d['deviceName']} ${d['deviceModel']}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _bulk(List<String> ids) async {
    final flags = await showModalBottomSheet<Map<String, bool>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _BulkSheet(count: ids.length),
    );
    if (flags == null || flags.isEmpty) return;
    final r = await _api.bulkUpdateMobileDevices(ids, flags);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _toast(context, 'Đã cập nhật ${ids.length} thiết bị');
      _selected.clear();
      _load();
    } else {
      _toast(context, r['message']?.toString() ?? 'Không cập nhật được', error: true);
    }
  }

  Future<void> _revoke(Map<String, dynamic> d) async {
    final name = (d['employee'] as Map?)?['employeeName'] ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thu hồi điện thoại của $name?')),
        content: Text(tr('Nhân viên sẽ không chấm công được trên "${d['deviceName']}" cho tới khi đăng ký lại và được duyệt.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Thu hồi')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.revokeDevice('${d['id']}');
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _load();
    } else {
      _toast(context, r['message']?.toString() ?? 'Không thu hồi được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SboxLoading(message: 'Đang tải thiết bị…');
    final wide = MediaQuery.of(context).size.width >= 900;
    final list = _visible;
    return Column(children: [
      Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 10, wide ? 24 : 12, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: tr('Tìm nhân viên, tên máy'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (_selected.isNotEmpty)
            SboxButton(label: 'Chỉnh ${_selected.length} máy', icon: Icons.tune_rounded, onPressed: () => _bulk(_selected.toList()))
          else
            SboxButton.secondary(
              label: wide ? 'Chỉnh tất cả (${list.length})' : 'Chỉnh tất cả',
              icon: Icons.tune_rounded,
              onPressed: list.isEmpty ? null : () => _bulk(list.map((d) => '${d['id']}').toList()),
            ),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? const SboxEmptyState(icon: Icons.phonelink_off_rounded, title: 'Chưa có điện thoại được cấp quyền')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 12, wide ? 24 : 12, 40),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _row(list[i], wide),
                ),
              ),
      ),
    ]);
  }

  Widget _row(Map<String, dynamic> d, bool wide) {
    final id = '${d['id']}';
    final e = Map<String, dynamic>.from((d['employee'] as Map?) ?? {});
    final flags = Wrap(spacing: 6, runSpacing: 6, children: [
      for (final f in _Flag.all)
        if (d[f.key] == true) SboxStatusChip(label: f.label, icon: f.icon, tone: SboxTone.brand),
      if (d['resigned'] == true) const SboxStatusChip(label: 'NV đã nghỉ', tone: SboxTone.danger),
    ]);
    return SboxCard(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Checkbox(
            value: _selected.contains(id),
            onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
          ),
          _Avatar(name: '${e['employeeName'] ?? ''}', photo: e['photoUrl']?.toString(), size: 36),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('${e['employeeName'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                tr('${d['deviceName'] ?? ''} · dùng ${_ago(DateTime.tryParse('${d['lastUsedAt']}')).isEmpty ? 'chưa có' : _ago(DateTime.tryParse('${d['lastUsedAt']}'))}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
              ),
            ]),
          ),
          if (wide) Expanded(flex: 4, child: flags),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: SboxColors.slate500),
            onSelected: (v) => v == 'edit' ? _bulk([id]) : _revoke(d),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(tr('Chỉnh quyền'))),
              PopupMenuItem(value: 'revoke', child: Text(tr('Thu hồi'), style: const TextStyle(color: SboxColors.danger))),
            ],
          ),
        ]),
        if (!wide) Padding(padding: const EdgeInsets.fromLTRB(60, 6, 12, 0), child: flags),
      ]),
    );
  }
}

/// Chỉnh quyền hàng loạt: mỗi quyền chọn Giữ nguyên / Bật / Tắt.
class _BulkSheet extends StatefulWidget {
  const _BulkSheet({required this.count});
  final int count;

  @override
  State<_BulkSheet> createState() => _BulkSheetState();
}

class _BulkSheetState extends State<_BulkSheet> {
  final Map<String, bool?> _v = {for (final f in _Flag.all) f.key: null};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Chỉnh quyền ${widget.count} điện thoại'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(tr('Quyền để «Giữ nguyên» sẽ không đổi.'), style: const TextStyle(color: SboxColors.slate500)),
          const SizedBox(height: 12),
          for (final f in _Flag.all)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(f.icon, size: 20, color: SboxColors.slate500),
                const SizedBox(width: 10),
                Expanded(child: Text(tr(f.label), style: const TextStyle(fontWeight: FontWeight.w600))),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(value: 0, label: Text(tr('Giữ'))),
                    ButtonSegment(value: 1, label: Text(tr('Bật'))),
                    ButtonSegment(value: 2, label: Text(tr('Tắt'))),
                  ],
                  selected: {_v[f.key] == null ? 0 : (_v[f.key]! ? 1 : 2)},
                  onSelectionChanged: (s) => setState(() => _v[f.key] = s.first == 0 ? null : s.first == 1),
                ),
              ]),
            ),
          const SizedBox(height: 16),
          SboxButton(
            label: 'Áp dụng',
            icon: Icons.check_rounded,
            expand: true,
            onPressed: _v.values.every((x) => x == null)
                ? null
                : () => Navigator.pop(context, {for (final e in _v.entries) if (e.value != null) e.key: e.value!}),
          ),
        ]),
      ),
    );
  }
}

// ─── Chưa đăng ký ─────────────────────────────────────────────

class MdUnregisteredView extends StatefulWidget {
  const MdUnregisteredView({super.key});

  @override
  State<MdUnregisteredView> createState() => _MdUnregisteredViewState();
}

class _MdUnregisteredViewState extends State<MdUnregisteredView> {
  final _api = ApiService();
  List<Map<String, dynamic>> _list = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.getUnregisteredMobileEmployees();
    if (!mounted) return;
    setState(() {
      _list = _rows(r['data']);
      _loading = false;
    });
  }

  Future<void> _remind(List<String> ids) async {
    setState(() => _sending = true);
    final r = await _api.remindMobileRegistration(ids);
    if (!mounted) return;
    setState(() => _sending = false);
    if (r['isSuccess'] == true) {
      final d = (r['data'] as Map?) ?? {};
      final skipped = (d['skipped'] as num?)?.toInt() ?? 0;
      _toast(context, 'Đã nhắc ${d['sent'] ?? 0} người${skipped > 0 ? ' ($skipped người chưa có tài khoản đăng nhập)' : ''}');
      _selected.clear();
      setState(() {});
    } else {
      _toast(context, r['message']?.toString() ?? 'Không gửi được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SboxLoading(message: 'Đang tải…');
    if (_list.isEmpty) {
      return const SboxEmptyState(icon: Icons.celebration_rounded, title: 'Mọi nhân viên đã đăng ký điện thoại');
    }
    final wide = MediaQuery.of(context).size.width >= 900;
    final canRemind = _list.where((e) => e['hasAccount'] == true && e['pending'] != true).map((e) => '${e['employeeId']}').toList();
    return Column(children: [
      Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 10, wide ? 24 : 12, 10),
        child: Row(children: [
          Expanded(
            child: Text(tr('${_list.length} nhân viên chưa có điện thoại được duyệt'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          SboxButton(
            label: _selected.isEmpty ? 'Nhắc tất cả (${canRemind.length})' : 'Nhắc ${_selected.length} người',
            icon: Icons.notifications_active_outlined,
            loading: _sending,
            onPressed: _sending || (canRemind.isEmpty && _selected.isEmpty)
                ? null
                : () => _remind(_selected.isEmpty ? canRemind : _selected.toList()),
          ),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 12, wide ? 24 : 12, 40),
          itemCount: _list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final e = _list[i];
            final id = '${e['employeeId']}';
            final noAccount = e['hasAccount'] != true;
            return SboxCard(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Row(children: [
                Checkbox(
                  value: _selected.contains(id),
                  onChanged: noAccount ? null : (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
                ),
                _Avatar(name: '${e['employeeName'] ?? ''}', photo: e['photoUrl']?.toString(), size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('${e['employeeName'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    _empSubtitle(e),
                  ]),
                ),
                if (e['pending'] == true)
                  const SboxStatusChip(label: 'Đang chờ duyệt', tone: SboxTone.warning, dot: true)
                else if (noAccount)
                  const SboxStatusChip(label: 'Chưa có tài khoản', tone: SboxTone.neutral)
                else
                  const SboxStatusChip(label: 'Chưa đăng ký', tone: SboxTone.danger, dot: true),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}
