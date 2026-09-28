import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import 'meal_menu_quick_editor.dart';
import 'meal_ui.dart';

/// «Hôm nay ăn gì»: thực đơn từng buổi của ngày, trạng thái suất ăn của tôi
/// (đã ăn – số phiếu / đã đăng ký) và tiền ăn tháng này. Căn tin (quyền Sửa) nhập thực đơn ngay tại đây.
class MealTodayView extends StatefulWidget {
  const MealTodayView({super.key, required this.canEditMenu});
  final bool canEditMenu;

  @override
  State<MealTodayView> createState() => _MealTodayViewState();
}

class _MealTodayViewState extends State<MealTodayView> {
  final _api = ApiService();
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getMealToday(date: _date);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true) {
        _data = res['data'] as Map<String, dynamic>?;
        _error = null;
      } else {
        _error = res['message']?.toString() ?? 'Không tải được thực đơn';
      }
    });
  }

  void _shift(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = [
      for (final s in (_data?['sessions'] as List? ?? const []))
        if (s is Map<String, dynamic>) s,
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth < 600 ? 12.0 : 20.0;
        final cols = c.maxWidth >= 1100 ? 3 : c.maxWidth >= 720 ? 2 : 1;
        final w = (c.maxWidth - pad * 2 - (cols - 1) * 14) / cols;
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 40),
          children: [
            _hero(sessions),
            const SizedBox(height: 16),
            if (_loading && _data == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              MealUi.card(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)))
            else if (sessions.isEmpty)
              MealUi.card(
                child: Column(children: [
                  const Icon(Icons.no_meals_rounded, size: 48, color: SboxColors.slate400),
                  const SizedBox(height: 8),
                  Text(tr('Chưa cấu hình buổi ăn. Quản lý vào «Quản lý buổi ăn» để thêm Sáng / Trưa / Tối.'),
                      textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
                ]),
              )
            else
              Wrap(spacing: 14, runSpacing: 14, children: [
                for (final s in sessions) SizedBox(width: w, child: _sessionCard(s)),
              ]),
            const SizedBox(height: 16),
            _monthCard(),
          ],
        );
      }),
    );
  }

  Widget _hero(List<Map<String, dynamic>> sessions) {
    final isToday = MealUi.sameDay(_date, DateTime.now());
    final open = sessions.where((s) => s['phase'] == 'open').firstOrNull;
    final next = sessions.where((s) => s['phase'] == 'upcoming').firstOrNull;
    final headline = !isToday
        ? 'Thực đơn ${MealUi.weekday(_date).toLowerCase()}'
        : open != null
            ? '${open['name']} đang phục vụ'
            : next != null
                ? '${next['name']} lúc ${next['startTime']}'
                : 'Hôm nay ăn gì?';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SboxColors.brand700, SboxColors.brand500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(MealUi.dateLong(_date), style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(tr(headline),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            if (open != null && open['myTicketNo'] != null) ...[
              const SizedBox(height: 6),
              Text(tr('Bạn đã chấm cơm — phiếu #${open['myTicketNo']}'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
        _navBtn(Icons.chevron_left_rounded, () => _shift(-1)),
        if (!isToday)
          TextButton(
            onPressed: () {
              setState(() => _date = DateTime.now());
              _load();
            },
            child: Text(tr('Hôm nay'), style: const TextStyle(color: Colors.white)),
          ),
        _navBtn(Icons.chevron_right_rounded, () => _shift(1)),
      ]),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.15)),
      );

  Widget _sessionCard(Map<String, dynamic> s) {
    final phase = s['phase']?.toString() ?? 'upcoming';
    final dishes = [
      for (final d in (s['dishes'] as List? ?? const []))
        if (d is Map) d,
    ];
    final ticket = s['myTicketNo'];
    final registered = s['myRegistered'];
    final highlight = phase == 'open';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlight ? SboxColors.success : SboxColors.slate200, width: highlight ? 1.6 : 1),
        boxShadow: highlight
            ? [BoxShadow(color: SboxColors.success.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))]
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(14)),
              child: Icon(MealUi.sessionIcon(s['name']?.toString() ?? ''), color: SboxColors.brand600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['name']?.toString() ?? '',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
                Text(
                  '${s['startTime']} – ${s['endTime']}'
                  '${MealUi.n(s['price']) > 0 ? ' · ${MealUi.money(s['price'])}' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500),
                ),
              ]),
            ),
            MealUi.phaseChip(phase),
            if (widget.canEditMenu)
              IconButton(
                tooltip: tr('Nhập thực đơn'),
                icon: const Icon(Icons.edit_note_rounded, color: SboxColors.brand600),
                onPressed: () async {
                  final ok = await showMealMenuQuickEditor(context,
                      date: _date, sessionId: s['id'].toString(), sessionName: s['name'].toString());
                  if (ok) _load();
                },
              ),
          ]),
        ),
        const Divider(height: 1, color: SboxColors.slate100),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: dishes.isEmpty
              ? Row(children: [
                  const Icon(Icons.hourglass_empty_rounded, size: 18, color: SboxColors.slate400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr('Căn tin chưa cập nhật thực đơn'),
                        style: const TextStyle(color: SboxColors.slate500)),
                  ),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final d in dishes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(MealUi.dishIcon(d['category']?.toString()), size: 18, color: SboxColors.brand500),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(d['dishName']?.toString() ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600, color: SboxColors.slate800)),
                            if ((d['description']?.toString() ?? '').isNotEmpty)
                              Text(d['description'].toString(),
                                  style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                          ]),
                        ),
                        if ((d['category']?.toString() ?? '').isNotEmpty)
                          Text(d['category'].toString(),
                              style: const TextStyle(fontSize: 11, color: SboxColors.slate400)),
                      ]),
                    ),
                  if ((s['note']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('💬 ${s['note']}', style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
                  ],
                ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: SboxColors.slate50,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          child: Row(children: [
            if (ticket != null)
              _status(Icons.check_circle_rounded, 'Đã ăn · phiếu #$ticket lúc ${_hm(s['myMealTime'])}',
                  SboxColors.success)
            else if (registered == true)
              _status(Icons.event_available_rounded, 'Đã đăng ký suất', SboxColors.brand600)
            else if (registered == false)
              _status(Icons.event_busy_rounded, 'Đã huỷ đăng ký', SboxColors.slate500)
            else
              _status(Icons.radio_button_unchecked_rounded, phase == 'closed' ? 'Không ăn' : 'Chưa chấm cơm',
                  SboxColors.slate500),
            const Spacer(),
            Text(tr('${MealUi.n(s['served']).toInt()} người đã ăn'),
                style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          ]),
        ),
      ]),
    );
  }

  String _hm(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? '' : MealUi.time(d);
  }

  Widget _status(IconData icon, String text, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(tr(text), style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
      ]);

  Widget _monthCard() {
    final m = _data?['myMonth'] as Map<String, dynamic>?;
    if (m == null) return const SizedBox.shrink();
    final period = m['period']?.toString() ?? '';
    final label = period.length == 7 ? '${period.substring(5)}/${period.substring(0, 4)}' : period;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MealUi.sectionTitle('Suất ăn của tôi tháng $label', icon: Icons.account_balance_wallet_rounded),
      MealUi.statGrid([
        MealUi.stat('Số suất đã ăn', '${MealUi.n(m['meals']).toInt()}', icon: Icons.restaurant_rounded),
        MealUi.stat('Tiền ăn', MealUi.money(m['amount']),
            icon: Icons.payments_rounded, color: SboxColors.warning),
        MealUi.stat('Đã trả', MealUi.money(m['paid']), icon: Icons.task_alt_rounded, color: SboxColors.success),
        MealUi.stat('Còn phải trả', MealUi.money(m['balance']),
            icon: Icons.receipt_long_rounded,
            color: MealUi.n(m['balance']) > 0 ? SboxColors.danger : SboxColors.success),
      ]),
    ]);
  }
}
