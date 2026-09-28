import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'aa_common.dart';

double? _d(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse('$v');

String _punchLabel(int? t) => switch (t) {
      0 => 'Vào ca',
      1 => 'Ra ca',
      2 => 'Bắt đầu đi đường',
      3 => 'Đến điểm làm',
      4 => 'Nghỉ trưa / OT vào',
      5 => 'Nghỉ trưa / OT ra',
      _ => 'Chấm công',
    };

/// Khung chi tiết một yêu cầu: bằng chứng, bản đồ, ngữ cảnh ngày công, nút duyệt.
class AaDetailPane extends StatefulWidget {
  const AaDetailPane({super.key, required this.item, required this.api, required this.onDecided, this.enableMapTiles = true, this.compact = false});
  final AaItem item;
  final ApiService api;
  final VoidCallback onDecided;
  final bool enableMapTiles;

  /// Trên điện thoại: nút thao tác ghim dưới đáy.
  final bool compact;

  @override
  State<AaDetailPane> createState() => _AaDetailPaneState();
}

class _AaDetailPaneState extends State<AaDetailPane> {
  Map<String, dynamic>? _ctx;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AaDetailPane old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) _load();
  }

  Future<void> _load() async {
    setState(() {
      _ctx = null;
      _error = null;
    });
    final it = widget.item;
    final r = it.isMobile ? await widget.api.getMobileRecordContext(it.id) : await widget.api.getCorrectionContext(it.id);
    if (!mounted || it.id != widget.item.id) return;
    setState(() {
      if (r['isSuccess'] == true && r['data'] is Map) {
        _ctx = Map<String, dynamic>.from(r['data'] as Map);
      } else {
        _error = '${r['message'] ?? 'Không tải được chi tiết'}';
      }
    });
  }

  Future<void> _decide(String action) async {
    final it = widget.item;
    String? reason;
    if (action == 'reject') {
      reason = await aaAskRejectReason(context, title: it.isMobile ? 'Từ chối chấm công' : 'Từ chối yêu cầu');
      if (reason == null) return;
    }
    if (action == 'fine') {
      final amount = _d(_ctx?['forgotCheckPenalty']) ?? 0;
      final ok = await SboxDialogs.confirm(context,
          title: 'Duyệt và phạt quên chấm công?',
          message: amount > 0
              ? 'Lập phiếu phạt «Quên chấm công» ${SboxFmt.money(amount)} (trừ vào lương) sau khi duyệt.'
              : 'Mức phạt «Quên chấm công» chưa cài đặt.',
          confirmLabel: 'Duyệt và phạt',
          icon: Icons.gavel);
      if (!ok) return;
    }
    setState(() => _busy = true);
    final Map<String, dynamic> r;
    if (it.isMobile) {
      r = await widget.api.approveMobileAttendance(recordId: it.id, approved: action == 'approve', rejectionReason: reason);
    } else if (action == 'fine') {
      r = await widget.api.approveCorrectionAndFine(it.id);
    } else {
      r = await widget.api.approveAttendanceCorrection(requestId: it.id, isApproved: action == 'approve', approverNote: reason);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = r['isSuccess'] == true;
    final data = r['data'];
    final msg = !ok
        ? '${r['message'] ?? 'Không thực hiện được'}'
        : data is Map && data['message'] != null
            ? '${data['message']}'
            : data is Map && data['ticketCode'] != null
                ? 'Đã duyệt và lập phiếu phạt ${data['ticketCode']}'
                : action == 'reject'
                    ? 'Đã từ chối'
                    : 'Đã duyệt';
    aaToast(context, msg, error: !ok);
    if (ok) widget.onDecided();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final (label, tone, icon) = aaRisk(it);
    final header = Row(children: [
      AaAvatar(name: it.employeeName, photo: it.photoUrl, size: 48),
      const SizedBox(width: SboxSpace.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(it.employeeName, style: SboxType.titleStyle()),
          Text([it.employeeCode, it.department].whereType<String>().where((e) => e.isNotEmpty).join(' · '), style: SboxType.captionStyle()),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SboxStatusChip(label: label, tone: tone, icon: icon),
        if (it.isMobile && it.riskScore > 0) ...[
          const SizedBox(height: 4),
          Text('Điểm rủi ro ${it.riskScore}/100', style: SboxType.captionStyle()),
        ],
      ]),
    ]);

    Widget body;
    if (_error != null) {
      body = SboxEmptyState(icon: Icons.error_outline, title: _error!);
    } else if (_ctx == null) {
      body = const SboxLoading();
    } else {
      body = it.isMobile ? _mobileBody(_ctx!) : _correctionBody(_ctx!);
    }

    final actions = Row(children: [
      Expanded(child: SboxButton.danger(label: 'Từ chối', icon: Icons.close_rounded, onPressed: _busy ? null : () => _decide('reject'))),
      if (!it.isMobile && (it.correctionAction ?? 0) == 0) ...[
        const SizedBox(width: SboxSpace.sm),
        Expanded(child: SboxButton.secondary(label: 'Duyệt + phạt', icon: Icons.gavel, onPressed: _busy ? null : () => _decide('fine'))),
      ],
      const SizedBox(width: SboxSpace.sm),
      Expanded(
        flex: 2,
        child: SboxButton(label: 'Duyệt', icon: Icons.check_rounded, loading: _busy, onPressed: _busy ? null : () => _decide('approve')),
      ),
    ]);

    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const SizedBox(height: SboxSpace.md),
      Container(
        padding: const EdgeInsets.all(SboxSpace.md),
        decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: SboxRadius.mdAll),
        child: Row(children: [
          Icon(it.isMobile ? Icons.fingerprint : Icons.edit_calendar_outlined, color: SboxColors.brand600),
          const SizedBox(width: SboxSpace.sm),
          Expanded(child: Text(it.title, style: SboxType.titleSmStyle())),
          Text(aaDate(it.time), style: SboxType.smallStyle()),
        ]),
      ),
      body,
    ]);

    if (widget.compact) {
      return Column(children: [
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(SboxSpace.lg), child: content)),
        Container(
          padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.sm, SboxSpace.lg, SboxSpace.lg),
          decoration: const BoxDecoration(color: SboxColors.white, border: Border(top: BorderSide(color: SboxColors.border))),
          child: SafeArea(top: false, child: actions),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      content,
      const SizedBox(height: SboxSpace.lg),
      actions,
    ]);
  }

  // ─── Chấm công mobile ────────────────────────────────────────────

  Widget _mobileBody(Map<String, dynamic> c) {
    final r = Map<String, dynamic>.from(c['record'] as Map? ?? {});
    final lat = _d(r['latitude']);
    final lng = _d(r['longitude']);
    final locations = (c['locations'] as List? ?? []).whereType<Map>().toList();
    final flags = (r['riskFlags'] as List? ?? []).map((e) => '$e').toList();
    final site = r['sitePhotoUrl']?.toString();
    final face = _d(r['faceMatchScore']);
    final acc = _d(r['gpsAccuracy']);
    final shift = c['shift'] is Map ? Map<String, dynamic>.from(c['shift'] as Map) : null;
    final device = c['device'] is Map ? Map<String, dynamic>.from(c['device'] as Map) : null;
    final reason = (r['outsideReason'] ?? r['note'])?.toString();
    final punch = _t(r['punchTime']) ?? widget.item.time;

    final evidence = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        flex: 3,
        child: SizedBox(
          height: 172,
          child: Container(
            decoration: BoxDecoration(color: SboxColors.slate100, borderRadius: SboxRadius.mdAll, border: Border.all(color: SboxColors.border)),
            clipBehavior: Clip.antiAlias,
            child: site == null
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.no_photography_outlined, color: SboxColors.slate400),
                    const SizedBox(height: 4),
                    Text(r['evidencePurgedAt'] != null ? tr('Ảnh đã xóa theo hạn lưu') : tr('Không có ảnh hiện trường'),
                        style: SboxType.captionStyle(), textAlign: TextAlign.center),
                  ])
                : InkWell(
                    onTap: () => launchUrl(Uri.parse(aaUrl(site)), mode: LaunchMode.externalApplication),
                    child: Image.network(aaUrl(site), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: SboxColors.slate400))),
                  ),
          ),
        ),
      ),
      const SizedBox(width: SboxSpace.sm),
      Expanded(
        flex: 2,
        child: Column(children: [
          _ScoreTile(
            icon: Icons.face_retouching_natural,
            label: 'Khớp khuôn mặt',
            value: face == null ? '—' : '${face.round()}%',
            tone: face == null ? SboxTone.neutral : face >= 85 ? SboxTone.success : face >= 70 ? SboxTone.warning : SboxTone.danger,
          ),
          const SizedBox(height: SboxSpace.sm),
          _ScoreTile(
            icon: Icons.near_me_outlined,
            label: 'Cách vị trí',
            value: aaDistance(_d(r['distanceFromLocation'])),
            tone: (_d(r['distanceFromLocation']) ?? 99999) <= 300
                ? SboxTone.success
                : (_d(r['distanceFromLocation']) ?? 99999) <= 1500
                    ? SboxTone.warning
                    : SboxTone.danger,
          ),
        ]),
      ),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: SboxSpace.md),
      evidence,
      if (lat != null && lng != null) ...[
        const SizedBox(height: SboxSpace.sm),
        _PunchMap(lat: lat, lng: lng, accuracy: acc, locations: locations, tiles: widget.enableMapTiles),
      ],
      if (reason != null && reason.isNotEmpty)
        AaSection(
          title: 'Lý do của nhân viên',
          child: Container(
            padding: const EdgeInsets.all(SboxSpace.md),
            decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: SboxRadius.mdAll),
            child: Text('“$reason”', style: SboxType.bodyStyle(SboxColors.brand900)),
          ),
        ),
      if (flags.isNotEmpty)
        AaSection(
          title: 'Dấu hiệu cần chú ý',
          child: Column(children: [
            for (final f in flags)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: SboxColors.warning),
                  const SizedBox(width: 6),
                  Expanded(child: Text(f, style: SboxType.smallStyle(SboxColors.warningText))),
                ]),
              ),
          ]),
        ),
      AaSection(
        title: 'Thông tin chấm',
        child: Column(children: [
          AaFact(icon: Icons.schedule, label: 'Thời gian', value: '${_punchLabel(widget.item.punchType)} · ${aaTime(punch)} ${aaDate(punch)}'),
          AaFact(icon: Icons.place_outlined, label: 'Vị trí gần nhất', value: '${r['locationName'] ?? '—'}'),
          AaFact(
              icon: Icons.gps_fixed,
              label: 'Sai số GPS',
              value: acc == null ? 'Không có' : '±${acc.round()} m',
              tone: acc != null && acc > 100 ? SboxTone.danger : null),
          AaFact(
              icon: Icons.event_note_outlined,
              label: 'Ca làm',
              value: shift == null ? 'Không có lịch' : '${shift['name'] ?? 'Ca'} ${shift['start'] ?? ''}–${shift['end'] ?? ''}'),
          if (device != null)
            AaFact(icon: Icons.smartphone, label: 'Thiết bị', value: '${device['name'] ?? ''} ${device['model'] ?? ''}'.trim()),
          AaFact(icon: Icons.bar_chart_rounded, label: 'Ngoài vị trí tháng này', value: '${c['outsideThisMonth'] ?? 0} lần'),
        ]),
      ),
      _timeline(c, highlight: widget.item.id),
      _history(c),
    ]);
  }

  Widget _timeline(Map<String, dynamic> c, {String? highlight}) {
    final rows = <({DateTime t, String label, String sub, bool hi, SboxTone tone})>[];
    for (final m in (c['sameDay'] as List? ?? []).whereType<Map>()) {
      final t = _t(m['punchTime']);
      if (t == null) continue;
      final st = '${m['status']}';
      rows.add((
        t: t,
        label: '${_punchLabel((m['punchType'] as num?)?.toInt())} (mobile)',
        sub: '${m['locationName'] ?? ''}${m['isOutside'] == true ? ' · ngoài vị trí' : ''}',
        hi: '${m['id']}' == highlight,
        tone: st == 'rejected' ? SboxTone.danger : st == 'pending' ? SboxTone.warning : SboxTone.success,
      ));
    }
    for (final l in (c['logs'] as List? ?? []).whereType<Map>()) {
      final t = _t(l['attendanceTime']);
      if (t == null || l['fromMobile'] == true) continue;
      rows.add((t: t, label: 'Máy chấm công', sub: '${l['note'] ?? ''}', hi: false, tone: SboxTone.brand));
    }
    rows.sort((a, b) => a.t.compareTo(b.t));
    return AaSection(
      title: 'Các lần chấm trong ngày',
      child: rows.isEmpty
          ? Text(tr('Chưa có lần chấm nào khác'), style: SboxType.smallStyle())
          : Column(children: [
              for (final r in rows)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: SboxSpace.sm, vertical: 6),
                  decoration: BoxDecoration(
                    color: r.hi ? SboxColors.brand50 : null,
                    borderRadius: SboxRadius.smAll,
                  ),
                  child: Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: r.tone.fg, shape: BoxShape.circle)),
                    const SizedBox(width: SboxSpace.sm),
                    SizedBox(width: 48, child: Text(aaTime(r.t), style: SboxType.bodyStrong())),
                    Expanded(child: Text(r.label, style: SboxType.smallStyle(SboxColors.text))),
                    Flexible(child: Text(r.sub, style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ]),
    );
  }

  Widget _history(Map<String, dynamic> c) {
    final list = (c['history'] as List? ?? []).whereType<Map>().toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return AaSection(
      title: 'Lần chấm ngoài vị trí trước đây',
      child: Column(children: [
        for (final h in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(h['status'] == 'rejected' ? Icons.cancel_outlined : Icons.check_circle_outline,
                  size: 16, color: h['status'] == 'rejected' ? SboxColors.danger : SboxColors.success),
              const SizedBox(width: 6),
              Text(_t(h['punchTime']) == null ? '' : aaDateTime(_t(h['punchTime'])!), style: SboxType.smallStyle(SboxColors.text)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${h['locationName'] ?? ''} · ${aaDistance(_d(h['distanceFromLocation']))}'
                  '${h['rejectReason'] != null ? ' · ${h['rejectReason']}' : ''}',
                  style: SboxType.captionStyle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  // ─── Yêu cầu sửa / bổ sung công ─────────────────────────────────

  Widget _correctionBody(Map<String, dynamic> c) {
    final r = Map<String, dynamic>.from(c['request'] as Map? ?? {});
    final shift = c['shift'] is Map ? Map<String, dynamic>.from(c['shift'] as Map) : null;
    final action = (r['action'] as num?)?.toInt() ?? 0;
    final approvals = (r['approvals'] as List? ?? []).whereType<Map>().toList();
    final oldD = _t(r['oldDate']);
    final newD = _t(r['newDate']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: SboxSpace.md),
      Row(children: [
        Expanded(child: _BeforeAfter(title: 'Trước', value: action == 0 ? 'Không có' : '${r['oldTime'] ?? '—'} ${oldD == null ? '' : aaDate(oldD)}', tone: SboxTone.neutral)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, color: SboxColors.slate400)),
        Expanded(
          child: _BeforeAfter(
            title: 'Sau khi duyệt',
            value: action == 2 ? 'Xóa lần chấm' : '${r['newTime'] ?? '—'} ${newD == null ? '' : aaDate(newD)}',
            tone: action == 2 ? SboxTone.danger : SboxTone.success,
          ),
        ),
      ]),
      AaSection(
        title: 'Lý do của nhân viên',
        child: Container(
          padding: const EdgeInsets.all(SboxSpace.md),
          decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: SboxRadius.mdAll),
          child: Text('“${r['reason'] ?? ''}”', style: SboxType.bodyStyle(SboxColors.brand900)),
        ),
      ),
      AaSection(
        title: 'Thông tin',
        child: Column(children: [
          AaFact(
            icon: Icons.event_note_outlined,
            label: 'Ca làm',
            value: shift == null
                ? 'Không có lịch'
                : shift['dayOff'] == true
                    ? 'Ngày nghỉ theo lịch'
                    : '${shift['name'] ?? 'Ca'} ${shift['start'] ?? ''}–${shift['end'] ?? ''}',
            tone: shift?['dayOff'] == true ? SboxTone.warning : null,
          ),
          if (r['newPunchType'] != null) AaFact(icon: Icons.login, label: 'Loại chấm', value: '${r['newPunchType']}'),
          AaFact(
            icon: Icons.history,
            label: 'Yêu cầu tháng này',
            value: '${c['requestsThisMonth'] ?? 0} lần',
            tone: ((c['requestsThisMonth'] as num?) ?? 0) >= 4 ? SboxTone.warning : null,
          ),
          AaFact(icon: Icons.gavel, label: 'Mức phạt quên chấm', value: SboxFmt.money(_d(c['forgotCheckPenalty']) ?? 0)),
        ]),
      ),
      _timeline(c),
      if (approvals.length > 1)
        AaSection(
          title: 'Luồng duyệt',
          child: Column(children: [
            for (final a in approvals)
              AaFact(
                icon: a['status'] == 'Approved' ? Icons.check_circle : Icons.radio_button_unchecked,
                label: '${a['stepName'] ?? 'Cấp ${a['stepOrder']}'}',
                value: '${a['assignedUserName'] ?? ''} · ${a['status']}',
                tone: a['status'] == 'Approved' ? SboxTone.success : null,
              ),
          ]),
        ),
    ]);
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({required this.icon, required this.label, required this.value, required this.tone});
  final IconData icon;
  final String label;
  final String value;
  final SboxTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SboxSpace.md),
      decoration: BoxDecoration(color: tone.bg, borderRadius: SboxRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: tone.fg),
          const SizedBox(width: 4),
          Expanded(child: Text(tr(label), style: SboxType.captionStyle(tone.fg), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 2),
        Text(value, style: SboxType.moneyStyle(size: SboxType.title, c: tone.fg)),
      ]),
    );
  }
}

class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.title, required this.value, required this.tone});
  final String title;
  final String value;
  final SboxTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SboxSpace.md),
      decoration: BoxDecoration(color: tone.bg, borderRadius: SboxRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(title), style: SboxType.captionStyle(tone.fg)),
        Text(value, style: SboxType.titleSmStyle(tone.fg)),
      ]),
    );
  }
}

/// Bản đồ: điểm chấm (đỏ, vòng sai số GPS) và các vị trí khai báo (xanh, bán kính).
class _PunchMap extends StatelessWidget {
  const _PunchMap({required this.lat, required this.lng, required this.accuracy, required this.locations, required this.tiles});
  final double lat;
  final double lng;
  final double? accuracy;
  final List<Map> locations;
  final bool tiles;

  @override
  Widget build(BuildContext context) {
    final punch = LatLng(lat, lng);
    final locs = [
      for (final l in locations)
        if (_d(l['latitude']) != null && _d(l['longitude']) != null)
          (p: LatLng(_d(l['latitude'])!, _d(l['longitude'])!), r: _d(l['radius']) ?? 100, name: '${l['name'] ?? ''}'),
    ];
    // Khung nhìn gồm điểm chấm + vị trí gần nhất
    const dist = Distance();
    final nearest = locs.isEmpty ? null : (locs.toList()..sort((a, b) => dist(a.p, punch).compareTo(dist(b.p, punch)))).first;
    final points = [punch, if (nearest != null) nearest.p];
    final bounds = LatLngBounds.fromPoints(points);
    final spanKm = nearest == null ? 0.3 : math.max(0.3, dist(nearest.p, punch) / 1000);
    return ClipRRect(
      borderRadius: SboxRadius.mdAll,
      child: SizedBox(
        height: 220,
        child: Stack(children: [
          Positioned.fill(child: Container(color: const Color(0xFFE8EEF3))),
          FlutterMap(
            options: MapOptions(
              initialCameraFit: points.length > 1
                  ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(96, 56, 96, 40), maxZoom: 17)
                  : null,
              initialCenter: punch,
              initialZoom: spanKm < 1 ? 16 : 13,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              if (tiles)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'sbox.sana.vn',
                ),
              CircleLayer(circles: [
                for (final l in locs)
                  CircleMarker(
                    point: l.p,
                    radius: math.max(30, l.r),
                    useRadiusInMeter: true,
                    color: SboxColors.brand500.withValues(alpha: 0.12),
                    borderColor: SboxColors.brand500.withValues(alpha: 0.6),
                    borderStrokeWidth: 1.5,
                  ),
                if (accuracy != null)
                  CircleMarker(
                    point: punch,
                    radius: math.max(10, accuracy!),
                    useRadiusInMeter: true,
                    color: SboxColors.danger.withValues(alpha: 0.1),
                    borderColor: SboxColors.danger.withValues(alpha: 0.4),
                    borderStrokeWidth: 1,
                  ),
              ]),
              if (nearest != null)
                PolylineLayer(polylines: [
                  Polyline(points: [punch, nearest.p], color: SboxColors.slate500, strokeWidth: 2),
                ]),
              MarkerLayer(markers: [
                for (final l in locs)
                  Marker(
                    point: l.p,
                    width: 160,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(6)),
                        child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: SboxColors.brand700)),
                      ),
                      const Icon(Icons.business, size: 18, color: SboxColors.brand600),
                    ]),
                  ),
                Marker(
                  point: punch,
                  width: 36,
                  height: 36,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on, size: 34, color: SboxColors.danger),
                ),
              ]),
              if (tiles) const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
            ],
          ),
        ]),
      ),
    );
  }
}
