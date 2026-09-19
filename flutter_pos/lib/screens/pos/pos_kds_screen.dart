import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/pos_store_printer.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_floor_realtime.dart';
import '../../utils/pos_kds_alert.dart';
import '../../utils/pos_kitchen_direct_connect.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_qr_order_voice.dart';
import '../../utils/pos_browser_fullscreen.dart';
import '../../utils/play_system_ui.dart';
import '../../utils/system_ui_inset_mode.dart';
import '../../utils/navigation_notifier.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../settings_hub_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// KDS bếp: món mới = chờ làm. Đang làm → Ra món (in + rời bảng). Hủy: Đồng ý từng món.
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
  static const _bg = Color(0xFFF4F6FB);
  static const _bar = Color(0xFFFFFFFF);
  static const _card = Color(0xFFFFFFFF);
  static const _line = Color(0xFFE5E7EB);
  static const _ink = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _chipIdle = Color(0xFFF3F4F6);
  static const _blue = Color(0xFF2563EB);
  static const _blueSoft = Color(0xFFEFF6FF);
  static const _orange = Color(0xFFF59E0B);
  static const _orangeSoft = Color(0xFFFFF7ED);
  static const _green = Color(0xFF22C55E);
  static const _greenSoft = Color(0xFFECFDF5);
  static const _chipOn = _blue;
  static const _sheet = Color(0xFFFFFFFF);
  static const _ticketHead = Color(0xFFF8FAFC);
  static const _accent = _blue;
  static const _note = Color(0xFF6B7280);
  static const _queued = _orange;
  static const _cooking = _blue;
  static const _ready = _green;
  static const _late = Color(0xFFDC2626);
  static const _voided = Color(0xFF9CA3AF);
  static const _inkOnLight = Color(0xFF111827);
  static const _namePanel = Color(0xFFFFFFFF);
  static const _freshGlow = _blue;

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
  bool _lateOnly = false;
  bool _noDishTables = false;
  int _lateMinutes = PosKdsAlert.defaultLateMinutes;
  DateTime? _clockMinute;
  String? _statusFilter;
  bool _printOnDone = false;
  bool _voiceOn = true;
  bool _bellBeforeVoice = true;
  bool _printTingOn = true;
  bool _voiceSeeded = false;
  bool _voidSeeded = false;
  /// SL đã báo bếp (KitchenSentQty lũy kế) đã đọc loa — chỉ tăng;
  /// không xóa khi làm xong / API nháy thiếu (tránh đọc lại phiếu cũ + phiếu mới).
  final Map<String, double> _announcedMaxQty = {};
  final Map<String, DateTime> _freshUntil = {};
  final Set<String> _announcedVoidIds = {};
  /// Phiếu hủy đã Đồng ý — ẩn ngay, không chờ reload (tránh sheet/thẻ kẹt).
  final Set<String> _ackedVoidIds = {};
  bool _isKdsFullscreen = false;
  final _boardRev = ValueNotifier<int>(0);
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
    PosKdsAlert.enterUi();
    NotificationOverlayManager().clear();
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
      if (!mounted) return;
      final now = DateTime.now();
      _nowTick.value = now;
      _pruneFresh();
      final minute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      if (_clockMinute != minute) {
        _clockMinute = minute;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    PosQrOrderVoiceAlert.instance.leaveKds();
    PosKdsAlert.leaveUi();
    unawaited(PosQrOrderVoiceAlert.instance.stopSpeaking());
    _floor.dispose();
    _poll?.cancel();
    _clock?.cancel();
    _nowTick.dispose();
    _boardRev.dispose();
    if (_isKdsFullscreen && !kIsWeb) {
      SystemUiInsetMode.immersive.value = false;
      unawaited(restoreSystemBarsEdgeToEdge());
    }
    super.dispose();
  }

  Future<void> _toggleKdsFullscreen() async {
    if (kIsWeb) {
      final active = await togglePosBrowserFullscreen();
      if (!mounted) return;
      SystemUiInsetMode.immersive.value = active;
      setState(() => _isKdsFullscreen = active);
      return;
    }
    final next = !_isKdsFullscreen;
    SystemUiInsetMode.immersive.value = next;
    if (next) {
      await hideSystemBarsForImmersive();
    } else {
      await restoreSystemBarsEdgeToEdge();
    }
    if (!mounted) return;
    setState(() => _isKdsFullscreen = next);
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
    _lateMinutes = (prefs.getInt(PosKdsAlert.lateMinutesKey) ??
            PosKdsAlert.defaultLateMinutes)
        .clamp(1, 120);
    _voiceOn = prefs.getBool(PosKdsAlert.voiceOnKey) ?? true;
    _bellBeforeVoice = prefs.getBool(PosKdsAlert.bellBeforeVoiceKey) ?? true;
    _printTingOn = prefs.getBool(PosKdsAlert.printTingKey) ?? true;
    try {
      final deviceId = await PosPrintOrchestrator.stableDeviceId();
      _kdsPrinters = await PosKitchenDirectConnect.reachableKitchenPrinters(
        deviceId: deviceId,
      );
    } catch (_) {}
  }

  Future<void> _saveKdsPrintPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pos_kds_print_on_done', _printOnDone);
    await prefs.setBool('pos_kds_newest_first', _newestFirst);
    await prefs.setBool('pos_kds_only_unfinished', _onlyUnfinished);
    await prefs.setInt(PosKdsAlert.lateMinutesKey, _lateMinutes);
    await prefs.setBool(PosKdsAlert.voiceOnKey, _voiceOn);
    await prefs.setBool(PosKdsAlert.bellBeforeVoiceKey, _bellBeforeVoice);
    await prefs.setBool(PosKdsAlert.printTingKey, _printTingOn);
    if (_kdsPrinterId == null || _kdsPrinterId!.isEmpty) {
      await prefs.remove('pos_kds_printer_id');
    } else {
      await prefs.setString('pos_kds_printer_id', _kdsPrinterId!);
    }
  }

  Future<void> _printReadyHits(List<_KdsHit> hits) async {
    if (!_printOnDone || hits.isEmpty) return;
    final deviceId = await PosPrintOrchestrator.stableDeviceId();
    final printer = await PosKitchenDirectConnect.resolvePrintTarget(
      deviceId: deviceId,
      preferredId: _kdsPrinterId,
      stationId: _stationId,
    );
    if (printer == null) {
      NotificationOverlayManager().showError(
        title: 'Không in ra món',
        message: tr(
            'Chưa chọn máy in bếp. Mở biểu tượng máy in, kết nối USB/LAN.'),
        relatedEntityType: kPosKdsNotifyKind,
      );
      return;
    }
    if (_kdsPrinterId != printer.id) {
      _kdsPrinterId = printer.id;
      unawaited(_saveKdsPrintPrefs());
    }
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

  bool _itemIsQueued(_KdsItem i) =>
      !_isVoided(i) &&
      i.status != 'cooking' &&
      i.status != 'ready' &&
      i.status != 'done';

  bool _itemIsLate(_KdsItem i, _KdsTicket t, [DateTime? now]) {
    if (!_itemIsQueued(i)) return false;
    return _waitAt(i.sentAt ?? t.sentAt, now ?? DateTime.now()).inMinutes >=
        _lateMinutes;
  }

  bool _tableHasNoStartedDish(_KdsTicket t) {
    final open = t.items.where((i) => !_isVoided(i)).toList();
    if (open.isEmpty) return false;
    return open.every(_itemIsQueued);
  }

  List<_KdsTicket> get _scopedTickets {
    var list = _tickets;
    if (_noDishTables) {
      list = list.where(_tableHasNoStartedDish).toList();
    }
    if (_lateOnly) {
      final now = DateTime.now();
      list = [
        for (final t in list)
          if (t.items.any((i) => _itemIsLate(i, t, now)))
            _ticketWithItems(
              t,
              t.items.where((i) => _itemIsLate(i, t, now)).toList(),
            ),
      ];
    }
    return list;
  }

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
    final sentByKey = <String, double>{};
    final openByKey = <String, double>{};
    final hitByKey = <String, _KdsHit>{};
    for (final h in prep) {
      final key = _announceKey(h);
      if (key.isEmpty) continue;
      final open = h.item.qty;
      final sent = h.item.sentQty > 0 ? h.item.sentQty : open;
      sentByKey[key] = (sentByKey[key] ?? 0) + sent;
      openByKey[key] = (openByKey[key] ?? 0) + open;
      hitByKey[key] = h;
    }

    final newcomers = <_KdsHit>[];
    for (final e in sentByKey.entries) {
      final prev = _announcedMaxQty[e.key] ?? 0;
      final open = openByKey[e.key] ?? 0;
      if (!first && e.value > prev + 0.0001) {
        // SentQty là lũy kế (phiếu trước + phiếu mới). Chỉ đọc phần tăng;
        // không đọc lại SL đã làm xong nếu mốc bị mất.
        var delta = e.value - prev;
        if (delta > open) delta = open;
        if (delta > 0.0001) {
          final h = hitByKey[e.key]!;
          newcomers.add(_KdsHit(
            ticket: h.ticket,
            item: h.item,
            speakQty: delta,
          ));
        }
      }
      if (e.value > prev) {
        _announcedMaxQty[e.key] = e.value;
      } else if (e.value + 0.0001 < prev) {
        // Hủy trên dòng còn hiện: hạ mốc theo KitchenSentQty thật.
        _announcedMaxQty[e.key] = e.value;
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
        if (!first) {
          final hit = _KdsHit(ticket: t, item: i);
          newcomers.add(hit);
          _reduceAnnounced(hit);
        }
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

  void _markFresh(List<_KdsHit> hits) {
    if (hits.isEmpty) return;
    final until = DateTime.now().add(const Duration(seconds: 90));
    for (final h in hits) {
      final k = _announceKey(h);
      if (k.isNotEmpty) _freshUntil[k] = until;
    }
  }

  void _pruneFresh() {
    if (_freshUntil.isEmpty) return;
    final now = DateTime.now();
    final before = _freshUntil.length;
    _freshUntil.removeWhere((_, t) => !t.isAfter(now));
    if (_freshUntil.length != before && mounted) setState(() {});
  }

  bool _hitIsFresh(_KdsHit h) {
    final t = _freshUntil[_announceKey(h)];
    return t != null && t.isAfter(DateTime.now());
  }

  bool _itemIsFresh(_KdsItem item, _KdsTicket ticket) =>
      _hitIsFresh(_KdsHit(ticket: ticket, item: item));

  bool _aggIsFresh(_KdsAgg a) => a.hits.any(_hitIsFresh);

  Future<void> _ringThenSpeak(List<String> chunks, {required bool pingNew}) async {
    final hasVoice = chunks.isNotEmpty && _voiceOn;
    final bell = _bellBeforeVoice && (hasVoice || pingNew);
    if (bell) await PosKdsAlert.playBell();
    if (hasVoice) {
      if (bell) await Future<void>.delayed(const Duration(milliseconds: 380));
      if (!mounted) return;
      await PosQrOrderVoiceAlert.instance.speakSequence(chunks);
    } else if (pingNew && !_bellBeforeVoice) {
      await PosKdsAlert.playTing();
    }
  }

  /// Hạ mốc đã đọc khi hủy — ghi chú phiếu hủy có thể khác dòng gốc.
  void _reduceAnnounced(_KdsHit h) {
    var left = h.item.qty;
    if (left <= 0) left = 1;
    void apply(String key) {
      final prev = _announcedMaxQty[key];
      if (prev == null || left <= 0) return;
      final cut = prev < left ? prev : left;
      final next = prev - cut;
      left -= cut;
      if (next <= 0.0001) {
        _announcedMaxQty.remove(key);
      } else {
        _announcedMaxQty[key] = next;
      }
    }

    final exact = _announceKey(h);
    if (exact.isNotEmpty) apply(exact);
    if (left <= 0.0001) return;
    final pid = h.item.productId.trim();
    final name = h.item.productName.trim().toLowerCase();
    final id = pid.isNotEmpty ? pid : name;
    if (id.isEmpty) return;
    final prefix = '${h.ticket.orderId}|$id|';
    for (final key in _announcedMaxQty.keys.toList()) {
      if (key.startsWith(prefix)) apply(key);
    }
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

  String _aggVisualStatus(_KdsAgg a) {
    if (a.hits.every((h) => _isVoided(h.item))) return 'voided';
    return a.hottest == 'done' ? 'ready' : a.hottest;
  }

  Color _statusAccent(String status) => switch (status) {
        'cooking' => _blue,
        'ready' || 'done' => _green,
        'voided' => _voided,
        _ => _orange,
      };

  Color _statusSoft(String status) => switch (status) {
        'cooking' => _blueSoft,
        'ready' || 'done' => _greenSoft,
        'voided' => _chipIdle,
        _ => _orangeSoft,
      };

  Color _aggAccent(_KdsAgg a) => _statusAccent(_aggVisualStatus(a));

  List<_KdsAgg> get _visibleAggs {
    final f = _statusFilter;
    if (f == null) return _aggregates;
    return _aggregates.where((a) => _aggVisualStatus(a) == f).toList();
  }

  List<_KdsTicket> get _visibleTickets {
    final f = _statusFilter;
    final src = _scopedTickets;
    if (f == null) return src;
    return src.where((t) {
      return t.items.any((i) {
        if (_isVoided(i)) return f == 'voided';
        final s = i.status == 'done' ? 'ready' : i.status;
        return s == f;
      });
    }).toList();
  }

  Widget _statusPillsFromHits(List<_KdsHit> hits) {
    double qtyOf(String status) => hits
        .where((h) => h.item.status == status)
        .fold(0.0, (s, h) => s + h.item.qty);
    Widget pill(double qty, String label) {
      if (qty <= 0) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(right: 4, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _chipIdle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _line),
        ),
        child: Text(
          '${_qtyFmt.format(qty)} $label',
          style: const TextStyle(
            color: _muted,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      );
    }

    return Wrap(
      children: [
        pill(qtyOf('queued'), tr('chờ')),
        pill(qtyOf('cooking'), tr('làm')),
        pill(qtyOf('ready'), tr('xong')),
        pill(qtyOf('voided'), tr('hủy')),
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
    var tickets = <_KdsTicket>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          tickets.add(_KdsTicket.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    _pruneAckedVoidIds(tickets);
    tickets = _withoutAckedVoids(tickets);
    tickets.sort((a, b) => _newestFirst
        ? b.oldest.compareTo(a.oldest)
        : a.oldest.compareTo(b.oldest));
    final newcomers = _collectNewPrepHits(tickets);
    final voidHits = _collectNewVoidHits(tickets);
    _markFresh(newcomers);
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
    if (voiceChunks.isNotEmpty && (_voiceOn || _bellBeforeVoice)) {
      unawaited(_ringThenSpeak(voiceChunks, pingNew: pingNew || newcomers.isNotEmpty));
    } else if (pingNew && open > _lastOpenCount) {
      unawaited(PosKdsAlert.playTing());
    }
    setState(() {
      _tickets = tickets;
      _lastOpenCount = open;
      _loading = false;
      _error = null;
    });
    _boardRev.value++;
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

  bool _canKdsAct() {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    return perm.canCreate('PosKds') || perm.canEdit('PosProducts');
  }

  void _denyKdsAct() {
    NotificationOverlayManager().showWarning(
      title: 'Không có quyền',
      message: tr('Tài khoản chỉ xem KDS — không được chuyển món / xác nhận'),
      relatedEntityType: kPosKdsNotifyKind,
    );
  }

  Future<void> _setLines(List<String> ids, String status) async {
    if (!_canKdsAct()) {
      _denyKdsAct();
      return;
    }
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
        relatedEntityType: kPosKdsNotifyKind,
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
    if (!_canKdsAct()) {
      _denyKdsAct();
      return;
    }
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
        relatedEntityType: kPosKdsNotifyKind,
      );
      return;
    }
    _lastBumpedOrderId = t.orderId;
    final hits = [for (final i in t.items) _KdsHit(ticket: t, item: i)];
    await _loadTickets(silent: true);
    unawaited(_printReadyHits(hits));
  }

  Future<void> _ackVoids(List<String> ids) async {
    if (!_canKdsAct()) {
      _denyKdsAct();
      return;
    }
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
        relatedEntityType: kPosKdsNotifyKind,
      );
      return;
    }
    _ackedVoidIds.addAll(want);
    setState(() => _tickets = _withoutAckedVoids(_tickets));
    _boardRev.value++;
    await _loadTickets(silent: true);
  }

  _KdsTicket _ticketWithItems(_KdsTicket t, List<_KdsItem> items) =>
      _KdsTicket(
        orderId: t.orderId,
        orderNo: t.orderNo,
        tableName: t.tableName,
        areaName: t.areaName,
        channel: t.channel,
        sentAt: t.sentAt,
        status: t.status,
        items: items,
      );

  List<_KdsTicket> _withoutAckedVoids(List<_KdsTicket> tickets) {
    if (_ackedVoidIds.isEmpty) return tickets;
    final out = <_KdsTicket>[];
    for (final t in tickets) {
      final items =
          t.items.where((i) => !_ackedVoidIds.contains(i.id)).toList();
      if (items.isEmpty) continue;
      out.add(items.length == t.items.length ? t : _ticketWithItems(t, items));
    }
    return out;
  }

  void _pruneAckedVoidIds(List<_KdsTicket> incoming) {
    if (_ackedVoidIds.isEmpty) return;
    _ackedVoidIds.removeWhere(
      (id) => !incoming.any((t) => t.items.any((i) => i.id == id)),
    );
  }

  _KdsAgg? _aggByName(String name) {
    final key = name.trim().toLowerCase();
    for (final a in _aggregates) {
      if (a.name.trim().toLowerCase() == key) return a;
    }
    return null;
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
        relatedEntityType: kPosKdsNotifyKind,
      );
      return;
    }
    await _loadTickets(silent: true);
  }

  List<_KdsAgg> get _aggregates {
    final map = <String, _KdsAgg>{};
    for (final t in _scopedTickets) {
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
    final s = status ?? 'queued';
    return _KdsTone(_statusAccent(s), Colors.white);
  }

  int get _itemCount => _tickets.fold(
      0,
      (s, t) =>
          s +
          t.items
              .where((i) => !_isVoided(i))
              .fold(0, (a, i) => a + i.qty.round()));

  int get _lateCount {
    final now = DateTime.now();
    var n = 0;
    for (final t in _tickets) {
      for (final i in t.items) {
        if (_itemIsLate(i, t, now)) n++;
      }
    }
    return n;
  }

  int get _noDishTableCount =>
      _tickets.where(_tableHasNoStartedDish).length;

  @override
  Widget build(BuildContext context) {
    final pushed = PosHubScope.pushedSubPageOf(context);
    final aggs = _visibleAggs;
    return Theme(
      data: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.light(
          primary: _blue,
          secondary: _orange,
          surface: _card,
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: _sheet,
          textStyle: TextStyle(color: _ink),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? _chipOn : _muted),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? _chipOn.withOpacity(0.42)
                  : _line),
        ),
      ),
      child: Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(pushed, aggs),
          _buildFilters(),
          Expanded(child: _buildBody(aggs)),
        ],
      ),
    ),
    );
  }

  Widget _buildHeader(bool pushed, List<_KdsAgg> aggs) {
    final lateN = _lateCount;
    return Material(
      color: _bar,
      elevation: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
      child: SafeArea(
        top: !_isKdsFullscreen,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              if (pushed)
                IconButton(
                  tooltip: tr('Quay lại'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: _ink),
                ),
              const Icon(Icons.soup_kitchen, color: _blue, size: 28),
              const SizedBox(width: 8),
              Text(
                tr('BẾP'),
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  letterSpacing: 0.4,
                  height: 1,
                ),
              ),
              const SizedBox(width: 12),
              _viewToggle(),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _statIcon(Icons.restaurant_outlined,
                          '${_itemCount} ${tr('món')}'),
                      const SizedBox(width: 14),
                      _statIcon(Icons.table_restaurant_outlined,
                          '${_tickets.length} ${tr('bàn')}'),
                      if (aggs.isNotEmpty) ...[
                        const SizedBox(width: 14),
                        _statIcon(Icons.grid_view_outlined,
                            '${aggs.length} ${tr('loại')}'),
                      ],
                      if (lateN > 0) ...[
                        const SizedBox(width: 14),
                        InkWell(
                          onTap: () {
                            setState(() => _lateOnly = !_lateOnly);
                          },
                          child: _statIcon(
                            Icons.schedule,
                            '${lateN} ${tr('trễ')}',
                            color: _late,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _KdsTickText(
                    tick: _nowTick,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      height: 1.1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    builder: (now) => _clockFmt.format(now),
                  ),
                  _KdsTickText(
                    tick: _nowTick,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                    builder: (now) => _dateLabel(now),
                  ),
                ],
              ),
              if (_lastBumpedOrderId != null)
                TextButton(
                  onPressed: _recall,
                  child: Text(tr('Gọi lại'),
                      style: const TextStyle(
                          color: _chipOn, fontWeight: FontWeight.w800)),
                ),
              IconButton(
                tooltip: tr(_isKdsFullscreen
                    ? 'Thu nhỏ'
                    : 'Phóng toàn màn hình'),
                onPressed: () => unawaited(_toggleKdsFullscreen()),
                icon: Icon(
                  _isKdsFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  color: _ink,
                ),
              ),
              IconButton(
                tooltip: tr('Đọc món cần chế biến'),
                onPressed: _speakPending,
                icon: Icon(
                  _voiceOn ? Icons.volume_up : Icons.volume_off,
                  color: _voiceOn ? _blue : _muted,
                ),
              ),
              IconButton(
                tooltip: tr('Máy in KDS'),
                onPressed: _openKdsPrintSettings,
                icon: Icon(
                  _printOnDone ? Icons.print : Icons.print_disabled,
                  color: _printOnDone ? _blue : _muted,
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
                            strokeWidth: 2, color: _muted),
                      )
                    : const Icon(Icons.refresh, color: _muted),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Thêm'),
                color: _sheet,
                icon: const Icon(Icons.more_vert, color: _muted),
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
                  } else if (v == 'voice_settings') {
                    unawaited(
                      PosQrOrderVoiceAlert.instance.showSettingsSheet(context),
                    );
                  } else if (v == 'fullscreen') {
                    unawaited(_toggleKdsFullscreen());
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'fullscreen',
                    child: Text(tr(_isKdsFullscreen
                        ? 'Thu nhỏ'
                        : 'Phóng toàn màn hình')),
                  ),
                  PopupMenuItem(
                    value: 'voice_toggle',
                    child: Text(tr(_voiceOn
                        ? 'Tắt loa tự đọc'
                        : 'Bật loa tự đọc')),
                  ),
                  PopupMenuItem(
                    value: 'voice_settings',
                    child: Text(tr('Chọn giọng và tốc độ')),
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
      ),
    );
  }

  String _dateLabel(DateTime now) {
    const days = [
      '',
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7',
      'CN',
    ];
    final d = days[now.weekday];
    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    return '$d, $dd/$mm/${now.year}';
  }

  Widget _statIcon(IconData icon, String text, {Color color = _muted}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: on ? _chipOn : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? Colors.white : _ink,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _chipIdle,
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

  Widget _buildFilters() {
    final lateN = _lateCount;
    final noDishN = _noDishTableCount;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            text,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        );
    return Material(
      color: _bar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    label('${tr('Trạng thái')}:'),
                    _toneChip(tr('Tất cả'), null, _blue, _blueSoft),
                    _toneChip(tr('Đang làm'), 'cooking', _blue, _blueSoft),
                    _toneChip(tr('Chờ làm'), 'queued', _orange, _orangeSoft),
                    _toneChip(tr('Làm xong'), 'ready', _green, _greenSoft),
                    const SizedBox(width: 16),
                    label('${tr('Máy in')}:'),
                    _stationChip(null, tr('Tất cả')),
                    for (final s in _stations) _stationChip(s.id, s.name),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
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
                      lateN > 0
                          ? '${tr('Trễ')} ($lateN)'
                          : tr('Trễ'),
                      _lateOnly,
                      () {
                        setState(() => _lateOnly = !_lateOnly);
                      },
                      accent: _late,
                    ),
                    _filterChip(
                      noDishN > 0
                          ? '${tr('Bàn chưa có món')} ($noDishN)'
                          : tr('Bàn chưa có món'),
                      _noDishTables,
                      () {
                        setState(() {
                          _noDishTables = !_noDishTables;
                          if (_noDishTables) _view = _KdsView.table;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toneChip(String label, String? value, Color accent, Color soft) {
    final on = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? accent : soft,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => _statusFilter = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                color: on ? Colors.white : accent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stationChip(String? id, String label) {
    final on = _stationId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? _chipOn : _chipIdle,
        shape: StadiumBorder(
          side: BorderSide(color: on ? _chipOn : _line),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
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
                color: on ? Colors.white : _ink,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool on, VoidCallback tap,
      {Color accent = _blue}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? accent : _chipIdle,
        shape: StadiumBorder(
          side: BorderSide(
            color: on ? accent : _line,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                color: on ? Colors.white : _ink,
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
      backgroundColor: _sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _line,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Text(tr('Máy in KDS'),
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 18)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Đọc món cần chế biến'),
                        style: const TextStyle(color: _ink)),
                    subtitle: Text(
                      tr('Tự đọc món mới. Chạm loa trên cột Đang làm / Xong để đọc lại. Nút chỉnh giọng để chọn giọng mượt và tốc độ.'),
                      style: const TextStyle(color: _muted),
                    ),
                    value: _voiceOn,
                    onChanged: (v) {
                      setLocal(() => _voiceOn = v);
                      setState(() => _voiceOn = v);
                      unawaited(_saveKdsPrintPrefs());
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Chuông trước khi đọc'),
                        style: const TextStyle(color: _ink)),
                    subtitle: Text(
                      tr('Kêu 1 tiếng chuông, rồi mới đọc tên món / số lượng.'),
                      style: const TextStyle(color: _muted),
                    ),
                    value: _bellBeforeVoice,
                    onChanged: (v) {
                      setLocal(() => _bellBeforeVoice = v);
                      setState(() => _bellBeforeVoice = v);
                      unawaited(_saveKdsPrintPrefs());
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Ting khi in phiếu từ máy khác'),
                        style: const TextStyle(color: _ink)),
                    subtitle: Text(
                      tr('Máy bếp / Print Agent kêu ting khi nhận lệnh in phiếu bếp.'),
                      style: const TextStyle(color: _muted),
                    ),
                    value: _printTingOn,
                    onChanged: (v) {
                      setLocal(() => _printTingOn = v);
                      setState(() => _printTingOn = v);
                      unawaited(_saveKdsPrintPrefs());
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(tr('Báo trễ món'),
                      style: const TextStyle(
                          color: _ink, fontWeight: FontWeight.w700)),
                  Text(
                    tr('Chưa nhấn Đang làm quá số phút này thì tính là trễ.'),
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        tooltip: tr('Giảm'),
                        onPressed: _lateMinutes <= 1
                            ? null
                            : () {
                                final next = _lateMinutes - 1;
                                setLocal(() => _lateMinutes = next);
                                setState(() => _lateMinutes = next);
                                unawaited(_saveKdsPrintPrefs());
                              },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '$_lateMinutes ${tr('phút')}',
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Tăng'),
                        onPressed: _lateMinutes >= 120
                            ? null
                            : () {
                                final next = _lateMinutes + 1;
                                setLocal(() => _lateMinutes = next);
                                setState(() => _lateMinutes = next);
                                unawaited(_saveKdsPrintPrefs());
                              },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final m in const [5, 10, 15, 20, 30])
                        ChoiceChip(
                          label: Text('$m ${tr('phút')}'),
                          selected: _lateMinutes == m,
                          onSelected: (_) {
                            setLocal(() => _lateMinutes = m);
                            setState(() => _lateMinutes = m);
                            unawaited(_saveKdsPrintPrefs());
                          },
                        ),
                    ],
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
                      icon: const Icon(Icons.tune, color: _accent),
                      label: Text(tr('Chọn giọng và tốc độ'),
                          style: const TextStyle(color: _accent)),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('In phiếu khi bấm Ra món'),
                        style: const TextStyle(color: _ink)),
                    subtitle: Text(
                      tr('In rồi tự gỡ món khỏi bảng bếp'),
                      style: const TextStyle(color: _muted),
                    ),
                    value: _printOnDone,
                    onChanged: (v) {
                      setLocal(() => _printOnDone = v);
                      setState(() => _printOnDone = v);
                      unawaited(_saveKdsPrintPrefs());
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(tr('Thêm máy in bếp trên máy này'),
                      style: const TextStyle(
                          color: _ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final saved =
                                await PosKitchenDirectConnect.connectUsb(
                                    context);
                            if (saved == null || !mounted) return;
                            await _loadKdsPrintPrefs();
                            final id =
                                (saved.storePrinterId ?? saved.id).trim();
                            if (id.isNotEmpty) _kdsPrinterId = id;
                            if (mounted) setState(() {});
                            unawaited(_saveKdsPrintPrefs());
                          },
                          icon: const Icon(Icons.usb, size: 18),
                          label: Text(tr('USB nội bộ')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final saved =
                                await PosKitchenDirectConnect.connectLan(
                                    context);
                            if (saved == null || !mounted) return;
                            await _loadKdsPrintPrefs();
                            final id =
                                (saved.storePrinterId ?? saved.id).trim();
                            if (id.isNotEmpty) _kdsPrinterId = id;
                            if (mounted) setState(() {});
                            unawaited(_saveKdsPrintPrefs());
                          },
                          icon: const Icon(Icons.wifi, size: 18),
                          label: Text(tr('LAN / WiFi')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(tr('Kết nối máy in'),
                      style: const TextStyle(
                          color: _ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (_kdsPrinters.isEmpty)
                    Text(
                      tr('Chưa có máy bếp trên thiết bị này. Kết nối USB/LAN nội bộ, hoặc chọn máy đã chia sẻ Agent.'),
                      style: const TextStyle(color: _muted),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      value: _kdsPrinters.any((p) => p.id == _kdsPrinterId)
                          ? _kdsPrinterId
                          : null,
                      hint: Text(tr('Chọn máy in bếp'),
                          style: const TextStyle(color: _muted)),
                      dropdownColor: _sheet,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: _chipIdle,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in _kdsPrinters)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              '${p.name}${p.isDeviceLocal ? ' · USB/LAN nội bộ' : ''}',
                              style: const TextStyle(color: _ink),
                            ),
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
            ),
          );
        });
      },
    );
  }

  Widget _buildBody(List<_KdsAgg> aggs) {
    if (_loading && _tickets.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: _chipOn));
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
                size: 56, color: _muted),
            const SizedBox(height: 12),
            Text(
              tr('Chưa có món báo bếp'),
              style: const TextStyle(color: _muted, fontSize: 18),
            ),
          ],
        ),
      );
    }
    final scopedEmpty = _view == _KdsView.dish
        ? aggs.isEmpty
        : _visibleTickets.isEmpty;
    if (scopedEmpty) {
      final msg = _lateOnly && _noDishTables
          ? tr('Không có bàn chưa có món bị trễ')
          : _lateOnly
              ? tr('Không có món trễ')
              : _noDishTables
                  ? tr('Không có bàn chưa có món')
                  : tr('Không có món khớp bộ lọc');
      return Center(
        child: Text(msg, style: const TextStyle(color: _muted, fontSize: 16)),
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
              color: _chipOn,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }

  Widget _buildDishGrid(List<_KdsAgg> aggs) {
    return LayoutBuilder(builder: (context, c) {
      final n = (c.maxWidth / 260).floor().clamp(1, 6);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: n,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 198,
        ),
        itemCount: aggs.length,
        itemBuilder: (_, i) => _dishCard(aggs[i]),
      );
    });
  }

  Widget _statusBadge(String status) {
    final accent = _statusAccent(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _statusSoft(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _qtyBadge(String qty, String status, {bool fresh = false}) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _statusAccent(status),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (fresh)
            Text(
              tr('MỚI'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 7,
                height: 1,
              ),
            ),
          Text(
            qty,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              height: 1.05,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _prepActions({
    required VoidCallback onCook,
    required VoidCallback onDone,
    bool cooking = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: FilledButton(
              onPressed: _busy ? null : onCook,
              style: FilledButton.styleFrom(
                backgroundColor: cooking ? _blue : _orange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: cooking ? _blue : _orange,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                tr('Đang làm'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _primaryCta(
            label: tr('Ra món'),
            color: _blue,
            icon: Icons.restaurant,
            onTap: onDone,
          ),
        ),
      ],
    );
  }

  Widget _primaryCta({
    required String label,
    required Color color,
    required VoidCallback? onTap,
    IconData icon = Icons.check,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: FilledButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _dishCard(_KdsAgg a) {
    final voided = a.hits.every((h) => _isVoided(h.item));
    final status = _aggVisualStatus(a);
    final fresh = _aggIsFresh(a);
    final tables = a.tableLabels;
    final noteSample = a.hits
        .map((h) => (h.item.note ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .take(2)
        .join(' · ');
    final sub = tables.length > 1
        ? '${tables.length} ${tr('bàn')}'
        : '${_qtyFmt.format(a.qty)} ${tr('phần')}';
    final late =
        a.hits.any((h) => _itemIsLate(h.item, h.ticket, DateTime.now()));
    return Material(
      color: _statusSoft(status),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: fresh ? _blue : _statusAccent(status).withOpacity(0.18),
          width: fresh ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openAggSheet(a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _qtyBadge(_qtyFmt.format(a.qty), status, fresh: fresh),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                a.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: voided ? _voided : _ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  height: 1.2,
                                  decoration: voided
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            _speakIconBtn(
                              tooltip: tr('Đọc nhóm này'),
                              onTap: () => _speakAgg(a),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: status == 'queued'
                              ? () => unawaited(_aggCook(a))
                              : null,
                          child: _statusBadge(status),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sub,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (noteSample.isNotEmpty)
                          Text(
                            noteSample,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _note,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.table_restaurant_outlined,
                      size: 14, color: _muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      tables.isEmpty ? '—' : tables.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                  Icon(Icons.schedule,
                      size: 14, color: late ? _late : _muted),
                  const SizedBox(width: 4),
                  _KdsTickText(
                    tick: _nowTick,
                    style: TextStyle(
                      color: late ? _late : _muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    builder: (now) => _waitShortAt(a.oldest, now),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (voided)
                _primaryCta(
                  label: tr('Đồng ý'),
                  color: _voided,
                  onTap: () => _ackVoids(
                    [for (final h in a.hits) if (_isVoided(h.item)) h.item.id],
                  ),
                )
              else if (status == 'ready')
                _primaryCta(
                  label: tr('ĐÃ HOÀN THÀNH'),
                  color: _green,
                  onTap: null,
                )
              else
                _prepActions(
                  cooking: status == 'cooking',
                  onCook: () => _aggCook(a),
                  onDone: () => _aggDone(a),
                ),
            ],
          ),
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
        color: _voiceOn ? _blue : _muted,
      ),
    );
  }

  Widget _sideBtn(String label, Color color, VoidCallback onTap) {
    final fg = Colors.white;
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

  void _openAggSheet(_KdsAgg initial) {
    final productName = initial.name;
    if (_voiceOn) _speakAgg(initial);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return ValueListenableBuilder<int>(
          valueListenable: _boardRev,
          builder: (ctx, _, __) {
            final a = _aggByName(productName);
            if (a == null || a.hits.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted && Navigator.of(ctx).canPop()) {
                  Navigator.pop(ctx);
                }
              });
              return const SizedBox(height: 8);
            }
            final hasLive = a.hits.any((h) => !_isVoided(h.item));
            final hasVoid = a.hits.any((h) => _isVoided(h.item));
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
                      color: _line,
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
                        color: _ink,
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
                              color: _ink,
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
                            backgroundColor: _blue,
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
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(tr('Ra món'),
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                if (hasVoid) ...[
                  if (hasLive) const SizedBox(height: 8),
                  Text(tr('Món hủy — Đồng ý từng dòng'),
                      style: const TextStyle(
                          color: _muted, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 12),
                Text(tr('Theo bàn'),
                    style: const TextStyle(
                        color: _muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: a.hits.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: _line),
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
                            color: voided ? _voided : _ink,
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
                                    _miniAct(tr('Ra món'), _ready,
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
      },
    );
  }

  Widget _miniAct(String label, Color color, VoidCallback onTap) {
    final fg = Colors.white;
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: n,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 248,
        ),
        itemCount: _visibleTickets.length,
        itemBuilder: (_, i) => _ticketCard(_visibleTickets[i]),
      );
    });
  }

  String _ticketVisualStatus(_KdsTicket t) {
    if (t.items.isNotEmpty && t.items.every(_isVoided)) return 'voided';
    if (t.items.any((i) => i.status == 'queued')) return 'queued';
    if (t.items.any((i) => i.status == 'cooking')) return 'cooking';
    if (t.items.any((i) => i.status == 'ready' || i.status == 'done')) {
      return 'ready';
    }
    return 'queued';
  }

  Widget _ticketCard(_KdsTicket t) {
    final oldest = t.oldest;
    final allVoided = t.items.isNotEmpty && t.items.every(_isVoided);
    final status = _ticketVisualStatus(t);
    final extra = t.items.length > 4 ? t.items.length - 4 : 0;
    final shown = extra > 0 ? t.items.take(4).toList() : t.items;
    final fresh = t.items.any((i) => _itemIsFresh(i, t));
    final late =
        t.items.any((i) => _itemIsLate(i, t, DateTime.now()));
    return Material(
      color: _statusSoft(status),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: fresh ? _blue : _statusAccent(status).withOpacity(0.18),
          width: fresh ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                _speakIconBtn(
                  tooltip: tr('Đọc bàn này'),
                  onTap: () => _speakTicket(t),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in shown) _itemRow(item, t),
                  if (extra > 0)
                    Text('+ $extra',
                        style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
            ),
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: late ? _late : _muted),
                const SizedBox(width: 4),
                _KdsTickText(
                  tick: _nowTick,
                  style: TextStyle(
                    color: late ? _late : _muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  builder: (now) => _waitShortAt(oldest, now),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (allVoided)
              _primaryCta(
                label: tr('Đồng ý'),
                color: _voided,
                onTap: () => _ackVoids(
                  [for (final i in t.items) if (_isVoided(i)) i.id],
                ),
              )
            else if (status == 'ready')
              _primaryCta(
                label: tr('ĐÃ HOÀN THÀNH'),
                color: _green,
                onTap: null,
              )
            else
              _prepActions(
                cooking: status == 'cooking',
                onCook: () => _setTicketCooking(t),
                onDone: () => _setTicketDone(t),
              ),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(_KdsItem item, _KdsTicket ticket) {
    final sent = item.sentAt ?? ticket.sentAt;
    final voided = _isVoided(item);
    final tone = _toneFor(item.status, sent);
    final note = (item.note ?? '').trim();
    final fresh = _itemIsFresh(item, ticket);
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: fresh
              ? Border.all(color: _freshGlow, width: 1.5)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 52,
              color: tone.bg,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fresh)
                    Text(
                      tr('MỚI'),
                      style: TextStyle(
                        color: tone.fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 8,
                        letterSpacing: 0.4,
                      ),
                    ),
                  Text(
                    _qtyFmt.format(item.qty),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: tone.fg,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      height: 1.05,
                      decoration: voided ? TextDecoration.lineThrough : null,
                      decorationColor: tone.fg,
                      decorationThickness: 2.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: _namePanel,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              softWrap: true,
                              style: TextStyle(
                                color: voided ? _voided : _ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                height: 1.2,
                                decoration: voided
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: _voided,
                                decorationThickness: 2.2,
                              ),
                            ),
                            if (note.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                note,
                                softWrap: true,
                                style: TextStyle(
                                  color: _note,
                                  fontSize: 11,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  decoration: voided
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: _voided,
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
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          builder: (now) => _waitShortAt(sent, now),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
