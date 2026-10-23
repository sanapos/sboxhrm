import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_gym_trainer.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'pos_gym_checkin_screen.dart';

final _hm = DateFormat('HH:mm');
final _dm = DateFormat('dd/MM');
final _dmy = DateFormat('dd/MM/yyyy');
const _wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

DateTime? _date(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _weekStart(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));
String _dayLabel(DateTime d) => '${_wd[d.weekday - 1]} ${_dm.format(d)}';

/// Trạng thái lịch tập: 0 hẹn · 1 đã tập · 2 hủy · 3 vắng.
(String, SboxTone) _sessionStatus(int s) => switch (s) {
      1 => ('Đã tập', SboxTone.success),
      2 => ('Đã hủy', SboxTone.neutral),
      3 => ('Khách vắng', SboxTone.danger),
      _ => ('Đã hẹn', SboxTone.brand),
    };

/// Tài khoản PT: hội viên mình phụ trách (thẻ / gói, buổi tập, lần đo gần nhất, lịch hẹn) và lịch tập theo tuần.
/// Lễ tân / quản lý (quyền Check-in gym) xem được mọi PT, chọn PT ở đầu màn.
class PosGymPtScreen extends StatefulWidget {
  const PosGymPtScreen({super.key});

  @override
  State<PosGymPtScreen> createState() => _PosGymPtScreenState();
}

class _PosGymPtScreenState extends State<PosGymPtScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _api = ApiService();
  Map<String, dynamic>? _me;
  String? _error;
  String? _trainerId;
  int _reload = 0;

  bool get _manageAll => _me?['manageAll'] == true;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    final res = await _api.getGymPtMe();
    if (!mounted) return;
    setState(() {
      if (res['isSuccess'] == true && res['data'] is Map) {
        _me = Map<String, dynamic>.from(res['data'] as Map);
        _error = null;
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được thông tin PT');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hideTitle = HrmPageChrome.hideInPageTitle(context);
    final trainers = [
      for (final t in (_me?['trainers'] as List? ?? const []))
        if (t is Map && t['employeeId'] != null) Map<String, dynamic>.from(t),
    ];
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: hideTitle
          ? null
          : AppBar(
              title: Text(tr('PT · Khách của tôi')),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              foregroundColor: SboxColors.text,
              elevation: 0.5,
            ),
      body: _me == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(tr(_error!), textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.danger)),
                    ),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Material(
                color: Colors.white,
                child: Row(children: [
                  Expanded(
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: SboxColors.brand700,
                      unselectedLabelColor: SboxColors.slate600,
                      indicatorColor: SboxColors.brand600,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      tabs: [
                        Tab(icon: const Icon(Icons.people_alt_outlined, size: 18), iconMargin: EdgeInsets.zero,
                            height: 52, text: tr(_manageAll && _trainerId == null ? 'Hội viên có PT' : 'Khách của tôi')),
                        Tab(icon: const Icon(Icons.event_note_outlined, size: 18), iconMargin: EdgeInsets.zero,
                            height: 52, text: tr('Lịch tập')),
                      ],
                    ),
                  ),
                  // Lễ tân / quản lý chọn PT; PT chỉ thấy chính mình.
                  if (_manageAll)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: DropdownButton<String?>(
                        value: trainers.any((t) => '${t['employeeId']}' == _trainerId) ? _trainerId : null,
                        underline: const SizedBox.shrink(),
                        hint: Text(tr('Tất cả PT')),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text(tr('Tất cả PT'))),
                          for (final t in trainers)
                            DropdownMenuItem<String?>(
                              value: '${t['employeeId']}',
                              child: Text(tr('${t['name'] ?? ''} (${t['clients']})')),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _trainerId = v;
                          _reload++;
                        }),
                      ),
                    )
                  else if ('${_me?['name'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(tr('${_me!['name']}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
              const Divider(height: 1, color: SboxColors.slate200),
              Expanded(
                child: TabBarView(controller: _tabs, children: [
                  _ClientsTab(key: ValueKey('c$_reload'), trainerId: _trainerId, manageAll: _manageAll,
                      onBooked: () => setState(() => _reload++)),
                  _ScheduleTab(key: ValueKey('s$_reload'), trainerId: _trainerId, manageAll: _manageAll),
                ]),
              ),
            ]),
    );
  }
}

// ── Tab 1: khách của tôi ─────────────────────────────────────────────────────

class _ClientsTab extends StatefulWidget {
  const _ClientsTab({super.key, required this.trainerId, required this.manageAll, required this.onBooked});
  final String? trainerId;
  final bool manageAll;
  final VoidCallback onBooked;

  @override
  State<_ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<_ClientsTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  String _filter = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.getGymPtClients(trainerId: widget.trainerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is List) {
        _items = [for (final e in res['data'] as List) if (e is Map) Map<String, dynamic>.from(e)];
        _error = null;
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được danh sách');
      }
    });
  }

  bool _needMeasure(Map c) {
    final at = _date(c['lastAssessedAt']);
    return at == null || DateTime.now().difference(at).inDays > 30;
  }

  bool _packWarn(Map c) {
    if (c['packageActive'] != true) return true;
    final exp = _date(c['expiresAt']);
    final left = (c['remainingSessions'] as num?)?.toInt();
    return (exp != null && exp.difference(DateTime.now()).inDays <= 7) ||
        (c['unlimited'] != true && left != null && left <= 2);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final q = _q.trim().toLowerCase();
    final shown = _items.where((c) {
      if (q.isNotEmpty &&
          !'${c['name'] ?? ''}'.toLowerCase().contains(q) &&
          !'${c['phone'] ?? ''}'.contains(q)) {
        return false;
      }
      return switch (_filter) {
        'measure' => _needMeasure(c),
        'pack' => _packWarn(c),
        'nobook' => c['nextSessionAt'] == null,
        _ => true,
      };
    }).toList();
    final today = _day(DateTime.now());
    final bookedToday = _items.where((c) {
      final n = _date(c['nextSessionAt']);
      return n != null && _day(n) == today;
    }).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(tr(_error!), style: const TextStyle(color: SboxColors.danger))
          else ...[
            _Grid([
              _Stat('Hội viên', '${_items.length}', SboxTone.brand, _filter == 'all', () => setState(() => _filter = 'all')),
              _Stat('Có lịch hôm nay', '$bookedToday', SboxTone.success, false, null),
              _Stat('Cần đo lại (>30 ngày)', '${_items.where(_needMeasure).length}', SboxTone.warning,
                  _filter == 'measure', () => setState(() => _filter = _filter == 'measure' ? 'all' : 'measure')),
              _Stat('Sắp hết / hết gói', '${_items.where(_packWarn).length}', SboxTone.danger, _filter == 'pack',
                  () => setState(() => _filter = _filter == 'pack' ? 'all' : 'pack')),
            ]),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Tìm tên / số điện thoại'),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              ChoiceChip(
                label: Text(tr('Chưa có lịch hẹn')),
                selected: _filter == 'nobook',
                onSelected: (_) => setState(() => _filter = _filter == 'nobook' ? 'all' : 'nobook'),
              ),
            ]),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              _empty(
                Icons.sports_gymnastics,
                'Chưa có hội viên',
                widget.manageAll
                    ? 'Gán PT cho hội viên ở màn Check-in hội viên → lịch sử tập → «PT & thể trạng» → «Gán PT».'
                    : 'Lễ tân / quản lý gán bạn làm PT phụ trách cho hội viên — hội viên sẽ hiện ở đây.',
              )
            else if (shown.isEmpty)
              _empty(Icons.filter_alt_off, 'Không có hội viên phù hợp', 'Bỏ lọc hoặc đổi từ khóa.')
            else
              for (final c in shown) _clientCard(c),
          ],
        ],
      ),
    );
  }

  Widget _clientCard(Map<String, dynamic> c) {
    final name = '${c['name'] ?? ''}';
    final exp = _date(c['expiresAt']);
    final left = (c['remainingSessions'] as num?)?.toInt();
    final pack = c['packageName'] == null
        ? 'Chưa có thẻ / gói'
        : [
            '${c['packageName']}',
            if (c['packageActive'] != true) 'đã hết'
            else if (c['unlimited'] != true && left != null) 'còn $left buổi',
            if (exp != null) 'HSD ${_dmy.format(exp)}',
          ].join(' · ');
    final last = _date(c['lastVisitAt']);
    final measured = _date(c['lastAssessedAt']);
    final weight = (c['lastWeightKg'] as num?)?.toDouble();
    final next = _date(c['nextSessionAt']);
    Widget line(IconData icon, String text, {Color color = SboxColors.slate600, FontWeight? weight}) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(tr(text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: color, fontWeight: weight)),
            ),
          ]),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await showGymTrainerSheet(context, customerId: '${c['customerId']}', name: name);
          if (mounted) _load();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: SboxColors.brand50,
                child: Text(name.isEmpty ? '?' : name.trim().split(' ').last[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.brand700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(name), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(
                    tr([
                      if ('${c['phone'] ?? ''}'.isNotEmpty) '${c['phone']}',
                      if (widget.manageAll && '${c['trainerName'] ?? ''}'.isNotEmpty) 'PT ${c['trainerName']}',
                    ].join(' · ')),
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
                  ),
                ]),
              ),
              if (next != null)
                _pill(_day(next) == _day(DateTime.now()) ? 'Hôm nay ${_hm.format(next)}' : '${_dayLabel(next)} ${_hm.format(next)}',
                    SboxTone.success),
            ]),
            const SizedBox(height: 6),
            line(Icons.card_membership_outlined, pack,
                color: _packWarn(c) ? SboxColors.warningText : SboxColors.slate600,
                weight: _packWarn(c) ? FontWeight.w600 : null),
            line(Icons.directions_run,
                last == null ? 'Chưa tập 90 ngày qua' : 'Tập gần nhất ${_dayLabel(last)} · ${c['visits30']} buổi / 30 ngày'),
            line(Icons.monitor_weight_outlined,
                measured == null
                    ? 'Chưa đo thể trạng'
                    : 'Đo gần nhất ${_dmy.format(measured)}${weight != null ? ' · ${weight.toStringAsFixed(weight == weight.roundToDouble() ? 0 : 1)}kg' : ''}',
                color: _needMeasure(c) ? SboxColors.warningText : SboxColors.slate600),
            const SizedBox(height: 4),
            Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
              TextButton.icon(
                onPressed: () => showGymMemberHistory(context, customerId: '${c['customerId']}', name: name),
                icon: const Icon(Icons.history, size: 16),
                label: Text(tr('Lịch sử tập')),
              ),
              TextButton.icon(
                onPressed: () async {
                  await showGymTrainerSheet(context, customerId: '${c['customerId']}', name: name);
                  if (mounted) _load();
                },
                icon: const Icon(Icons.straighten, size: 16),
                label: Text(tr('Thể trạng & phác đồ')),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  if (await showPtBookDialog(context, clients: _items, customerId: '${c['customerId']}')) {
                    _load();
                    widget.onBooked();
                  }
                },
                icon: const Icon(Icons.event_available, size: 16),
                label: Text(tr('Đặt lịch')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Tab 2: lịch tập theo tuần ────────────────────────────────────────────────

class _ScheduleTab extends StatefulWidget {
  const _ScheduleTab({super.key, required this.trainerId, required this.manageAll});
  final String? trainerId;
  final bool manageAll;

  @override
  State<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<_ScheduleTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  DateTime _week = _weekStart(DateTime.now());
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _clients = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _api.getGymPtClients(trainerId: widget.trainerId).then((res) {
      if (!mounted || res['isSuccess'] != true || res['data'] is! List) return;
      _clients = [for (final e in res['data'] as List) if (e is Map) Map<String, dynamic>.from(e)];
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getGymPtSessions(
        from: _week, to: _week.add(const Duration(days: 6)), trainerId: widget.trainerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is List) {
        _items = [for (final e in res['data'] as List) if (e is Map) Map<String, dynamic>.from(e)];
        _error = null;
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được lịch tập');
      }
    });
  }

  void _shift(int weeks) {
    _week = _week.add(Duration(days: 7 * weeks));
    _load();
  }

  Future<void> _setStatus(Map s, int status) async {
    final res = await _api.updateGymPtSession('${s['id']}', {'status': status});
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Chưa cập nhật', message: res['message']?.toString() ?? '');
      return;
    }
    // Đã tập → đánh giá buổi luôn (gắn vào lượt check-in cùng ngày nếu có).
    if (status == 1) {
      final row = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : const <String, dynamic>{};
      if (row['reviewed'] != true) {
        final at = _date(s['startAt']);
        await showGymSessionReview(context,
            customerId: '${s['customerId']}',
            name: '${s['customerName'] ?? ''}',
            visitId: row['visitId']?.toString(),
            visitLabel: at == null ? null : 'Buổi PT ${_dayLabel(at)} ${_hm.format(at)}');
      }
    }
    if (mounted) _load();
  }

  Future<void> _reschedule(Map s) async {
    final at = _date(s['startAt']) ?? DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: at, firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(at));
    if (t == null || !mounted) return;
    final next = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    final res = await _api.updateGymPtSession('${s['id']}', {'startAt': next.toUtc().toIso8601String()});
    if (!mounted) return;
    res['isSuccess'] == true
        ? NotificationOverlayManager().showSuccess(title: 'Đã dời lịch', message: tr('${s['customerName']} → ${_dayLabel(next)} ${_hm.format(next)}'))
        : NotificationOverlayManager().showError(title: 'Chưa dời được', message: res['message']?.toString() ?? '');
    _load();
  }

  Future<void> _delete(Map s) async {
    final series = s['seriesId'] != null;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa lịch ${s['customerName']}?')),
        content: series ? Text(tr('Lịch này đặt lặp hàng tuần.')) : null,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Không'))),
          if (series)
            TextButton(onPressed: () => Navigator.pop(ctx, 'series'), child: Text(tr('Xóa cả các buổi sau'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'one'), child: Text(tr(series ? 'Chỉ buổi này' : 'Xóa'))),
        ],
      ),
    );
    if (choice == null) return;
    await _api.deleteGymPtSession('${s['id']}', series: choice == 'series');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final days = [for (var i = 0; i < 7; i++) _week.add(Duration(days: i))];
    final byDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final s in _items) {
      final at = _date(s['startAt']);
      if (at == null) continue;
      byDay.putIfAbsent(_day(at), () => []).add(s);
    }
    final today = _day(DateTime.now());
    final active = _items.where((s) => s['status'] != 2).length;
    final done = _items.where((s) => s['status'] == 1).length;

    return Scaffold(
      backgroundColor: SboxColors.page,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'gym_pt_book',
        onPressed: () async {
          if (await showPtBookDialog(context, clients: _clients)) _load();
        },
        icon: const Icon(Icons.event_available),
        label: Text(tr('Đặt lịch')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left), tooltip: tr('Tuần trước')),
              Expanded(
                child: Text(
                  tr('Tuần ${_dm.format(days.first)} – ${_dm.format(days.last)}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right), tooltip: tr('Tuần sau')),
              if (_week != _weekStart(DateTime.now()))
                TextButton(
                  onPressed: () {
                    _week = _weekStart(DateTime.now());
                    _load();
                  },
                  child: Text(tr('Tuần này')),
                ),
            ]),
            Text(tr('$active buổi hẹn · $done đã tập'),
                textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate600, fontSize: 13)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(tr(_error!), style: const TextStyle(color: SboxColors.danger))
            else
              for (final d in days) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                  child: Row(children: [
                    Text(tr(_dayLabel(d)),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: d == today ? SboxColors.brand700 : SboxColors.slate700)),
                    if (d == today) ...[const SizedBox(width: 6), _pill('Hôm nay', SboxTone.brand)],
                    const Spacer(),
                    if ((byDay[d] ?? const []).isNotEmpty)
                      Text(tr('${byDay[d]!.length} buổi'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                  ]),
                ),
                if ((byDay[d] ?? const []).isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Text(tr('Trống'), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate400)),
                  )
                else
                  for (final s in byDay[d]!) _sessionCard(s),
              ],
          ],
        ),
      ),
    );
  }

  Widget _sessionCard(Map<String, dynamic> s) {
    final at = _date(s['startAt']);
    final mins = (s['durationMinutes'] as num?)?.toInt() ?? 60;
    final status = (s['status'] as num?)?.toInt() ?? 0;
    final (label, tone) = _sessionStatus(status);
    final checkedIn = s['visitId'] != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: status == 0 && at != null && at.isBefore(DateTime.now()) ? SboxColors.warningText : SboxColors.slate200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 58,
            child: Text(
              at == null ? '' : '${_hm.format(at)}\n${_hm.format(at.add(Duration(minutes: mins)))}',
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.3, color: SboxColors.brand700),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('${s['customerName'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(
                tr([
                  if (widget.manageAll && '${s['trainerName'] ?? ''}'.isNotEmpty) 'PT ${s['trainerName']}',
                  if (checkedIn) 'đã check-in',
                  if (s['reviewed'] == true) 'đã đánh giá',
                  if (s['seriesId'] != null) 'lặp hàng tuần',
                ].join(' · ')),
                style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
              ),
              if ('${s['note'] ?? ''}'.isNotEmpty)
                Text(tr('${s['note']}'), style: const TextStyle(fontSize: 13, color: SboxColors.slate700)),
            ]),
          ),
          _pill(label, tone),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) => switch (v) {
              'move' => _reschedule(s),
              'reopen' => _setStatus(s, 0),
              'delete' => _delete(s),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'move', child: Text(tr('Dời giờ'))),
              if (status != 0) PopupMenuItem(value: 'reopen', child: Text(tr('Đặt lại «Đã hẹn»'))),
              PopupMenuItem(value: 'delete', child: Text(tr('Xóa lịch'))),
            ],
          ),
        ]),
        if (status == 0)
          Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
            TextButton(onPressed: () => _setStatus(s, 2), child: Text(tr('Hủy'))),
            TextButton(onPressed: () => _setStatus(s, 3), child: Text(tr('Khách vắng'))),
            FilledButton.icon(
              onPressed: () => _setStatus(s, 1),
              icon: const Icon(Icons.check, size: 16),
              label: Text(tr('Đã tập · đánh giá')),
            ),
          ])
        else if (status == 1 && s['reviewed'] != true)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await showGymSessionReview(context,
                    customerId: '${s['customerId']}',
                    name: '${s['customerName'] ?? ''}',
                    visitId: s['visitId']?.toString(),
                    visitLabel: at == null ? null : 'Buổi PT ${_dayLabel(at)} ${_hm.format(at)}');
                if (mounted) _load();
              },
              icon: const Icon(Icons.rate_review_outlined, size: 16),
              label: Text(tr('Đánh giá buổi')),
            ),
          ),
      ]),
    );
  }
}

// ── Đặt lịch ─────────────────────────────────────────────────────────────────

const _focusPresets = ['Ngực – vai', 'Lưng – tay', 'Chân – mông', 'Toàn thân', 'Cardio', 'Đo thể trạng', 'Kiểm tra kỹ thuật'];

/// Hộp đặt lịch PT: chọn hội viên, ngày, giờ, thời lượng, lặp hàng tuần, nội dung buổi. Trả về true nếu đã đặt.
Future<bool> showPtBookDialog(BuildContext context,
    {required List<Map<String, dynamic>> clients, String? customerId}) async {
  var clientId = customerId ?? (clients.length == 1 ? '${clients.first['customerId']}' : null);
  final now = DateTime.now();
  var day = _day(now);
  var time = TimeOfDay(hour: now.hour < 17 ? 18 : now.hour + 1 > 21 ? 6 : now.hour + 1, minute: 0);
  if (now.hour >= 21) day = day.add(const Duration(days: 1));
  var duration = 60;
  var repeat = 0;
  final note = TextEditingController();
  FocusManager.instance.primaryFocus?.unfocus();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Widget section(String t) => Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(tr(t), style: const TextStyle(fontWeight: FontWeight.w700)),
          );
      Widget choice<T>(String label, T value, T group, void Function(T) on) => ChoiceChip(
            label: Text(tr(label), style: const TextStyle(fontSize: 12.5)),
            showCheckmark: false,
            selected: value == group,
            onSelected: (_) => setState(() => on(value)),
          );
      final tomorrow = _day(now).add(const Duration(days: 1));
      return AlertDialog(
        title: Text(tr('Đặt lịch tập PT')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                initialValue: clients.any((c) => '${c['customerId']}' == clientId) ? clientId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Hội viên'), isDense: true, border: const OutlineInputBorder()),
                items: [
                  for (final c in clients)
                    DropdownMenuItem(
                      value: '${c['customerId']}',
                      child: Text(tr('${c['name']}${'${c['phone'] ?? ''}'.isEmpty ? '' : ' · ${c['phone']}'}'),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => clientId = v),
              ),
              section('Ngày'),
              Wrap(spacing: 6, runSpacing: 4, children: [
                choice('Hôm nay', _day(now), day, (v) => day = v),
                choice('Ngày mai', tomorrow, day, (v) => day = v),
                for (var i = 2; i < 7; i++)
                  choice(_dayLabel(_day(now).add(Duration(days: i))), _day(now).add(Duration(days: i)), day, (v) => day = v),
                ActionChip(
                  avatar: const Icon(Icons.calendar_month, size: 16),
                  label: Text(tr(day.isAfter(_day(now).add(const Duration(days: 6))) ? _dayLabel(day) : 'Chọn ngày'),
                      style: const TextStyle(fontSize: 12.5)),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: ctx, initialDate: day, firstDate: _day(now), lastDate: now.add(const Duration(days: 365)));
                    if (d != null) setState(() => day = _day(d));
                  },
                ),
              ]),
              section('Giờ'),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final h in const [6, 7, 8, 9, 16, 17, 18, 19, 20])
                  choice('${h.toString().padLeft(2, '0')}:00', TimeOfDay(hour: h, minute: 0), time, (v) => time = v),
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  label: Text(tr('Giờ khác · ${time.format(ctx)}'), style: const TextStyle(fontSize: 12.5)),
                  onPressed: () async {
                    final t = await showTimePicker(context: ctx, initialTime: time);
                    if (t != null) setState(() => time = t);
                  },
                ),
              ]),
              section('Thời lượng'),
              Wrap(spacing: 6, children: [
                for (final m in const [45, 60, 90, 120]) choice('$m phút', m, duration, (v) => duration = v),
              ]),
              section('Lặp hàng tuần (cùng thứ, cùng giờ)'),
              Wrap(spacing: 6, children: [
                choice('Chỉ buổi này', 0, repeat, (v) => repeat = v),
                for (final w in const [3, 7, 11]) choice('${w + 1} tuần', w, repeat, (v) => repeat = v),
              ]),
              section('Nội dung buổi'),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final f in _focusPresets)
                  ActionChip(
                    label: Text(tr(f), style: const TextStyle(fontSize: 12.5)),
                    onPressed: () => setState(() => note.text = note.text.trim().isEmpty ? f : '${note.text.trim()}, $f'),
                  ),
              ]),
              const SizedBox(height: 6),
              TextField(
                controller: note,
                decoration: InputDecoration(
                    labelText: tr('Ghi chú (không bắt buộc)'), isDense: true, border: const OutlineInputBorder()),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: clientId == null ? null : () => Navigator.pop(ctx, true),
            child: Text(tr(repeat == 0 ? 'Đặt lịch' : 'Đặt ${repeat + 1} buổi')),
          ),
        ],
      );
    }),
  );
  FocusManager.instance.primaryFocus?.unfocus();
  if (ok != true || clientId == null || !context.mounted) return false;
  final start = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  final res = await ApiService().addGymPtSession({
    'customerId': clientId,
    'startAt': start.toUtc().toIso8601String(),
    'durationMinutes': duration,
    'repeatWeeks': repeat,
    if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
  });
  if (res['isSuccess'] != true) {
    NotificationOverlayManager().showError(title: 'Chưa đặt được lịch', message: res['message']?.toString() ?? '');
    return false;
  }
  final d = res['data'] is Map ? res['data'] as Map : const {};
  final skipped = (d['skipped'] as List? ?? const []).join(', ');
  final who = clients.where((c) => '${c['customerId']}' == clientId).map((c) => '${c['name']}').firstOrNull ?? '';
  skipped.isEmpty
      ? NotificationOverlayManager().showSuccess(
          title: 'Đã đặt ${d['created']} buổi', message: tr('$who · ${_dayLabel(start)} ${_hm.format(start)}'))
      : NotificationOverlayManager().showWarning(
          title: 'Đã đặt ${d['created']} buổi', message: tr('Bỏ qua buổi trùng lịch PT: $skipped'));
  return true;
}

// ── Dùng chung ───────────────────────────────────────────────────────────────

Widget _pill(String text, SboxTone tone) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(tr(text), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tone.fg)),
    );

Widget _empty(IconData icon, String title, String text) => Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: Column(children: [
        Icon(icon, size: 36, color: SboxColors.brand500),
        const SizedBox(height: 8),
        Text(tr(title), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 6),
        Text(tr(text), textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate600, height: 1.4)),
      ]),
    );

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.tone, this.selected, this.onTap);
  final String label;
  final String value;
  final SboxTone tone;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? tone.fg : SboxColors.slate200, width: selected ? 1.6 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tone.fg)),
            ]),
          ),
        ),
      );
}

class _Grid extends StatelessWidget {
  const _Grid(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth < 520 ? 2 : children.length;
        const gap = 8.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}
