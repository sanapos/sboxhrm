import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../utils/file_saver.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_list_filters.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Gym: hội viên check-in bằng máy chấm công (vân tay / khuôn mặt / thẻ) hoặc tại quầy.
/// Tách biệt chấm công nhân viên — hội viên có PIN riêng (9xxxxxxx), lượt quét ghi vào lượt tập,
/// trừ 1 buổi / ngày (thẻ thời gian chỉ kiểm tra hạn).
///
/// 3 tab: Lượt tập (theo ngày) · Hội viên trên máy (đăng ký khách lên máy, lấy vân tay / khuôn mặt)
/// · Báo cáo buổi tập (theo kỳ, theo từng hội viên, xuất Excel).
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
    // Trong khung chính thanh trên đã ghi tiêu đề + nút quay về — chỉ giữ hàng tab.
    final hideTitle = HrmPageChrome.hideInPageTitle(context);
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: hideTitle
          ? null
          : AppBar(
              title: Text(tr('Check-in hội viên')),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              foregroundColor: SboxColors.text,
              elevation: 0.5,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: SboxColors.brand700,
              unselectedLabelColor: SboxColors.slate600,
              indicatorColor: SboxColors.brand600,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: [
                Tab(icon: const Icon(Icons.how_to_reg_outlined, size: 18), iconMargin: EdgeInsets.zero,
                    height: 52, text: tr('Lượt tập')),
                Tab(icon: const Icon(Icons.fingerprint, size: 18), iconMargin: EdgeInsets.zero,
                    height: 52, text: tr('Hội viên trên máy')),
                Tab(icon: const Icon(Icons.bar_chart_rounded, size: 18), iconMargin: EdgeInsets.zero,
                    height: 52, text: tr('Báo cáo buổi tập')),
              ],
            ),
          ),
          const Divider(height: 1, color: SboxColors.slate200),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _VisitsTab(onGoMembers: () => _tabs.animateTo(1)),
                const _MembersTab(),
                const _ReportTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dùng chung ───────────────────────────────────────────────────────────────

final _hm = DateFormat('HH:mm');
final _dmy = DateFormat('dd/MM/yyyy');
final _dm = DateFormat('dd/MM');

DateTime? _date(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  // API trả giờ UTC (có thể thiếu «Z») → đổi giờ máy.
  if (!d.isUtc && !RegExp(r'([zZ]|[+-]\d\d:?\d\d)$').hasMatch(s) && s.contains('T')) {
    return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second).toLocal();
  }
  return d.toLocal();
}

String _duration(int minutes) {
  if (minutes < 60) return '$minutes phút';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h giờ' : '$h giờ $m phút';
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

const _wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// Nhãn nút chọn ngày — ngắn để không bị cắt trên điện thoại.
String _dayLabel(DateTime d) {
  final now = DateTime.now();
  if (_sameDay(d, now)) return 'Hôm nay';
  if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'Hôm qua';
  return '${_wd[d.weekday - 1]} ${_dm.format(d)}';
}

/// "Thẻ tháng · HSD 20/10/2026" / "Gói 10 buổi · còn 3 · HSD …" / "Chưa có thẻ / gói".
String _packageText(Map m) {
  final name = m['packageName']?.toString();
  if (name == null || name.isEmpty) return 'Chưa có thẻ / gói';
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

/// Trạng thái lượt tập do máy / quầy ghi.
(String, SboxTone) _visitStatus(Map v) {
  final inside = v['checkOutAt'] == null;
  return switch (v['status']?.toString()) {
    'NoPackage' => ('Chưa có thẻ / gói', SboxTone.danger),
    'Expired' => ('Thẻ hết hạn', SboxTone.danger),
    'OutOfSessions' => ('Hết buổi', SboxTone.danger),
    _ => inside ? ('Đang tập', SboxTone.success) : ('Đã về', SboxTone.neutral),
  };
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.tone, {this.icon});
  final String text;
  final SboxTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: tone.fg), const SizedBox(width: 3)],
          Text(tr(text),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tone.fg)),
        ]),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap, this.borderColor});
  final Widget child;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor ?? SboxColors.slate200),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: child),
          ),
        ),
      );
}

/// Ô số liệu bấm được để lọc danh sách.
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.tone, this.selected = false, this.onTap});
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
              Text(tr(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 1,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tone.fg)),
            ]),
          ),
        ),
      );
}

/// Lưới ô số liệu: 2 cột điện thoại, 4 cột màn rộng — ô bằng nhau.
class _StatGrid extends StatelessWidget {
  const _StatGrid(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth < 520 ? 2 : children.length;
        const gap = 8.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      });
}

Widget _emptyBox({required IconData icon, required String title, required String text, List<Widget> actions = const []}) =>
    Container(
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
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
        ],
      ]),
    );

// ── Chọn / tạo khách hàng ────────────────────────────────────────────────────

Future<Map<String, dynamic>?> _pickCustomer(BuildContext context, {String title = 'Chọn hội viên'}) {
  return showDialog<Map<String, dynamic>>(context: context, builder: (_) => _CustomerPickerDialog(title: title));
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({required this.title});
  final String title;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  Timer? _debounce;
  bool _creating = false;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
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

  Future<void> _createCustomer() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Thiếu tên', message: tr('Nhập tên hội viên'));
      return;
    }
    setState(() => _saving = true);
    final res = await _api.createPosCustomer({
      'name': name,
      if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      Navigator.pop(context, Map<String, dynamic>.from(res['data'] as Map));
    } else {
      NotificationOverlayManager()
          .showError(title: 'Không tạo được khách', message: res['message']?.toString() ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: maxH.clamp(320, 560)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(tr(_creating ? 'Thêm khách mới' : widget.title),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: tr('Đóng'),
                ),
              ]),
              const SizedBox(height: 6),
              if (_creating) ...[
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('Tên hội viên *'), isDense: true, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: tr('Số điện thoại'), isDense: true, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Text(tr('Khách được lưu vào danh sách khách hàng POS — bán thẻ / gói tập cho khách ở màn Bán hàng.'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
                const Spacer(),
                Row(children: [
                  TextButton(onPressed: () => setState(() => _creating = false), child: Text(tr('Quay lại tìm'))),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _createCustomer,
                    child: Text(tr(_saving ? 'Đang lưu…' : 'Lưu & chọn')),
                  ),
                ]),
              ] else ...[
                TextField(
                  controller: _searchCtrl,
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
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _creating = true;
                      final q = _searchCtrl.text.trim();
                      if (RegExp(r'^[0-9 +]+$').hasMatch(q)) {
                        _phoneCtrl.text = q;
                      } else {
                        _nameCtrl.text = q;
                      }
                    }),
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: Text(tr('Khách mới (chưa có trong danh sách)')),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                          ? Center(child: Text(tr('Không tìm thấy khách'), style: const TextStyle(color: SboxColors.slate600)))
                          : ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: SboxColors.slate100),
                              itemBuilder: (_, i) {
                                final c = _items[i];
                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                  leading: const CircleAvatar(
                                    radius: 16,
                                    backgroundColor: SboxColors.brand50,
                                    child: Icon(Icons.person_outline, size: 18, color: SboxColors.brand700),
                                  ),
                                  title: Text(c['name']?.toString() ?? '',
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                      [c['phone'], c['customerCode']]
                                          .where((x) => (x ?? '').toString().isNotEmpty)
                                          .join(' · '),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () => Navigator.pop(context, c),
                                );
                              },
                            ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Lịch sử tập của một hội viên ─────────────────────────────────────────────

Future<void> _showMemberHistory(BuildContext context,
    {required String customerId, required String name, DateTime? from, DateTime? to}) {
  final now = DateTime.now();
  final f = from ?? DateTime(now.year, now.month, now.day).subtract(const Duration(days: 89));
  final t = to ?? now;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _MemberHistory(customerId: customerId, name: name, from: f, to: t, scroll: scroll),
    ),
  );
}

class _MemberHistory extends StatefulWidget {
  const _MemberHistory({required this.customerId, required this.name, required this.from, required this.to, required this.scroll});
  final String customerId;
  final String name;
  final DateTime from;
  final DateTime to;
  final ScrollController scroll;

  @override
  State<_MemberHistory> createState() => _MemberHistoryState();
}

class _MemberHistoryState extends State<_MemberHistory> {
  List<Map> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService().getGymVisits(from: widget.from, to: widget.to, customerId: widget.customerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _items = (((res['data'] as Map)['items'] as List?) ?? []).whereType<Map>().toList();
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được lịch sử');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mins = _items.map((v) => (v['durationMinutes'] as num?)?.toInt() ?? 0).where((m) => m > 0).toList();
    final days = _items
        .map((v) => _date(v['checkInAt']))
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet()
        .length;
    final warn = _items.where((v) => v['status'] != 'Ok').length;
    final pack = _items.isNotEmpty ? _packageText(_items.first) : null;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Center(
          child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: SboxColors.slate300, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 12),
        Text(tr(widget.name), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(tr('Lịch sử tập ${_dmy.format(widget.from)} – ${_dmy.format(widget.to)}'),
            style: const TextStyle(color: SboxColors.slate600)),
        if (pack != null) ...[
          const SizedBox(height: 4),
          Text(tr(pack),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _packageWarn(_items.first) ? SboxColors.warningText : SboxColors.slate700)),
        ],
        const SizedBox(height: 12),
        _StatGrid([
          _StatTile(label: 'Số lượt', value: '${_items.length}', tone: SboxTone.brand),
          _StatTile(label: 'Số ngày tập', value: '$days', tone: SboxTone.success),
          _StatTile(
              label: 'TB mỗi lượt',
              value: mins.isEmpty ? '–' : _duration((mins.reduce((a, b) => a + b) / mins.length).round()),
              tone: SboxTone.violet),
          _StatTile(label: 'Cần kiểm tra', value: '$warn', tone: warn > 0 ? SboxTone.danger : SboxTone.neutral),
        ]),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Text(tr(_error!), style: const TextStyle(color: SboxColors.danger))
        else if (_items.isEmpty)
          _emptyBox(icon: Icons.event_busy, title: 'Chưa có lượt tập', text: 'Hội viên chưa tập lần nào trong kỳ này.')
        else
          for (final v in _items) _historyRow(v),
      ],
    );
  }

  Widget _historyRow(Map v) {
    final inAt = _date(v['checkInAt']);
    final outAt = _date(v['checkOutAt']);
    final mins = (v['durationMinutes'] as num?)?.toInt();
    final (label, tone) = _visitStatus(v);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SboxColors.slate100))),
      child: Row(children: [
        SizedBox(
          width: 86,
          child: Text(inAt == null ? '' : '${_wd[inAt.weekday - 1]}\n${_dmy.format(inAt)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.3)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${inAt == null ? '' : _hm.format(inAt)} → ${outAt == null ? '…' : _hm.format(outAt)}'
              '${mins != null && mins > 0 ? ' · ${_duration(mins)}' : ''}',
              style: const TextStyle(fontSize: 13.5),
            ),
            Text(
              tr([
                (v['deviceName'] ?? '').toString(),
                if (v['sessionDeducted'] == true) 'trừ 1 buổi',
              ].where((s) => s.isNotEmpty).join(' · ')),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
            ),
          ]),
        ),
        _Pill(label, tone),
      ]),
    );
  }
}

// ── Tab 1: lượt tập theo ngày (hôm nay tự làm mới 10 giây) ───────────────────

class _VisitsTab extends StatefulWidget {
  const _VisitsTab({required this.onGoMembers});
  final VoidCallback onGoMembers;

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

  bool get _isToday => _sameDay(_day, DateTime.now());

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

  void _shiftDay(int delta) {
    final next = _day.add(Duration(days: delta));
    if (next.isAfter(DateTime.now())) return;
    _day = next;
    _load();
  }

  Future<void> _manualCheckIn() async {
    final c = await _pickCustomer(context, title: 'Check-in tại quầy');
    if (c == null || !mounted) return;
    final res = await _api.gymCheckIn(c['id'].toString());
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final v = res['data'] is Map ? res['data'] as Map : const {};
      final ok = v['status'] == 'Ok';
      final msg = '${c['name']} · ${v['note'] ?? _packageText(v)}';
      ok
          ? NotificationOverlayManager().showSuccess(title: 'Đã check-in', message: msg)
          : NotificationOverlayManager().showWarning(title: 'Đã check-in — cần kiểm tra thẻ / gói', message: msg);
      if (!_isToday) _day = DateTime.now();
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
    int n(String k) => (_data[k] as num?)?.toInt() ?? 0;
    final filterLabel = switch (_filter) {
      'inside' => 'Đang tập',
      'warn' => 'Cần kiểm tra',
      _ => 'Tất cả lượt',
    };
    return Scaffold(
      backgroundColor: SboxColors.page,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'gym_checkin_fab',
        onPressed: _manualCheckIn,
        icon: const Icon(Icons.how_to_reg),
        label: Text(tr('Check-in tại quầy')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
          children: [
            // Chọn ngày: ‹ Hôm nay · 04/10 › — hôm nay tự cập nhật.
            Row(children: [
              IconButton(
                onPressed: () => _shiftDay(-1),
                icon: const Icon(Icons.chevron_left),
                tooltip: tr('Ngày trước'),
                visualDensity: VisualDensity.compact,
              ),
              Flexible(
                flex: 3,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(tr(_dayLabel(_day)), maxLines: 1, overflow: TextOverflow.ellipsis),
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
              ),
              IconButton(
                onPressed: _isToday ? null : () => _shiftDay(1),
                icon: const Icon(Icons.chevron_right),
                tooltip: tr('Ngày sau'),
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(flex: 1),
              if (_isToday)
                Tooltip(
                  message: tr('Tự cập nhật mỗi 10 giây'),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8,
                        decoration: const BoxDecoration(color: SboxColors.success, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(tr('Trực tiếp'), style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
                  ]),
                ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: tr('Làm mới')),
            ]),
            const SizedBox(height: 6),
            _StatGrid([
              _StatTile(
                label: 'Đang tập',
                value: '${n('inside')}',
                tone: SboxTone.success,
                selected: _filter == 'inside',
                onTap: () => setState(() => _filter = _filter == 'inside' ? 'all' : 'inside'),
              ),
              _StatTile(
                label: 'Lượt tập',
                value: '${n('total')}',
                tone: SboxTone.brand,
                selected: _filter == 'all',
                onTap: () => setState(() => _filter = 'all'),
              ),
              _StatTile(label: 'Hội viên', value: '${n('customers')}', tone: SboxTone.violet),
              _StatTile(
                label: 'Cần kiểm tra',
                value: '${n('warnings')}',
                tone: n('warnings') > 0 ? SboxTone.danger : SboxTone.neutral,
                selected: _filter == 'warn',
                onTap: () => setState(() => _filter = _filter == 'warn' ? 'all' : 'warn'),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Text(tr('$filterLabel (${items.length})'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              if (_filter != 'all')
                TextButton(onPressed: () => setState(() => _filter = 'all'), child: Text(tr('Bỏ lọc'))),
            ]),
            const SizedBox(height: 6),
            if (_loading && all.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(tr(_error!), style: const TextStyle(color: SboxColors.danger))
            else if (all.isEmpty)
              _emptyBox(
                icon: Icons.fingerprint,
                title: _isToday ? 'Hôm nay chưa có lượt tập' : 'Ngày này không có lượt tập',
                text: 'Cách dùng:\n'
                    '① Đăng ký hội viên lên máy chấm công (tab «Hội viên trên máy»), lấy vân tay / khuôn mặt / thẻ.\n'
                    '② Hội viên quét trên máy khi vào và khi ra — lượt tập tự hiện ở đây.\n'
                    '③ Khách quên thẻ: bấm «Check-in tại quầy».',
                actions: [
                  OutlinedButton.icon(
                    onPressed: widget.onGoMembers,
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: Text(tr('Đăng ký hội viên lên máy')),
                  ),
                ],
              )
            else if (items.isEmpty)
              _emptyBox(icon: Icons.filter_alt_off, title: 'Không có lượt phù hợp', text: 'Bấm «Bỏ lọc» để xem tất cả.')
            else
              for (final v in items) _visitTile(v),
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
        (inAt == null ? 0 : DateTime.now().difference(inAt).inMinutes.clamp(0, 24 * 60).toInt());
    final (label, tone) = _visitStatus(v);
    final timeText = inside
        ? 'Vào ${inAt == null ? '' : _hm.format(inAt)} · đã tập ${_duration(minutes)}'
        : 'Vào ${inAt == null ? '' : _hm.format(inAt)} → Ra ${_hm.format(outAt)} · ${_duration(minutes)}';
    final source = (v['deviceName'] ?? '').toString();
    final phone = (v['phone'] ?? '').toString();
    final hasPack = (v['packageName'] ?? '').toString().isNotEmpty;
    final note = (v['note'] ?? '').toString();
    return _Card(
      borderColor: ok ? null : SboxColors.dangerSoft,
      onTap: () => _showMemberHistory(context,
          customerId: v['customerId'].toString(), name: v['customerName']?.toString() ?? ''),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: tone.bg,
          child: Icon(ok ? (inside ? Icons.fitness_center : Icons.logout) : Icons.warning_amber_rounded,
              size: 18, color: tone.fg),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(tr(v['customerName']?.toString() ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              const SizedBox(width: 8),
              _Pill(label, tone),
            ]),
            const SizedBox(height: 2),
            Text(tr(timeText), style: const TextStyle(fontSize: 13, color: SboxColors.slate700)),
            // Có gói: tên gói / còn buổi / HSD. Không hợp lệ: lý do (trạng thái đã ghi ở nhãn) — không lặp 3 lần.
            if (hasPack)
              Text(
                tr([_packageText(v), if (v['sessionDeducted'] == true) 'đã trừ 1 buổi'].join(' · ')),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    color: _packageWarn(v) ? SboxColors.warningText : SboxColors.slate600,
                    fontWeight: _packageWarn(v) ? FontWeight.w600 : FontWeight.w400),
              ),
            if (!ok && note.isNotEmpty && note != label)
              Text(tr(note),
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.dangerText, fontWeight: FontWeight.w600)),
            Row(children: [
              Expanded(
                child: Text(
                  tr([if (source.isNotEmpty) source, if (phone.isNotEmpty) phone].join(' · ')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
                ),
              ),
              if (inside && _isToday)
                TextButton.icon(
                  onPressed: () => _checkOut(v),
                  icon: const Icon(Icons.logout, size: 16),
                  label: Text(tr('Cho ra')),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ]),
          ]),
        ),
      ]),
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
  String _filter = 'all';

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

  /// Một khách có thể đăng ký nhiều máy → gom theo khách.
  List<List<Map<String, dynamic>>> get _groups {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final m in _items) {
      map.putIfAbsent(m['customerId'].toString(), () => []).add(m);
    }
    return map.values.toList();
  }

  static bool _noBio(Map m) =>
      ((m['fingerprintCount'] as num?) ?? 0) == 0 &&
      ((m['faceCount'] as num?) ?? 0) == 0 &&
      (m['cardNumber'] ?? '').toString().isEmpty;

  Future<void> _add({Map<String, dynamic>? customer}) async {
    customer ??= await _pickCustomer(context, title: 'Chọn khách đăng ký lên máy');
    if (customer == null || !mounted) return;
    final devices = (await _api.getDevices(storeOnly: true)).whereType<Map>().toList();
    if (!mounted) return;
    if (devices.isEmpty) {
      NotificationOverlayManager().showError(
          title: 'Chưa có máy chấm công',
          message: tr('Cửa hàng chưa có máy chấm công. Thêm máy ở Thiết lập → Máy chấm công rồi quay lại.'));
      return;
    }
    final already = _items
        .where((m) => m['customerId'].toString() == customer!['id'].toString())
        .map((m) => m['deviceId'].toString())
        .toSet();
    final free = devices.where((d) => !already.contains(d['id'].toString())).toList();
    if (free.isEmpty) {
      NotificationOverlayManager().showInfo(
          title: 'Đã đăng ký đủ máy', message: tr('${customer['name']} đã có trên tất cả máy chấm công.'));
      return;
    }
    final picked = <String>{if (free.length == 1) free.first['id'].toString()};
    final cardCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text(tr('Đăng ký lên máy chấm công')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.person, color: SboxColors.brand700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('${customer!['name']}${(customer['phone'] ?? '').toString().isEmpty ? '' : ' · ${customer['phone']}'}'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Text(tr('Máy hội viên sẽ quét (cửa ra vào / quầy lễ tân):'),
                      style: const TextStyle(fontSize: 13, color: SboxColors.slate700)),
                  for (final d in free)
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
                      labelText: tr('Số thẻ từ (nếu hội viên dùng thẻ)'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('Hội viên được cấp mã PIN riêng (bắt đầu bằng 9) — không tính công, '
                        'không hiện trong danh sách nhân sự. Sau khi đăng ký, lấy vân tay / khuôn mặt.'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
                  ),
                ],
              ),
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
    final card = cardCtrl.text;
    cardCtrl.dispose();
    if (ok != true || !mounted) return;
    final res = await _api.addGymMember(customer['id'].toString(), picked.toList(), cardNumber: card);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã đăng ký lên máy',
          message: tr('Bấm «Lấy vân tay» hoặc «Lấy khuôn mặt» trên thẻ hội viên để khách đăng ký sinh trắc học.'));
      _load();
    } else {
      NotificationOverlayManager()
          .showError(title: 'Không đăng ký được', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _enroll(Map m, bool face) async {
    final res = face
        ? await _api.enrollFaceWithResponse(m['deviceId'].toString(), m['pin'].toString())
        : await _api.enrollFingerprintWithResponse(m['deviceId'].toString(), m['pin'].toString(), 0);
    if (!mounted) return;
    if (res?['isSuccess'] == true) {
      NotificationOverlayManager().showInfo(
          title: face ? 'Đã gửi lệnh lấy khuôn mặt' : 'Đã gửi lệnh lấy vân tay',
          message: tr('Mời ${m['customerName']} ${face ? 'nhìn vào camera' : 'đặt ngón tay 3 lần'} trên máy '
              '${m['deviceName']}. Nếu máy không hiện màn đăng ký, lấy trực tiếp trên máy: '
              'Menu → Người dùng → tìm PIN ${m['pin']}.'));
    } else {
      NotificationOverlayManager().showError(
          title: 'Không gửi được lệnh',
          message: tr('${res?['message'] ?? ''} — có thể lấy trực tiếp trên máy: Menu → Người dùng → PIN ${m['pin']}.'));
    }
  }

  Future<void> _remove(Map m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Gỡ hội viên khỏi máy?')),
        content: Text(tr('${m['customerName']} sẽ không quét được trên máy ${m['deviceName']}. '
            'Lịch sử lượt tập và thẻ / gói vẫn giữ.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Gỡ khỏi máy')),
          ),
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
    final groups = _groups;
    final noBio = groups.where((g) => g.any(_noBio)).length;
    final warn = groups.where((g) => _packageWarn(g.first)).length;
    final shown = switch (_filter) {
      'nobio' => groups.where((g) => g.any(_noBio)).toList(),
      'warn' => groups.where((g) => _packageWarn(g.first)).toList(),
      _ => groups,
    };
    return Scaffold(
      backgroundColor: SboxColors.page,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'gym_member_fab',
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: Text(tr('Thêm hội viên lên máy')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: SboxColors.infoSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 18, color: SboxColors.infoText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Hội viên là KHÁCH HÀNG được đăng ký lên máy chấm công với mã PIN riêng (bắt đầu bằng 9). '
                        'Quét vân tay / khuôn mặt / thẻ chỉ ghi lượt tập — không tính công, '
                        'không lẫn vào danh sách nhân sự.'),
                    style: const TextStyle(fontSize: 12.5, color: SboxColors.infoText, height: 1.35),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Tìm tên, SĐT, PIN'),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) {
                _search = v;
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in [
                  ('all', 'Tất cả (${groups.length})'),
                  ('nobio', 'Chưa lấy vân tay / khuôn mặt ($noBio)'),
                  ('warn', 'Sắp hết / chưa có gói ($warn)'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(tr(f.$2)),
                      selected: _filter == f.$1,
                      onSelected: (_) => setState(() => _filter = f.$1),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            if (_loading && _items.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(tr(_error!), style: const TextStyle(color: SboxColors.danger))
            else if (groups.isEmpty)
              _emptyBox(
                icon: Icons.person_add_alt,
                title: _search.isEmpty ? 'Chưa có hội viên nào trên máy' : 'Không tìm thấy hội viên',
                text: 'Bấm «Thêm hội viên lên máy» → chọn khách (hoặc tạo khách mới) → chọn máy → '
                    'lấy vân tay / khuôn mặt.',
                actions: [
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: Text(tr('Thêm hội viên lên máy')),
                  ),
                ],
              )
            else if (shown.isEmpty)
              _emptyBox(icon: Icons.filter_alt_off, title: 'Không có hội viên phù hợp', text: 'Chọn «Tất cả» để xem toàn bộ.')
            else
              for (final g in shown) _memberCard(g),
          ],
        ),
      ),
    );
  }

  Widget _memberCard(List<Map<String, dynamic>> links) {
    final m = links.first;
    final last = links.map((x) => _date(x['lastVisitAt'])).whereType<DateTime>().fold<DateTime?>(
        null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final phone = (m['phone'] ?? '').toString();
    final warn = _packageWarn(m);
    return _Card(
      onTap: () => _showMemberHistory(context, customerId: m['customerId'].toString(), name: m['customerName'].toString()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: SboxColors.brand50,
            child: Text(
              (m['customerName']?.toString() ?? '?').trim().split(' ').last.characters.firstOrNull?.toUpperCase() ?? '?',
              style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.brand700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(m['customerName']?.toString() ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(
                tr([if (phone.isNotEmpty) phone, 'PIN ${m['pin']}',
                  if (last != null) 'tập gần nhất ${_dm.format(last)}'].join(' · ')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600),
              ),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: tr('Thao tác khác'),
            icon: const Icon(Icons.more_vert, color: SboxColors.slate500),
            onSelected: (v) {
              if (v == 'history') {
                _showMemberHistory(context, customerId: m['customerId'].toString(), name: m['customerName'].toString());
              }
              if (v == 'more') _add(customer: {'id': m['customerId'], 'name': m['customerName'], 'phone': m['phone']});
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'history', child: Text(tr('Lịch sử tập'))),
              PopupMenuItem(value: 'more', child: Text(tr('Đăng ký thêm máy khác'))),
            ],
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(warn ? Icons.warning_amber_rounded : Icons.card_membership, size: 16,
              color: warn ? SboxColors.warningText : SboxColors.slate500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tr(_packageText(m)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    color: warn ? SboxColors.warningText : SboxColors.slate700,
                    fontWeight: warn ? FontWeight.w600 : FontWeight.w400)),
          ),
        ]),
        for (final l in links) _deviceRow(l),
      ]),
    );
  }

  Widget _deviceRow(Map l) {
    final fp = (l['fingerprintCount'] as num?)?.toInt() ?? 0;
    final face = (l['faceCount'] as num?)?.toInt() ?? 0;
    final card = (l['cardNumber'] ?? '').toString();
    final online = l['deviceOnline'] == true;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
      decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.circle, size: 8, color: online ? SboxColors.success : SboxColors.slate400),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr('${l['deviceName']}${online ? '' : ' · mất kết nối'}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _Pill(fp > 0 ? '$fp vân tay' : 'Chưa vân tay', fp > 0 ? SboxTone.success : SboxTone.neutral,
              icon: Icons.fingerprint),
          _Pill(face > 0 ? 'Có khuôn mặt' : 'Chưa khuôn mặt', face > 0 ? SboxTone.success : SboxTone.neutral,
              icon: Icons.face_retouching_natural),
          if (card.isNotEmpty) _Pill('Thẻ $card', SboxTone.brand, icon: Icons.credit_card),
        ]),
        Wrap(spacing: 0, children: [
          TextButton.icon(
            onPressed: () => _enroll(l, false),
            icon: const Icon(Icons.fingerprint, size: 18),
            label: Text(tr('Lấy vân tay')),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          TextButton.icon(
            onPressed: () => _enroll(l, true),
            icon: const Icon(Icons.face_retouching_natural, size: 18),
            label: Text(tr('Lấy khuôn mặt')),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          TextButton.icon(
            onPressed: () => _remove(l),
            icon: const Icon(Icons.person_remove_outlined, size: 18, color: SboxColors.danger),
            label: Text(tr('Gỡ khỏi máy'), style: const TextStyle(color: SboxColors.danger)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ]),
      ]),
    );
  }
}

// ── Tab 3: báo cáo buổi tập theo hội viên ───────────────────────────────────

class _ReportTab extends StatefulWidget {
  const _ReportTab();

  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  PosKiotTimeFilterState _time = PosKiotTimeFilterState.thisMonth();
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  String? _error;
  String _q = '';
  String _sort = 'visits';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    final to = _time.to ?? now;
    // «Toàn thời gian»: báo cáo tối đa 1 năm gần nhất.
    final from = _time.from ?? to.subtract(const Duration(days: 365));
    return (from, to.isAfter(now) ? now : to);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (from, to) = _range;
    final res = await _api.getGymReport(from: from, to: to);
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
    final (from, to) = _range;
    final res = await _api.downloadGymReportExcel(from: from, to: to);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Không xuất được Excel', message: res['message']?.toString() ?? '');
      return;
    }
    await saveAndOpenFileBytes(
      List<int>.from(res['data'] as List),
      'bao_cao_buoi_tap_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final all = ((_data['items'] as List?) ?? []).whereType<Map>().toList();
    final q = _q.trim().toLowerCase();
    final items = all
        .where((r) => q.isEmpty ||
            (r['customerName'] ?? '').toString().toLowerCase().contains(q) ||
            (r['phone'] ?? '').toString().contains(q))
        .toList();
    num v(Map r, String k) => (r[k] as num?) ?? 0;
    switch (_sort) {
      case 'hours':
        items.sort((a, b) => v(b, 'totalHours').compareTo(v(a, 'totalHours')));
      case 'warn':
        items.sort((a, b) => v(b, 'warnings').compareTo(v(a, 'warnings')));
      case 'expiring':
        items.sort((a, b) => (b['expiringSoon'] == true ? 1 : 0).compareTo(a['expiringSoon'] == true ? 1 : 0));
      default:
        items.sort((a, b) => v(b, 'visits').compareTo(v(a, 'visits')));
    }
    String n(String k) => '${_data[k] ?? 0}';
    final (from, to) = _range;
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 760;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
          children: [
            Row(children: [
              PosTimeRangeChip(
                state: _time,
                onChanged: (s) {
                  setState(() => _time = s);
                  _load();
                },
              ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                onPressed: _loading ? null : _excel,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(tr('Excel')),
              ),
            ]),
            const SizedBox(height: 4),
            Text(tr('${_dmy.format(from)} – ${_dmy.format(to)}'),
                style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            const SizedBox(height: 8),
            SboxKpiStrip(items: [
              SboxKpi(label: 'Lượt tập', value: n('totalVisits'), icon: Icons.fitness_center, tone: SboxTone.brand),
              SboxKpi(label: 'Hội viên tập', value: n('members'), icon: Icons.people_outline, tone: SboxTone.violet),
              SboxKpi(label: 'Tổng giờ tập', value: n('totalHours'), icon: Icons.timer_outlined, tone: SboxTone.success),
              SboxKpi(
                  label: 'TB mỗi lượt',
                  value: '${n('avgMinutes')} phút',
                  icon: Icons.av_timer,
                  tone: SboxTone.neutral),
              SboxKpi(
                  label: 'Lượt cần kiểm tra',
                  value: n('warnings'),
                  icon: Icons.warning_amber_rounded,
                  tone: SboxTone.danger,
                  onTap: () => setState(() => _sort = 'warn')),
              SboxKpi(
                  label: 'Sắp hết hạn / buổi',
                  value: n('expiring'),
                  icon: Icons.event_busy,
                  tone: SboxTone.warning,
                  onTap: () => setState(() => _sort = 'expiring')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr('Tìm hội viên'),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (s) => setState(() => _q = s),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: tr('Sắp xếp'),
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => [
                  for (final s in [
                    ('visits', 'Nhiều lượt nhất'),
                    ('hours', 'Nhiều giờ nhất'),
                    ('warn', 'Nhiều cảnh báo'),
                    ('expiring', 'Sắp hết hạn / buổi'),
                  ])
                    PopupMenuItem(value: s.$1, child: Text(tr(s.$2))),
                ],
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SboxColors.slate300),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.sort, size: 18, color: SboxColors.slate600),
                    Icon(Icons.arrow_drop_down, size: 18, color: SboxColors.slate600),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (_loading && all.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(tr(_error!), style: const TextStyle(color: SboxColors.danger))
            else if (items.isEmpty)
              _emptyBox(
                icon: Icons.insights,
                title: all.isEmpty ? 'Không có lượt tập trong kỳ' : 'Không tìm thấy hội viên',
                text: all.isEmpty ? 'Đổi khoảng thời gian để xem các kỳ khác.' : 'Thử tên hoặc số điện thoại khác.',
              )
            else if (wide)
              _table(items, from, to)
            else
              for (final r in items) _reportCard(r, from, to),
          ],
        );
      }),
    );
  }

  void _openHistory(Map r, DateTime from, DateTime to) => _showMemberHistory(context,
      customerId: r['customerId'].toString(), name: r['customerName']?.toString() ?? '', from: from, to: to);

  Widget _reportCard(Map r, DateTime from, DateTime to) {
    final warnings = (r['warnings'] as num?)?.toInt() ?? 0;
    final expiring = r['expiringSoon'] == true;
    final remain = (r['remaining'] ?? '').toString();
    final exp = (r['expiresAt'] ?? '').toString();
    Widget metric(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
          ]),
        );
    return _Card(
      onTap: () => _openHistory(r, from, to),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(r['customerName']?.toString() ?? ''),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(
                tr([if ((r['phone'] ?? '').toString().isNotEmpty) r['phone'], 'lần cuối ${r['lastVisit'] ?? ''}']
                    .join(' · ')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
              ),
            ]),
          ),
          if (warnings > 0) ...[const SizedBox(width: 6), _Pill('$warnings cảnh báo', SboxTone.danger)],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          metric('Lượt', '${r['visits'] ?? 0}'),
          metric('Ngày tập', '${r['days'] ?? 0}'),
          metric('Tổng giờ', '${r['totalHours'] ?? 0}'),
          metric('TB phút', '${r['avgMinutes'] ?? 0}'),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(expiring ? Icons.warning_amber_rounded : Icons.card_membership,
              size: 15, color: expiring ? SboxColors.warningText : SboxColors.slate500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr([
                (r['package'] ?? '').toString(),
                if (remain.isNotEmpty) remain == 'Không giới hạn' ? remain : 'còn $remain buổi',
                if (exp.isNotEmpty) 'HSD $exp',
              ].join(' · ')),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  color: expiring ? SboxColors.warningText : SboxColors.slate700,
                  fontWeight: expiring ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _table(List<Map> items, DateTime from, DateTime to) {
    const head = TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: SboxColors.slate600);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SboxColors.slate200),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, c) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: DataTable(
              columnSpacing: 20,
              headingRowHeight: 40,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 52,
              headingRowColor: WidgetStateProperty.all(SboxColors.slate50),
              showCheckboxColumn: false,
              columns: [
                DataColumn(label: Text(tr('Hội viên'), style: head)),
                DataColumn(label: Text(tr('Lượt'), style: head), numeric: true),
                DataColumn(label: Text(tr('Ngày tập'), style: head), numeric: true),
                DataColumn(label: Text(tr('Tổng giờ'), style: head), numeric: true),
                DataColumn(label: Text(tr('TB phút'), style: head), numeric: true),
                DataColumn(label: Text(tr('Cảnh báo'), style: head), numeric: true),
                DataColumn(label: Text(tr('Lần cuối'), style: head)),
                DataColumn(label: Text(tr('Thẻ / gói'), style: head)),
                DataColumn(label: Text(tr('Còn lại'), style: head)),
                DataColumn(label: Text(tr('Hết hạn'), style: head)),
              ],
              rows: [
                for (final r in items)
                  DataRow(
                    onSelectChanged: (_) => _openHistory(r, from, to),
                    cells: [
                      DataCell(Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('${r['customerName'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w600)),
                          if ((r['phone'] ?? '').toString().isNotEmpty)
                            Text('${r['phone']}', style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                        ],
                      )),
                      DataCell(Text('${r['visits'] ?? 0}')),
                      DataCell(Text('${r['days'] ?? 0}')),
                      DataCell(Text('${r['totalHours'] ?? 0}')),
                      DataCell(Text('${r['avgMinutes'] ?? 0}')),
                      DataCell(Text('${r['warnings'] ?? 0}',
                          style: TextStyle(
                              color: ((r['warnings'] as num?) ?? 0) > 0 ? SboxColors.dangerText : null,
                              fontWeight: ((r['warnings'] as num?) ?? 0) > 0 ? FontWeight.w700 : null))),
                      DataCell(Text('${r['lastVisit'] ?? ''}')),
                      DataCell(Text(tr('${r['package'] ?? ''}'),
                          style: TextStyle(color: r['expiringSoon'] == true ? SboxColors.warningText : null))),
                      DataCell(Text(tr('${r['remaining'] ?? ''}'))),
                      DataCell(Text('${r['expiresAt'] ?? ''}')),
                    ],
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
