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
import '../../utils/navigation_notifier.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../settings_hub_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// KDS bếp: món mới = chờ làm. Đang làm → Làm xong (in + rời bảng). Hủy: Đồng ý từng món.
class PosKdsScreen extends StatefulWidget {
  const PosKdsScreen({super.key});

  @override
  State<PosKdsScreen> createState() => _PosKdsScreenState();
}

enum _KdsView { dish, table }

class _KdsTone {
  const _KdsTone(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

class _PosKdsScreenState extends State<PosKdsScreen> {
  static const _bg = Color(0xFF070B14);
  static const _bar = Color(0xFF0C1222);
  static const _card = Color(0xFF141C2E);
  static const _line = Color(0xFF243049);
  static const _queued = Color(0xFFFBBF24);
  static const _cooking = Color(0xFF2563EB);
  static const _ready = Color(0xFF059669);
  static const _late = Color(0xFFBE123C);
  static const _voided = Color(0xFFDC2626);
  static const _inkOnLight = Color(0xFF1A1200);

  final _api = ApiService();
  final _floor = PosFloorRealtimeSubscription(
    debounce: const Duration(milliseconds: 250),
  );
  final _qtyFmt = NumberFormat('#,##0.###', 'vi_VN');
  final _clockFmt = DateFormat('HH:mm:ss');

  bool _loading = true;
  bool _busy = false;
  bool _ticketsLoading = false;
  bool _ticketsReloadQueued = false;
  bool _ticketsReloadPing = false;
  String? _ticketsReloadVoidMessage;
  DateTime? _lastSpeakTap;
  String? _error;
  String? _stationId;
  _KdsView _view = _KdsView.dish;
  bool _newestFirst = false;
  bool _onlyUnfinished = false;
  bool _printOnDone = false;
  bool _voiceOn = true;
  bool _voiceSeeded = false;
  bool _voidSeeded = false;
  /// SL đã đọc theo line id — chỉ tăng, không xóa khi API nháy thiếu (tránh đọc lại cả bàn).
  final Map<String, double> _announcedMaxQty = {};
  final Set<String> _announcedVoidIds = {};
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
    unawaited(PosQrOrderVoiceAlert.instance.warmUp());
    unawaited(_bootstrap());
    _floor.start((event) {
      if (!mounted) return;
      final reason =
          (event['reason'] ?? event['Reason'] ?? '').toString().toLowerCase();
      final msg = (event['message'] ?? event['Message'])?.toString();
      unawaited(_loadTickets(
        silent: true,
        pingNew: _kdsShouldAnnounce(event),
        voidMessage: reason == 'kitchenvoid' ? msg : null,
      ));
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
    unawaited(PosQrOrderVoiceAlert.instance.stopSpeaking());
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
    // Gom theo bàn/đơn → 1 phiếu trả món (tiết kiệm giấy).
    final groups = <String, List<_KdsHit>>{};
    for (final h in hits) {
      final key = '${h.ticket.orderId}|${h.ticket.shortTable}';
      groups.putIfAbsent(key, () => []).add(h);
    }
    for (final group in groups.values) {
      final first = group.first;
      unawaited(PosPrintOrchestrator.instance.dispatchKdsReadySlip(
        printer: printer,
        tableName: first.ticket.shortTable,
        areaName: first.ticket.areaName,
        orderNo: first.ticket.orderNo,
        readyAt: now,
        lines: [
          for (final h in group)
            (
              productName: h.item.productName,
              qty: h.item.qty,
              calledAt: h.item.sentAt ?? h.ticket.sentAt,
            ),
        ],
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

  bool _isVoided(_KdsItem i) => i.status == 'voided';

  bool _needsPrep(_KdsItem i) =>
      i.status != 'ready' && i.status != 'done' && i.status != 'voided';

  /// Loa khi món mới báo bếp hoặc khi hủy món đã báo.
  bool _kdsShouldAnnounce(Map<String, dynamic> event) {
    final reason =
        (event['reason'] ?? event['Reason'] ?? '').toString().toLowerCase();
    return reason == 'kitchensend' ||
        reason == 'qrorder' ||
        reason == 'kitchenvoid';
  }

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

    // Gộp theo SP + topping + đơn — không theo Id dòng (autosave tạo Guid mới).
    final qtyByKey = <String, double>{};
    final hitByKey = <String, _KdsHit>{};
    for (final h in prep) {
      final key = _announceKey(h);
      if (key.isEmpty) continue;
      final sent = h.item.sentQty > 0 ? h.item.sentQty : h.item.qty;
      qtyByKey[key] = (qtyByKey[key] ?? 0) + sent;
      hitByKey[key] = h;
    }

    final newcomers = <_KdsHit>[];
    for (final e in qtyByKey.entries) {
      final prev = _announcedMaxQty[e.key] ?? 0;
      if (!first && e.value > prev + 0.0001) {
        final h = hitByKey[e.key]!;
        newcomers.add(_KdsHit(
          ticket: h.ticket,
          item: h.item,
          speakQty: e.value - prev,
        ));
      }
      if (e.value > prev) _announcedMaxQty[e.key] = e.value;
    }
    // Hủy món đã báo bếp: hạ mốc để lần báo mới sau này vẫn đọc loa.
    for (final key in _announcedMaxQty.keys.toList()) {
      final nowQty = qtyByKey[key];
      if (nowQty == null) {
        _announcedMaxQty.remove(key);
      } else if (nowQty < _announcedMaxQty[key]!) {
        _announcedMaxQty[key] = nowQty;
      }
    }
    if (first) return const [];
    return newcomers;
  }

  List<_KdsHit> _collectNewVoidHits(List<_KdsTicket> tickets) {
    final first = !_voidSeeded;
    _voidSeeded = true;
    final newcomers = <_KdsHit>[];
    for (final t in tickets) {
      for (final i in t.items) {
        if (!_isVoided(i) || i.id.isEmpty) continue;
        if (_announcedVoidIds.contains(i.id)) continue;
        _announcedVoidIds.add(i.id);
        if (!first) newcomers.add(_KdsHit(ticket: t, item: i));
      }
    }
    return newcomers;
  }

  String _announceKey(_KdsHit h) {
    final pid = h.item.productId.trim();
    final name = h.item.productName.trim().toLowerCase();
    final note = (h.item.note ?? '').trim().toLowerCase();
    final id = pid.isNotEmpty ? pid : name;
    if (id.isEmpty) return '';
    return '${h.ticket.orderId}|$id|$note';
  }

  String _qtyWords(double q) {
    if (q == q.roundToDouble()) return '${q.round()}';
    return _qtyFmt.format(q);
  }

  /// Bỏ tiền tố trùng «Bàn/Ban» để không đọc «bàn bàn 05».
  String _speakTableCore(String raw) {
    var t = raw.trim();
    t = t.replaceFirst(RegExp(r'^(bàn|ban)\s*', caseSensitive: false), '');
    t = t.trim();
    return t.isEmpty ? raw.trim() : t;
  }

  /// Bỏ tiền tố trùng «Khu / Khu vực».
  String _speakAreaCore(String raw) {
    var t = raw.trim();
    t = t.replaceFirst(
        RegExp(r'^(khu\s*vực|khu\s*vuc|khu)\s*', caseSensitive: false), '');
    t = t.trim();
    return t.isEmpty ? raw.trim() : t;
  }

  String _tablePlaceSpeak(_KdsTicket t) {
    final table = _speakTableCore(t.shortTable);
    final area = (t.areaName ?? '').trim();
    if (area.isEmpty) return 'bàn $table';
    return 'bàn $table - Khu ${_speakAreaCore(area)}';
  }

  /// Sau SL món: «thêm topping A số lượng 1, B số lượng 1. Khách hàng báo: …».
  String _extrasSpeak(String? note) {
    final raw = (note ?? '').trim();
    if (raw.isEmpty) return '';
    final tops = <String>[];
    final notes = <String>[];
    for (final line in raw
        .split(RegExp(r'[\n\r]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)) {
      if (line.startsWith('+')) {
        var t = line.replaceFirst(RegExp(r'^\+\s*'), '').trim();
        t = t.replaceFirst(
          RegExp(r'^(topping|thêm topping)\s*[:\-–]?\s*', caseSensitive: false),
          '',
        );
        final m = RegExp(
          r'^(.*?)(?:\s*[x×]\s*(\d+(?:[.,]\d+)?))\s*$',
          caseSensitive: false,
        ).firstMatch(t);
        final name = ((m?.group(1) ?? t)).trim();
        if (name.isEmpty) continue;
        final qRaw = (m?.group(2) ?? '1').replaceAll(',', '.');
        final q = double.tryParse(qRaw) ?? 1;
        tops.add('$name số lượng ${_qtyWords(q)}');
      } else {
        var n = line.replaceFirst(
          RegExp(r'^(khách hàng báo|ghi chú)\s*[:\-–]?\s*', caseSensitive: false),
          '',
        );
        if (n.isNotEmpty) notes.add(n);
      }
    }
    final parts = <String>[];
    if (tops.isNotEmpty) parts.add('thêm topping ${tops.join(', ')}');
    if (notes.isNotEmpty) parts.add('Khách hàng báo: ${notes.join(', ')}');
    return parts.join('. ');
  }

  /// Tên món → số lượng → topping → ghi chú khách.
  String _itemSpeak(_KdsHit h) {
    final qty = h.speakQty ?? h.item.qty;
    var s = '${h.item.productName.trim()}, số lượng ${_qtyWords(qty)}';
    final extras = _extrasSpeak(h.item.note);
    if (extras.isNotEmpty) s += '. $extras';
    return s;
  }

  /// [fresh]=true → món mới; false → đọc lại. [fullTable]=true không cắt số món.
  List<String> _kdsSpeakChunks(
    List<_KdsHit> hits, {
    required bool fresh,
    bool fullTable = false,
  }) {
    if (hits.isEmpty) return const [];
    final byTicket = <String, List<_KdsHit>>{};
    for (final h in hits) {
      byTicket.putIfAbsent(h.ticket.orderId, () => []).add(h);
    }
    final chunks = <String>[];
    var extraTables = 0;
    var extraItems = 0;
    var tables = 0;
    var items = 0;
    const maxTables = 4;
    const maxItems = 12;
    for (final group in byTicket.values) {
      if (!fullTable && tables >= maxTables) {
        extraTables++;
        extraItems += group.length;
        continue;
      }
      tables++;
      final t = group.first.ticket;
      chunks.add(fresh
          ? 'Món mới ${_tablePlaceSpeak(t)}'
          : 'Đọc lại ${_tablePlaceSpeak(t)}');
      for (var i = 0; i < group.length; i++) {
        if (!fullTable && items >= maxItems) {
          extraItems += group.length - i;
          break;
        }
        items++;
        chunks.add(_itemSpeak(group[i]));
      }
    }
    if (extraTables > 0) {
      chunks.add('còn $extraTables bàn khác');
    } else if (extraItems > 0) {
      chunks.add('còn $extraItems món khác');
    }
    return chunks;
  }

  /// VD: «Thông báo hủy 1 món Bàn 03 Khoai tây chiên».
  List<String> _voidSpeakChunks(List<_KdsHit> hits) {
    final out = <String>[];
    for (final h in hits) {
      final table = h.ticket.shortTable.trim();
      final name = h.item.productName.trim();
      if (name.isEmpty) continue;
      final place = table.isEmpty ? '' : ' $table';
      out.add('Thông báo hủy ${_qtyWords(h.item.qty)} món$place $name');
    }
    return out;
  }

  void _speakHits(List<_KdsHit> hits, {String? empty}) {
    final prep = hits.where((h) => _needsPrep(h.item)).toList();
    if (prep.isEmpty) {
      unawaited(PosQrOrderVoiceAlert.instance
          .speak(empty ?? 'Không còn món cần chế biến'));
      return;
    }
    unawaited(PosQrOrderVoiceAlert.instance.speakSequence(
      _kdsSpeakChunks(prep, fresh: false),
    ));
  }

  void _speakAgg(_KdsAgg a) {
    final voids = a.hits.where((h) => _isVoided(h.item)).toList();
    if (voids.isNotEmpty && voids.length == a.hits.length) {
      unawaited(PosQrOrderVoiceAlert.instance.speakSequence(
        _voidSpeakChunks(voids),
      ));
      return;
    }
    final prep = a.hits.where((h) => _needsPrep(h.item)).toList();
    if (prep.isEmpty) {
      unawaited(PosQrOrderVoiceAlert.instance
          .speak('Không còn ${a.name} cần chế biến'));
      return;
    }
    final qty = prep.fold<double>(0, (s, h) => s + h.item.qty);
    // Tên → số lượng.
    unawaited(PosQrOrderVoiceAlert.instance.speak(
      '${a.name}, số lượng ${_qtyWords(qty)}',
    ));
  }

  void _speakTicket(_KdsTicket t) {
    final voids = [
      for (final i in t.items)
        if (_isVoided(i)) _KdsHit(ticket: t, item: i),
    ];
    final live = [
      for (final i in t.items)
        if (!_isVoided(i)) _KdsHit(ticket: t, item: i),
    ];
    if (live.isEmpty && voids.isEmpty) {
      unawaited(PosQrOrderVoiceAlert.instance.speak(
        'Đọc lại ${_tablePlaceSpeak(t)}. Không còn món cần chế biến',
      ));
      return;
    }
    unawaited(PosQrOrderVoiceAlert.instance.speakSequence([
      ..._voidSpeakChunks(voids),
      if (live.isNotEmpty)
        ..._kdsSpeakChunks(live, fresh: false, fullTable: true),
    ]));
  }

  Future<void> _speakPending() async {
    final now = DateTime.now();
    if (_lastSpeakTap != null &&
        now.difference(_lastSpeakTap!) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastSpeakTap = now;
    final prep = _prepHitsOf(_tickets).where((h) => _needsPrep(h.item)).toList();
    if (prep.isEmpty) {
      unawaited(PosQrOrderVoiceAlert.instance
          .speak('Không còn món cần chế biến'));
      return;
    }
    // Nút loa: ưu tiên tóm tắt ngắn — không đọc cả hàng đợi.
    if (prep.length > 8) {
      final tables = <String>{};
      for (final h in prep) {
        tables.add(h.ticket.shortTable);
      }
      unawaited(PosQrOrderVoiceAlert.instance.speak(
        'Có ${prep.length} món cần chế biến trên ${tables.length} bàn',
      ));
      return;
    }
    _speakHits(prep);
  }

  Future<void> _setTicketCooking(_KdsTicket t) async {
    final ids = [
      for (final i in t.items)
        if (i.status == 'queued') i.id,
    ];
    if (ids.isEmpty) return;
    await _setLines(ids, 'cooking');
  }

  Future<void> _setTicketDone(_KdsTicket t) async {
    final ids = [
      for (final i in t.items)
        if (!_isVoided(i) && i.status != 'done') i.id,
    ];
    if (ids.isEmpty) return;
    await _setLines(ids, 'done');
    _lastBumpedOrderId = t.orderId;
  }

  List<String> _hitIds(Iterable<_KdsHit> hits, bool Function(_KdsItem) where) =>
      [for (final h in hits) if (where(h.item)) h.item.id];

  Future<void> _aggCook(_KdsAgg a) async {
    final ids = _hitIds(a.hits, (i) => i.status == 'queued');
    if (ids.isEmpty) return;
    await _setLines(ids, 'cooking');
  }

  Future<void> _aggDone(_KdsAgg a) async {
    final ids = _hitIds(
      a.hits,
      (i) => !_isVoided(i) && i.status != 'done',
    );
    if (ids.isEmpty) return;
    await _setLines(ids, 'done');
  }

  Color _aggAccent(_KdsAgg a) {
    if (a.hits.every((h) => _isVoided(h.item))) return _voided;
    if (a.hits.any((h) => h.item.status == 'queued')) {
      return _waitColor(a.oldest, status: 'queued');
    }
    if (a.hits.any((h) => h.item.status == 'cooking')) return _cooking;
    if (a.hits.any((h) => h.item.status == 'ready')) return _ready;
    return _voided;
  }

  Widget _statusPillsFromHits(List<_KdsHit> hits) {
    double qtyOf(String status) => hits
        .where((h) => h.item.status == status)
        .fold(0.0, (s, h) => s + h.item.qty);
    Widget pill(double qty, String label, Color bg, Color fg) {
      if (qty <= 0) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(right: 4, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${_qtyFmt.format(qty)} $label',
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      );
    }

    return Wrap(
      children: [
        pill(qtyOf('queued'), tr('chờ'), _queued, _inkOnLight),
        pill(qtyOf('cooking'), tr('làm'), _cooking, Colors.white),
        pill(qtyOf('ready'), tr('xong'), _ready, Colors.white),
        pill(qtyOf('voided'), tr('hủy'), _voided, Colors.white),
      ],
    );
  }

  void _toggleVoice() {
    setState(() => _voiceOn = !_voiceOn);
    unawaited(_saveKdsPrintPrefs());
    if (_voiceOn) {
      final n = _prepHitsOf(_tickets).where((h) => _needsPrep(h.item)).length;
      unawaited(PosQrOrderVoiceAlert.instance.speak(
        n == 0
            ? 'Đã bật loa bếp'
            : 'Đã bật loa. Có $n món cần chế biến',
      ));
    }
  }

  Future<void> _loadTickets({
    bool silent = false,
    bool pingNew = false,
    String? voidMessage,
  }) async {
    if (_ticketsLoading) {
      _ticketsReloadQueued = true;
      _ticketsReloadPing = _ticketsReloadPing || pingNew;
      if ((voidMessage ?? '').trim().isNotEmpty) {
        _ticketsReloadVoidMessage = voidMessage;
      }
      return;
    }
    _ticketsLoading = true;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
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
    final voidHits = _collectNewVoidHits(tickets);
    if (_onlyUnfinished) {
      tickets.removeWhere((t) => !_ticketUnfinished(t));
    }
    final open = tickets.fold<int>(
        0,
        (s, t) =>
            s + t.items.where((i) => !_isVoided(i)).length);
    final voiceChunks = <String>[
      ..._voidSpeakChunks(voidHits),
      if (newcomers.isNotEmpty)
        ..._kdsSpeakChunks(newcomers, fresh: true, fullTable: true),
    ];
    if (voiceChunks.isEmpty &&
        _voiceOn &&
        (voidMessage ?? '').trim().isNotEmpty) {
      voiceChunks.add(voidMessage!.trim());
    }
    if (voiceChunks.isNotEmpty && _voiceOn) {
      unawaited(PosQrOrderVoiceAlert.instance.speakSequence(voiceChunks));
    } else if (pingNew && open > _lastOpenCount) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    setState(() {
      _tickets = tickets;
      _lastOpenCount = open;
      _loading = false;
      _error = null;
    });
    } finally {
      _ticketsLoading = false;
      if (_ticketsReloadQueued) {
        final ping = _ticketsReloadPing;
        final queuedVoid = _ticketsReloadVoidMessage;
        _ticketsReloadQueued = false;
        _ticketsReloadPing = false;
        _ticketsReloadVoidMessage = null;
        if (mounted) {
          unawaited(_loadTickets(
            silent: true,
            pingNew: ping,
            voidMessage: queuedVoid,
          ));
        }
      }
    }
  }

  Future<void> _setLines(List<String> ids, String status) async {
    ids = [
      for (final id in ids)
        if (id.isNotEmpty &&
            !_tickets.any((t) => t.items.any((i) => i.id == id && _isVoided(i))))
          id,
    ];
    if (ids.isEmpty || _busy) return;
    final snapshot =
        status == 'done' ? _hitsForIds(ids) : const <_KdsHit>[];
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

  Future<void> _ackVoids(List<String> ids) async {
    final want = ids.where((e) => e.trim().isNotEmpty).toList();
    if (want.isEmpty || _busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final res = await _api.ackPosKdsVoids(want);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'KDS',
        message: res['message']?.toString() ?? 'Không xác nhận hủy được',
      );
      return;
    }
    await _loadTickets(silent: true);
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

  Color _waitColor(DateTime sent, {String? status}) =>
      _toneFor(status, sent).bg;

  _KdsTone _toneFor(String? status, [DateTime? sent]) {
    if (status == 'voided') return const _KdsTone(_voided, Colors.white);
    if (status == 'ready' || status == 'done') {
      return const _KdsTone(_ready, Colors.white);
    }
    if (status == 'cooking') return const _KdsTone(_cooking, Colors.white);
    if (sent != null && _waitAt(sent, DateTime.now()).inMinutes >= 10) {
      return const _KdsTone(_late, Colors.white);
    }
    return const _KdsTone(_queued, _inkOnLight);
  }

  int get _itemCount => _tickets.fold(
      0,
      (s, t) =>
          s +
          t.items
              .where((i) => !_isVoided(i))
              .fold(0, (a, i) => a + i.qty.round()));

  int get _lateCount {
    var n = 0;
    for (final t in _tickets) {
      for (final i in t.items) {
        if (_isVoided(i) || i.status == 'done') continue;
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
          _buildLegend(),
          Expanded(child: _buildBody(aggs)),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    Widget chip(String label, Color bg, Color fg) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      );
    }

    return Material(
      color: _bar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            chip(tr('Chờ làm'), _queued, _inkOnLight),
            chip(tr('Đang làm'), _cooking, Colors.white),
            chip(tr('Làm xong — in và rời bảng'), _ready, Colors.white),
            chip(tr('Hủy — Đồng ý từng món'), _voided, Colors.white),
          ],
        ),
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
                tooltip: tr('Đọc món cần chế biến. Giữ để chọn giọng'),
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
              PopupMenuButton<String>(
                tooltip: tr('Thêm'),
                icon: const Icon(Icons.more_vert, color: Colors.white70),
                onSelected: (v) async {
                  if (v == 'pos_settings') {
                    SettingsHubScreen.pendingSubIndex.value = null;
                    if (NavigationNotifier.mainLayoutReady.value) {
                      NavigationNotifier.navigateToModule.value =
                          'SettingsHub';
                    } else if (mounted) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SettingsHubScreen()),
                      );
                    }
                  } else if (v == 'voice_toggle') {
                    _toggleVoice();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'voice_toggle',
                    child: Text(tr(_voiceOn
                        ? 'Tắt loa tự đọc'
                        : 'Bật loa tự đọc')),
                  ),
                  PopupMenuItem(
                    value: 'pos_settings',
                    child: Text(tr('Thiết lập POS')),
                  ),
                ],
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
              _announcedMaxQty.clear();
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
                    title: Text(tr('In phiếu khi bấm Làm xong'),
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      tr('In rồi tự gỡ món khỏi bảng bếp'),
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
          mainAxisExtent: 128,
        ),
        itemCount: aggs.length,
        itemBuilder: (_, i) => _dishCard(aggs[i]),
      );
    });
  }

  Widget _dishCard(_KdsAgg a) {
    final voided = a.hits.every((h) => _isVoided(h.item));
    final c = _aggAccent(a);
    final tables = a.tableLabels;
    final noteSample = a.hits
        .map((h) => (h.item.note ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .take(2)
        .join(' · ');
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openAggSheet(a),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: c),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _qtyFmt.format(a.qty),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                            height: 1,
                            decoration:
                                voided ? TextDecoration.lineThrough : null,
                            decorationColor: _voided,
                            decorationThickness: 2.4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            a.name,
                            softWrap: true,
                            style: TextStyle(
                              color: voided ? _voided : Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              height: 1.2,
                              decoration:
                                  voided ? TextDecoration.lineThrough : null,
                              decorationColor: _voided,
                              decorationThickness: 2.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _statusPillsFromHits(a.hits),
                    if (noteSample.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        noteSample,
                        softWrap: true,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFB86B),
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                            softWrap: true,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
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
                  if (!voided) ...[
                    Expanded(
                      child: _sideBtn(
                        tr('Đang làm'),
                        _cooking,
                        () => _aggCook(a),
                      ),
                    ),
                    Container(height: 1, color: _line),
                    Expanded(
                      child: _sideBtn(
                        tr('Làm xong'),
                        _ready,
                        () => _aggDone(a),
                      ),
                    ),
                  ],
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
    final fg = color == _queued ? _inkOnLight : Colors.white;
    return InkWell(
      onTap: _busy ? null : onTap,
      child: ColoredBox(
        color: color,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  void _openAggSheet(_KdsAgg a) {
    final hasLive = a.hits.any((h) => !_isVoided(h.item));
    final hasVoid = a.hits.any((h) => _isVoided(h.item));
    if (_voiceOn) _speakAgg(a);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101827),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final c = _aggAccent(a);
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
                      style: const TextStyle(
                        color: Colors.white,
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
                                '${tr('Chờ')} ${_waitShortAt(a.oldest, now)}',
                          ),
                          const SizedBox(height: 6),
                          _statusPillsFromHits(a.hits),
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
                if (hasLive)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            unawaited(_aggCook(a));
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _cooking,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(tr('Đang làm'),
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            unawaited(_aggDone(a));
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _ready,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(tr('Làm xong'),
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                if (hasVoid) ...[
                  if (hasLive) const SizedBox(height: 8),
                  Text(tr('Món hủy — Đồng ý từng dòng'),
                      style: const TextStyle(
                          color: Colors.white54, fontWeight: FontWeight.w700)),
                ],
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
                      final voided = _isVoided(h.item);
                      final hc = _waitColor(sent, status: h.item.status);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${_qtyFmt.format(h.item.qty)}×  ${h.ticket.title}',
                          style: TextStyle(
                            color: voided ? _voided : Colors.white,
                            fontWeight: FontWeight.w700,
                            decoration:
                                voided ? TextDecoration.lineThrough : null,
                            decorationColor: _voided,
                          ),
                        ),
                        subtitle: _KdsTickText(
                          tick: _nowTick,
                          style: TextStyle(color: hc),
                          builder: (now) => [
                            if (!voided) _waitShortAt(sent, now),
                            _statusLabel(h.item.status),
                            if ((h.item.note ?? '').isNotEmpty) h.item.note!,
                          ].join(' · '),
                        ),
                        trailing: voided
                            ? _miniAct(
                                tr('Đồng ý'),
                                _voided,
                                () => _ackVoids([h.item.id]),
                              )
                            : Wrap(
                                spacing: 6,
                                children: [
                                  if (h.item.status == 'queued')
                                    _miniAct(tr('Đang làm'), _cooking,
                                        () => _setLine(h.item, 'cooking')),
                                  if (h.item.status != 'done')
                                    _miniAct(tr('Làm xong'), _ready,
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
    final fg = color == _queued ? _inkOnLight : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
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
          mainAxisExtent: 220,
        ),
        itemCount: _tickets.length,
        itemBuilder: (_, i) => _ticketCard(_tickets[i]),
      );
    });
  }

  Widget _ticketCard(_KdsTicket t) {
    final oldest = t.oldest;
    final allVoided = t.items.isNotEmpty && t.items.every(_isVoided);
    final accent = allVoided
        ? _voided
        : t.items.any((i) => i.status == 'queued')
            ? _waitColor(oldest, status: 'queued')
            : t.items.any((i) => i.status == 'cooking')
                ? _cooking
                : t.items.any((i) => i.status == 'ready')
                    ? _ready
                    : _voided;
    final extra = t.items.length > 5 ? t.items.length - 5 : 0;
    final shown = extra > 0 ? t.items.take(5).toList() : t.items;
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(width: 5, color: accent),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: const Color(0xFF0F1724),
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.title,
                          softWrap: true,
                          maxLines: 2,
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
                          color: accent,
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
                if (!allVoided) ...[
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
                      tr('Làm xong'),
                      _ready,
                      () => _setTicketDone(t),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(_KdsItem item, _KdsTicket ticket) {
    final sent = item.sentAt ?? ticket.sentAt;
    final voided = _isVoided(item);
    final tone = _toneFor(item.status, sent);
    final note = (item.note ?? '').trim();
    return InkWell(
      onTap: voided
          ? null
          : () {
              final next = switch (item.status) {
                'queued' => 'cooking',
                'cooking' => 'done',
                'ready' => 'done',
                _ => 'cooking',
              };
              unawaited(_setLine(item, next));
            },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                _qtyFmt.format(item.qty),
                style: TextStyle(
                  color: tone.fg,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  decoration: voided ? TextDecoration.lineThrough : null,
                  decorationColor: tone.fg,
                  decorationThickness: 2.2,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    softWrap: true,
                    style: TextStyle(
                      color: tone.fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.25,
                      decoration: voided ? TextDecoration.lineThrough : null,
                      decorationColor: tone.fg,
                      decorationThickness: 2.2,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      softWrap: true,
                      style: TextStyle(
                        color: tone.fg.withOpacity(0.9),
                        fontSize: 11,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        decoration:
                            voided ? TextDecoration.lineThrough : null,
                        decorationColor: tone.fg,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (voided)
              _miniAct(
                tr('Đồng ý'),
                _voided,
                () => _ackVoids([item.id]),
              )
            else
              _KdsTickText(
                tick: _nowTick,
                style: TextStyle(
                  color: tone.fg,
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
        'cooking' => tr('Đang làm'),
        'ready' => tr('Làm xong'),
        'done' => tr('Làm xong'),
        'voided' => tr('Hủy'),
        _ => tr('Chờ làm'),
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
  const _KdsHit({
    required this.ticket,
    required this.item,
    this.speakQty,
  });
  final _KdsTicket ticket;
  final _KdsItem item;
  /// SL đọc TTS (phần tăng); null → dùng item.qty.
  final double? speakQty;
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
    final voids = hits.where((h) => h.item.status == 'voided').length;
    final parts = <String>[];
    if (queued > 0) parts.add('$queued ${t('mới')}');
    if (cooking > 0) parts.add('$cooking ${t('làm')}');
    if (ready > 0) parts.add('$ready ${t('xong')}');
    if (voids > 0) parts.add('$voids ${t('hủy')}');
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
    this.productId = '',
    this.sentQty = 0,
    this.note,
    this.sentAt,
  });
  final String id;
  final String productId;
  final String productName;
  final double qty;
  final double sentQty;
  final String status;
  final String? note;
  final DateTime? sentAt;

  factory _KdsItem.fromJson(Map<String, dynamic> j) {
    final q = j['qty'] ?? j['Qty'] ?? 0;
    final sentQ = j['sentQty'] ?? j['SentQty'] ?? q;
    final sentRaw = j['sentAt'] ?? j['SentAt'];
    return _KdsItem(
      id: (j['id'] ?? j['Id'] ?? '').toString(),
      productId: (j['productId'] ?? j['ProductId'] ?? '').toString(),
      productName: (j['productName'] ?? j['ProductName'] ?? '').toString(),
      qty: q is num ? q.toDouble() : double.tryParse('$q') ?? 0,
      sentQty: sentQ is num ? sentQ.toDouble() : double.tryParse('$sentQ') ?? 0,
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
