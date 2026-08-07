import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/mobile_attendance.dart';
import '../services/api_service.dart';
import '../utils/travel_hours_calculator.dart';
import 'hrm_page_chrome.dart';
import 'manual_travel_dialog.dart';
import 'mobile_attendance_record_detail_sheet.dart';
import 'notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _theme = HrmPageChrome.primaryNavy;

class _TravelSlip {
  _TravelSlip({
    required this.start,
    this.arrive,
    this.startRecord,
    this.arriveRecord,
  });

  final DateTime start;
  final DateTime? arrive;
  final MobileAttendanceRecord? startRecord;
  final MobileAttendanceRecord? arriveRecord;

  bool get isComplete =>
      arrive != null && startRecord != null && arriveRecord != null;

  double get hours {
    if (!isComplete || arrive == null) return 0;
    if (arrive!.isBefore(start)) return 0;
    return arrive!.difference(start).inMinutes / 60.0;
  }

  String get statusLabel {
    if (startRecord != null && arriveRecord == null) return 'Thiếu đến điểm';
    if (startRecord == null && arriveRecord != null) return 'Thiếu bắt đầu đi';
    if (!isComplete) return 'Thiếu chấm';
    final s = startRecord?.status ?? arriveRecord?.status ?? '';
    if (s == 'approved' || s == 'auto_approved') return 'Đã duyệt';
    if (s == 'pending') return 'Chờ duyệt';
    if (s == 'rejected') return 'Từ chối';
    return s.isEmpty ? '—' : s;
  }
}

/// Danh sách phiếu đi đường theo NV + ngày: thêm / sửa / xóa.
Future<bool> showTravelDaySlipsSheet(
  BuildContext context, {
  required ApiService api,
  required List<Map<String, dynamic>> employees,
  required String employeeId,
  required String employeeName,
  required DateTime day,
  bool canEdit = true,
}) async {
  var changed = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return _TravelDaySlipsBody(
        api: api,
        employees: employees,
        employeeId: employeeId,
        employeeName: employeeName,
        day: day,
        canEdit: canEdit,
        onChanged: () => changed = true,
      );
    },
  );

  return changed;
}

class _TravelDaySlipsBody extends StatefulWidget {
  const _TravelDaySlipsBody({
    required this.api,
    required this.employees,
    required this.employeeId,
    required this.employeeName,
    required this.day,
    required this.canEdit,
    required this.onChanged,
  });

  final ApiService api;
  final List<Map<String, dynamic>> employees;
  final String employeeId;
  final String employeeName;
  final DateTime day;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  State<_TravelDaySlipsBody> createState() => _TravelDaySlipsBodyState();
}

class _TravelDaySlipsBodyState extends State<_TravelDaySlipsBody> {
  final _timeFmt = DateFormat('HH:mm');
  final _dateFmt = DateFormat('dd/MM/yyyy');
  bool _loading = true;
  String? _error;
  List<_TravelSlip> _slips = [];
  List<String> _empKeys = [];

  @override
  void initState() {
    super.initState();
    _empKeys = _resolveEmployeeKeys();
    _load();
  }

  List<String> _resolveEmployeeKeys() {
    final keys = <String>{widget.employeeId.trim()};
    for (final e in widget.employees) {
      final id = e['id']?.toString() ?? '';
      final code = e['employeeCode']?.toString() ?? '';
      final pin = e['pin']?.toString() ?? '';
      final uid = e['applicationUserId']?.toString() ?? '';
      final match = id == widget.employeeId ||
          code == widget.employeeId ||
          pin == widget.employeeId ||
          uid == widget.employeeId;
      if (!match) continue;
      for (final k in [id, code, pin, uid]) {
        if (k.trim().isNotEmpty) keys.add(k.trim());
      }
    }
    return keys.toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = DateTime(widget.day.year, widget.day.month, widget.day.day);
      final to = DateTime(
          widget.day.year, widget.day.month, widget.day.day, 23, 59, 59);
      // Lấy theo từng key NV (history hỗ trợ employeeId)
      final all = <MobileAttendanceRecord>[];
      final seen = <String>{};
      for (final key in _empKeys) {
        final res = await widget.api.getMobileAttendanceHistory(
          employeeId: key,
          fromDate: from,
          toDate: to,
          punchTypes: '2,3',
          pageSize: 500,
        );
        if (res['isSuccess'] != true) continue;
        final raw = res['data'];
        final list = raw is List
            ? raw
            : (raw is Map ? (raw['items'] ?? raw['records']) : null);
        if (list is! List) continue;
        for (final e in list) {
          if (e is! Map) continue;
          final r = MobileAttendanceRecord.fromJson(
              Map<String, dynamic>.from(e));
          if (!isTravelPunchType(r.punchType)) continue;
          if (seen.add(r.id)) all.add(r);
        }
      }
      // Fallback: store-wide day load rồi lọc theo key
      if (all.isEmpty) {
        final res = await widget.api.getMobileAttendanceHistory(
          fromDate: from,
          toDate: to,
          punchTypes: '2,3',
          pageSize: 5000,
        );
        if (res['isSuccess'] == true) {
          final raw = res['data'];
          final list = raw is List
              ? raw
              : (raw is Map ? (raw['items'] ?? raw['records']) : null);
          if (list is List) {
            for (final e in list) {
              if (e is! Map) continue;
              final r = MobileAttendanceRecord.fromJson(
                  Map<String, dynamic>.from(e));
              if (!isTravelPunchType(r.punchType)) continue;
              if (!_empKeys.contains(r.odooEmployeeId.trim())) continue;
              if (seen.add(r.id)) all.add(r);
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _slips = _buildSlips(all);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _slips = [];
      });
    }
  }

  List<_TravelSlip> _buildSlips(List<MobileAttendanceRecord> records) {
    final list = List<MobileAttendanceRecord>.from(records)
      ..sort((a, b) => a.punchTime.compareTo(b.punchTime));
    final out = <_TravelSlip>[];
    MobileAttendanceRecord? pendingStart;
    for (final r in list) {
      if (r.punchType == mobilePunchTravelStart) {
        if (pendingStart != null) {
          out.add(_TravelSlip(
            start: pendingStart.punchTime,
            startRecord: pendingStart,
          ));
        }
        pendingStart = r;
      } else if (r.punchType == mobilePunchTravelArrive) {
        if (pendingStart != null) {
          out.add(_TravelSlip(
            start: pendingStart.punchTime,
            arrive: r.punchTime,
            startRecord: pendingStart,
            arriveRecord: r,
          ));
          pendingStart = null;
        } else {
          out.add(_TravelSlip(
            start: r.punchTime,
            arrive: r.punchTime,
            arriveRecord: r,
          ));
        }
      }
    }
    if (pendingStart != null) {
      out.add(_TravelSlip(
        start: pendingStart.punchTime,
        startRecord: pendingStart,
      ));
    }
    return out;
  }

  String _fmtHours(double h) {
    if (h <= 0) return '—';
    final hh = h.floor();
    final mm = ((h - hh) * 60).round();
    if (mm <= 0) return '${hh}h';
    return '${hh}h${mm}p';
  }

  String _slipTimeLabel(_TravelSlip s) {
    if (s.startRecord != null && s.arriveRecord != null) {
      return '${_timeFmt.format(s.start)} → ${_timeFmt.format(s.arrive!)} · ${_fmtHours(s.hours)}';
    }
    if (s.startRecord != null) {
      return '${_timeFmt.format(s.start)} → ? · ${_fmtHours(0)}';
    }
    if (s.arriveRecord != null) {
      return '? → ${_timeFmt.format(s.arrive!)} · ${_fmtHours(0)}';
    }
    return '—';
  }

  Future<void> _addSlip({
    String? existingStartRecordId,
    String? existingArriveRecordId,
    DateTime? startHint,
    DateTime? arriveHint,
  }) async {
    final isSupplement = (existingStartRecordId != null &&
            existingStartRecordId.isNotEmpty) ||
        (existingArriveRecordId != null && existingArriveRecordId.isNotEmpty);
    final start = startHint ??
        DateTime(widget.day.year, widget.day.month, widget.day.day, 7, 0);
    final arrive = arriveHint ??
        DateTime(widget.day.year, widget.day.month, widget.day.day, 8, 0);
    final ok = await showManualTravelDialog(
      context,
      api: widget.api,
      employees: widget.employees,
      initialEmployeeId: widget.employeeId,
      initialDay: widget.day,
      initialStart: TimeOfDay.fromDateTime(start),
      initialArrive: TimeOfDay.fromDateTime(arrive),
      title: isSupplement
          ? 'Bổ sung cặp đi đường · ${widget.employeeName}'
          : 'Thêm đi đường · ${widget.employeeName}',
      existingStartRecordId: existingStartRecordId,
      existingArriveRecordId: existingArriveRecordId,
    );
    if (ok) {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _editTime(MobileAttendanceRecord record) async {
    final initial = record.punchTime.toLocal();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null || !mounted) return;
    final newTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    final res = await widget.api.updateMobileAttendanceRecord(
      recordId: record.id,
      punchTime: newTime,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(
        title: 'Thành công',
        message: tr('Đã sửa giờ chấm đi đường'),
      );
      widget.onChanged();
      await _load();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không sửa được giờ',
      );
    }
  }

  Future<void> _deleteRecord(MobileAttendanceRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa phiếu đi đường?')),
        content: Text(tr(
            'Xóa bản ghi ${_timeFmt.format(record.punchTime)} (${travelPunchTypeLabel(record.punchType)}).')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await widget.api.deleteMobileAttendanceRecord(record.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: tr('Đã xóa phiếu'));
      widget.onChanged();
      await _load();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không xóa được',
      );
    }
  }

  Future<void> _deleteSlip(_TravelSlip s) async {
    final ids = <String>[
      if (s.startRecord != null) s.startRecord!.id,
      if (s.arriveRecord != null) s.arriveRecord!.id,
    ];
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa cặp đi đường?')),
        content: Text(tr(
            'Xóa cả Bắt đầu đi và Đến điểm làm (${_slipTimeLabel(s)}).')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa cả cặp')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    var failed = 0;
    String? lastError;
    for (final id in ids) {
      final res = await widget.api.deleteMobileAttendanceRecord(id);
      if (res['isSuccess'] != true) {
        failed++;
        lastError = res['message']?.toString();
      }
    }
    if (!mounted) return;
    if (failed == 0) {
      appNotification.showSuccess(
          title: 'Thành công', message: tr('Đã xóa cặp đi đường'));
      widget.onChanged();
      await _load();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: lastError ?? 'Không xóa được cặp đi đường',
      );
      if (failed < ids.length) {
        widget.onChanged();
        await _load();
      }
    }
  }

  void _openDetail(MobileAttendanceRecord record) {
    showMobileAttendanceRecordDetailSheet(
      context,
      record: record,
      apiService: widget.api,
      canManageRecord: widget.canEdit,
      canEditRecord: widget.canEdit,
      canDeleteRecord: widget.canEdit,
      onRecordChanged: () {
        widget.onChanged();
        _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Đi đường · ${widget.employeeName}'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr(_dateFmt.format(widget.day)),
              style: const TextStyle(fontSize: 13, color: Color(0xFF71717A)),
            ),
            const SizedBox(height: 12),
            if (widget.canEdit)
              FilledButton.icon(
                onPressed: _addSlip,
                icon: const Icon(Icons.add_road, size: 18),
                label: Text(tr('Thêm chấm đi đường')),
                style: FilledButton.styleFrom(
                  backgroundColor: _theme,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr(_error!),
                    style: const TextStyle(color: Colors.red)),
              )
            else if (_slips.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(Icons.directions_car_outlined,
                        size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 10),
                    Text(tr('Chưa có phiếu đi đường trong ngày này'),
                        style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _slips.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = _slips[i];
                    return Material(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: (s.isComplete
                                      ? _theme
                                      : const Color(0xFFD97706))
                                  .withValues(alpha: 0.12),
                              child: Icon(
                                s.isComplete
                                    ? Icons.directions_car
                                    : Icons.warning_amber,
                                size: 18,
                                color: s.isComplete
                                    ? _theme
                                    : const Color(0xFFD97706),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr(_slipTimeLabel(s)),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    tr(s.statusLabel),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: s.isComplete
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: tr('Thao tác'),
                              onSelected: (v) {
                                switch (v) {
                                  case 'edit_start':
                                    if (s.startRecord != null) {
                                      _editTime(s.startRecord!);
                                    }
                                    break;
                                  case 'edit_arrive':
                                    if (s.arriveRecord != null) {
                                      _editTime(s.arriveRecord!);
                                    }
                                    break;
                                  case 'detail_start':
                                    if (s.startRecord != null) {
                                      _openDetail(s.startRecord!);
                                    }
                                    break;
                                  case 'detail_arrive':
                                    if (s.arriveRecord != null) {
                                      _openDetail(s.arriveRecord!);
                                    }
                                    break;
                                  case 'delete_pair':
                                    _deleteSlip(s);
                                    break;
                                  case 'delete_start':
                                    if (s.startRecord != null) {
                                      _deleteRecord(s.startRecord!);
                                    }
                                    break;
                                  case 'delete_arrive':
                                    if (s.arriveRecord != null) {
                                      _deleteRecord(s.arriveRecord!);
                                    }
                                    break;
                                  case 'add_pair':
                                    final hasStart = s.startRecord != null;
                                    final hasArrive = s.arriveRecord != null;
                                    final base = hasStart
                                        ? s.start
                                        : (s.arrive ?? s.start);
                                    _addSlip(
                                      existingStartRecordId: s.startRecord?.id,
                                      existingArriveRecordId:
                                          s.arriveRecord?.id,
                                      startHint: hasStart
                                          ? s.start
                                          : base.subtract(
                                              const Duration(hours: 1)),
                                      arriveHint: hasArrive
                                          ? s.arrive
                                          : DateTime(
                                              base.year,
                                              base.month,
                                              base.day,
                                              (base.hour + 1).clamp(0, 23),
                                              base.minute),
                                    );
                                    break;
                                }
                              },
                              itemBuilder: (ctx) => [
                                if (widget.canEdit && s.startRecord != null)
                                  PopupMenuItem(
                                    value: 'edit_start',
                                    child: Text(tr('Sửa giờ bắt đầu đi')),
                                  ),
                                if (widget.canEdit && s.arriveRecord != null)
                                  PopupMenuItem(
                                    value: 'edit_arrive',
                                    child: Text(tr('Sửa giờ đến điểm')),
                                  ),
                                if (widget.canEdit && !s.isComplete)
                                  PopupMenuItem(
                                    value: 'add_pair',
                                    child: Text(tr('Bổ sung cặp đi đường')),
                                  ),
                                if (s.startRecord != null)
                                  PopupMenuItem(
                                    value: 'detail_start',
                                    child: Text(tr('Chi tiết bắt đầu đi')),
                                  ),
                                if (s.arriveRecord != null)
                                  PopupMenuItem(
                                    value: 'detail_arrive',
                                    child: Text(tr('Chi tiết đến điểm')),
                                  ),
                                if (widget.canEdit &&
                                    (s.startRecord != null ||
                                        s.arriveRecord != null))
                                  PopupMenuItem(
                                    value: 'delete_pair',
                                    child: Text(
                                      tr(s.isComplete
                                          ? 'Xóa cả cặp đi đường'
                                          : 'Xóa phiếu đi đường'),
                                      style:
                                          const TextStyle(color: Colors.red),
                                    ),
                                  ),
                                if (widget.canEdit && s.startRecord != null)
                                  PopupMenuItem(
                                    value: 'delete_start',
                                    child: Text(tr('Xóa bắt đầu đi'),
                                        style: const TextStyle(
                                            color: Colors.red)),
                                  ),
                                if (widget.canEdit && s.arriveRecord != null)
                                  PopupMenuItem(
                                    value: 'delete_arrive',
                                    child: Text(tr('Xóa đến điểm'),
                                        style: const TextStyle(
                                            color: Colors.red)),
                                  ),
                              ],
                            ),
                          ],
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
  }
}
