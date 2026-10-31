import '../../utils/sbox_app_variant.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
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
import '../../services/signalr_service.dart';
import '../../utils/pos_floor_realtime.dart';
import '../../utils/pos_kds_alert.dart';
import '../../utils/pos_kitchen_direct_connect.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_qr_order_voice.dart';
import '../../utils/pos_browser_fullscreen.dart';
import '../../utils/play_system_ui.dart';
import '../../utils/system_ui_inset_mode.dart';
import '../../utils/vietnamese_font.dart';
import '../../utils/navigation_notifier.dart';
import '../../models/hrm.dart' show NotificationType;
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
  /// Giao diện sáng / tối — mỗi máy bếp tự chọn (menu ⋯), lưu trên máy.
  bool _dark = false;
  /// Cỡ chữ cả màn bếp (1.0 thường · 1.2 lớn · 1.4 rất lớn) — bếp đứng xa màn.
  double _textScale = 1.0;
  _KdsPalette get _p => _dark ? _KdsPalette.night : _KdsPalette.day;
  Color get _bg => _p.bg;
  Color get _bar => _p.bar;
  Color get _card => _p.card;
  Color get _line => _p.line;
  Color get _ink => _p.ink;
  Color get _muted => _p.muted;
  Color get _chipIdle => _p.chipIdle;
  Color get _blue => _p.blue;
  Color get _blueSoft => _p.blueSoft;
  Color get _orange => _p.orange;
  Color get _orangeSoft => _p.orangeSoft;
  Color get _green => _p.green;
  Color get _greenSoft => _p.greenSoft;
  Color get _chipOn => _blue;
  Color get _sheet => _p.sheet;
  Color get _ticketHead => _p.ticketHead;
  Color get _accent => _blue;
  Color get _note => _p.note;
  Color get _cooking => _blue;
  Color get _ready => _green;
  Color get _late => _p.late;
  Color get _voided => _p.voided;
  Color get _namePanel => _p.namePanel;
  Color get _freshGlow => _blue;

  final _api = ApiService();
  final _floor = PosFloorRealtimeSubscription(
    debounce: Duration(milliseconds: 250),
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
  StreamSubscription<bool>? _connSub;
  DateTime? _lastTicketsLoadAt;
  final _nowTick = ValueNotifier<DateTime>(DateTime.now());

  @override
  void initState() {
    super.initState();
    PosQrOrderVoiceAlert.instance.enterKds();
    PosKdsAlert.enterUi();
    NotificationOverlayManager().clear();
    unawaited(PosQrOrderVoiceAlert.instance.warmUp());
    unawaited(_ensureSpeakerAudible());
    unawaited(_bootstrap());
    _floor.start((event) {
      if (!mounted) return;
      final reason =
          (event['reason'] ?? event['Reason'] ?? '').toString().toLowerCase();
      // Hàng hóa / HĐ quầy / thiết lập không đổi vé bếp.
      if (PosSyncReasons.notFloor.contains(reason)) return;
      final msg = (event['message'] ?? event['Message'])?.toString();
      unawaited(_loadTickets(
        silent: true,
        pingNew: _kdsShouldAnnounce(event),
        voidMessage: reason == 'kitchenvoid' ? msg : null,
      ));
    });
    // Dự phòng khi mất sự kiện realtime: 8 giây khi SignalR mất kết nối; đang kết nối thì vé mới đã về qua
    // sự kiện → chỉ hỏi lại mỗi 30 giây (trước đây 8 giây/lần dù đang kết nối — mỗi màn bếp ~450 lần/giờ).
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      final last = _lastTicketsLoadAt;
      if (SignalRService().isConnected &&
          last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 30)) {
        return;
      }
      unawaited(_loadTickets(silent: true));
    });
    // Vừa kết nối lại: có thể đã lỡ sự kiện → tải ngay.
    _connSub = SignalRService().onConnectionStateChanged.listen((connected) {
      if (connected && mounted) unawaited(_loadTickets(silent: true));
    });
    _clock = Timer.periodic(Duration(seconds: 1), (_) {
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
    _connSub?.cancel();
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

  /// Máy bếp (T1…) hay để loa ngoài = 0 → đọc món / chuông không ra tiếng. Đang bật đọc món
  /// mà loa tắt hẳn thì nâng lên 60% và báo cho bếp biết.
  Future<void> _ensureSpeakerAudible() async {
    final prefs = await SharedPreferences.getInstance();
    final voice = prefs.getBool(PosKdsAlert.voiceOnKey) ?? true;
    final bell = prefs.getBool(PosKdsAlert.bellBeforeVoiceKey) ?? true;
    if (!voice && !bell) return;
    final st = await PosQrOrderVoiceAlert.instance.audioState();
    if (st == null) return;
    final music = (st['music'] as num?)?.toInt() ?? 1;
    if (music > 0) return;
    final now = await PosQrOrderVoiceAlert.instance.ensureVolume(percent: 60);
    final max = (st['musicMax'] as num?)?.toInt() ?? 0;
    if (!mounted || now == null || now <= 0) return;
    NotificationOverlayManager().showWarning(
      title: 'Loa đang tắt tiếng',
      message: tr('Đã bật loa lên $now/$max để nghe đọc món. Chỉnh bằng nút âm lượng của máy.'),
    );
  }

  Future<void> _testSpeaker() async {
    final st = await PosQrOrderVoiceAlert.instance.audioState();
    var music = (st?['music'] as num?)?.toInt();
    final max = (st?['musicMax'] as num?)?.toInt();
    if (music == 0) {
      music = await PosQrOrderVoiceAlert.instance.ensureVolume(percent: 60);
    }
    await PosKdsAlert.playBell();
    await Future<void>.delayed(Duration(milliseconds: 380));
    await PosQrOrderVoiceAlert.instance.speak('Loa bếp hoạt động. Bàn 1, hai phần bún chả');
    if (!mounted) return;
    final vi = st?['viAvailable'];
    NotificationOverlayManager().show(
      title: 'Thử loa',
      message: tr([
        if (music != null && max != null) 'Âm lượng loa: $music/$max',
        if (vi == false) 'Máy chưa có giọng tiếng Việt — chỉ kêu bíp. Cài «Giọng nói Google» + gói tiếng Việt.',
      ].join(' · ')),
      type: vi == false ? NotificationType.warning : NotificationType.info,
    );
  }

  Future<void> _loadKdsPrintPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _printOnDone = prefs.getBool('pos_kds_print_on_done') ?? false;
    _kdsPrinterId = prefs.getString('pos_kds_printer_id');
    _newestFirst = prefs.getBool('pos_kds_newest_first') ?? false;
    _dark = prefs.getBool('pos_kds_dark') ?? false;
    _textScale = (prefs.getDouble('pos_kds_text_scale') ?? 1.0).clamp(1.0, 1.4);
    // Mặc định mở «Gộp món»; nhớ lựa chọn lần trước trên máy.
    _view = prefs.getString('pos_kds_view') == 'table' ? _KdsView.table : _KdsView.dish;
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
    await prefs.setBool('pos_kds_dark', _dark);
    await prefs.setDouble('pos_kds_text_scale', _textScale);
    await prefs.setString('pos_kds_view', _view == _KdsView.table ? 'table' : 'dish');
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
    if (first) return [];
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
    final until = DateTime.now().add(Duration(seconds: 90));
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
      if (bell) await Future<void>.delayed(Duration(milliseconds: 380));
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
    if (hits.isEmpty) return [];
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
        now.difference(_lastSpeakTap!) < Duration(milliseconds: 900)) {
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

  /// Nền thẻ: trơn (trắng / xám than) cho mọi trạng thái, chỉ món hủy nhạt màu hơn.
  Color _statusSoft(String status) => status == 'voided' ? _chipIdle : _card;

  /// Nền nhạt của màu nhấn (ô số lượng, nhãn trạng thái).
  Color _tint(Color c) => c.withOpacity(_dark ? 0.26 : 0.12);

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
      if (qty <= 0) return SizedBox.shrink();
      return Container(
        margin: EdgeInsets.only(right: 4, bottom: 2),
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _chipIdle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: Text(
          '${_qtyFmt.format(qty)} $label',
          style: TextStyle(
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
    _lastTicketsLoadAt = DateTime.now();
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
    return perm.canCreate('PosKds');
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
        status == 'done' ? _hitsForIds(ids) : <_KdsHit>[];
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
    if (d.inHours >= 24) return '${d.inDays} ${tr('ngày')}';
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
        // ThemeData mới không kế thừa font app → giữ Be Vietnam Pro như các màn khác.
        fontFamily: kVietnameseFontFamily,
        fontFamilyFallback: kVietnameseFontFallback,
        brightness: _dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: _bg,
        colorScheme: (_dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
          primary: _blue,
          secondary: _orange,
          surface: _card,
          onSurface: _ink,
        ),
        dividerColor: _line,
        popupMenuTheme: PopupMenuThemeData(
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
      // Cỡ chữ riêng cho bếp (đứng xa màn) — áp cho cả bảng, không đổi cỡ chữ máy.
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_textScale)),
        child: Column(
          children: [
            _buildHeader(pushed, aggs),
            _buildFilters(),
            Expanded(child: _buildBody(aggs)),
          ],
        ),
      ),
    ),
    );
  }

  /// Thanh đầu một hàng: ← BẾP · Gộp món|Theo bàn · trạm ▾ · Chờ / Đang làm / Trễ · giờ · Đã xong · loa · máy in · ⋯
  Widget _buildHeader(bool pushed, List<_KdsAgg> aggs) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    double qtyWhere(bool Function(_KdsItem i, _KdsTicket t) test) {
      var q = 0.0;
      for (final t in _tickets) {
        for (final i in t.items) {
          if (test(i, t)) q += i.qty;
        }
      }
      return q;
    }

    final queuedN = qtyWhere((i, _) => _itemIsQueued(i));
    final cookingN = qtyWhere((i, _) => i.status == 'cooking');
    final lateN = _lateCount;
    return Material(
      color: _bar,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
        child: SafeArea(
          top: !_isKdsFullscreen,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                if (pushed)
                  IconButton(
                    tooltip: tr('Quay lại'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: _ink),
                  ),
                Icon(Icons.soup_kitchen, color: _blue, size: narrow ? 22 : 28),
                if (!narrow) ...[
                  const SizedBox(width: 6),
                  Text(
                    tr('BẾP'),
                    style: TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      letterSpacing: 0.4,
                      height: 1,
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                _viewToggle(compact: narrow),
                const SizedBox(width: 8),
                _stationPicker(compact: narrow),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Đếm theo PHẦN (1+1+3=5) — ghi rõ để khỏi lẫn với số món ở hàng lọc «Chờ làm (3)».
                        _countPill(tr('phần chờ'), queuedN, _orange,
                            on: _statusFilter == 'queued',
                            onTap: () => setState(() => _statusFilter =
                                _statusFilter == 'queued' ? null : 'queued')),
                        _countPill(tr('phần đang làm'), cookingN, _blue,
                            on: _statusFilter == 'cooking',
                            onTap: () => setState(() => _statusFilter =
                                _statusFilter == 'cooking' ? null : 'cooking')),
                        _countPill(tr('Trễ'), lateN.toDouble(), _late,
                            on: _lateOnly,
                            onTap: () => setState(() => _lateOnly = !_lateOnly)),
                        if (aggs.isNotEmpty && !narrow)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, right: 8),
                            child: _statIcon(Icons.table_restaurant_outlined,
                                '${_tickets.length} ${tr('bàn')} · ${aggs.length} ${tr('món')}'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!narrow)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _KdsTickText(
                          tick: _nowTick,
                          style: TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                            height: 1.1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          builder: (n) => _clockFmt.format(n),
                        ),
                        _KdsTickText(
                          tick: _nowTick,
                          style: TextStyle(color: _muted, fontWeight: FontWeight.w600, fontSize: 11),
                          builder: (n) => _dateLabel(n),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  tooltip: tr('Đã xong gần đây · gọi lại'),
                  onPressed: () => unawaited(_openRecentDone()),
                  icon: Icon(Icons.history, color: _ink),
                ),
                if (!narrow) ...[
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
                ],
                _headerMenu(narrow: narrow),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _countPill(String label, double qty, Color color,
      {required bool on, required VoidCallback onTap}) {
    final has = qty > 0;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? color : (has ? color.withOpacity(_dark ? 0.22 : 0.12) : _chipIdle),
        shape: StadiumBorder(side: BorderSide(color: has ? color : _line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: _qtyFmt.format(qty),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                TextSpan(text: '  $label', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
              style: TextStyle(color: on ? Colors.white : (has ? color : _muted)),
            ),
          ),
        ),
      ),
    );
  }

  /// Chọn trạm bếp (theo máy in bếp của món) — dropdown thay hàng chip dài bị cắt chữ.
  Widget _stationPicker({bool compact = false}) {
    if (_stations.isEmpty) return const SizedBox.shrink();
    final current = _stations.where((s) => s.id == _stationId).firstOrNull;
    return PopupMenuButton<String>(
      tooltip: tr('Trạm bếp'),
      color: _sheet,
      onSelected: (v) {
        setState(() {
          _stationId = v.isEmpty ? null : v;
          _voiceSeeded = false;
          _announcedMaxQty.clear();
        });
        unawaited(_loadTickets());
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: '',
          checked: _stationId == null,
          child: Text(tr('Tất cả trạm'), style: TextStyle(color: _ink)),
        ),
        for (final s in _stations)
          CheckedPopupMenuItem(
            value: s.id,
            checked: _stationId == s.id,
            child: Text(s.name, style: TextStyle(color: _ink)),
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 8),
        decoration: BoxDecoration(
          color: current == null ? _chipIdle : _blueSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: current == null ? _line : _blue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.outdoor_grill_outlined, size: 18, color: current == null ? _muted : _blue),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 90 : 170),
              child: Text(
                current?.name ?? tr('Tất cả trạm'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: _muted),
          ],
        ),
      ),
    );
  }

  Widget _headerMenu({required bool narrow}) {
    return PopupMenuButton<String>(
      tooltip: tr('Thêm'),
      color: _sheet,
      icon: Icon(Icons.more_vert, color: _muted),
      onSelected: (v) async {
        switch (v) {
          case 'pos_settings':
            SettingsHubScreen.pendingSubIndex.value = null;
            if (NavigationNotifier.mainLayoutReady.value) {
              NavigationNotifier.navigateToModule.value = 'SettingsHub';
            } else if (mounted) {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SettingsHubScreen()),
              );
            }
          case 'kds_print':
            unawaited(_openKdsPrintSettings());
          case 'voice_toggle':
            _toggleVoice();
          case 'speak':
            unawaited(_speakPending());
          case 'voice_settings':
            unawaited(PosQrOrderVoiceAlert.instance.showSettingsSheet(context));
          case 'fullscreen':
            unawaited(_toggleKdsFullscreen());
          case 'theme':
            setState(() => _dark = !_dark);
            unawaited(_saveKdsPrintPrefs());
          case 'text_scale':
            setState(() => _textScale = _textScale >= 1.35 ? 1.0 : (_textScale >= 1.15 ? 1.4 : 1.2));
            unawaited(_saveKdsPrintPrefs());
          case 'sort':
            setState(() => _newestFirst = !_newestFirst);
            unawaited(_saveKdsPrintPrefs());
            unawaited(_loadTickets(silent: true));
          case 'logout':
            await showPosLogoutDialog(context);
        }
      },
      itemBuilder: (_) {
        PopupMenuItem<String> item(String v, IconData icon, String label) => PopupMenuItem(
              value: v,
              child: Row(children: [
                Icon(icon, size: 20, color: _muted),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(color: _ink))),
              ]),
            );
        final scaleLabel = _textScale >= 1.35
            ? tr('Cỡ chữ: rất lớn')
            : _textScale >= 1.15
                ? tr('Cỡ chữ: lớn')
                : tr('Cỡ chữ: thường');
        return [
          item('theme', _dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              tr(_dark ? 'Giao diện sáng' : 'Giao diện tối')),
          item('text_scale', Icons.format_size, scaleLabel),
          item('sort', Icons.swap_vert, tr(_newestFirst ? 'Xếp: mới nhất trước' : 'Xếp: lâu nhất trước')),
          item('fullscreen', _isKdsFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              tr(_isKdsFullscreen ? 'Thu nhỏ' : 'Phóng toàn màn hình')),
          const PopupMenuDivider(),
          if (narrow) item('speak', Icons.campaign_outlined, tr('Đọc món cần chế biến')),
          item('voice_toggle', _voiceOn ? Icons.volume_off_outlined : Icons.volume_up_outlined,
              tr(_voiceOn ? 'Tắt loa tự đọc' : 'Bật loa tự đọc')),
          item('voice_settings', Icons.record_voice_over_outlined, tr('Chọn giọng và tốc độ')),
          item('kds_print', Icons.print_outlined, tr('Máy in KDS · âm thanh')),
          const PopupMenuDivider(),
          item('pos_settings', Icons.tune, tr('Thiết lập SBOX')),
          // App SBOX KDS không có hub «Nhiều hơn» → đăng xuất ở đây.
          if (kSboxKdsApp) item('logout', Icons.logout, tr('Đăng xuất')),
        ];
      },
    );
  }

  /// Vé đã ra món trong 6 giờ — bấm «Gọi lại» đưa cả vé về bảng bếp (bấm nhầm Ra món).
  Future<void> _openRecentDone() async {
    var res = await _api.getPosKdsRecentDone(printerId: _stationId);
    if (!mounted) return;
    var orders = (res['data'] is Map ? (res['data']['orders'] as List?) : null) ?? const [];
    final timeFmt = DateFormat('HH:mm');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> recall(String orderId) async {
          if (!_canKdsAct()) {
            _denyKdsAct();
            return;
          }
          final r = await _api.recallPosKdsTicket(orderId);
          if (r['isSuccess'] != true) {
            NotificationOverlayManager().showError(
              title: 'Gọi lại',
              message: r['message']?.toString() ?? 'Không gọi lại được',
              relatedEntityType: kPosKdsNotifyKind,
            );
            return;
          }
          await _loadTickets(silent: true);
          res = await _api.getPosKdsRecentDone(printerId: _stationId);
          orders = (res['data'] is Map ? (res['data']['orders'] as List?) : null) ?? const [];
          if (ctx.mounted) setLocal(() {});
        }

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(children: [
                    Icon(Icons.history, color: _blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr('Đã ra món · 6 giờ gần nhất'),
                          style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: _muted),
                    ),
                  ]),
                ),
                Divider(height: 1, color: _line),
                Expanded(
                  child: orders.isEmpty
                      ? Center(
                          child: Text(
                            res['isSuccess'] == true
                                ? tr('Chưa có vé nào ra món trong 6 giờ qua')
                                : (res['message']?.toString() ?? tr('Không tải được')),
                            style: TextStyle(color: _muted, fontSize: 16),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: orders.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: _line),
                          itemBuilder: (_, i) {
                            final o = Map<String, dynamic>.from(orders[i] as Map);
                            final table = (o['tableName'] ?? '').toString().trim();
                            final area = (o['areaName'] ?? '').toString().trim();
                            final title = [
                              if (table.isNotEmpty) table else (o['orderNo'] ?? '').toString(),
                              if (area.isNotEmpty) area,
                            ].join(' · ');
                            final at = DateTime.tryParse((o['doneAt'] ?? '').toString())?.toLocal();
                            final items = ((o['items'] as List?) ?? const [])
                                .whereType<Map>()
                                .map((e) => '${_qtyFmt.format((e['qty'] as num?) ?? 0)} ${e['productName']}')
                                .join(' · ');
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 6),
                              title: Text(title, style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 16)),
                              subtitle: Text(
                                [
                                  if (at != null)
                                    '${tr('Xong lúc')} ${timeFmt.format(at)} (${_waitShortAt(at, DateTime.now())} ${tr('trước')})',
                                  items,
                                ].join('\n'),
                                style: TextStyle(color: _muted, height: 1.35),
                              ),
                              trailing: OutlinedButton.icon(
                                onPressed: _busy ? null : () => unawaited(recall('${o['orderId']}')),
                                icon: Icon(Icons.undo, color: _orange, size: 18),
                                label: Text(tr('Gọi lại'), style: TextStyle(color: _orange, fontWeight: FontWeight.w700)),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  side: BorderSide(color: _orange),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// Màu đầu thẻ theo thời gian chờ món chưa làm: xanh < 5 phút, vàng tới ngưỡng trễ, đỏ khi trễ.
  Color _waitStripe(DateTime oldest, {required bool allDone, required bool voided}) {
    if (voided) return _voided;
    if (allDone) return _green;
    final m = _waitAt(oldest, DateTime.now()).inMinutes;
    if (m >= _lateMinutes) return _late;
    if (m >= 5) return _orange;
    return _green;
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

  Widget _statIcon(IconData icon, String text, {Color? color}) {
    color ??= _muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        SizedBox(width: 4),
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

  Widget _viewToggle({bool compact = false}) {
    Widget tab(String label, _KdsView v) {
      final on = _view == v;
      return InkWell(
        onTap: () {
          setState(() => _view = v);
          unawaited(_saveKdsPrintPrefs());
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16, vertical: compact ? 7 : 9),
          decoration: BoxDecoration(
            color: on ? _chipOn : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? Colors.white : _ink,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 13 : 14,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _chipIdle,
        borderRadius: BorderRadius.circular(14),
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
    int countOf(String? f) {
      if (_view == _KdsView.dish) {
        return f == null ? _aggregates.length : _aggregates.where((a) => _aggVisualStatus(a) == f).length;
      }
      if (f == null) return _scopedTickets.length;
      return _scopedTickets.where((t) => t.items.any((i) {
            if (_isVoided(i)) return f == 'voided';
            final s = i.status == 'done' ? 'ready' : i.status;
            return s == f;
          })).length;
    }

    String withN(String label, int n) => n > 0 ? '$label ($n)' : label;
    return Material(
      color: _bar,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _toneChip(withN(tr('Tất cả'), countOf(null)), null, _blue, _blueSoft),
            _toneChip(withN(tr('Chờ làm'), countOf('queued')), 'queued', _orange, _orangeSoft),
            _toneChip(withN(tr('Đang làm'), countOf('cooking')), 'cooking', _blue, _blueSoft),
            _toneChip(withN(tr('Làm xong'), countOf('ready')), 'ready', _green, _greenSoft),
            const SizedBox(width: 12),
            _filterChip(
              lateN > 0 ? '${tr('Trễ')} ($lateN)' : tr('Trễ'),
              _lateOnly,
              () => setState(() => _lateOnly = !_lateOnly),
              accent: _late,
            ),
            _filterChip(
              noDishN > 0 ? '${tr('Bàn chưa có món')} ($noDishN)' : tr('Bàn chưa có món'),
              _noDishTables,
              () => setState(() {
                _noDishTables = !_noDishTables;
                if (_noDishTables) _view = _KdsView.table;
              }),
            ),
            if (_lastBumpedOrderId != null)
              _filterChip(tr('↶ Gọi lại vé vừa ra'), false, () => unawaited(_recall()), accent: _orange),
          ]),
        ),
      ),
      ),
    );
  }

  Widget _toneChip(String label, String? value, Color accent, Color soft) {
    final on = _statusFilter == value;
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: Material(
        color: on ? accent : soft,
        shape: StadiumBorder(),
        child: InkWell(
          customBorder: StadiumBorder(),
          onTap: () => setState(() => _statusFilter = value),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  Widget _filterChip(String label, bool on, VoidCallback tap,
      {Color? accent}) {
    accent ??= _blue;
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: Material(
        color: on ? accent : _chipIdle,
        shape: StadiumBorder(
          side: BorderSide(
            color: on ? accent : _line,
          ),
        ),
        child: InkWell(
          customBorder: StadiumBorder(),
          onTap: tap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _line,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Text(tr('Máy in KDS'),
                      style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 18)),
                  SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Đọc món cần chế biến'),
                        style: TextStyle(color: _ink)),
                    subtitle: Text(
                      tr('Tự đọc món mới. Chạm loa trên cột Đang làm / Xong để đọc lại. Nút chỉnh giọng để chọn giọng mượt và tốc độ.'),
                      style: TextStyle(color: _muted),
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
                        style: TextStyle(color: _ink)),
                    subtitle: Text(
                      tr('Kêu 1 tiếng chuông, rồi mới đọc tên món / số lượng.'),
                      style: TextStyle(color: _muted),
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
                        style: TextStyle(color: _ink)),
                    subtitle: Text(
                      tr('Máy bếp / Print Agent kêu ting khi nhận lệnh in phiếu bếp.'),
                      style: TextStyle(color: _muted),
                    ),
                    value: _printTingOn,
                    onChanged: (v) {
                      setLocal(() => _printTingOn = v);
                      setState(() => _printTingOn = v);
                      unawaited(_saveKdsPrintPrefs());
                    },
                  ),
                  SizedBox(height: 4),
                  Text(tr('Báo trễ món'),
                      style: TextStyle(
                          color: _ink, fontWeight: FontWeight.w700)),
                  Text(
                    tr('Chưa nhấn Đang làm quá số phút này thì tính là trễ.'),
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  SizedBox(height: 8),
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
                        icon: Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '$_lateMinutes ${tr('phút')}',
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
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
                        icon: Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final m in [5, 10, 15, 20, 30])
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
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          unawaited(
                            PosQrOrderVoiceAlert.instance.showSettingsSheet(context),
                          );
                        },
                        icon: Icon(Icons.tune, color: _accent),
                        label: Text(tr('Chọn giọng và tốc độ'),
                            style: TextStyle(color: _accent)),
                      ),
                      TextButton.icon(
                        onPressed: () => unawaited(_testSpeaker()),
                        icon: Icon(Icons.campaign_outlined, color: _accent),
                        label: Text(tr('Thử loa'),
                            style: TextStyle(color: _accent)),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('In phiếu khi bấm Ra món'),
                        style: TextStyle(color: _ink)),
                    subtitle: Text(
                      tr('In rồi tự gỡ món khỏi bảng bếp'),
                      style: TextStyle(color: _muted),
                    ),
                    value: _printOnDone,
                    onChanged: (v) {
                      setLocal(() => _printOnDone = v);
                      setState(() => _printOnDone = v);
                      unawaited(_saveKdsPrintPrefs());
                    },
                  ),
                  SizedBox(height: 6),
                  Text(tr('Thêm máy in bếp trên máy này'),
                      style: TextStyle(
                          color: _ink, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
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
                          icon: Icon(Icons.usb, size: 18),
                          label: Text(tr('USB nội bộ')),
                        ),
                      ),
                      SizedBox(width: 8),
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
                          icon: Icon(Icons.wifi, size: 18),
                          label: Text(tr('LAN / WiFi')),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  // Máy Sunmi (T1 / T2 / V2s / K2) có máy in nhiệt gắn liền — in phiếu bếp ngay trên máy.
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final saved =
                          await PosKitchenDirectConnect.connectSunmi(context);
                      if (saved == null || !mounted) return;
                      await _loadKdsPrintPrefs();
                      final id = (saved.storePrinterId ?? saved.id).trim();
                      if (id.isNotEmpty) _kdsPrinterId = id;
                      if (mounted) setState(() {});
                      unawaited(_saveKdsPrintPrefs());
                    },
                    icon: Icon(Icons.print_outlined, size: 18),
                    label: Text(tr('Máy in Sunmi gắn trên máy')),
                  ),
                  SizedBox(height: 10),
                  Text(tr('Kết nối máy in'),
                      style: TextStyle(
                          color: _ink, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  if (_kdsPrinters.isEmpty)
                    Text(
                      tr('Chưa có máy bếp trên thiết bị này. Kết nối USB / LAN / Sunmi nội bộ, hoặc chọn máy đã chia sẻ Agent.'),
                      style: TextStyle(color: _muted),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      value: _kdsPrinters.any((p) => p.id == _kdsPrinterId)
                          ? _kdsPrinterId
                          : null,
                      hint: Text(tr('Chọn máy in bếp'),
                          style: TextStyle(color: _muted)),
                      dropdownColor: _sheet,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _chipIdle,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in _kdsPrinters)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              '${p.name}${p.isDeviceLocal ? (p.isSunmi ? ' · Sunmi trên máy' : ' · USB/LAN nội bộ') : ''}',
                              style: TextStyle(color: _ink),
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
      return Center(
          child: CircularProgressIndicator(color: _chipOn));
    }
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: TextStyle(color: Colors.redAccent)));
    }
    if (_tickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_outlined,
                size: 56, color: _muted),
            SizedBox(height: 12),
            Text(
              tr('Chưa có món báo bếp'),
              style: TextStyle(color: _muted, fontSize: 18),
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
        child: Text(msg, style: TextStyle(color: _muted, fontSize: 16)),
      );
    }
    return Stack(
      children: [
        _view == _KdsView.dish ? _buildDishGrid(aggs) : _buildTableGrid(),
        if (_busy)
          Positioned(
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
      // Chữ lớn → thẻ to hơn, ít cột hơn (không tràn chữ).
      final n = (c.maxWidth / (260 * _textScale)).floor().clamp(1, 7);
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: n,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 206 * _textScale,
        ),
        itemCount: aggs.length,
        itemBuilder: (_, i) => _dishCard(aggs[i]),
      );
    });
  }

  Widget _statusBadge(String status) {
    final accent = _statusAccent(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _tint(accent),
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
        color: _tint(_statusAccent(status)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (fresh)
            Text(
              tr('MỚI'),
              style: TextStyle(
                color: _statusAccent(status),
                fontWeight: FontWeight.w800,
                fontSize: 7,
                height: 1,
              ),
            ),
          Text(
            qty,
            style: TextStyle(
              color: _statusAccent(status),
              fontWeight: FontWeight.w700,
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
              onPressed: _busy || cooking ? null : onCook,
              // Nút phụ nhưng phải rõ: nền nhạt + viền / chữ màu trạng thái (Chờ làm = hổ phách).
              style: FilledButton.styleFrom(
                backgroundColor: _tint(_orange),
                foregroundColor: _orange,
                disabledBackgroundColor: _tint(_blue),
                disabledForegroundColor: _blue,
                side: BorderSide(color: (cooking ? _blue : _orange).withOpacity(0.75), width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                tr(cooking ? 'Đang làm…' : 'Bắt đầu làm'),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _primaryCta(
            label: tr('Ra món'),
            color: _green,
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
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    // Combo gộp nhiều bàn: cộng món con (5 combo → «5 Trà sữa · 5 Nem rán») — bếp làm theo món con.
    final parts = <String, double>{};
    for (final h in a.hits) {
      for (final c in h.item.components) {
        parts[c.name] = (parts[c.name] ?? 0) + c.qty;
      }
    }
    final partsText = parts.entries.map((e) => '${_qtyFmt.format(e.value)} ${e.key}').join(' · ');
    final late =
        a.hits.any((h) => _itemIsLate(h.item, h.ticket, DateTime.now()));
    final stripe = _waitStripe(a.oldest, allDone: status == 'ready', voided: voided);
    return Material(
      color: _statusSoft(status),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: fresh ? _blue : (late ? _late.withOpacity(0.55) : _line),
          width: fresh || late ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openAggSheet(a),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: stripe, width: 4))),
          child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _qtyBadge(_qtyFmt.format(a.qty), status, fresh: fresh),
                  SizedBox(width: 10),
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
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
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
                        SizedBox(height: 4),
                        GestureDetector(
                          onTap: status == 'queued'
                              ? () => unawaited(_aggCook(a))
                              : null,
                          child: _statusBadge(status),
                        ),
                        SizedBox(height: 4),
                        Text(
                          sub,
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (partsText.isNotEmpty)
                          Text(
                            '• $partsText',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (noteSample.isNotEmpty)
                          Text(
                            noteSample,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
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
              Spacer(),
              Row(
                children: [
                  Icon(Icons.table_restaurant_outlined,
                      size: 14, color: _muted),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      tables.isEmpty ? '—' : tables.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                  Icon(Icons.schedule,
                      size: 14, color: late ? _late : _muted),
                  SizedBox(width: 4),
                  _KdsTickText(
                    tick: _nowTick,
                    style: TextStyle(
                      color: late ? _late : _muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    builder: (now) => _waitShortAt(a.oldest, now),
                  ),
                ],
              ),
              SizedBox(height: 8),
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
      ),
    );
  }

  Widget _speakIconBtn(
      {required String tooltip, required VoidCallback onTap}) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
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
              fontWeight: FontWeight.w700,
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
      shape: RoundedRectangleBorder(
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
              return SizedBox(height: 8);
            }
            final hasLive = a.hits.any((h) => !_isVoided(h.item));
            final hasVoid = a.hits.any((h) => _isVoided(h.item));
            final c = _aggAccent(a);
            return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      _qtyFmt.format(a.qty),
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 36,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.name,
                            style: TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                          ),
                          _KdsTickText(
                            tick: _nowTick,
                            style: TextStyle(color: c, fontWeight: FontWeight.w700),
                            builder: (now) =>
                                '${tr('Chờ')} ${_waitShortAt(a.oldest, now)}',
                          ),
                          SizedBox(height: 6),
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
                SizedBox(height: 12),
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
                            padding: EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(tr('Đang làm'),
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            unawaited(_aggDone(a));
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(tr('Ra món'),
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                if (hasVoid) ...[
                  if (hasLive) SizedBox(height: 8),
                  Text(tr('Món hủy — Đồng ý từng dòng'),
                      style: TextStyle(
                          color: _muted, fontWeight: FontWeight.w700)),
                ],
                SizedBox(height: 12),
                Text(tr('Theo bàn'),
                    style: TextStyle(
                        color: _muted, fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: a.hits.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: _line),
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
                            if (h.item.components.isNotEmpty)
                              h.item.components.map((c) => '${_qtyFmt.format(c.qty)} ${c.name}').join(', '),
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
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildTableGrid() {
    return LayoutBuilder(builder: (context, c) {
      final n = (c.maxWidth / (290 * _textScale)).floor().clamp(1, 7);
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: n,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 290 * _textScale,
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
    final late = t.items.any((i) => _itemIsLate(i, t, DateTime.now()));
    final stripe = _waitStripe(oldest, allDone: status == 'ready', voided: allVoided);
    final area = (t.areaName ?? '').trim();
    return Material(
      color: _statusSoft(status),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: fresh ? _blue : (late ? _late.withOpacity(0.55) : _line),
          width: fresh || late ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Đầu thẻ đổi màu theo thời gian chờ: bàn · khu · số phút — nhìn từ xa biết bàn nào gấp.
          Container(
            decoration: BoxDecoration(
              color: _ticketHead,
              border: Border(
                left: BorderSide(color: stripe, width: 5),
                bottom: BorderSide(color: _line),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  [t.title, if (area.isNotEmpty && !t.title.contains(area)) area].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _tint(stripe), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.schedule, size: 14, color: stripe),
                  const SizedBox(width: 4),
                  _KdsTickText(
                    tick: _nowTick,
                    style: TextStyle(
                      color: stripe,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    builder: (now) => _waitShortAt(oldest, now),
                  ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [if ((t.orderNo ?? '').isNotEmpty) t.orderNo!, if ((t.channel ?? '').trim().isNotEmpty) t.channel!.trim()].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
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
                        style: TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(height: 8),
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
        margin: EdgeInsets.symmetric(vertical: 3),
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
              color: _tint(tone.bg),
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fresh)
                    Text(
                      tr('MỚI'),
                      style: TextStyle(
                        color: tone.bg,
                        fontWeight: FontWeight.w700,
                        fontSize: 8,
                        letterSpacing: 0.4,
                      ),
                    ),
                  Text(
                    _qtyFmt.format(item.qty),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: tone.bg,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      height: 1.05,
                      decoration: voided ? TextDecoration.lineThrough : null,
                      decorationColor: tone.bg,
                      decorationThickness: 2.2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: _namePanel,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(8, 6, 8, 6),
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
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                height: 1.2,
                                decoration: voided
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: _voided,
                                decorationThickness: 2.2,
                              ),
                            ),
                            for (final c in item.components)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(
                                  '• ${_qtyFmt.format(c.qty)} ${c.name}',
                                  softWrap: true,
                                  style: TextStyle(
                                    color: voided ? _voided : _ink,
                                    fontSize: 12.5,
                                    height: 1.25,
                                    fontWeight: FontWeight.w600,
                                    decoration: voided ? TextDecoration.lineThrough : null,
                                    decorationColor: _voided,
                                  ),
                                ),
                              ),
                            if (note.isNotEmpty) ...[
                              SizedBox(height: 2),
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
                      SizedBox(width: 6),
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
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
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
    this.components = const [],
  });
  final String id;
  final String productId;
  final String productName;
  final double qty;
  final double sentQty;
  final String status;
  final String? note;
  final DateTime? sentAt;

  /// Món bên trong combo (SL đã nhân số combo) — trước vé chỉ ghi tên combo, bếp không biết làm gì.
  final List<({String name, double qty})> components;

  factory _KdsItem.fromJson(Map<String, dynamic> j) {
    final q = j['qty'] ?? j['Qty'] ?? 0;
    final sentQ = j['sentQty'] ?? j['SentQty'] ?? q;
    final sentRaw = j['sentAt'] ?? j['SentAt'];
    final comps = <({String name, double qty})>[];
    for (final c in (j['components'] ?? j['Components'] ?? const []) as List) {
      if (c is! Map) continue;
      final cq = c['qty'] ?? c['Qty'] ?? 0;
      final name = (c['name'] ?? c['Name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      comps.add((name: name, qty: cq is num ? cq.toDouble() : double.tryParse('$cq') ?? 0));
    }
    return _KdsItem(
      components: comps,
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


/// Bảng màu KDS: sáng (mặc định) / tối (bếp tối, đỡ chói).
class _KdsPalette {
  const _KdsPalette({
    required this.bg,
    required this.bar,
    required this.card,
    required this.line,
    required this.ink,
    required this.muted,
    required this.chipIdle,
    required this.blue,
    required this.blueSoft,
    required this.orange,
    required this.orangeSoft,
    required this.green,
    required this.greenSoft,
    required this.sheet,
    required this.ticketHead,
    required this.note,
    required this.late,
    required this.voided,
    required this.namePanel,
  });

  final Color bg, bar, card, line, ink, muted, chipIdle, blue, blueSoft, orange, orangeSoft;
  final Color green, greenSoft, sheet, ticketHead, note, late, voided, namePanel;

  static const day = _KdsPalette(
    bg: Color(0xFFF3F4F6),
    bar: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFE4E7EC),
    ink: Color(0xFF111827),
    muted: Color(0xFF6B7280),
    chipIdle: Color(0xFFF2F4F7),
    blue: Color(0xFF1F6FA3),
    blueSoft: Color(0xFFEAF2F8),
    orange: Color(0xFFB7791F),
    orangeSoft: Color(0xFFFBF3E4),
    green: Color(0xFF15803D),
    greenSoft: Color(0xFFE8F5EC),
    sheet: Color(0xFFFFFFFF),
    ticketHead: Color(0xFFF9FAFB),
    note: Color(0xFF4B5563),
    late: Color(0xFFC0392B),
    voided: Color(0xFF9CA3AF),
    namePanel: Color(0xFFF9FAFB),
  );

  static const night = _KdsPalette(
    bg: Color(0xFF0F1115),
    bar: Color(0xFF15181D),
    card: Color(0xFF1B1F25),
    line: Color(0xFF2B3139),
    ink: Color(0xFFE9ECF0),
    muted: Color(0xFF8A93A0),
    chipIdle: Color(0xFF232830),
    blue: Color(0xFF5BA4D4),
    blueSoft: Color(0xFF182A38),
    orange: Color(0xFFD9A048),
    orangeSoft: Color(0xFF2C2416),
    green: Color(0xFF2F9E66),
    greenSoft: Color(0xFF16291F),
    sheet: Color(0xFF1B1F25),
    ticketHead: Color(0xFF1B1F25),
    note: Color(0xFFB5BDC8),
    late: Color(0xFFE5766B),
    voided: Color(0xFF5E6672),
    namePanel: Color(0xFF15181D),
  );
}
