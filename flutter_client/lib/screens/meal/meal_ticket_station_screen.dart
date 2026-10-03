import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/meal_ticket_print.dart';
import '../../widgets/notification_overlay.dart';

/// Trạm in phiếu ăn đặt tại căn tin: máy chấm công căn tin gửi lượt chấm lên server →
/// trạm này tự in 1 phiếu ăn cho mỗi lượt chấm và hiển thị số phiếu lớn trên màn hình.
class MealTicketStationScreen extends StatefulWidget {
  const MealTicketStationScreen({super.key});

  @override
  State<MealTicketStationScreen> createState() => _MealTicketStationScreenState();
}

class _MealTicketStationScreenState extends State<MealTicketStationScreen> {
  final _api = ApiService();
  static const _pollEvery = Duration(seconds: 3);

  /// Khi mở trạm, chỉ tự in phiếu phát sinh trong vòng 10 phút; phiếu cũ hơn chờ bấm «In».
  static const _autoPrintWindow = Duration(minutes: 10);

  MealTicketPrinterConfig _cfg = const MealTicketPrinterConfig();
  Timer? _timer;
  Timer? _clock;
  bool _running = true;
  bool _busy = false;
  String? _storeName;
  String? _error;
  DateTime _now = DateTime.now();
  List<MealTicket> _today = [];
  Map<String, int> _servedBySession = {};
  MealTicket? _last;
  final Set<String> _printing = {};
  final Map<String, DateTime> _failedAt = {};
  int _printedThisRun = 0;

  @override
  void initState() {
    super.initState();
    MealTicketPrinterConfig.load().then((c) {
      if (!mounted) return;
      setState(() => _cfg = c);
      _tick();
      _timer = Timer.periodic(_pollEvery, (_) => _tick());
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final res = await _api.getMealTickets(take: 60);
      if (!mounted) return;
      if (res['isSuccess'] != true) {
        setState(() => _error = res['message']?.toString() ?? 'Không tải được phiếu ăn');
        return;
      }
      final data = res['data'] as Map<String, dynamic>? ?? const {};
      final items = [
        for (final j in (data['items'] as List? ?? const []))
          if (j is Map<String, dynamic>) MealTicket.fromJson(j),
      ];
      final served = <String, int>{};
      (data['servedBySession'] as Map? ?? const {}).forEach((k, v) => served['$k'] = (v as num).toInt());
      setState(() {
        _error = null;
        _today = items;
        _servedBySession = served;
        _storeName = (data['store'] as Map?)?['name']?.toString();
        _last ??= items.isNotEmpty ? items.first : null;
      });
      if (_running && _cfg.autoPrint && _cfg.isConfigured) await _autoPrint(items);
    } finally {
      _busy = false;
    }
  }

  Future<void> _autoPrint(List<MealTicket> items) async {
    final now = DateTime.now();
    final pending = items
        .where((t) => !t.printed && now.difference(t.mealTime) <= _autoPrintWindow)
        .where((t) => !_printing.contains(t.id))
        .where((t) => _failedAt[t.id] == null || now.difference(_failedAt[t.id]!) > const Duration(seconds: 20))
        .toList()
      ..sort((a, b) => a.ticketNo.compareTo(b.ticketNo));
    for (final t in pending) {
      if (!mounted || !_running) return;
      await _print(t, silent: true);
    }
  }

  Future<bool> _print(MealTicket t, {bool silent = false}) async {
    if (_printing.contains(t.id)) return false;
    _printing.add(t.id);
    try {
      final ok = await MealTicketPrinter.printTicket(t, _cfg, storeName: _storeName);
      if (ok) {
        _failedAt.remove(t.id);
        await _api.markMealTicketPrinted(t.id);
        if (mounted) {
          setState(() {
            _last = t;
            _printedThisRun++;
            _today = [
              for (final x in _today)
                x.id == t.id
                    ? MealTicket.fromJson({
                        'id': x.id,
                        'ticketNo': x.ticketNo,
                        'mealTime': x.mealTime.toIso8601String(),
                        'sessionName': x.sessionName,
                        'employeeName': x.employeeName,
                        'employeeCode': x.employeeCode,
                        'department': x.department,
                        'price': x.price,
                        'source': x.source,
                        'printedAt': DateTime.now().toIso8601String(),
                        'printCount': x.printCount + 1,
                        'dishes': [for (final d in x.dishes) {'dishName': d}],
                      })
                    : x,
            ];
          });
        }
      } else {
        _failedAt[t.id] = DateTime.now();
        if (mounted) setState(() => _error = 'Không in được phiếu #${t.ticketNo} — kiểm tra máy in');
        if (!silent) {
          NotificationOverlayManager().showError(title: 'In phiếu ăn', message: 'Máy in chưa sẵn sàng');
        }
      }
      return ok;
    } finally {
      _printing.remove(t.id);
    }
  }

  Future<void> _printAllPending() async {
    final pending = _today.where((t) => !t.printed).toList()..sort((a, b) => a.ticketNo.compareTo(b.ticketNo));
    for (final t in pending) {
      if (!await _print(t)) break;
    }
  }

  Future<void> _testPrint() async {
    final ok = await MealTicketPrinter.printTicket(
      MealTicket(
        id: 'test',
        ticketNo: 0,
        mealTime: DateTime.now(),
        sessionName: 'In thử',
        employeeName: 'Nguyễn Văn Mẫu',
        employeeCode: 'NV000',
        department: 'Phòng mẫu',
        price: 25000,
        dishes: const ['Cơm trắng', 'Gà kho gừng', 'Canh bí'],
      ),
      _cfg,
      storeName: _storeName,
    );
    if (!mounted) return;
    ok
        ? NotificationOverlayManager().showSuccess(title: 'In thử', message: 'Đã gửi phiếu in thử')
        : NotificationOverlayManager().showError(title: 'In thử', message: 'Không in được — kiểm tra cấu hình máy in');
  }

  // ═════════════ UI ═════════════

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final pending = _today.where((t) => !t.printed).length;
    return Scaffold(
      backgroundColor: SboxColors.slate900,
      appBar: AppBar(
        backgroundColor: SboxColors.slate900,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(children: [
          const Icon(Icons.receipt_long_rounded),
          const SizedBox(width: 10),
          Flexible(child: Text(tr('Trạm in phiếu ăn'), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 14),
          Text(DateFormat('HH:mm:ss').format(_now),
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], color: SboxColors.slate300)),
        ]),
        actions: [
          _statusPill(),
          IconButton(
            tooltip: _running ? tr('Tạm dừng in tự động') : tr('Tiếp tục in tự động'),
            icon: Icon(_running ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
            onPressed: () => setState(() => _running = !_running),
          ),
          IconButton(
            tooltip: tr('Cài đặt máy in phiếu'),
            icon: const Icon(Icons.settings_rounded),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(children: [
        if (!_cfg.isConfigured) _banner(Icons.print_disabled_rounded, 'Chưa chọn máy in phiếu ăn', 'Chọn máy in',
            _openSettings, SboxColors.warning),
        if (_error != null) _banner(Icons.error_outline_rounded, _error!, 'Thử lại', _tick, SboxColors.danger),
        if (pending > 0)
          _banner(Icons.pending_actions_rounded, '$pending phiếu chưa in', 'In tất cả', _printAllPending,
              SboxColors.brand600),
        Expanded(
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 3, child: _hero()),
                  SizedBox(width: 380, child: _ticketList()),
                ])
              : Column(children: [SizedBox(height: 300, child: _hero()), Expanded(child: _ticketList())]),
        ),
      ]),
    );
  }

  Widget _statusPill() {
    final ok = _cfg.isConfigured && _error == null;
    final color = !_running ? SboxColors.slate400 : ok ? SboxColors.success : SboxColors.warning;
    final text = !_running ? 'Tạm dừng' : ok ? 'Đang chạy · ${_cfg.printerLabel}' : 'Cần kiểm tra';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(tr(text), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _banner(IconData icon, String text, String action, VoidCallback onTap, Color color) => Container(
        width: double.infinity,
        color: color.withValues(alpha: 0.16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(tr(text), style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          TextButton(onPressed: onTap, child: Text(tr(action), style: TextStyle(color: color))),
        ]),
      );

  Widget _hero() {
    final t = _last;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SboxColors.brand700, SboxColors.brand500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: t == null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.fingerprint_rounded, size: 72, color: Colors.white70),
                const SizedBox(height: 12),
                Text(tr('Mời chấm vân tay / khuôn mặt tại máy căn tin'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(tr('Phiếu ăn sẽ tự in sau mỗi lượt chấm'),
                    style: const TextStyle(color: Colors.white70)),
              ]),
            )
          : LayoutBuilder(builder: (context, c) {
              final big = c.maxHeight > 360;
              return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(tr('PHIẾU ĂN'),
                    style: const TextStyle(color: Colors.white70, letterSpacing: 4, fontWeight: FontWeight.w700)),
                FittedBox(
                  child: Text(t.ticketNo.toString().padLeft(3, '0'),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: big ? 140 : 84,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                Text(t.employeeName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: big ? 30 : 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  [
                    t.sessionName,
                    DateFormat('HH:mm').format(t.mealTime),
                    if ((t.department ?? '').isNotEmpty) t.department!,
                  ].join('  ·  '),
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                if (big && t.dishes.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in t.dishes)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(d, style: const TextStyle(color: Colors.white)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Text(tr('Đã in $_printedThisRun phiếu từ khi mở trạm · hôm nay ${_servedBySession.values.fold<int>(0, (a, b) => a + b)} suất'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]);
            }),
    );
  }

  Widget _ticketList() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
      decoration: BoxDecoration(
        color: SboxColors.slate800,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(children: [
            Expanded(
              child: Text(tr('Phiếu hôm nay (${_today.length})'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        Expanded(
          child: _today.isEmpty
              ? Center(child: Text(tr('Chưa có lượt chấm cơm'), style: const TextStyle(color: SboxColors.slate400)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: _today.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: SboxColors.slate700),
                  itemBuilder: (_, i) {
                    final t = _today[i];
                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 46,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: (t.printed ? SboxColors.success : SboxColors.warning).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('#${t.ticketNo}',
                            style: TextStyle(
                                color: t.printed ? SboxColors.success : SboxColors.warning,
                                fontWeight: FontWeight.w800)),
                      ),
                      title: Text(t.employeeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${t.sessionName} · ${DateFormat('HH:mm').format(t.mealTime)} · ${t.source}'
                        '${t.printed ? '' : ' · ${tr('chưa in')}'}',
                        style: const TextStyle(color: SboxColors.slate400, fontSize: 12),
                      ),
                      trailing: IconButton(
                        tooltip: t.printed ? tr('In lại') : tr('In'),
                        icon: Icon(t.printed ? Icons.replay_rounded : Icons.print_rounded,
                            color: SboxColors.slate300, size: 20),
                        onPressed: () => _print(t),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Future<void> _openSettings() async {
    final printers = kIsWeb ? const [] : await MealTicketPrinter.thermalPrinters();
    if (!mounted) return;
    var cfg = _cfg;
    final footerCtl = TextEditingController(text: cfg.footer);
    final saved = await showModalBottomSheet<MealTicketPrinterConfig>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Máy in phiếu ăn'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(tr('Cấu hình lưu trên máy này (máy đặt tại căn tin).'),
                  style: const TextStyle(color: SboxColors.slate500, fontSize: 13)),
              const SizedBox(height: 14),
              SegmentedButton<MealTicketPrinterMode>(
                segments: [
                  ButtonSegment(
                      value: MealTicketPrinterMode.thermal,
                      icon: const Icon(Icons.receipt_rounded),
                      label: Text(tr('Máy in nhiệt'))),
                  ButtonSegment(
                      value: MealTicketPrinterMode.system,
                      icon: const Icon(Icons.print_rounded),
                      label: Text(tr('Máy in hệ thống'))),
                ],
                selected: {cfg.mode},
                onSelectionChanged: (v) => setS(() => cfg = cfg.copyWith(mode: v.first)),
              ),
              const SizedBox(height: 12),
              if (cfg.mode == MealTicketPrinterMode.thermal) ...[
                if (printers.isEmpty)
                  Text(
                    tr('Chưa có máy in nhiệt nào trên máy này. Vào Cài đặt → Máy in để thêm máy in (LAN / USB / Bluetooth), '
                        'sau đó quay lại chọn.'),
                    style: const TextStyle(color: SboxColors.warningText),
                  )
                else
                  for (final p in printers)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: p.id,
                      groupValue: cfg.thermalProfileId,
                      title: Text(p.name),
                      subtitle: Text('${p.connectionType.name.toUpperCase()} · ${p.paperSize}'),
                      onChanged: (v) => setS(() => cfg = cfg.copyWith(thermalProfileId: v)),
                    ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.print_outlined),
                  title: Text(cfg.systemPrinterName ?? tr('Chưa chọn — mỗi phiếu sẽ mở hộp thoại in')),
                  subtitle: Text(tr('Khổ giấy 80mm; chọn sẵn máy in để in tự động không cần bấm')),
                  trailing: kIsWeb
                      ? null
                      : OutlinedButton(
                          onPressed: () async {
                            final p = await Printing.pickPrinter(context: ctx);
                            if (p != null) {
                              setS(() => cfg = cfg.copyWith(systemPrinterUrl: p.url, systemPrinterName: p.name));
                            }
                          },
                          child: Text(tr('Chọn máy in')),
                        ),
                ),
              ],
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: cfg.autoPrint,
                title: Text(tr('Tự in khi có người chấm cơm')),
                onChanged: (v) => setS(() => cfg = cfg.copyWith(autoPrint: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: cfg.showMenu,
                title: Text(tr('In thực đơn trên phiếu')),
                onChanged: (v) => setS(() => cfg = cfg.copyWith(showMenu: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: cfg.showPrice,
                title: Text(tr('In giá suất ăn')),
                onChanged: (v) => setS(() => cfg = cfg.copyWith(showPrice: v)),
              ),
              TextField(
                controller: footerCtl,
                decoration: InputDecoration(labelText: tr('Lời chào cuối phiếu'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.print_rounded),
                    label: Text(tr('In thử')),
                    onPressed: () async {
                      final prev = _cfg;
                      _cfg = cfg.copyWith(footer: footerCtl.text);
                      await _testPrint();
                      _cfg = prev;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_rounded),
                    label: Text(tr('Lưu')),
                    onPressed: () => Navigator.pop(ctx, cfg.copyWith(footer: footerCtl.text)),
                  ),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
    footerCtl.dispose();
    if (saved != null) {
      await saved.save();
      if (mounted) setState(() => _cfg = saved);
    }
  }
}
