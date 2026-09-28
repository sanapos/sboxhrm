import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/page_top_actions.dart';
import 'staff_map_ui.dart';

/// Bản đồ nhân sự: vị trí của tất cả nhân viên (trực tuyến / vừa mất tín hiệu / ngoại tuyến / chưa có vị trí),
/// nơi làm việc và lộ trình di chuyển trong ca của từng người (đường đi, điểm dừng, chấm công, check-in, tua lại).
class StaffMapScreen extends StatefulWidget {
  const StaffMapScreen({super.key});

  @override
  State<StaffMapScreen> createState() => _StaffMapScreenState();
}

class _StaffMapScreenState extends State<StaffMapScreen> {
  final _api = ApiService();
  final _map = MapController();
  final _searchCtl = TextEditingController();
  bool _mapReady = false;

  // ── Trực tiếp ──
  Map<String, dynamic>? _live;
  bool _loading = true;
  String? _error;
  Timer? _refresh;
  DateTime? _refreshedAt;
  String _status = 'all';
  String? _department;
  String? _focusId;
  bool _fittedOnce = false;

  // ── Lộ trình ──
  Map<String, dynamic>? _routeEmp;
  Map<String, dynamic>? _route;
  bool _routeLoading = false;
  DateTime _routeDate = DateTime.now();
  String _routeWindow = 'shift'; // shift | day | <shiftId>
  double _playback = 1; // 0..1
  Timer? _playTimer;

  bool get _routeMode => _routeEmp != null;

  @override
  void initState() {
    super.initState();
    _loadLive();
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_routeMode) _loadLive(silent: true);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _playTimer?.cancel();
    _searchCtl.dispose();
    _map.dispose();
    super.dispose();
  }

  // ═════════════ DỮ LIỆU ═════════════

  List<Map<String, dynamic>> _rows(dynamic v) => [
        for (final x in (v as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];

  Future<void> _loadLive({bool silent = false}) async {
    if (!silent) setState(() => _loading = _live == null);
    final res = await _api.getStaffMapLive();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true) {
        _live = res['data'] as Map<String, dynamic>?;
        _error = null;
        _refreshedAt = DateTime.now();
      } else if (!silent) {
        _error = res['message']?.toString() ?? 'Không tải được vị trí nhân viên';
      }
    });
    if (!_fittedOnce && _live != null) {
      _fittedOnce = true;
      _fitLive();
    }
  }

  Future<void> _openRoute(Map<String, dynamic> e, {DateTime? date}) async {
    _playTimer?.cancel();
    setState(() {
      _routeEmp = e;
      _routeDate = date ?? DateTime.now();
      _routeWindow = 'shift';
      _route = null;
      _playback = 1;
    });
    await _loadRoute();
  }

  Future<void> _loadRoute() async {
    final e = _routeEmp;
    if (e == null) return;
    _playTimer?.cancel();
    setState(() => _routeLoading = true);
    final res = await _api.getStaffRoute(
      employeeId: e['employeeId'].toString(),
      date: _routeDate,
      shiftId: _routeWindow == 'shift' || _routeWindow == 'day' ? null : _routeWindow,
      wholeDay: _routeWindow == 'day',
    );
    if (!mounted) return;
    setState(() {
      _routeLoading = false;
      _playback = 1;
      _route = res['isSuccess'] == true ? res['data'] as Map<String, dynamic>? : null;
      if (res['isSuccess'] != true) _error = res['message']?.toString();
    });
    _fitRoute();
  }

  void _closeRoute() {
    _playTimer?.cancel();
    setState(() {
      _routeEmp = null;
      _route = null;
    });
    _loadLive(silent: true);
    _fitLive();
  }

  // ═════════════ LỌC ═════════════

  List<Map<String, dynamic>> get _all => _rows(_live?['employees']);

  bool _matchStatus(Map<String, dynamic> e) => switch (_status) {
        'online' || 'stale' || 'offline' || 'none' => e['status'] == _status,
        'onShift' => e['onShift'] == true,
        'lost' => e['signalLostOnShift'] == true,
        _ => true,
      };

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtl.text.trim().toLowerCase();
    return _all.where((e) {
      if (!_matchStatus(e)) return false;
      if (_department != null && e['department'] != _department) return false;
      if (q.isEmpty) return true;
      return [e['employeeName'], e['employeeCode'], e['department'], e['position']]
          .any((x) => (x?.toString() ?? '').toLowerCase().contains(q));
    }).toList();
  }

  LatLng? _pos(Map<String, dynamic> e) {
    final lat = e['latitude'], lng = e['longitude'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  // ═════════════ CAMERA ═════════════

  void _fit(List<LatLng> pts, {double padding = 60}) {
    if (pts.isEmpty || !_mapReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (pts.length == 1) {
          _map.move(pts.first, 16);
        } else {
          _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: EdgeInsets.all(padding)));
        }
      } catch (_) {}
    });
  }

  void _fitLive() {
    final pts = _filtered.map(_pos).whereType<LatLng>().toList();
    if (pts.isEmpty) {
      pts.addAll(_rows(_live?['workLocations']).map((w) => LatLng(StaffMapUi.n(w['latitude']).toDouble(), StaffMapUi.n(w['longitude']).toDouble())));
    }
    _fit(pts);
  }

  void _fitRoute() {
    final pts = _routePoints;
    if (pts.isNotEmpty) _fit(pts, padding: 70);
  }

  void _focus(LatLng p, {double zoom = 17}) {
    if (!_mapReady) return;
    try {
      _map.move(p, math.max(zoom, _map.camera.zoom));
    } catch (_) {}
  }

  // ═════════════ LỘ TRÌNH: ĐIỂM + TUA LẠI ═════════════

  List<Map<String, dynamic>> get _routeRaw => _rows(_route?['points']);

  List<LatLng> get _routePoints => _routeRaw
      .map((p) => LatLng(StaffMapUi.n(p['lat']).toDouble(), StaffMapUi.n(p['lng']).toDouble()))
      .toList();

  List<DateTime> get _routeTimes => _routeRaw.map((p) => StaffMapUi.utc(p['t']) ?? DateTime.now()).toList();

  /// Vị trí tại thời điểm tua (nội suy giữa 2 điểm).
  (LatLng, DateTime)? _playbackAt() {
    final pts = _routePoints;
    final times = _routeTimes;
    if (pts.isEmpty) return null;
    if (pts.length == 1) return (pts.first, times.first);
    final t0 = times.first.millisecondsSinceEpoch, t1 = times.last.millisecondsSinceEpoch;
    final t = t0 + ((t1 - t0) * _playback).round();
    for (var i = 1; i < pts.length; i++) {
      final a = times[i - 1].millisecondsSinceEpoch, b = times[i].millisecondsSinceEpoch;
      if (t <= b) {
        final f = b == a ? 1.0 : (t - a) / (b - a);
        return (
          LatLng(pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * f,
              pts[i - 1].longitude + (pts[i].longitude - pts[i - 1].longitude) * f),
          DateTime.fromMillisecondsSinceEpoch(t),
        );
      }
    }
    return (pts.last, times.last);
  }

  void _togglePlay() {
    if (_playTimer != null) {
      _playTimer!.cancel();
      setState(() => _playTimer = null);
      return;
    }
    if (_playback >= 1) _playback = 0;
    _playTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _playback = math.min(1, _playback + 0.004);
        if (_playback >= 1) {
          t.cancel();
          _playTimer = null;
        }
      });
      final at = _playbackAt();
      if (at != null && _mapReady) {
        try {
          _map.move(at.$1, _map.camera.zoom);
        } catch (_) {}
      }
    });
    setState(() {});
  }

  /// Tách đường đi thành các đoạn liền mạch; đoạn mất tín hiệu vẽ riêng (mảnh, xám).
  (List<List<LatLng>>, List<List<LatLng>>) _segments() {
    final pts = _routePoints;
    final times = _routeTimes;
    final solid = <List<LatLng>>[];
    final gaps = <List<LatLng>>[];
    if (pts.isEmpty) return (solid, gaps);
    var cur = <LatLng>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      final minutes = times[i].difference(times[i - 1]).inMinutes;
      final meters = const Distance().as(LengthUnit.Meter, pts[i - 1], pts[i]);
      if (minutes >= 15 && meters > 80) {
        if (cur.length > 1) solid.add(cur);
        gaps.add([pts[i - 1], pts[i]]);
        cur = [pts[i]];
      } else {
        cur.add(pts[i]);
      }
    }
    if (cur.length > 1) solid.add(cur);
    return (solid, gaps);
  }

  // ═════════════ GIAO DIỆN ═════════════

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    return RegisterPageTopActions(
      actions: [
        HrmTopBarAction(
          icon: Icons.refresh_rounded,
          label: 'Làm mới',
          onPressed: () => _routeMode ? _loadRoute() : _loadLive(),
        ),
      ],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: _loading && _live == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _live == null
                ? Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)))
                : wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(
                          width: 400,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(right: BorderSide(color: SboxColors.slate200)),
                            ),
                            child: _routeMode ? _routePanel() : _livePanel(),
                          ),
                        ),
                        Expanded(child: _mapView()),
                      ])
                    : Stack(children: [
                        Positioned.fill(child: _mapView()),
                        DraggableScrollableSheet(
                          initialChildSize: 0.42,
                          minChildSize: 0.14,
                          maxChildSize: 0.92,
                          snap: true,
                          builder: (ctx, sc) => Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)],
                            ),
                            child: _routeMode ? _routePanel(scroll: sc) : _livePanel(scroll: sc),
                          ),
                        ),
                      ]),
      ),
    );
  }

  // ── Bản đồ ──

  Widget _mapView() {
    final work = _rows(_routeMode ? (_route?['workLocations']) : (_live?['workLocations']));
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: const LatLng(16.0, 106.5),
          initialZoom: 5.5,
          onMapReady: () {
            _mapReady = true;
            _routeMode ? _fitRoute() : _fitLive();
          },
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'sbox.sana.vn',
          ),
          CircleLayer(circles: [
            for (final w in work)
              CircleMarker(
                point: LatLng(StaffMapUi.n(w['latitude']).toDouble(), StaffMapUi.n(w['longitude']).toDouble()),
                radius: math.max(30, StaffMapUi.n(w['radius']).toDouble()),
                useRadiusInMeter: true,
                color: SboxColors.brand500.withValues(alpha: 0.08),
                borderColor: SboxColors.brand500.withValues(alpha: 0.5),
                borderStrokeWidth: 1.5,
              ),
          ]),
          if (_routeMode) ..._routeLayers() else _liveMarkers(),
          MarkerLayer(markers: [
            for (final w in work)
              Marker(
                point: LatLng(StaffMapUi.n(w['latitude']).toDouble(), StaffMapUi.n(w['longitude']).toDouble()),
                width: 150,
                height: 22,
                alignment: Alignment.topCenter,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(w['name']?.toString() ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: SboxColors.brand700)),
                    ),
                  ),
                ),
              ),
          ]),
          const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
        ],
      ),
      Positioned(
        right: 12,
        top: 12,
        child: Column(children: [
          _mapBtn(Icons.center_focus_strong_rounded, 'Xem tất cả', () => _routeMode ? _fitRoute() : _fitLive()),
          const SizedBox(height: 8),
          _mapBtn(Icons.add_rounded, 'Phóng to', () {
            try {
              _map.move(_map.camera.center, _map.camera.zoom + 1);
            } catch (_) {}
          }),
          const SizedBox(height: 8),
          _mapBtn(Icons.remove_rounded, 'Thu nhỏ', () {
            try {
              _map.move(_map.camera.center, _map.camera.zoom - 1);
            } catch (_) {}
          }),
        ]),
      ),
      if (_routeMode && _route != null && _routePoints.length > 1)
        Positioned(left: 12, right: 64, bottom: MediaQuery.of(context).size.width >= 1000 ? 16 : null, top: MediaQuery.of(context).size.width >= 1000 ? null : 12, child: _playbackBar()),
    ]);
  }

  Widget _mapBtn(IconData icon, String tip, VoidCallback onTap) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: IconButton(tooltip: tr(tip), icon: Icon(icon, color: SboxColors.slate700), onPressed: onTap),
      );

  Widget _liveMarkers() {
    final list = _filtered.where((e) => _pos(e) != null).toList();
    // Nhiều người cùng chỗ → xếp vòng nhỏ để không đè nhau
    final placed = <LatLng>[];
    final markers = <Marker>[];
    for (final e in list) {
      var p = _pos(e)!;
      final same = placed.where((q) => (q.latitude - p.latitude).abs() < 0.00008 && (q.longitude - p.longitude).abs() < 0.00008).length;
      if (same > 0) {
        final a = same * 0.9;
        p = LatLng(p.latitude + 0.00009 * math.cos(a), p.longitude + 0.00009 * math.sin(a));
      }
      placed.add(_pos(e)!);
      final focused = _focusId == e['employeeId']?.toString();
      final status = e['status']?.toString();
      markers.add(Marker(
        point: p,
        width: 120,
        height: focused ? 78 : 66,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: () {
            setState(() => _focusId = e['employeeId']?.toString());
            _showEmployeeSheet(e);
          },
          child: Opacity(
            opacity: status == 'offline' ? 0.6 : 1,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              StaffMapUi.avatar(e, _api, size: focused ? 50 : 40, pulse: status == 'online'),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: focused ? SboxColors.brand700 : Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
                ),
                child: Text(
                  (e['employeeName']?.toString() ?? '').split(' ').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: focused ? Colors.white : SboxColors.slate800),
                ),
              ),
            ]),
          ),
        ),
      ));
    }
    return MarkerLayer(markers: markers);
  }

  List<Widget> _routeLayers() {
    if (_route == null) return const [];
    final (solid, gaps) = _segments();
    final pts = _routePoints;
    final stops = _rows(_route?['stops']);
    final events = _rows(_route?['timeline']).where((t) =>
        (t['type'] == 'punch_in' || t['type'] == 'punch_out' || t['type'] == 'checkin') && t['lat'] is num && t['lng'] is num);
    final at = _playbackAt();
    Widget pin(IconData icon, Color color, {double size = 30}) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.55),
        );
    return [
      PolylineLayer(polylines: [
        for (final g in gaps)
          Polyline(points: g, color: SboxColors.slate400.withValues(alpha: 0.7), strokeWidth: 2.5),
        for (final s in solid)
          Polyline(points: s, color: SboxColors.brand600, strokeWidth: 5, borderColor: Colors.white, borderStrokeWidth: 2),
        if (at != null && _playback < 1)
          Polyline(
            points: [
              ...pts.take(_indexAt(at.$2)),
              at.$1,
            ],
            color: SboxColors.success,
            strokeWidth: 5,
          ),
      ]),
      MarkerLayer(markers: [
        for (final s in stops)
          Marker(
            point: LatLng(StaffMapUi.n(s['lat']).toDouble(), StaffMapUi.n(s['lng']).toDouble()),
            width: 34,
            height: 34,
            child: Tooltip(
              message: '${tr('Dừng')} ${StaffMapUi.duration(StaffMapUi.n(s['minutes']))}'
                  '${s['place'] != null ? ' · ${s['place']}' : ''}',
              child: Container(
                decoration: BoxDecoration(
                  color: SboxColors.warning,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                alignment: Alignment.center,
                child: Text('${s['index']}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
          ),
        for (final e in events)
          Marker(
            point: LatLng(StaffMapUi.n(e['lat']).toDouble(), StaffMapUi.n(e['lng']).toDouble()),
            width: 28,
            height: 28,
            child: Tooltip(
              message: '${e['title']} ${StaffMapUi.hm(StaffMapUi.utc(e['time']))}',
              child: pin(StaffMapUi.timelineIcon(e['type']?.toString()), StaffMapUi.timelineColor(e['type']?.toString()), size: 28),
            ),
          ),
        if (pts.isNotEmpty) Marker(point: pts.first, width: 30, height: 30, child: pin(Icons.flag_rounded, SboxColors.success)),
        if (pts.length > 1) Marker(point: pts.last, width: 30, height: 30, child: pin(Icons.sports_score_rounded, SboxColors.brand700)),
        if (at != null && _playback < 1)
          Marker(
            point: at.$1,
            width: 44,
            height: 44,
            child: StaffMapUi.avatar({..._routeEmp!, 'status': 'online'}, _api, size: 44, pulse: true),
          ),
      ]),
    ];
  }

  int _indexAt(DateTime t) {
    final times = _routeTimes;
    var i = 0;
    while (i < times.length && !times[i].isAfter(t)) {
      i++;
    }
    return i;
  }

  Widget _playbackBar() {
    final at = _playbackAt();
    final times = _routeTimes;
    return Material(
      color: Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
        child: Row(children: [
          IconButton(
            tooltip: tr(_playTimer != null ? 'Tạm dừng' : 'Tua lại hành trình'),
            onPressed: _togglePlay,
            icon: Icon(_playTimer != null ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: SboxColors.brand600, size: 32),
          ),
          Text(StaffMapUi.hm(times.first), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          Expanded(
            child: Slider(
              value: _playback,
              onChanged: (v) {
                _playTimer?.cancel();
                setState(() {
                  _playTimer = null;
                  _playback = v;
                });
                final p = _playbackAt();
                if (p != null) _focus(p.$1, zoom: 15);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(8)),
            child: Text(StaffMapUi.hm(at?.$2),
                style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.brand700,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]),
      ),
    );
  }

  // ── Bảng trực tiếp ──

  Widget _livePanel({ScrollController? scroll}) {
    final s = _live?['summary'] as Map<String, dynamic>? ?? const {};
    final list = _filtered;
    final depts = [for (final d in (_live?['departments'] as List? ?? const [])) d.toString()];
    return CustomScrollView(controller: scroll, slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (scroll != null)
              Center(
                child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: SboxColors.slate300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            Row(children: [
              Expanded(
                child: Text(tr('Bản đồ nhân sự'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: SboxColors.success, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(tr(_refreshedAt == null ? '' : 'Cập nhật ${StaffMapUi.hm(_refreshedAt)}'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ]),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.9,
              children: [
                _statTile('all', 'Tổng NV', s['total'], SboxColors.brand600),
                _statTile('online', 'Trực tuyến', s['online'], SboxColors.success),
                _statTile('onShift', 'Đang trong ca', s['onShift'], SboxColors.violet),
                _statTile('lost', 'Mất tín hiệu trong ca', s['signalLostOnShift'], SboxColors.danger),
                _statTile('offline', 'Ngoại tuyến', StaffMapUi.n(s['offline']) + StaffMapUi.n(s['stale']), SboxColors.slate500),
                _statTile('none', 'Chưa có vị trí', s['noLocation'], SboxColors.slate400),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: tr('Tìm tên, mã NV, bộ phận'),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (depts.length > 1) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  ChoiceChip(
                    label: Text(tr('Tất cả bộ phận')),
                    selected: _department == null,
                    onSelected: (_) => setState(() => _department = null),
                  ),
                  for (final d in depts)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(d),
                        selected: _department == d,
                        onSelected: (v) {
                          setState(() => _department = v ? d : null);
                          _fitLive();
                        },
                      ),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 6),
            Text(tr('${list.length} nhân viên · ${list.where((e) => _pos(e) != null).length} có vị trí trên bản đồ'),
                style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          ]),
        ),
      ),
      if (list.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(tr('Không có nhân viên phù hợp'), style: const TextStyle(color: SboxColors.slate500))),
          ),
        )
      else
        SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => _empTile(list[i])),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }

  Widget _statTile(String key, String label, dynamic value, Color color) {
    final sel = _status == key;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() => _status = sel ? 'all' : key);
        _fitLive();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? color.withValues(alpha: 0.12) : SboxColors.slate50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? color : SboxColors.slate200, width: sel ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${StaffMapUi.n(value)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: SboxColors.slate600)),
        ]),
      ),
    );
  }

  String _statusLine(Map<String, dynamic> e) {
    final status = e['status']?.toString();
    final ago = StaffMapUi.ago(e['minutesAgo'] == null ? null : StaffMapUi.n(e['minutesAgo']).toInt());
    return switch (status) {
      'online' => 'Trực tuyến · $ago',
      'stale' => 'Mất tín hiệu · $ago',
      'offline' => 'Vị trí cuối $ago',
      _ => e['hasAccount'] == false ? 'Chưa có tài khoản app' : 'Chưa gửi vị trí hôm nay',
    };
  }

  Widget _empTile(Map<String, dynamic> e) {
    final p = _pos(e);
    final shiftStart = StaffMapUi.wall(e['shiftStart']);
    final shiftEnd = StaffMapUi.wall(e['shiftEnd']);
    final focused = _focusId == e['employeeId']?.toString();
    return Material(
      color: focused ? SboxColors.brand50 : Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _focusId = e['employeeId']?.toString());
          if (p != null) _focus(p);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StaffMapUi.avatar(e, _api, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e['employeeName']?.toString() ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate900)),
                Text([e['employeeCode'], e['department']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(color: StaffMapUi.statusColor(e['status']?.toString()), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(tr(_statusLine(e)),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: StaffMapUi.statusColor(e['status']?.toString()), fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 5),
                Wrap(spacing: 5, runSpacing: 4, children: [
                  if (e['signalLostOnShift'] == true)
                    StaffMapUi.pill('Trong ca nhưng mất tín hiệu', SboxColors.danger, icon: Icons.warning_amber_rounded),
                  if (shiftStart != null)
                    StaffMapUi.pill('Ca ${StaffMapUi.hm(shiftStart)}–${StaffMapUi.hm(shiftEnd)}',
                        e['onShift'] == true ? SboxColors.violet : SboxColors.slate500, icon: Icons.schedule_rounded),
                  if (e['atWorkLocation'] != null)
                    StaffMapUi.pill('Tại ${e['atWorkLocation']}', SboxColors.success, icon: Icons.apartment_rounded),
                  if (e['activeCheckin'] != null)
                    StaffMapUi.pill('Đang ở ${e['activeCheckin']}', SboxColors.violet, icon: Icons.storefront_rounded),
                  if (StaffMapUi.n(e['distanceTodayKm']) > 0)
                    StaffMapUi.pill('${StaffMapUi.n(e['distanceTodayKm'])} km', SboxColors.brand600, icon: Icons.route_rounded),
                  if (e['battery'] != null)
                    StaffMapUi.pill('${e['battery']}%', StaffMapUi.n(e['battery']) <= 15 ? SboxColors.danger : SboxColors.slate500,
                        icon: Icons.battery_std_rounded),
                ]),
              ]),
            ),
            IconButton(
              tooltip: tr('Xem lộ trình'),
              onPressed: e['hasAccount'] == false ? null : () => _openRoute(e),
              icon: const Icon(Icons.timeline_rounded, color: SboxColors.brand600),
            ),
          ]),
        ),
      ),
    );
  }

  void _showEmployeeSheet(Map<String, dynamic> e) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    if (wide) return; // Máy tính: bảng bên trái đã làm nổi bật người được chọn
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _empTile(e),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () {
                Navigator.pop(ctx);
                _openRoute(e);
              },
              icon: const Icon(Icons.timeline_rounded),
              label: Text(tr('Xem lộ trình trong ca')),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Bảng lộ trình ──

  Widget _routePanel({ScrollController? scroll}) {
    final e = _routeEmp!;
    final r = _route;
    final sm = r?['summary'] as Map<String, dynamic>? ?? const {};
    final shifts = _rows(r?['shifts']);
    final timeline = _rows(r?['timeline']);
    final isToday = _DayLabel.sameDay(_routeDate, DateTime.now());
    return CustomScrollView(controller: scroll, slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (scroll != null)
              Center(
                child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: SboxColors.slate300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            Row(children: [
              IconButton(tooltip: tr('Quay lại bản đồ'), onPressed: _closeRoute, icon: const Icon(Icons.arrow_back_rounded)),
              StaffMapUi.avatar(e, _api, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e['employeeName']?.toString() ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(tr('Lộ trình · ${r?['windowLabel'] ?? ''}'),
                      style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(children: [
                IconButton.outlined(
                  onPressed: () {
                    setState(() {
                      _routeDate = _routeDate.subtract(const Duration(days: 1));
                      _routeWindow = 'shift';
                    });
                    _loadRoute();
                  },
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _routeDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 60)),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) {
                        setState(() {
                          _routeDate = d;
                          _routeWindow = 'shift';
                        });
                        _loadRoute();
                      }
                    },
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: Text(isToday ? tr('Hôm nay') : _DayLabel.label(_routeDate)),
                  ),
                ),
                IconButton.outlined(
                  onPressed: isToday
                      ? null
                      : () {
                          setState(() {
                            _routeDate = _routeDate.add(const Duration(days: 1));
                            _routeWindow = 'shift';
                          });
                          _loadRoute();
                        },
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                ChoiceChip(
                  label: Text(tr(shifts.isEmpty ? 'Không có ca' : 'Trong ca')),
                  selected: _routeWindow == 'shift',
                  onSelected: (_) {
                    setState(() => _routeWindow = 'shift');
                    _loadRoute();
                  },
                ),
                if (shifts.length > 1)
                  for (final s in shifts)
                    ChoiceChip(
                      label: Text(s['label']?.toString() ?? ''),
                      selected: _routeWindow == s['id']?.toString(),
                      onSelected: (_) {
                        setState(() => _routeWindow = s['id'].toString());
                        _loadRoute();
                      },
                    ),
                ChoiceChip(
                  label: Text(tr('Cả ngày')),
                  selected: _routeWindow == 'day',
                  onSelected: (_) {
                    setState(() => _routeWindow = 'day');
                    _loadRoute();
                  },
                ),
              ]),
            ),
          ]),
        ),
      ),
      if (_routeLoading)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())))
      else if (r == null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr(_error ?? 'Không tải được lộ trình'), style: const TextStyle(color: SboxColors.danger)),
          ),
        )
      else ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                _sumTile('Quãng đường', '${StaffMapUi.n(sm['distanceKm'])} km', Icons.route_rounded, SboxColors.brand600),
                _sumTile('Di chuyển', StaffMapUi.duration(StaffMapUi.n(sm['movingMinutes'])), Icons.directions_walk_rounded, SboxColors.success),
                _sumTile('Dừng', '${StaffMapUi.n(sm['stops'])} lần · ${StaffMapUi.duration(StaffMapUi.n(sm['stoppedMinutes']))}',
                    Icons.local_parking_rounded, SboxColors.warning),
                _sumTile('Mất tín hiệu', StaffMapUi.n(sm['gaps']) == 0 ? 'Không' : StaffMapUi.duration(StaffMapUi.n(sm['gapMinutes'])),
                    Icons.signal_wifi_off_rounded, StaffMapUi.n(sm['gaps']) == 0 ? SboxColors.slate400 : SboxColors.danger),
                _sumTile('Có vị trí', '${StaffMapUi.hm(StaffMapUi.utc(sm['first']))}–${StaffMapUi.hm(StaffMapUi.utc(sm['last']))}',
                    Icons.schedule_rounded, SboxColors.violet),
                _sumTile('Chấm công / điểm', '${StaffMapUi.n(sm['punches'])} / ${StaffMapUi.n(sm['checkins'])}',
                    Icons.fact_check_rounded, SboxColors.slate600),
              ],
            ),
          ),
        ),
        if (_routePoints.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  tr('Không có dữ liệu vị trí trong khoảng này. Vị trí chỉ được ghi khi nhân viên mở app SBOX trên điện thoại '
                      'trong giờ ca đã duyệt (hoặc được bật chấm ngoài công ty) và cho phép định vị.'),
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(tr('Dòng thời gian'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
        SliverList.builder(
          itemCount: timeline.length,
          itemBuilder: (_, i) => _timelineItem(timeline[i], last: i == timeline.length - 1),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    ]);
  }

  Widget _sumTile(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: SboxColors.slate50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
            ),
          ]),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(tr(value), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
          ),
        ]),
      );

  Widget _timelineItem(Map<String, dynamic> t, {required bool last}) {
    final type = t['type']?.toString();
    final color = StaffMapUi.timelineColor(type);
    final time = StaffMapUi.utc(t['time']);
    final end = StaffMapUi.utc(t['end']);
    final hasPos = t['lat'] is num && t['lng'] is num;
    return InkWell(
      onTap: hasPos ? () => _focus(LatLng(StaffMapUi.n(t['lat']).toDouble(), StaffMapUi.n(t['lng']).toDouble())) : null,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, left: 16),
              child: Text(StaffMapUi.hm(time),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate600)),
            ),
          ),
          SizedBox(
            width: 32,
            child: Column(children: [
              const SizedBox(height: 6),
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: type == 'stop'
                    ? Center(child: Text('${t['index']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)))
                    : Icon(StaffMapUi.timelineIcon(type), size: 15, color: color),
              ),
              if (!last) Expanded(child: Container(width: 2, color: SboxColors.slate200)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(t['title']?.toString() ?? ''),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate800)),
                if (end != null)
                  Text('${StaffMapUi.hm(time)} → ${StaffMapUi.hm(end)}',
                      style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                if ((t['detail']?.toString() ?? '').isNotEmpty)
                  Text(tr(t['detail'].toString()), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                if (t['warning'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: StaffMapUi.pill(t['warning'].toString(), SboxColors.danger, icon: Icons.warning_amber_rounded),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Ngày hiển thị gọn (không phụ thuộc locale).
class _DayLabel {
  _DayLabel._();
  static const _wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static String label(DateTime d) =>
      '${_wd[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
