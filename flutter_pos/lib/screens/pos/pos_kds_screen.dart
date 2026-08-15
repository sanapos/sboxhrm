import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/pos_store_printer.dart';
import '../../services/api_service.dart';
import '../../utils/pos_floor_realtime.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_qr_order_voice.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// KDS bếp: mặc định gộp món (quán đông), chạm Đang làm / Xong hàng loạt.
class PosKdsScreen extends StatefulWidget {
  const PosKdsScreen({super.key});

  @override
  State<PosKdsScreen> createState() => _PosKdsScreenState();
}

enum _KdsView { dish, table }

class _PosKdsScreenState extends State<PosKdsScreen> {
  static const _bg = Color(0xFF070B14);
  static const _bar = Color(0xFF0C1222);
  static const _card = Color(0xFF141C2E);
  static const _line = Color(0xFF243049);
  static const _queued = Color(0xFFFF8A3D);
  static const _cooking = Color(0xFF3DBBFF);
  static const _ready = Color(0xFF34D399);
  static const _late = Color(0xFFFF4D6A);

  final _api = ApiService();
  final _floor = PosFloorRealtimeSubscription(
    debounce: const Duration(milliseconds: 250),
  );
  final _qtyFmt = NumberFormat('#,##0.###', 'vi_VN');
  final _clockFmt = DateFormat('HH:mm:ss');

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _stationId;
  _KdsView _view = _KdsView.dish;
  bool _newestFirst = false;
  bool _onlyUnfinished = false;
  bool _printOnDone = false;
  bool _voiceOn = true;
  bool _voiceSeeded = false;
  final Map<String, double> _seenQty = {};
  String? _kdsPrinterId;
  List<PosStorePrinter> _kdsPrinters = [];
  List<_KdsStation> _stations = [];
  List<_KdsTicket> _tickets = [];
  String? _lastBumpedOrderId;
  int _lastOpenCount = 0;
  Timer? _poll;
  Timer? _clock;
  final _nowTick = ValueNotifier<DateTime>(DateTime.now());

  @override
  void initState() {
    super.initState();
    PosQrOrderVoiceAlert.instance.enterKds();
    unawaited(_bootstrap());
    _floor.start((event) {
      if (!mounted) return;
      unawaited(_loadTickets(silent: true, pingNew: true));
    });
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) unawaited(_loadTickets(silent: true));
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _nowTick.value = DateTime.now();
    });
  }

  @override
  void dispose() {
    PosQrOrderVoiceAlert.instance.leaveKds();
    _floor.dispose();
    _poll?.cancel();
    _clock?.cancel();
    _nowTick.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final st = await _api.getPosKdsStations();
    if (!mounted) return;
    if (st['isSuccess'] == true && st['data'] is Map) {
      final raw =
          (st['data'] as Map)['stations'] ?? (st['data'] as Map)['Stations'];
      final list = <_KdsStation>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            list.add(_KdsStation.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
      _stations = _dedupeStations(list);
    }
    await _loadKdsPrintPrefs();
    await _loadTickets();
  }

  String _stationKey(String name) {
    var s = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll(
      RegExp(
        r'\s*[\(\[]\s*(usb|lan|wifi|wi-?fi|agent|local|cloud|máy này)[^)\]]*[\)\]]',
        caseSensitive: false,
      ),
      '',
    );
    return s.trim();
  }

  List<_KdsStation> _dedupeStations(List<_KdsStation> raw) {
    final byId = <String, _KdsStation>{};
    for (final s in raw) {
      if (s.id.isEmpty) continue;
      byId.putIfAbsent(s.id, () => s);
    }
    final byName = <String, _KdsStation>{};
    for (final s in byId.values) {
      final key = _stationKey(s.name);
      if (key.isEmpty) continue;
      final prev = byName[key];
      byName[key] = prev == null ? s : prev.merge(s);
    }
    return byName.values.toList();
  }

  List<PosStorePrinter> _dedupePrinters(List<PosStorePrinter> raw) {
    final byId = <String, PosStorePrinter>{};
    for (final p in raw) {
      if (p.id.isEmpty) continue;
      byId[p.id] = p;
    }
    final byName = <String, PosStorePrinter>{};
    for (final p in byId.values) {
      final key = _stationKey(p.name);
      if (key.isEmpty) continue;
      final prev = byName[key];
      if (prev == null) {
        byName[key] = p;
        continue;
      }
      final prefer = (p.isDeviceLocal && !prev.isDeviceLocal) ||
          (p.isOnline && !prev.isOnline && p.isDeviceLocal == prev.isDeviceLocal);
      if (prefer) byName[key] = p;
    }
    return byName.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  bool _ticketUnfinished(_KdsTicket t) =>
      t.items.every((i) => i.status != 'ready' && i.status != 'done');

  Future<void> _loadKdsPrintPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _printOnDone = prefs.getBool('pos_kds_print_on_done') ?? false;
    _kdsPrinterId = prefs.getString('pos_kds_printer_id');
    _newestFirst = prefs.getBool('pos_kds_newest_first') ?? false;
    _onlyUnfinished = prefs.getBool('pos_kds_only_unfinished') ?? false;
    _voiceOn = prefs.getBool('pos_kds_voice_on') ?? true;
    try {
      final res = await _api.getPosStorePrinters();
      if (res['isSuccess'] == true) {
        final data = res['data'];
        final list = data is List
            ? data
            : (data is Map && data['items'] is List
                ? data['items'] as List
                : const []);
        _kdsPrinters = _dedupePrinters(list
            .whereType<Map>()
            .map((e) => PosStorePrinter.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => p.isActive && p.id.isNotEmpty)
            .toList());
      }
    } catch (_) {}
  }

  Future<void> _saveKdsPrintPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pos_kds_print_on_done', _printOnDone);
    await prefs.setBool('pos_kds_newest_first', _newestFirst);
    await prefs.setBool('pos_kds_only_unfinished', _onlyUnfinished);
    await prefs.setBool('pos_kds_voice_on', _voiceOn);
    if (_kdsPrinterId == null || _kdsPrinterId!.isEmpty) {
      await prefs.remove('pos_kds_printer_id');
    } else {
      await prefs.setString('pos_kds_printer_id', _kdsPrinterId!);
    }
  }

  Future<void> _printReadyHits(List<_KdsHit> hits) async {
    if (!_printOnDone || hits.isEmpty) return;
    PosStorePrinter? printer;
    for (final p in _kdsPrinters) {
      if (p.id == _kdsPrinterId) {
        printer = p;
        break;
      }
    }
    printer ??= _kdsPrinters.isEmpty ? null : _kdsPrinters.first;
    if (printer == null) return;
    final now = DateTime.now();
    for (final h in hits) {
      unawaited(PosPrintOrchestrator.instance.dispatchKdsReadySlip(
        printer: printer,
        productName: h.item.productName,
        qty: h.item.qty,
        tableName: h.ticket.shortTable,
        areaName: h.ticket.areaName,
        calledAt: h.item.sentAt ?? h.ticket.sentAt,
        readyAt: now,
        orderNo: h.ticket.orderNo,
      ));
    }
  }

  List<_KdsHit> _hitsForIds(List<String> ids) {
    final out = <_KdsHit>[];
    final want = ids.toSet();
    for (final t in _tickets) {
      for (final i in t.items) {
        if (want.contains(i.id)) out.add(_KdsHit(ticket: t, item: i));
      }
    }
    return out;
  }

  bool _needsPrep(_KdsItem i) => i.status != 'ready' && i.status != 'done';

  List<_KdsHit> _prepHitsOf(List<_KdsTicket> tickets) {
    final out = <_KdsHit>[];
    for (final t in tickets) {
      for (final i in t.items) {
        if (_needsPrep(i)) out.add(_KdsHit(ticket: t, item: i));
      }
    }
    return out;
  }

  List<_KdsHit> _collectNewPrepHits(List<_KdsTicket> tickets) {
    final prep = _prepHitsOf(tickets);
    final first = !_voiceSeeded;
    _voiceSeeded = true;
    final next = <String, double>{};
    final newcomers = <_KdsHit>[];
    for (final h in prep) {
      next[h.item.id] = h.item.qty;
      final prev = _seenQty[h.item.id];
      if (prev == null || h.item.qty > prev + 0.0001) {
        newcomers.add(h);
      }
    }
    _seenQty
      ..clear()
      ..addAll(next);
    if (first) return const [];
    return newcomers;
  }

  String _qtyWords(double q) {
    if (q == q.roundToDouble()) return '${q.round()}';
    return _qtyFmt.format(q);
  }

  String _itemSpeakNumbered(int index, _KdsItem i) {
    final note = (i.note ?? '').trim();
    var s = 'Món $index: ${i.productName}, số lượng ${_qtyWords(i.qty)}';
    if (note.isNotEmpty) s += ', $note';
    return s;
  }

  String _ticketSpeak(_KdsTicket t, List<_KdsItem> items) {
    final area = (t.areaName ?? '').trim();
    final table = t.shortTable;
    final head = [
      if (area.isNotEmpty) 'Khu vực $area',
      'Bàn $table',
      'Tổng số ${items.length} món',
    ].join(', ');
    final body = [
      for (var i = 0; i < items.length; i++) _itemSpeakNumbered(i + 1, items[i]),
    ].join('. ');
    return '$head. $body';
  }

  String _kdsSpeakPhrase(List<_KdsHit> hits, {required bool fresh}) {
    if (hits.isEmpty) return '';
    final byTicket = <String, List<_KdsHit>>{};
    for (final h in hits) {
      byTicket.putIfAbsent(h.ticket.orderId, () => []).add(h);
    }
    final parts = <String>[];
    var extra = 0;
    for (final group in byTicket.values) {
      if (parts.length >= 8) {
        extra += group.length;
        continue;
      }
      final t = group.first.ticket;
      parts.add(_ticketSpeak(t, [for (final h in group) h.item]));
    }
    final prefix = fresh ? 'Món mới. ' : '';
    final tail = extra > 0 ? '. Và $extra món khác' : '';
    return '$prefix${parts.join('. ')}$tail';
  }

  void _speakHits(List<_KdsHit> hits, {String? empty}) {
    final prep = hits.where((h) => _needsPrep(h.item)).toList();
    if (prep.isEmpty) {
      unawaited(PosQrOrderVoiceAlert.instance
          .speak(empty ?? 'Không còn món cần chế biến'));
      return;
    }
    unawaited(PosQrOrderVoiceAlert.instance.speak(
      _kdsSpeakPhrase(prep, fresh: false),
    ));
  }

  void _speakAgg(_KdsAgg a) {
    final prep = a.hits.where((h) => _needsPrep(h.item)).toList();
    if (prep.isEmpty) {
      unawaited(PosQrOrderVoiceAlert.instance
          .speak('Không còn ${a.name} cần chế biến'));
      return;
    }
    final qty = prep.fold<double>(0, (s, h) => s + h.item.qty);
    unawaited(PosQrOrderVoiceAlert.instance.speak(
      '${a.name}, số lượng ${_qtyWords(qty)}',
    ));
  }

  void _speakTicket(_KdsTicket t) {
    final prep = t.items.where(_needsPrep).toList();
    if (prep.isEmpty) {
      unawaited(PosQrOrderVoiceAlert.instance
          .speak('Bàn ${t.shortTable} không còn món cần chế biến'));
      return;
    }
    unawaited(PosQrOrderVoiceAlert.instance.speak(_ticketSpeak(t, prep)));
  }

  Future<void> _speakPending() async {
    _speakHits(_prepHitsOf(_tickets));
  }

  Future<void> _setTicketCooking(_KdsTicket t) async {
    final ids = [
      for (final i in t.items)
        if (i.status != 'done') i.id,
    ];
    await _setLines(ids, 'cooking');
  }

  void _toggleVoice() {
    setState(() => _voiceOn = !_voiceOn);
    unawaited(_saveKdsPrintPrefs());
    if (_voiceOn) unawaited(_speakPending());
  }

  Future<void> _loadTickets({bool silent = false, bool pingNew = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await _api.getPosKdsTickets(printerId: _stationId);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được KDS';
      });
      return;
    }
    final data = res['data'];
    final raw = data is Map ? (data['tickets'] ?? data['Tickets']) : null;
    final tickets = <_KdsTicket>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          tickets.add(_KdsTicket.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    tickets.sort((a, b) => _newestFirst
        ? b.oldest.compareTo(a.oldest)
        : a.oldest.compareTo(b.oldest));
    final newcomers = _collectNewPrepHits(tickets);
    if (_onlyUnfinished) {
      tickets.removeWhere((t) => !_ticketUnfinished(t));
    }
    final open = tickets.fold<int>(0, (s, t) => s + t.items.length);
    if (newcomers.isNotEmpty && _voiceOn) {
      unawaited(PosQrOrderVoiceAlert.instance.speak(
        _kdsSpeakPhrase(newcomers, fresh: true),
      ));
    } else if (pingNew && open > _lastOpenCount) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    setState(() {
      _tickets = tickets;
      _lastOpenCount = open;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _setLines(List<String> ids, String status) async {
    if (ids.isEmpty || _busy) return;
    final snapshot = status == 'done' ? _hitsForIds(ids) : const <_KdsHit>[];
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final res = ids.length == 1
        ? await _api.setPosKdsLinePrep(ids.first, status)
        : await _api.setPosKdsLinesPrep(ids, status);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'KDS',
        message: res['message']?.toString() ?? 'Không cập nhật được',
      );
      return;
    }
    await _loadTickets(silent: true);
    if (status == 'done') {
      unawaited(_printReadyHits(snapshot));
    }
  }

  Future<void> _setLine(_KdsItem item, String status) =>
      _setLines([item.id], status);

  Future<void> _bump(_KdsTicket t) async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final res = await _api.bumpPosKdsTicket(t.orderId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'KDS',
        message: res['message']?.toString() ?? 'Không bump được',
      );
      return;
    }
    _lastBumpedOrderId = t.orderId;
    final hits = [for (final i in t.items) _KdsHit(ticket: t, item: i)];
    await _loadTickets(silent: true);
    unawaited(_printReadyHits(hits));
  }

  Future<void> _recall() async {
    final id = _lastBumpedOrderId;
    if (id == null || _busy) return;
    final res = await _api.recallPosKdsTicket(id);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Gọi lại',
        message: res['message']?.toString() ?? 'Không gọi lại được',
      );
      return;
    }
    await _loadTickets(silent: true);
  }

  List<_KdsAgg> get _aggregates {
    final map = <String, _KdsAgg>{};
    for (final t in _tickets) {
      for (final i in t.items) {
        if (i.status == 'done') continue;
        final key = i.productName.trim().toLowerCase();
        if (key.isEmpty) continue;
        final sent = i.sentAt ?? t.sentAt;
        final hit = _KdsHit(ticket: t, item: i);
        final cur = map[key];
        if (cur == null) {
          map[key] = _KdsAgg(
            name: i.productName,
            qty: i.qty,
            oldest: sent,
            hottest: i.status,
            hits: [hit],
          );
        } else {
          cur.qty += i.qty;
          cur.hits.add(hit);
          if (sent.isBefore(cur.oldest)) cur.oldest = sent;
          cur.hottest = _hotter(cur.hottest, i.status);
        }
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => a.oldest.compareTo(b.oldest));
    return list;
  }

  String _hotter(String a, String b) {
    int rank(String s) => switch (s) {
          'ready' => 3,
          'cooking' => 2,
          _ => 1,
        };
    return rank(b) > rank(a) ? b : a;
  }

  Duration _waitAt(DateTime sent, DateTime now) {
    var d = now.toUtc().difference(sent.toUtc());
    if (d.isNegative) return Duration.zero;
    return d;
  }

  String _waitShortAt(DateTime sent, DateTime now) {
    final d = _waitAt(sent, now);
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}p';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  Color _waitColor(DateTime sent, {String? status}) {
    if (status == 'ready') return _ready;
    if (status == 'cooking') return _cooking;
    final mins = _waitAt(sent, DateTime.now()).inMinutes;
    if (mins >= 10) return _late;
    if (mins >= 5) return const Color(0xFFEAB308);
    return _queued;
  }

  int get _itemCount =>
      _tickets.fold(0, (s, t) => s + t.items.fold(0, (a, i) => a + i.qty.round()));

  int get _lateCount {
    var n = 0;
    for (final t in _tickets) {
      for (final i in t.items) {
        if (_waitAt(i.sentAt ?? t.sentAt, DateTime.now()).inMinutes >= 10) n++;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final pushed = PosHubScope.pushedSubPageOf(context);
    final aggs = _aggregates;
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(pushed, aggs),
          _buildStations(),
          Expanded(child: _buildBody(aggs)),
        ],
      ),
    );
  }

  Widget _buildHeader(bool pushed, List<_KdsAgg> aggs) {
    final lateN = _lateCount;
    return Material(
      color: _bar,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              if (pushed)
                IconButton(
                  tooltip: tr('Quay lại'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              const Icon(Icons.soup_kitchen_outlined,
                  color: Color(0xFFFF8A3D), size: 26),
              const SizedBox(width: 8),
              Text(
                tr('BẾP'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _statPill('${_itemCount} ${tr('món')}', Colors.white),
                      const SizedBox(width: 6),
                      _statPill('${_tickets.length} ${tr('bàn')}',
                          const Color(0xFF93C5FD)),
                      if (aggs.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _statPill('${aggs.length} ${tr('loại')}',
                            const Color(0xFFC4B5FD)),
                      ],
                      if (lateN > 0) ...[
                        const SizedBox(width: 6),
                        _statPill('${lateN} ${tr('trễ')}', _late),
                      ],
                      const SizedBox(width: 12),
                      _viewToggle(),
                      const SizedBox(width: 10),
                      _KdsTickText(
                        tick: _nowTick,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        builder: (now) => _clockFmt.format(now),
                      ),
                    ],
                  ),
                ),
              ),
              if (_lastBumpedOrderId != null)
                TextButton(
                  onPressed: _recall,
                  child: Text(tr('Gọi lại'),
                      style: const TextStyle(color: Colors.white)),
                ),
              IconButton(
                tooltip: tr('Đọc món cần chế biến'),
                onPressed: _speakPending,
                icon: Icon(
                  _voiceOn ? Icons.volume_up : Icons.volume_off,
                  color: _voiceOn ? _queued : Colors.white54,
                ),
              ),
              IconButton(
                tooltip: tr('Giọng và tốc độ đọc'),
                onPressed: () => unawaited(
                  PosQrOrderVoiceAlert.instance.showSettingsSheet(context),
                ),
                icon: const Icon(Icons.tune, color: Colors.white70),
              ),
              IconButton(
                tooltip: tr('Máy in KDS'),
                onPressed: _openKdsPrintSettings,
                icon: Icon(
                  _printOnDone ? Icons.print : Icons.print_disabled,
                  color: _printOnDone ? _ready : Colors.white54,
                ),
              ),
              IconButton(
                tooltip: tr('Tải lại'),
                onPressed: _loading ? null : () => _loadTickets(),
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white70),
                      )
                    : const Icon(Icons.refresh, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill(String text, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _viewToggle() {
    Widget tab(String label, _KdsView v) {
      final on = _view == v;
      return InkWell(
        onTap: () => setState(() => _view = v),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? _bg : Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2438),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab(tr('Gộp món'), _KdsView.dish),
          tab(tr('Theo bàn'), _KdsView.table),
        ],
      ),
    );
  }

  Widget _buildStations() {
    final chips = <Widget>[
      _stationChip(null, tr('Tất cả')),
      for (final s in _stations) _stationChip(s.id, s.name),
      const SizedBox(width: 10),
      _filterChip(
        _newestFirst ? tr('Mới nhất') : tr('Lâu nhất'),
        !_newestFirst,
        () {
          setState(() => _newestFirst = !_newestFirst);
          unawaited(_saveKdsPrintPrefs());
          unawaited(_loadTickets(silent: true));
        },
      ),
      _filterChip(
        tr('Chưa có món xong'),
        _onlyUnfinished,
        () {
          setState(() => _onlyUnfinished = !_onlyUnfinished);
          unawaited(_saveKdsPrintPrefs());
          unawaited(_loadTickets(silent: true));
        },
      ),
      _filterChip(
        tr('Đọc món'),
        _voiceOn,
        _toggleVoice,
      ),
    ];
    return Material(
      color: _bar,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Row(children: chips),
      ),
    );
  }

  Widget _stationChip(String? id, String label) {
    final on = _stationId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? const Color(0xFF2563EB) : const Color(0xFF1B2438),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() {
              _stationId = id;
              _voiceSeeded = false;
              _seenQty.clear();
            });
            unawaited(_loadTickets());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                color: on ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool on, VoidCallback tap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? const Color(0xFF334155) : const Color(0xFF1B2438),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                color: on ? Colors.white : Colors.white54,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openKdsPrintSettings() async {
    if (_kdsPrinters.isEmpty) await _loadKdsPrintPrefs();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('Máy in KDS'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Đọc món cần chế biến'),
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      tr('Tự đọc món mới. Chạm loa trên cột Đang làm / Xong để đọc lại. Nút chỉnh giọng để chọn giọng mượt và tốc độ.'),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    value: _voiceOn,
                    onChanged: (v) {
                      setLocal(() => _voiceOn = v);
                      setState(() => _voiceOn = v);
                      unawaited(_saveKdsPrintPrefs());
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(
                          PosQrOrderVoiceAlert.instance.showSettingsSheet(context),
                        );
                      },
                      icon: const Icon(Icons.tune, color: Color(0xFFFF8A3D)),
                      label: Text(tr('Chọn giọng và tốc độ'),
                          style: const TextStyle(color: Color(0xFFFF8A3D))),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('In phiếu khi món xong'),
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      tr('Tên món, bàn, khu, giờ gọi, giờ ra món'),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    value: _printOnDone,
                    onChanged: (v) {
                      setLocal(() => _printOnDone = v);
                      setState(() => _printOnDone = v);
                      unawaited(_saveKdsPrintPrefs());
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(tr('Kết nối máy in'),
                      style: const TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (_kdsPrinters.isEmpty)
                    Text(tr('Chưa có máy in cửa hàng — thêm ở Máy in (thiết bị)'),
                        style: const TextStyle(color: Colors.white38))
                  else
                    DropdownButtonFormField<String>(
                      value: _kdsPrinters.any((p) => p.id == _kdsPrinterId)
                          ? _kdsPrinterId
                          : _kdsPrinters.first.id,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color(0xFF1B2438),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in _kdsPrinters)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name,
                                style: const TextStyle(color: Colors.white)),
                          ),
                      ],
                      onChanged: (v) {
                        setLocal(() => _kdsPrinterId = v);
                        setState(() => _kdsPrinterId = v);
                        unawaited(_saveKdsPrintPrefs());
                      },
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildBody(List<_KdsAgg> aggs) {
    if (_loading && _tickets.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: const TextStyle(color: Colors.redAccent)));
    }
    if (_tickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_outlined,
                size: 56, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              tr('Chưa có món báo bếp'),
              style: const TextStyle(color: Colors.white54, fontSize: 18),
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        _view == _KdsView.dish ? _buildDishGrid(aggs) : _buildTableGrid(),
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }

  Widget _buildDishGrid(List<_KdsAgg> aggs) {
    return LayoutBuilder(builder: (context, c) {
      final n = (c.maxWidth / 340).floor().clamp(1, 6);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: n,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          mainAxisExtent: 100,
        ),
        itemCount: aggs.length,
        itemBuilder: (_, i) => _dishCard(aggs[i]),
      );
    });
  }

  Widget _dishCard(_KdsAgg a) {
    final c = _waitColor(a.oldest, status: a.hottest);
    final tables = a.tableLabels;
    final ids = a.hits.map((h) => h.item.id).toList();
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openAggSheet(a),
        child: Row(
          children: [
            Container(width: 5, color: c),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _qtyFmt.format(a.qty),
                          style: TextStyle(
                            color: c,
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                            height: 1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            a.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _KdsTickText(
                          tick: _nowTick,
                          style: TextStyle(
                            color: c,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          builder: (now) => _waitShortAt(a.oldest, now),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tables.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ),
                        Text(
                          a.statusSummary(tr),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 84,
              child: Column(
                children: [
                  _speakIconBtn(
                    tooltip: tr('Đọc nhóm này'),
                    onTap: () => _speakAgg(a),
                  ),
                  Expanded(
                    child: _sideBtn(
                      tr('Đang làm'),
                      _cooking,
                      () => _setLines(ids, 'cooking'),
                    ),
                  ),
                  Container(height: 1, color: _line),
                  Expanded(
                    child: _sideBtn(
                      tr('Xong'),
                      _ready,
                      () => _setLines(ids, 'done'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speakIconBtn(
      {required String tooltip, required VoidCallback onTap}) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(
        Icons.volume_up,
        size: 20,
        color: _voiceOn ? _queued : Colors.white54,
      ),
    );
  }

  Widget _sideBtn(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: _busy ? null : onTap,
      child: ColoredBox(
        color: color.withOpacity(0.12),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  void _openAggSheet(_KdsAgg a) {
    final ids = a.hits.map((h) => h.item.id).toList();
    if (_voiceOn) _speakAgg(a);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101827),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final c = _waitColor(a.oldest, status: a.hottest);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      _qtyFmt.format(a.qty),
                      style: TextStyle(
                        color: c,
                        fontWeight: FontWeight.w900,
                        fontSize: 36,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                          _KdsTickText(
                            tick: _nowTick,
                            style: TextStyle(color: c, fontWeight: FontWeight.w700),
                            builder: (now) =>
                                '${tr('Chờ')} ${_waitShortAt(a.oldest, now)} · ${a.statusSummary(tr)}',
                          ),
                        ],
                      ),
                    ),
                    _speakIconBtn(
                      tooltip: tr('Đọc nhóm này'),
                      onTap: () => _speakAgg(a),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          unawaited(_setLines(ids, 'cooking'));
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _cooking,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(tr('Đang làm tất cả'),
                            style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          unawaited(_setLines(ids, 'done'));
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _ready,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(tr('Xong tất cả'),
                            style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(tr('Theo bàn'),
                    style: const TextStyle(
                        color: Colors.white54, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: a.hits.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFF243049)),
                    itemBuilder: (_, i) {
                      final h = a.hits[i];
                      final sent = h.item.sentAt ?? h.ticket.sentAt;
                      final hc = _waitColor(sent, status: h.item.status);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${_qtyFmt.format(h.item.qty)}×  ${h.ticket.title}',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        subtitle: _KdsTickText(
                          tick: _nowTick,
                          style: TextStyle(color: hc),
                          builder: (now) => [
                            _waitShortAt(sent, now),
                            _statusLabel(h.item.status),
                            if ((h.item.note ?? '').isNotEmpty) h.item.note!,
                          ].join(' · '),
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            _miniAct(tr('Làm'), _cooking,
                                () => _setLine(h.item, 'cooking')),
                            _miniAct(tr('Xong'), _ready,
                                () => _setLine(h.item, 'done')),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _miniAct(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _buildTableGrid() {
    return LayoutBuilder(builder: (context, c) {
      final n = (c.maxWidth / 280).floor().clamp(1, 6);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: n,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          mainAxisExtent: 168,
        ),
        itemCount: _tickets.length,
        itemBuilder: (_, i) => _ticketCard(_tickets[i]),
      );
    });
  }

  Widget _ticketCard(_KdsTicket t) {
    final oldest = t.oldest;
    final color = _waitColor(oldest, status: t.status);
    final extra = t.items.length > 5 ? t.items.length - 5 : 0;
    final shown = extra > 0 ? t.items.take(5).toList() : t.items;
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(width: 5, color: color),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: color.withOpacity(0.16),
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      _KdsTickText(
                        tick: _nowTick,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        builder: (now) => _waitShortAt(oldest, now),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    children: [
                      for (final item in shown) _itemRow(item, t),
                      if (extra > 0)
                        Text('+ $extra',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 84,
            child: Column(
              children: [
                _speakIconBtn(
                  tooltip: tr('Đọc bàn này'),
                  onTap: () => _speakTicket(t),
                ),
                Expanded(
                  child: _sideBtn(
                    tr('Đang làm'),
                    _cooking,
                    () => _setTicketCooking(t),
                  ),
                ),
                Container(height: 1, color: _line),
                Expanded(
                  child: _sideBtn(
                    tr('Xong'),
                    _ready,
                    () => _bump(t),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(_KdsItem item, _KdsTicket ticket) {
    final sent = item.sentAt ?? ticket.sentAt;
    final c = _waitColor(sent, status: item.status);
    return InkWell(
      onTap: () {
        final next = switch (item.status) {
          'queued' => 'cooking',
          'cooking' => 'ready',
          'ready' => 'done',
          _ => 'cooking',
        };
        unawaited(_setLine(item, next));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                _qtyFmt.format(item.qty),
                style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            Expanded(
              child: Text(
                item.productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            _KdsTickText(
              tick: _nowTick,
              style: TextStyle(
                color: c,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              builder: (now) => _waitShortAt(sent, now),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String s) => switch (s) {
        'cooking' => tr('Làm'),
        'ready' => tr('Xong'),
        'done' => tr('Bump'),
        _ => tr('Mới'),
      };
}

class _KdsTickText extends StatelessWidget {
  const _KdsTickText({
    required this.tick,
    required this.builder,
    this.style,
  });
  final ValueListenable<DateTime> tick;
  final String Function(DateTime now) builder;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: tick,
      builder: (_, now, __) => Text(builder(now), style: style),
    );
  }
}

class _KdsHit {
  const _KdsHit({required this.ticket, required this.item});
  final _KdsTicket ticket;
  final _KdsItem item;
}

class _KdsAgg {
  _KdsAgg({
    required this.name,
    required this.qty,
    required this.oldest,
    required this.hottest,
    required this.hits,
  });
  final String name;
  double qty;
  DateTime oldest;
  String hottest;
  final List<_KdsHit> hits;

  List<String> get tableLabels {
    final seen = <String>{};
    final out = <String>[];
    for (final h in hits) {
      final n = h.ticket.shortTable;
      if (seen.add(n)) out.add(n);
    }
    return out;
  }

  int get queued => hits.where((h) => h.item.status == 'queued').length;
  int get cooking => hits.where((h) => h.item.status == 'cooking').length;
  int get ready => hits.where((h) => h.item.status == 'ready').length;

  String statusSummary(String Function(String) t) {
    final parts = <String>[];
    if (queued > 0) parts.add('$queued ${t('mới')}');
    if (cooking > 0) parts.add('$cooking ${t('làm')}');
    if (ready > 0) parts.add('$ready ${t('xong')}');
    return parts.join(' · ');
  }
}

class _KdsStation {
  const _KdsStation({
    required this.id,
    required this.name,
    this.printerIds = const [],
  });
  final String id;
  final String name;
  final List<String> printerIds;

  _KdsStation merge(_KdsStation other) {
    final ids = {...printerIds, other.id, ...other.printerIds}.toList();
    return _KdsStation(id: id, name: name, printerIds: ids);
  }

  factory _KdsStation.fromJson(Map<String, dynamic> j) {
    final ids = <String>[];
    final raw = j['printerIds'] ?? j['PrinterIds'];
    if (raw is List) {
      for (final e in raw) {
        final s = e.toString();
        if (s.isNotEmpty) ids.add(s);
      }
    }
    final id = (j['id'] ?? j['Id'] ?? '').toString();
    if (id.isNotEmpty && !ids.contains(id)) ids.insert(0, id);
    return _KdsStation(
      id: id,
      name: (j['name'] ?? j['Name'] ?? '').toString(),
      printerIds: ids,
    );
  }
}

class _KdsTicket {
  const _KdsTicket({
    required this.orderId,
    required this.sentAt,
    required this.status,
    required this.items,
    this.orderNo,
    this.tableName,
    this.areaName,
    this.channel,
  });

  final String orderId;
  final String? orderNo;
  final String? tableName;
  final String? areaName;
  final String? channel;
  final DateTime sentAt;
  final String status;
  final List<_KdsItem> items;

  String get title {
    final table = (tableName ?? '').trim();
    final area = (areaName ?? '').trim();
    if (table.isEmpty) return orderNo ?? 'Đơn';
    return area.isEmpty ? table : '$area · $table';
  }

  String get shortTable {
    final table = (tableName ?? '').trim();
    if (table.isNotEmpty) return table;
    return orderNo ?? '?';
  }

  DateTime get oldest => items
      .map((i) => i.sentAt ?? sentAt)
      .fold<DateTime>(sentAt, (a, b) => a.isBefore(b) ? a : b);

  factory _KdsTicket.fromJson(Map<String, dynamic> j) {
    final items = <_KdsItem>[];
    final raw = j['items'] ?? j['Items'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) items.add(_KdsItem.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return _KdsTicket(
      orderId: (j['orderId'] ?? j['OrderId'] ?? '').toString(),
      orderNo: (j['orderNo'] ?? j['OrderNo'])?.toString(),
      tableName: (j['tableName'] ?? j['TableName'])?.toString(),
      areaName: (j['areaName'] ?? j['AreaName'])?.toString(),
      channel: (j['channel'] ?? j['Channel'])?.toString(),
      sentAt: _parseUtc(j['sentAt'] ?? j['SentAt']),
      status: (j['status'] ?? j['Status'] ?? 'queued').toString(),
      items: items,
    );
  }
}

class _KdsItem {
  const _KdsItem({
    required this.id,
    required this.productName,
    required this.qty,
    required this.status,
    this.note,
    this.sentAt,
  });
  final String id;
  final String productName;
  final double qty;
  final String status;
  final String? note;
  final DateTime? sentAt;

  factory _KdsItem.fromJson(Map<String, dynamic> j) {
    final q = j['qty'] ?? j['Qty'] ?? 0;
    final sentRaw = j['sentAt'] ?? j['SentAt'];
    return _KdsItem(
      id: (j['id'] ?? j['Id'] ?? '').toString(),
      productName: (j['productName'] ?? j['ProductName'] ?? '').toString(),
      qty: q is num ? q.toDouble() : double.tryParse('$q') ?? 0,
      status: (j['status'] ?? j['Status'] ?? 'queued').toString(),
      note: (j['note'] ?? j['Note'])?.toString(),
      sentAt: sentRaw == null ? null : _parseUtc(sentRaw),
    );
  }
}

DateTime _parseUtc(dynamic raw) {
  if (raw == null) return DateTime.now().toUtc();
  final t = DateTime.tryParse(raw.toString());
  if (t == null) return DateTime.now().toUtc();
  if (t.isUtc) return t;
  return DateTime.utc(
    t.year,
    t.month,
    t.day,
    t.hour,
    t.minute,
    t.second,
    t.millisecond,
  );
}
