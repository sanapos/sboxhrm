import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_customer.dart';
import '../../models/pos_product.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/safe_navigator.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_deposit_payment_picker.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';

Color reservationAccent(PosResourceReservationDto b) {
  if (b.isCancelled) return const Color(0xFF64748B);
  if (b.isNoShow) return const Color(0xFFC2410C);
  if (b.isOrderCompleted) return const Color(0xFF15803D);
  if (b.isUsingTable) return const Color(0xFF0F766E);
  if (b.isSeated) return const Color(0xFF15803D);
  return b.isTimedSlot ? const Color(0xFF7C3AED) : PosTheme.kiotBlue;
}

String reservationStatusLabel(PosResourceReservationDto b) {
  if (b.isCancelled) return 'Đã hủy';
  if (b.isNoShow) return 'Không đến';
  if (b.isOrderCompleted) return 'Đã thanh toán';
  if (b.isUsingTable) return 'Đang dùng';
  if (b.isSeated) return 'Đã nhận';
  return 'Chưa đến';
}

String reservationDepositLabel(String status) {
  switch (status.toLowerCase()) {
    case 'held':
      return 'Đang giữ';
    case 'applied':
      return 'Đã trừ vào đơn';
    case 'refunded':
      return 'Đã hoàn';
    case 'forfeited':
      return 'Mất cọc';
    default:
      return 'Chưa thu';
  }
}

String reservationOrderStatusLabel(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'completed':
      return 'Đã thanh toán';
    case 'cancelled':
      return 'Đã hủy đơn';
    case 'draft':
      return 'Đang mở';
    default:
      return status ?? '';
  }
}

/// Lịch hẹn theo ngày (salon): multi-slot, dịch vụ, NV, ghế.
class PosAppointmentDayScreen extends StatefulWidget {
  const PosAppointmentDayScreen({
    super.key,
    this.onSeated,
    this.initialDay,
    this.initialResourceId,
    this.sellProfile,
  });

  /// Khi nhận khách (seat) — payload giống sơ đồ bàn.
  final void Function(Map<String, dynamic> result)? onSeated;
  final DateTime? initialDay;
  final String? initialResourceId;
  final PosSellProfile? sellProfile;

  @override
  State<PosAppointmentDayScreen> createState() =>
      _PosAppointmentDayScreenState();
}

class _PosAppointmentDayScreenState extends State<PosAppointmentDayScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

  late DateTime _day;
  late DateTime _month;
  bool _showMonth = false;
  bool _loading = true;
  String? _error;
  List<PosResourceReservationDto> _items = [];
  List<PosServiceResourceDto> _resources = [];
  String _statusFilter = 'all';
  bool _showGrid = false;
  int? _pipelineBooked;
  double? _pipelineDeposit;
  double? _pipelineExpected;
  int _upcomingBooked = 0;
  List<String> _availDays = [];
  List<Map<String, dynamic>> _availItems = [];

  PosSellProfile? _loadedProfile;
  bool _profileLoading = false;

  PosSellProfile get _profile =>
      widget.sellProfile ?? _loadedProfile ?? PosSellProfile.restaurant;

  String get _calendarTitle => _profile.bookingCalendarTitle;

  String get _noun => _profile.resourceNoun.isEmpty
      ? 'chỗ'
      : _profile.resourceNoun;

  List<PosResourceReservationDto> get _visibleItems {
    switch (_statusFilter) {
      case 'booked':
        return _items.where((e) => e.isBooked).toList();
      case 'seated':
        return _items.where((e) => e.isSeated).toList();
      case 'cancelled':
        return _items.where((e) => e.isCancelled).toList();
      case 'noshow':
        return _items.where((e) => e.isNoShow).toList();
      default:
        return _items;
    }
  }

  int get _bookedCount => _items.where((e) => e.isBooked).length;
  double get _depositHeldSum => _items
      .where((e) => e.hasDepositHeld)
      .fold(0.0, (s, e) => s + e.depositPaid);
  double get _expectedRevenueSum =>
      _items.fold(0.0, (s, e) => s + e.expectedRevenue);

  bool get _useRoomGrid =>
      _profile == PosSellProfile.hotel ||
      _profile == PosSellProfile.roomHourly ||
      _profile == PosSellProfile.restaurant;

  String? get _availabilityKind => switch (_profile) {
        PosSellProfile.hotel || PosSellProfile.roomHourly => 'room',
        PosSellProfile.restaurant => 'table',
        PosSellProfile.salon => 'chair',
        _ => null,
      };

  @override
  void initState() {
    super.initState();
    final now = widget.initialDay ?? DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    _month = DateTime(_day.year, _day.month);
    if (widget.sellProfile != null) {
      _showGrid = widget.sellProfile == PosSellProfile.hotel ||
          widget.sellProfile == PosSellProfile.roomHourly;
      unawaited(_reload());
    } else {
      _profileLoading = true;
      unawaited(_loadSellProfile());
    }
  }

  Future<void> _loadSellProfile() async {
    try {
      final res = await _api.getPosSellSettings();
      if (!mounted) return;
      PosSellProfile profile = PosSellProfile.restaurant;
      if (res['isSuccess'] == true && res['data'] is Map) {
        profile = PosStoreSellSettingsDto.fromJson(
          Map<String, dynamic>.from(res['data'] as Map),
        ).sellProfile;
      }
      setState(() {
        _loadedProfile = profile;
        _profileLoading = false;
        _showGrid = profile == PosSellProfile.hotel ||
            profile == PosSellProfile.roomHourly;
      });
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadedProfile = PosSellProfile.restaurant;
        _profileLoading = false;
        _error = 'Không tải cấu hình ngành: $e';
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final dayUtc = DateTime.utc(_day.year, _day.month, _day.day);
    final monthFrom = DateTime.utc(_month.year, _month.month, 1);
    final monthLast = DateUtils.getDaysInMonth(_month.year, _month.month);
    final monthTo = DateTime.utc(_month.year, _month.month, monthLast);
    try {
      final results = await Future.wait([
        _showMonth
            ? _api.getPosResourceReservations(
                from: monthFrom, to: monthTo, includeClosed: true)
            : _api.getPosResourceReservations(
                day: dayUtc, includeClosed: true),
        _api.getPosServiceResources(),
      ]);
      if (!mounted) return;
      final resList = results[0];
      final resRes = results[1];

      final list = <PosResourceReservationDto>[];
      final raw = resList['data'];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            list.add(PosResourceReservationDto.fromJson(
                Map<String, dynamic>.from(e)));
          }
        }
      }

      final resources = <PosServiceResourceDto>[];
      final rRaw = resRes['data'];
      final rItems = rRaw is List
          ? rRaw
          : (rRaw is Map ? (rRaw['items'] ?? rRaw['Items']) : null);
      if (rItems is List) {
        for (final e in rItems) {
          if (e is Map) {
            resources.add(PosServiceResourceDto.fromJson(
                Map<String, dynamic>.from(e)));
          }
        }
      }

      list.sort((a, b) {
        final ta = a.reservedAt ?? DateTime(1970);
        final tb = b.reservedAt ?? DateTime(1970);
        return ta.compareTo(tb);
      });

      final weekStart = _day.subtract(const Duration(days: 3));
      final weekEnd = _day.add(const Duration(days: 3));
      Map<String, dynamic>? pipe;
      Map<String, dynamic>? avail;
      try {
        final extra = await Future.wait([
          _api.getPosReservationPipeline(
            from: _showMonth ? monthFrom : dayUtc,
            to: _showMonth
                ? monthTo
                : DateTime.utc(_day.year, _day.month, _day.day)
                    .add(const Duration(days: 6)),
          ),
          _api.getPosReservationAvailability(
            from: DateTime.utc(weekStart.year, weekStart.month, weekStart.day),
            to: DateTime.utc(weekEnd.year, weekEnd.month, weekEnd.day),
            kind: _availabilityKind,
          ),
        ]);
        if (extra[0]['isSuccess'] == true && extra[0]['data'] is Map) {
          pipe = Map<String, dynamic>.from(extra[0]['data'] as Map);
        }
        if (extra[1]['isSuccess'] == true && extra[1]['data'] is Map) {
          avail = Map<String, dynamic>.from(extra[1]['data'] as Map);
        }
      } catch (_) {}

      int? pBooked;
      double? pDep;
      double? pExp;
      var upcoming = 0;
      if (pipe != null) {
        final totals = pipe['totals'] ?? pipe['Totals'];
        if (totals is Map) {
          pDep = (totals['depositHeld'] ?? totals['DepositHeld'] as num?)
              ?.toDouble();
          pExp = (totals['expectedRevenue'] ?? totals['ExpectedRevenue'] as num?)
              ?.toDouble();
        }
        final dayKey =
            '${_day.year.toString().padLeft(4, '0')}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';
        final days = pipe['days'] ?? pipe['Days'];
        if (days is List) {
          for (final e in days) {
            if (e is! Map) continue;
            final ds = (e['date'] ?? e['Date'] ?? '').toString();
            final booked =
                int.tryParse('${e['booked'] ?? e['Booked'] ?? 0}') ?? 0;
            if (ds == dayKey) {
              pBooked = booked;
            } else if (ds.compareTo(dayKey) > 0) {
              upcoming += booked;
            }
          }
        }
      }

      var availDays = <String>[];
      var availItems = <Map<String, dynamic>>[];
      if (avail != null) {
        final days = avail['days'] ?? avail['Days'];
        if (days is List) {
          availDays = days.map((e) => e.toString()).toList();
        }
        final items = avail['items'] ?? avail['Items'];
        if (items is List) {
          for (final e in items) {
            if (e is Map) availItems.add(Map<String, dynamic>.from(e));
          }
        }
      } else {
        availDays = List.generate(7, (i) {
          final d = weekStart.add(Duration(days: i));
          return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        });
        for (final r in resources.where((x) => x.isActive)) {
          final days = availDays.map((ds) {
            final parts = ds.split('-');
            final day = DateTime(int.parse(parts[0]), int.parse(parts[1]),
                int.parse(parts[2]));
            final next = day.add(const Duration(days: 1));
            final booked = list.any((b) {
              if (b.resourceId != r.id || !b.isBooked) return false;
              final start = b.reservedAt ?? day;
              final end = b.reservedUntil ?? start;
              return start.isBefore(next) &&
                  !end.isBefore(day);
            });
            final occupied = r.isOccupied &&
                DateUtils.isSameDay(day, DateTime.now());
            return {
              'date': ds,
              'status': occupied
                  ? 'Occupied'
                  : booked
                      ? 'Booked'
                      : 'Free',
            };
          }).toList();
          availItems.add({
            'id': r.id,
            'name': r.name,
            'areaName': r.areaName,
            'days': days,
          });
        }
      }

      setState(() {
        _items = list;
        _resources = resources.where((r) => r.isActive).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        _pipelineBooked = pBooked;
        _pipelineDeposit = pDep;
        _pipelineExpected = pExp;
        _upcomingBooked = upcoming;
        _availDays = availDays;
        _availItems = availItems;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _shiftDay(int delta) async {
    setState(() => _day = _day.add(Duration(days: delta)));
    await _reload();
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: appUiLocale(),
    );
    if (d == null) return;
    setState(() {
      _day = DateTime(d.year, d.month, d.day);
      _month = DateTime(d.year, d.month);
    });
    await _reload();
  }

  Future<void> _toggleMonthView() async {
    setState(() {
      _showMonth = !_showMonth;
      if (_showMonth) {
        _month = DateTime(_day.year, _day.month);
      } else {
        final last = DateUtils.getDaysInMonth(_month.year, _month.month);
        final d = _day.day > last ? last : _day.day;
        _day = DateTime(_month.year, _month.month, d);
      }
    });
    await _reload();
  }

  Future<void> _shiftMonth(int delta) async {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      final last = DateUtils.getDaysInMonth(_month.year, _month.month);
      final d = _day.day > last ? last : _day.day;
      _day = DateTime(_month.year, _month.month, d);
    });
    await _reload();
  }

  bool _bookingOverlapsDay(PosResourceReservationDto b, DateTime day) {
    final start = b.reservedAt?.toLocal();
    if (start == null) return false;
    final end = (b.reservedUntil ?? b.reservedAt)?.toLocal() ?? start;
    final d0 = DateTime(day.year, day.month, day.day);
    final d1 = d0.add(const Duration(days: 1));
    return start.isBefore(d1) && !end.isBefore(d0);
  }

  List<PosResourceReservationDto> _bookingsOnDay(DateTime day) {
    final list = _visibleItems.where((b) => _bookingOverlapsDay(b, day)).toList();
    list.sort((a, b) {
      final ta = a.reservedAt ?? DateTime(1970);
      final tb = b.reservedAt ?? DateTime(1970);
      return ta.compareTo(tb);
    });
    return list;
  }

  Future<void> _openMonthDaySheet(DateTime day) async {
    setState(() => _day = DateTime(day.year, day.month, day.day));
    final list = _bookingsOnDay(_day);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.75;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  title: Text(
                    tr(DateFormat('EEEE, dd/MM/yyyy', 'vi_VN').format(_day)),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(tr(list.isEmpty
                      ? 'Chưa có lịch'
                      : '${list.length} lịch hẹn')),
                  trailing: TextButton.icon(
                    onPressed: _resources.isEmpty
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            unawaited(_bookAppointment());
                          },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('Thêm')),
                  ),
                ),
                const Divider(height: 1),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('Bấm Thêm để đặt lịch ngày này.'),
                      style: TextStyle(color: PosTheme.textSecondary),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final b = list[i];
                        final start = b.reservedAt?.toLocal();
                        final time = start == null
                            ? ''
                            : DateFormat('HH:mm').format(start);
                        final table = [
                          if ((b.areaName ?? '').isNotEmpty) b.areaName,
                          b.resourceName,
                        ].join(' · ');
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                reservationAccent(b).withOpacity(0.15),
                            child: Icon(Icons.person_outline,
                                color: reservationAccent(b), size: 20),
                          ),
                          title: Text(
                            tr(b.customerName),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            tr([
                              if (time.isNotEmpty) time,
                              table,
                              reservationStatusLabel(b),
                              if ((b.phone ?? '').isNotEmpty) b.phone,
                            ].join(' · ')),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_openBooking(b));
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthCalendar() {
    final first = DateTime(_month.year, _month.month, 1);
    final lead = (first.weekday + 6) % 7;
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final today = DateTime.now();
    const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final cells = lead + daysInMonth;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: weekdays
                .map((w) => Expanded(
                      child: Text(
                        tr(w),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 88),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: rows > 5 ? 0.72 : 0.78,
            ),
            itemCount: rows * 7,
            itemBuilder: (_, i) {
              final dayNum = i - lead + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox.shrink();
              }
              final day = DateTime(_month.year, _month.month, dayNum);
              final bookings = _bookingsOnDay(day);
              final active = bookings
                  .where((b) => !b.isCancelled && !b.isNoShow)
                  .toList();
              final isToday = DateUtils.isSameDay(day, today);
              final selected = DateUtils.isSameDay(day, _day);
              final names = active
                  .map((b) => b.customerName.trim())
                  .where((n) => n.isNotEmpty)
                  .toList();
              final preview = names.isEmpty
                  ? ''
                  : names.length == 1
                      ? names.first
                      : '${names.first} +${names.length - 1}';
              final n = active.length < 1
                  ? 1
                  : (active.length > 6 ? 6 : active.length);
              var op = 0.08 + n * 0.06;
              if (op > 0.45) op = 0.45;
              final fill = active.isEmpty
                  ? Colors.white
                  : PosTheme.kiotBlue.withOpacity(op);
              return Material(
                color: fill,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => unawaited(_openMonthDaySheet(day)),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? PosTheme.kiotBlue
                            : isToday
                                ? PosTheme.kiotBlue.withOpacity(0.45)
                                : const Color(0xFFE2E8F0),
                        width: selected ? 1.6 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isToday
                                ? PosTheme.kiotBlue
                                : PosTheme.textPrimary,
                          ),
                        ),
                        if (active.isNotEmpty)
                          Text(
                            tr('${active.length} lịch'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        if (preview.isNotEmpty)
                          Expanded(
                            child: Text(
                              tr(preview),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                color: PosTheme.textSecondary,
                                height: 1.15,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _expireNoShows() async {
    final res = await _api.expirePosResourceReservationNoShows();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã quét khách không đến',
        message: res['message']?.toString() ?? 'Cập nhật lịch quá hạn',
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không quét được khách không đến',
      );
    }
  }

  Future<void> _collectExtraDeposit(PosResourceReservationDto b) async {
    final picked = await showPosCollectDepositDialog(
      context: context,
      title: 'Thu thêm cọc',
    );
    if (picked == null || !mounted) return;
    final amount = picked.amount;
    final res = await _api.collectPosResourceReservationDeposit(b.id, {
      'amount': amount,
      ...picked.pay.toCollectBody(),
    });
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã thu cọc',
        message:
            '${_moneyFmt.format(amount)}đ · ${picked.pay.methodLabel} · ${b.customerName}',
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Không thu được cọc',
        message: res['message']?.toString() ?? 'Lỗi',
      );
    }
  }

  Future<void> _bookAppointment({
    PosServiceResourceDto? resource,
    TimeOfDay? slotHint,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _BookAppointmentDialog(
        day: _day,
        resources: _resources,
        initialResourceId: resource?.id ?? widget.initialResourceId,
        slotHint: slotHint,
        sellProfile: _profile,
      ),
    );
    if (ok == true && mounted) await _reload();
  }

  Future<void> _editBooking(PosResourceReservationDto existing) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _BookAppointmentDialog(
        day: existing.reservedAt?.toLocal() ?? _day,
        resources: _resources,
        initialResourceId: existing.resourceId,
        sellProfile: _profile,
        existing: existing,
      ),
    );
    if (ok == true && mounted) await _reload();
  }

  Future<void> _openBooking(PosResourceReservationDto b) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => _BookingDetailDialog(
        booking: b,
        noun: _noun,
        moneyFmt: _moneyFmt,
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'edit') {
      await _editBooking(b);
      return;
    }
    if (action == 'deposit') {
      await _collectExtraDeposit(b);
      return;
    }
    if (action == 'cancel') {
      final depositHeld = b.hasDepositHeld;
      var refund = false;
      var forfeit = true;
      if (depositHeld) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Hủy lịch — xử lý cọc')),
            content: Text(tr(
                'Đã thu cọc ${_moneyFmt.format(b.depositPaid)}đ. Hoàn hay mất cọc?')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Không hủy'))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'refund'),
                  child: Text(tr('Hoàn cọc'))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'forfeit'),
                  child: Text(tr('Mất cọc'))),
            ],
          ),
        );
        if (choice == null) return;
        refund = choice == 'refund';
        forfeit = choice == 'forfeit';
      }
      final res = await _api.cancelPosResourceReservation(
        b.id,
        forfeitDeposit: forfeit,
        refundDeposit: refund,
      );
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        NotificationOverlayManager()
            .showSuccess(title: 'Đã hủy', message: b.customerName);
        await _reload();
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không hủy được',
        );
      }
      return;
    }
    if (action == 'seat') {
      final res = await _api.seatPosResourceReservation(b.id);
      if (!mounted) return;
      if (res['isSuccess'] != true) {
        NotificationOverlayManager().showError(
          title: 'Không nhận $_noun',
          message: res['message']?.toString() ?? 'Lỗi',
        );
        return;
      }
      final data = res['data'] as Map? ?? {};
      final payload = <String, dynamic>{
        'resourceId': data['resourceId']?.toString() ?? b.resourceId,
        'resourceCode': data['resourceCode']?.toString() ?? b.resourceCode,
        'resourceName': data['resourceName']?.toString() ?? b.resourceName,
        'saleOrderId': data['saleOrderId']?.toString(),
        'sessionId': data['sessionId']?.toString(),
        'orderNo': data['orderNo']?.toString(),
        'startedAt': data['startedAt']?.toString(),
        'guestCount': data['guestCount'] ?? b.guestCount,
        'paidAmount': data['paidAmount'],
        'depositApplied': data['depositApplied'],
        'customerId': data['customerId']?.toString() ?? b.customerId,
        'customerName': data['customerName']?.toString() ?? b.customerName,
        'fromAppointment': true,
      };
      if (widget.onSeated != null) {
        widget.onSeated!(payload);
        if (mounted) SafeNavigator.popPageIfPushed(context);
      } else {
        NotificationOverlayManager().showSuccess(
          title: 'Đã nhận $_noun',
          message: b.customerName,
        );
        await _reload();
      }
    }
  }

  Widget _buildAvailabilityGrid() {
    if (_availItems.isEmpty) {
      return Center(
        child: Text(tr('Chưa có bàn/phòng'),
            style: TextStyle(color: PosTheme.textSecondary)),
      );
    }
    Color cellColor(String status) {
      switch (status.toLowerCase()) {
        case 'booked':
          return const Color(0xFFF59E0B);
        case 'occupied':
          return const Color(0xFFDC2626);
        default:
          return const Color(0xFF16A34A);
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 108.0 + _availDays.length * 52,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
          itemCount: _availItems.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Row(
                children: [
                  const SizedBox(width: 100),
                  ..._availDays.map((ds) {
                    final parts = ds.split('-');
                    final d = parts.length == 3
                        ? DateTime(int.parse(parts[0]), int.parse(parts[1]),
                            int.parse(parts[2]))
                        : _day;
                    final selected = DateUtils.isSameDay(d, _day);
                    return SizedBox(
                      width: 52,
                      child: Text(
                        '${d.day}/${d.month}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                          color: selected ? PosTheme.kiotBlue : null,
                        ),
                      ),
                    );
                  }),
                ],
              );
            }
            final row = _availItems[i - 1];
            final name =
                '${row['areaName'] ?? row['AreaName'] ?? ''} ${row['name'] ?? row['Name'] ?? ''}'
                    .trim();
            final days = (row['days'] ?? row['Days'] as List?) ?? const [];
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      tr(name.isEmpty ? _noun : name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  ..._availDays.map((ds) {
                    Map<String, dynamic>? cell;
                    for (final e in days) {
                      if (e is Map &&
                          (e['date'] ?? e['Date'])?.toString() == ds) {
                        cell = Map<String, dynamic>.from(e);
                        break;
                      }
                    }
                    final status =
                        (cell?['status'] ?? cell?['Status'] ?? 'Free')
                            .toString();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        onTap: () {
                          final parts = ds.split('-');
                          if (parts.length == 3) {
                            setState(() => _day = DateTime(
                                int.parse(parts[0]),
                                int.parse(parts[1]),
                                int.parse(parts[2])));
                          }
                          final rid = (row['id'] ?? row['Id'])?.toString();
                          final match = _resources
                              .where((r) => r.id == rid)
                              .toList();
                          if (status.toLowerCase() == 'free' &&
                              match.isNotEmpty) {
                            unawaited(
                                _bookAppointment(resource: match.first));
                          } else {
                            unawaited(_reload());
                          }
                        },
                        child: Container(
                          width: 48,
                          height: 28,
                          decoration: BoxDecoration(
                            color: cellColor(status).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_profileLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Đặt chỗ / lịch hẹn'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final isToday = DateUtils.isSameDay(_day, DateTime.now());
    final visible = _visibleItems;
    final weekStart = _day.subtract(const Duration(days: 3));

    Color statusColor(PosResourceReservationDto b) => reservationAccent(b);

    String statusLabel(PosResourceReservationDto b) =>
        reservationStatusLabel(b);

    Widget filterChip(String id, String label) {
      final selected = _statusFilter == id;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          selected: selected,
          label: Text(tr(label), style: const TextStyle(fontSize: 12)),
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _statusFilter = id),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(tr(_calendarTitle)),
        actions: [
          IconButton(
            tooltip: tr(_showMonth ? 'Lịch ngày' : 'Lịch tháng'),
            onPressed: _loading ? null : () => unawaited(_toggleMonthView()),
            icon: Icon(_showMonth
                ? Icons.view_agenda_outlined
                : Icons.calendar_month),
          ),
          if (_useRoomGrid)
            IconButton(
              tooltip: tr(_showGrid ? 'Danh sách' : 'Lịch chỗ'),
              onPressed: () => setState(() => _showGrid = !_showGrid),
              icon: Icon(_showGrid
                  ? Icons.view_list_outlined
                  : Icons.grid_view_outlined),
            ),
          IconButton(
            tooltip: tr('Quét khách không đến'),
            onPressed: _loading ? null : () => unawaited(_expireNoShows()),
            icon: const Icon(Icons.event_busy_outlined),
          ),
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading ? null : () => unawaited(_reload()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _resources.isEmpty
            ? null
            : () => unawaited(_bookAppointment()),
        icon: const Icon(Icons.add),
        label: Text(tr(_profile.bookActionLabel)),
        backgroundColor: PosTheme.kiotBlue,
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => unawaited(
                            _showMonth ? _shiftMonth(-1) : _shiftDay(-1)),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => unawaited(_pickDay()),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              tr(_showMonth
                                  ? DateFormat('MMMM yyyy', 'vi_VN')
                                      .format(_month)
                                  : DateFormat('EEEE, dd/MM/yyyy', 'vi_VN')
                                      .format(_day)),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => unawaited(
                            _showMonth ? _shiftMonth(1) : _shiftDay(1)),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  if (!_showMonth)
                  SizedBox(
                    height: 52,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: 7,
                      itemBuilder: (_, i) {
                        final d = weekStart.add(Duration(days: i));
                        final selected = DateUtils.isSameDay(d, _day);
                        final today = DateUtils.isSameDay(d, DateTime.now());
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: InkWell(
                            onTap: () {
                              setState(() =>
                                  _day = DateTime(d.year, d.month, d.day));
                              unawaited(_reload());
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 44,
                              decoration: BoxDecoration(
                                color: selected
                                    ? PosTheme.kiotBlue
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: today && !selected
                                    ? Border.all(color: PosTheme.kiotBlue)
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    DateFormat('E', 'vi_VN').format(d),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: selected
                                          ? Colors.white
                                          : PosTheme.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    '${d.day}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: selected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('${_showMonth ? _bookedCount : (_pipelineBooked ?? _bookedCount)} đặt'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                        Text(
                          tr(
                              'Cọc ${_moneyFmt.format(_pipelineDeposit ?? _depositHeldSum)}đ'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          tr(
                              'Tạm tính ${_moneyFmt.format(_pipelineExpected ?? _expectedRevenueSum)}đ'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_upcomingBooked > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tr(
                              'Đã nhận $_upcomingBooked lịch dùng trong 7 ngày tới — mở đúng ngày trên lịch để chuẩn bị bàn. Cọc thu hôm đặt vào két ngày thu.'),
                          style: TextStyle(
                            fontSize: 12,
                            color: PosTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        filterChip('all', 'Tất cả (${_items.length})'),
                        filterChip('booked', 'Đặt ($_bookedCount)'),
                        filterChip(
                            'seated',
                            'Đã dùng (${_items.where((e) => e.isSeated).length})'),
                        filterChip(
                            'cancelled',
                            'Hủy (${_items.where((e) => e.isCancelled).length})'),
                        filterChip(
                            'noshow',
                            'Không đến (${_items.where((e) => e.isNoShow).length})'),
                      ],
                    ),
                  ),
                  if (isToday)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, top: 2),
                        child: Text(tr('Hôm nay'),
                            style: const TextStyle(
                                fontSize: 12, color: PosTheme.kiotBlue)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: _error != null
                ? Center(child: Text(tr(_error!)))
                : _showMonth
                    ? _buildMonthCalendar()
                    : _showGrid && _useRoomGrid
                    ? _buildAvailabilityGrid()
                    : visible.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available_outlined,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                                tr(_items.isEmpty
                                    ? 'Chưa có lịch trong ngày'
                                    : 'Không có lịch theo bộ lọc'),
                                style: TextStyle(
                                    color: PosTheme.textSecondary)),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () =>
                                  unawaited(_bookAppointment()),
                              icon: const Icon(Icons.add),
                              label: Text(tr(_profile.bookActionLabel)),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final b = visible[i];
                            final start = b.reservedAt?.toLocal();
                            final end = b.reservedUntil?.toLocal();
                            final time = start == null
                                ? '—'
                                : end == null
                                    ? DateFormat('HH:mm').format(start)
                                    : '${DateFormat('HH:mm').format(start)}–${DateFormat('HH:mm').format(end)}';
                            final table =
                                b.areaName == null || b.areaName!.isEmpty
                                    ? b.resourceName
                                    : '${b.areaName} · ${b.resourceName}';
                            final accent = statusColor(b);
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => unawaited(_openBooking(b)),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 64,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        decoration: BoxDecoration(
                                          color: accent.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          time,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            color: accent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    tr(b.customerName),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: accent
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    tr(statusLabel(b)),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: accent,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              tr([
                                                if ((b.serviceProductName ??
                                                        '')
                                                    .isNotEmpty)
                                                  b.serviceProductName!,
                                                if (b.durationMinutes !=
                                                    null)
                                                  b.durationMinutes! >= 1440
                                                      ? '${(b.durationMinutes! / 1440).round()} đêm'
                                                      : '${b.durationMinutes} phút',
                                                table,
                                              ].join(' · ')),
                                              style: TextStyle(
                                                fontSize: 13,
                                                color:
                                                    PosTheme.textSecondary,
                                              ),
                                            ),
                                            if ((b.assignedEmployeeName ??
                                                    '')
                                                .isNotEmpty)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        top: 2),
                                                child: Text(
                                                  tr('NV: ${b.assignedEmployeeName}'),
                                                  style: const TextStyle(
                                                      fontSize: 12),
                                                ),
                                              ),
                                            if ((b.phone ?? '').isNotEmpty)
                                              Text(b.phone!,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: PosTheme
                                                          .textSecondary)),
                                            if (PosReservationOccasion.label(
                                                    b.occasion)
                                                .isNotEmpty)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        top: 2),
                                                child: Text(
                                                  tr(PosReservationOccasion
                                                      .label(b.occasion)),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color: Color(0xFF7C3AED),
                                                  ),
                                                ),
                                              ),
                                            if (b.createdAt != null &&
                                                b.reservedAt != null &&
                                                !DateUtils.isSameDay(
                                                    b.createdAt!.toLocal(),
                                                    b.reservedAt!.toLocal()))
                                              Text(
                                                tr(
                                                    'Đặt ${DateFormat('dd/MM').format(b.createdAt!.toLocal())} · dùng ${DateFormat('dd/MM').format(b.reservedAt!.toLocal())}'),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      PosTheme.textSecondary,
                                                ),
                                              ),
                                            if (b.guestCount > 0)
                                              Text(
                                                tr('${b.guestCount} khách'),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      PosTheme.textSecondary,
                                                ),
                                              ),
                                            if (b.depositPaid > 0 ||
                                                b.preOrderValue > 0)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        top: 4),
                                                child: Text(
                                                  tr([
                                                    if (b.depositPaid > 0)
                                                      'Cọc ${_moneyFmt.format(b.depositPaid)}đ (${reservationDepositLabel(b.depositStatus)})',
                                                    if (b.preOrderValue > 0)
                                                      'Món ${_moneyFmt.format(b.preOrderValue)}đ',
                                                  ].join(' · ')),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF0F766E),
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            if ((b.orderNo ?? '').isNotEmpty ||
                                                b.orderTotal > 0)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        top: 4),
                                                child: Text(
                                                  tr([
                                                    if ((b.orderNo ?? '')
                                                        .isNotEmpty)
                                                      'HĐ ${b.orderNo}',
                                                    if (b.orderTotal > 0)
                                                      '${_moneyFmt.format(b.orderTotal)}đ',
                                                    if (b.orderPaid > 0)
                                                      'Đã trả ${_moneyFmt.format(b.orderPaid)}đ',
                                                  ].join(' · ')),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color: b.isOrderCompleted
                                                        ? const Color(
                                                            0xFF15803D)
                                                        : const Color(
                                                            0xFF0F766E),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _BookingDetailDialog extends StatelessWidget {
  const _BookingDetailDialog({
    required this.booking,
    required this.noun,
    required this.moneyFmt,
  });

  final PosResourceReservationDto booking;
  final String noun;
  final NumberFormat moneyFmt;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final accent = reservationAccent(b);
    final start = b.reservedAt?.toLocal();
    final end = b.reservedUntil?.toLocal();
    final time = start == null
        ? '—'
        : end == null
            ? DateFormat('HH:mm dd/MM').format(start)
            : '${DateFormat('HH:mm').format(start)}–${DateFormat('HH:mm').format(end)} · ${DateFormat('dd/MM/yyyy').format(start)}';
    final table = b.areaName == null || b.areaName!.isEmpty
        ? b.resourceName
        : '${b.areaName} · ${b.resourceName}';
    final size = MediaQuery.sizeOf(context);

    Widget row(String label, String value, {bool emphasize = false}) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(
                tr(label),
                style: TextStyle(
                  fontSize: 13,
                  color: PosTheme.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                tr(value),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Chi tiết lịch đặt'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr(b.customerName),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            tr(reservationStatusLabel(b)),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    row('Giờ', time, emphasize: true),
                    if (b.createdAt != null)
                      row(
                        'Ngày đặt lịch',
                        DateFormat('HH:mm dd/MM/yyyy')
                            .format(b.createdAt!.toLocal()),
                      ),
                    row(noun[0].toUpperCase() + noun.substring(1), table,
                        emphasize: true),
                    row('Số khách', '${b.guestCount}'),
                    row('Điện thoại', b.phone ?? ''),
                    row('Loại tiệc',
                        PosReservationOccasion.label(b.occasion)),
                    row('Yêu cầu thêm', b.specialRequest ?? ''),
                    row('Dịch vụ', b.serviceProductName ?? ''),
                    row('Nhân viên', b.assignedEmployeeName ?? ''),
                    if (b.depositPaid > 0 || b.depositAmount > 0)
                      row(
                        'Cọc',
                        [
                          if (b.depositPaid > 0)
                            '${moneyFmt.format(b.depositPaid)}đ',
                          reservationDepositLabel(b.depositStatus),
                          if ((b.depositPaymentMethod ?? '').isNotEmpty)
                            b.depositPaymentMethod!,
                        ].join(' · '),
                      ),
                    if (b.preOrderCount > 0 || b.preOrderValue > 0)
                      row(
                        'Món đặt trước',
                        [
                          if (b.preOrderCount > 0) '${b.preOrderCount} món',
                          if (b.preOrderValue > 0)
                            '${moneyFmt.format(b.preOrderValue)}đ',
                        ].join(' · '),
                      ),
                    if (b.isSeated ||
                        (b.orderNo ?? '').isNotEmpty ||
                        b.orderTotal > 0) ...[
                      const Divider(height: 24),
                      Text(
                        tr('Đơn hàng'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      row(
                        'Tình trạng',
                        b.isOrderCompleted
                            ? 'Khách đã dùng · đã thanh toán'
                            : b.isUsingTable
                                ? 'Khách đang dùng bàn'
                                : b.isSeated
                                    ? 'Đã nhận bàn'
                                    : reservationOrderStatusLabel(
                                        b.orderStatus),
                        emphasize: true,
                      ),
                      row(
                        'Mã HĐ',
                        (b.orderNo ?? '').isEmpty ? '—' : b.orderNo!,
                      ),
                      if (b.seatedAt != null)
                        row(
                          'Nhận lúc',
                          DateFormat('HH:mm dd/MM')
                              .format(b.seatedAt!.toLocal()),
                        ),
                      row(
                        'Giá trị đơn',
                        '${moneyFmt.format(b.orderTotal)}đ',
                        emphasize: true,
                      ),
                      row(
                        'Đã thanh toán',
                        '${moneyFmt.format(b.orderPaid)}đ',
                      ),
                      if (b.orderLineCount > 0)
                        row('Số món', '${b.orderLineCount}'),
                    ],
                    if ((b.note ?? '').trim().isNotEmpty) ...[
                      const Divider(height: 24),
                      row('Ghi chú', b.note!.trim()),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (b.isBooked) ...[
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'edit'),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(tr('Sửa')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(tr('Xóa lịch')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'deposit'),
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(tr('Thu cọc')),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, 'seat'),
                      icon: const Icon(Icons.login, size: 18),
                      label: Text(tr('Nhận $noun')),
                    ),
                  ] else
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('Đóng')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookAppointmentDialog extends StatefulWidget {
  const _BookAppointmentDialog({
    required this.day,
    required this.resources,
    this.initialResourceId,
    this.slotHint,
    this.sellProfile,
    this.existing,
  });

  final DateTime day;
  final List<PosServiceResourceDto> resources;
  final String? initialResourceId;
  final TimeOfDay? slotHint;
  final PosSellProfile? sellProfile;
  final PosResourceReservationDto? existing;

  @override
  State<_BookAppointmentDialog> createState() => _BookAppointmentDialogState();
}

class _BookAppointmentDialogState extends State<_BookAppointmentDialog> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _depositPaidCtrl = TextEditingController();
  var _depositPay = const PosDepositPayChoice();

  String? _customerId;
  String? _resourceId;
  String? _serviceProductId;
  String? _employeeId;
  late TimeOfDay _slotTime;
  int _durationMinutes = 60;
  int _stayNights = 1;
  int _guestCount = 1;
  late DateTime _usageDay;
  String? _occasion;
  final _requestCtrl = TextEditingController();
  final Set<String> _requestTags = {};
  bool _saving = false;
  bool _loadingMeta = true;

  List<PosProduct> _services = [];
  List<_EmpOpt> _employees = [];

  PosSellProfile get _profile =>
      widget.sellProfile ?? PosSellProfile.salon;
  bool get _isHotel => _profile == PosSellProfile.hotel;
  bool get _requireService => _profile == PosSellProfile.salon;
  bool get _showStaffPicker => _profile.assignsServiceStaff;
  String get _noun => _profile.resourceNoun.isEmpty
      ? 'chỗ'
      : _profile.resourceNoun;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _resourceId = existing?.resourceId ??
        widget.initialResourceId ??
        (widget.resources.isNotEmpty ? widget.resources.first.id : null);
    final now = DateTime.now();
    _usageDay = DateTime(widget.day.year, widget.day.month, widget.day.day);
    if (existing != null) {
      _nameCtrl.text = existing.customerName;
      _phoneCtrl.text = existing.phone ?? '';
      _noteCtrl.text = existing.note ?? '';
      _customerId = existing.customerId;
      _serviceProductId = existing.serviceProductId;
      _employeeId = existing.assignedEmployeeId;
      _guestCount = existing.guestCount < 1 ? 1 : existing.guestCount;
      _occasion = existing.occasion;
      final req = (existing.specialRequest ?? '').trim();
      if (req.isNotEmpty) {
        for (final chip in PosReservationOccasion.requestChips) {
          if (req.contains(chip)) _requestTags.add(chip);
        }
        final leftover = req
            .split(' · ')
            .where((p) => p.trim().isNotEmpty && !_requestTags.contains(p.trim()))
            .join(' · ');
        _requestCtrl.text = leftover;
      }
      final slot = existing.reservedAt?.toLocal();
      if (slot != null) {
        _usageDay = DateTime(slot.year, slot.month, slot.day);
      }
      _slotTime = slot == null
          ? TimeOfDay(hour: widget.day.hour, minute: 0)
          : TimeOfDay(hour: slot.hour, minute: slot.minute);
      _durationMinutes = existing.durationMinutes ?? 60;
      if (_isHotel && existing.durationMinutes != null) {
        _stayNights = (existing.durationMinutes! / 1440).round().clamp(1, 14);
      }
    } else {
      _slotTime = widget.slotHint ??
          TimeOfDay(
            hour: DateUtils.isSameDay(widget.day, now)
                ? ((now.hour + 1) % 24)
                : (_isHotel ? 14 : 9),
            minute: 0,
          );
    }
    unawaited(_loadMeta());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    _depositPaidCtrl.dispose();
    _requestCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final results = await Future.wait([
      _api.getPosProducts(
        productType: PosProductType.service,
        pageSize: 200,
        sortBy: PosProductSortBy.name,
        sortDesc: false,
      ),
      _api.getEmployees(pageSize: 500, excludeResigned: true),
    ]);
    if (!mounted) return;

    final services = <PosProduct>[];
    final prodRaw = results[0] as Map<String, dynamic>;
    final pData = prodRaw['data'];
    final pItems = pData is Map
        ? (pData['items'] ?? pData['Items'])
        : pData is List
            ? pData
            : null;
    if (pItems is List) {
      for (final e in pItems) {
        if (e is! Map) continue;
        final p = PosProduct.fromJson(Map<String, dynamic>.from(e));
        if (p.isActive) services.add(p);
      }
    }

    final employees = <_EmpOpt>[];
    final empList = results[1] as List<dynamic>;
    for (final e in empList) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = (m['id'] ?? m['Id'] ?? '').toString();
      if (id.isEmpty) continue;
      final last = (m['lastName'] ?? m['LastName'] ?? '').toString();
      final first = (m['firstName'] ?? m['FirstName'] ?? '').toString();
      final code = (m['employeeCode'] ?? m['EmployeeCode'] ?? '').toString();
      final name = '$last $first'.trim();
      employees.add(_EmpOpt(
        id: id,
        label: name.isEmpty ? code : (code.isEmpty ? name : '$name ($code)'),
      ));
    }
    employees.sort((a, b) => a.label.compareTo(b.label));

    setState(() {
      _services = services;
      _employees = employees;
      _loadingMeta = false;
      if (_serviceProductId == null &&
          services.isNotEmpty &&
          widget.existing == null &&
          _requireService) {
        _onServicePicked(services.first);
      }
    });
  }

  void _onServicePicked(PosProduct? p) {
    if (p == null) {
      _serviceProductId = null;
      return;
    }
    _serviceProductId = p.id;
    final d = p.defaultDurationMinutes;
    if (d != null && d > 0) _durationMinutes = d;
  }

  Future<void> _pickCustomer() async {
    final searchCtrl = TextEditingController();
    var hits = <PosCustomer>[];
    var loading = false;
    final picked = await showDialog<PosCustomer>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> search() async {
            setLocal(() => loading = true);
            final res = await _api.getPosCustomers(
              search: searchCtrl.text.trim(),
              pageSize: 20,
            );
            final raw = res['data'];
            final items = raw is Map
                ? (raw['items'] ?? raw['Items'])
                : raw is List
                    ? raw
                    : null;
            final next = <PosCustomer>[];
            if (items is List) {
              for (final e in items) {
                if (e is Map) {
                  next.add(
                      PosCustomer.fromJson(Map<String, dynamic>.from(e)));
                }
              }
            }
            if (ctx.mounted) {
              setLocal(() {
                hits = next;
                loading = false;
              });
            }
          }

          return AlertDialog(
            title: Text(tr('Chọn khách hàng')),
            content: SizedBox(
              width: 360,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      labelText: tr('Tìm tên / SĐT'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => unawaited(search()),
                      ),
                    ),
                    onSubmitted: (_) => unawaited(search()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: hits.length,
                            itemBuilder: (_, i) {
                              final c = hits[i];
                              return ListTile(
                                title: Text(tr(c.name)),
                                subtitle: Text(c.phone ?? ''),
                                onTap: () => Navigator.pop(ctx, c),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Đóng')),
              ),
            ],
          );
        },
      ),
    );
    searchCtrl.dispose();
    if (picked == null || !mounted) return;
    setState(() {
      _customerId = picked.id;
      _nameCtrl.text = picked.name;
      if ((picked.phone ?? '').isNotEmpty) {
        _phoneCtrl.text = picked.phone!;
      }
    });
  }

  Future<void> _submit() async {
    if (_resourceId == null || _resourceId!.isEmpty) {
      NotificationOverlayManager()
          .showError(title: 'Thiếu $_noun', message: 'Chọn $_noun');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty && _customerId == null) {
      NotificationOverlayManager()
          .showError(title: 'Thiếu khách', message: 'Nhập tên hoặc chọn CRM');
      return;
    }
    if (_requireService && _serviceProductId == null) {
      NotificationOverlayManager()
          .showError(title: 'Thiếu dịch vụ', message: 'Chọn dịch vụ');
      return;
    }

    final slotLocal = DateTime(
      _usageDay.year,
      _usageDay.month,
      _usageDay.day,
      _slotTime.hour,
      _slotTime.minute,
    );
    final depositPaid =
        double.tryParse(_depositPaidCtrl.text.trim().replaceAll(',', '')) ??
            0;

    setState(() => _saving = true);
    final body = <String, dynamic>{
      'resourceId': _resourceId,
      'customerName': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim().isEmpty
          ? null
          : _phoneCtrl.text.trim(),
      'customerId': _customerId,
      'guestCount': _guestCount < 1 ? 1 : _guestCount,
      'slotStart': slotLocal.toUtc().toIso8601String(),
      if (_isHotel) 'stayNights': _stayNights,
      if (!_isHotel) 'durationMinutes': _durationMinutes,
      if (_serviceProductId != null) 'serviceProductId': _serviceProductId,
      'assignedEmployeeId': _employeeId,
      'note':
          _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      'occasion': _occasion,
      'specialRequest': () {
        final parts = [
          ..._requestTags,
          if (_requestCtrl.text.trim().isNotEmpty) _requestCtrl.text.trim(),
        ];
        return parts.isEmpty ? null : parts.join(' · ');
      }(),
      if (widget.existing == null && depositPaid > 0) ...{
        'depositAmount': depositPaid,
        'depositPaid': depositPaid,
        ..._depositPay.toCreateBody(),
      },
    };
    final res = widget.existing == null
        ? await _api.createPosResourceReservation(body)
        : await _api.updatePosResourceReservation(widget.existing!.id, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: tr(widget.existing == null
            ? 'Đã ${_profile.bookActionLabel.toLowerCase()}'
            : 'Đã lưu lịch'),
        message:
            '${DateFormat('HH:mm dd/MM').format(slotLocal)} · ${_nameCtrl.text.trim()}',
      );
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: widget.existing == null ? 'Không đặt được' : 'Không sửa được',
        message: res['message']?.toString() ?? 'Lỗi',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceIds = {for (final p in _services) p.id};
    final employeeIds = {for (final e in _employees) e.id};
    final resourceIds = {for (final r in widget.resources) r.id};
    return AlertDialog(
      title: Text(tr(widget.existing == null
          ? _profile.bookActionLabel
          : 'Sửa lịch đặt')),
      content: SizedBox(
        width: 420,
        child: _loadingMeta
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving ? null : () => unawaited(_pickCustomer()),
                        icon: const Icon(Icons.person_search_outlined,
                            size: 18),
                        label: Text(tr(_customerId == null
                            ? 'Chọn khách CRM'
                            : 'Đổi khách CRM')),
                      ),
                    ),
                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: tr('Tên khách *'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phoneCtrl,
                      decoration: InputDecoration(
                        labelText: tr('SĐT'),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      value: _guestCount < 1 ? 1 : _guestCount,
                      decoration: InputDecoration(
                        labelText: tr('Số khách'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final n in ({
                          1, 2, 3, 4, 5, 6, 8, 10, 12, _guestCount.clamp(1, 99),
                        }.toList()
                          ..sort()))
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _guestCount = v);
                              }
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: resourceIds.contains(_resourceId)
                          ? _resourceId
                          : null,
                      decoration: InputDecoration(
                        labelText: tr('${_noun[0].toUpperCase()}${_noun.substring(1)} *'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: widget.resources
                          .map((r) => DropdownMenuItem(
                                value: r.id,
                                child: Text(tr(r.areaName.trim().isEmpty
                                    ? r.name
                                    : '${r.areaName} · ${r.name}')),
                              ))
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _resourceId = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: serviceIds.contains(_serviceProductId)
                          ? _serviceProductId
                          : null,
                      decoration: InputDecoration(
                        labelText: tr(_requireService
                            ? 'Dịch vụ *'
                            : 'Dịch vụ (tuỳ chọn)'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        if (!_requireService)
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(tr('— Không chọn —')),
                          ),
                        ..._services.map((p) => DropdownMenuItem<String?>(
                              value: p.id,
                              child: Text(tr(
                                  '${p.name}${p.defaultDurationMinutes != null ? ' (${p.defaultDurationMinutes}′)' : ''}')),
                            )),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) {
                              PosProduct? p;
                              for (final x in _services) {
                                if (x.id == v) {
                                  p = x;
                                  break;
                                }
                              }
                              setState(() => _onServicePicked(p));
                            },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      initialDate: _usageDay,
                                      firstDate: DateTime.now()
                                          .subtract(const Duration(days: 1)),
                                      lastDate: DateTime.now()
                                          .add(const Duration(days: 180)),
                                    );
                                    if (d != null) {
                                      setState(() => _usageDay = DateTime(
                                          d.year, d.month, d.day));
                                    }
                                  },
                            icon: const Icon(Icons.event, size: 18),
                            label: Text(tr(
                                DateFormat('dd/MM/yyyy').format(_usageDay))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final t = await showTimePicker(
                                      context: context,
                                      initialTime: _slotTime,
                                      builder: (c, child) => MediaQuery(
                                        data: MediaQuery.of(c).copyWith(
                                          alwaysUse24HourFormat: true,
                                        ),
                                        child:
                                            child ?? const SizedBox.shrink(),
                                      ),
                                    );
                                    if (t != null) {
                                      setState(() => _slotTime = t);
                                    }
                                  },
                            icon: const Icon(Icons.access_time, size: 18),
                            label: Text(tr(
                                '${_slotTime.hour.toString().padLeft(2, '0')}:${_slotTime.minute.toString().padLeft(2, '0')}')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: _isHotel
                              ? DropdownButtonFormField<int>(
                                  value: _stayNights,
                                  decoration: InputDecoration(
                                    labelText: tr('Đêm'),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: List.generate(
                                    14,
                                    (i) => DropdownMenuItem(
                                      value: i + 1,
                                      child: Text('${i + 1}'),
                                    ),
                                  ),
                                  onChanged: _saving
                                      ? null
                                      : (v) {
                                          if (v != null) {
                                            setState(() => _stayNights = v);
                                          }
                                        },
                                )
                              : Builder(builder: (ctx) {
                                  final mins = <int>{
                                    30,
                                    45,
                                    60,
                                    75,
                                    90,
                                    120,
                                    _durationMinutes,
                                  }.toList()
                                    ..sort();
                                  return DropdownButtonFormField<int>(
                                    value: _durationMinutes,
                                    decoration: InputDecoration(
                                      labelText: tr('Phút'),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: mins
                                        .map((m) => DropdownMenuItem(
                                              value: m,
                                              child: Text('$m'),
                                            ))
                                        .toList(),
                                    onChanged: _saving
                                        ? null
                                        : (v) {
                                            if (v != null) {
                                              setState(
                                                  () => _durationMinutes = v);
                                            }
                                          },
                                  );
                                }),
                        ),
                      ],
                    ),
                    if (_showStaffPicker) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        value: employeeIds.contains(_employeeId)
                            ? _employeeId
                            : null,
                        decoration: InputDecoration(
                          labelText: tr('Nhân viên phụ trách'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(tr('— Không chọn —')),
                          ),
                          ..._employees.map((e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(tr(e.label)),
                              )),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _employeeId = v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tr('Loại tổ chức'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final o in PosReservationOccasion.options)
                          ChoiceChip(
                            label: Text(tr(o.$2),
                                style: const TextStyle(fontSize: 12)),
                            selected: _occasion == o.$1,
                            onSelected: _saving
                                ? null
                                : (v) => setState(
                                    () => _occasion = v ? o.$1 : null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tr('Yêu cầu thêm'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final chip in PosReservationOccasion.requestChips)
                          FilterChip(
                            label: Text(tr(chip),
                                style: const TextStyle(fontSize: 12)),
                            selected: _requestTags.contains(chip),
                            onSelected: _saving
                                ? null
                                : (v) => setState(() {
                                      if (v) {
                                        _requestTags.add(chip);
                                      } else {
                                        _requestTags.remove(chip);
                                      }
                                    }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _requestCtrl,
                      decoration: InputDecoration(
                        labelText: tr('Yêu cầu khác (ghi chú)'),
                        hintText: tr('VD: không cay, bàn gần cửa sổ…'),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    if (widget.existing == null) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _depositPaidCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('Thu cọc ngay'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixText: 'đ',
                        ),
                      ),
                      const SizedBox(height: 10),
                      PosDepositPaymentPicker(
                        compact: true,
                        value: _depositPay,
                        onChanged: (v) => setState(() => _depositPay = v),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: _noteCtrl,
                      decoration: InputDecoration(
                        labelText: tr('Ghi chú'),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(tr('Huỷ')),
        ),
        FilledButton(
          onPressed: _saving || _loadingMeta ? null : () => unawaited(_submit()),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(tr(widget.existing == null
                  ? _profile.bookActionLabel
                  : 'Lưu')),
        ),
      ],
    );
  }
}

class _EmpOpt {
  _EmpOpt({required this.id, required this.label});
  final String id;
  final String label;
}
