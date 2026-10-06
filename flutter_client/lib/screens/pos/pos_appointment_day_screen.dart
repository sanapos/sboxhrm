import 'dart:async';

import '../../providers/permission_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_customer.dart';
import '../../models/pos_product.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/safe_navigator.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_deposit_payment_picker.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';

import '../../theme/sbox_tokens.dart';
Color reservationAccent(PosResourceReservationDto b) {
  if (b.isCancelled) return SboxColors.slate500;
  if (b.isNoShow) return const Color(0xFFC2410C);
  if (b.isOrderCompleted) return SboxColors.payHover;
  if (b.isUsingTable) return const Color(0xFF0F766E);
  if (b.isSeated) return SboxColors.payHover;
  return b.isTimedSlot ? SboxColors.violet : PosTheme.kiotBlue;
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
  /// Cọc của khách không đến — cửa hàng giữ lại (thu nhập), không còn «đang giữ».
  double get _depositForfeitedSum => _items
      .where((e) => e.depositStatus.toLowerCase() == 'forfeited')
      .fold(0.0, (s, e) => s + e.depositPaid);


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
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(tr(list.isEmpty
                      ? 'Chưa có lịch'
                      : '${list.length} lịch hẹn')),
                  trailing: !_canBook
                      ? null
                      : TextButton.icon(
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
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => unawaited(_openMonthDaySheet(day)),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? PosTheme.kiotBlue
                            : isToday
                                ? PosTheme.kiotBlue.withOpacity(0.45)
                                : SboxColors.slate200,
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
                            fontWeight: FontWeight.w700,
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
        message: tr('${_moneyFmt.format(amount)}đ · ${picked.pay.methodLabel} · ${b.customerName}'),
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Không thu được cọc',
        message: res['message']?.toString() ?? 'Lỗi',
      );
    }
  }

  /// Đặt / sửa / hủy / cọc lịch hẹn = quyền Tạo «Đặt chỗ» (server chặn cùng mức).
  bool get _canBook => context.read<PermissionProvider>().canCreate('PosBooking');

  bool _denyBooking() {
    if (_canBook) return false;
    NotificationOverlayManager().showError(
      title: 'Không có quyền',
      message: tr('Tài khoản không có quyền đặt / sửa lịch hẹn'),
    );
    return true;
  }

  Future<void> _bookAppointment({
    PosServiceResourceDto? resource,
    TimeOfDay? slotHint,
  }) async {
    if (_denyBooking()) return;
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
    if (_denyBooking()) return;
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
    if (action != 'edit' && _denyBooking()) return;
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
          return SboxColors.warning;
        case 'occupied':
          return SboxColors.danger;
        default:
          return SboxColors.success;
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
                              selected ? FontWeight.w700 : FontWeight.w500,
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

    // Trong khung chính thanh trên đã có tiêu đề — không vẽ thêm «Lịch đặt bàn»; các nút chuyển xuống hàng ngày.
    final hideTitle = HrmPageChrome.hideInPageTitle(context);
    final headerActions = <Widget>[
      IconButton(
        tooltip: tr(_showMonth ? 'Xem theo ngày' : 'Xem theo tháng'),
        onPressed: _loading ? null : () => unawaited(_toggleMonthView()),
        icon: Icon(_showMonth ? Icons.view_agenda_outlined : Icons.calendar_month),
      ),
      PopupMenuButton<String>(
        tooltip: tr('Thao tác khác'),
        icon: const Icon(Icons.more_vert),
        onSelected: (v) {
          if (v == 'grid') setState(() => _showGrid = !_showGrid);
          if (v == 'noshow') unawaited(_expireNoShows());
        },
        itemBuilder: (_) => [
          if (_useRoomGrid)
            PopupMenuItem(
              value: 'grid',
              child: ListTile(
                dense: true,
                leading: Icon(_showGrid ? Icons.view_list_outlined : Icons.grid_view_outlined),
                title: Text(tr(_showGrid ? 'Xem dạng danh sách' : 'Xem lịch theo bàn / phòng')),
              ),
            ),
          PopupMenuItem(
            value: 'noshow',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(tr('Đánh dấu khách không đến (quá giờ)')),
            ),
          ),
        ],
      ),
    ];
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: hideTitle
          ? null
          : AppBar(
              title: Text(tr(_calendarTitle)),
              actions: headerActions,
            ),
      floatingActionButton: context.watch<PermissionProvider>().canCreate('PosBooking')
          ? FloatingActionButton.extended(
              onPressed: _resources.isEmpty
                  ? null
                  : () => unawaited(_bookAppointment()),
              icon: const Icon(Icons.add),
              label: Text(tr(_profile.bookActionLabel)),
              backgroundColor: PosTheme.kiotBlue,
            )
          : null,
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
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              tr(_showMonth
                                  ? DateFormat('MMMM yyyy', 'vi_VN')
                                      .format(_month)
                                  : DateFormat(hideTitle ? 'EEE, dd/MM/yyyy' : 'EEEE, dd/MM/yyyy', 'vi_VN')
                                      .format(_day)),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
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
                      if (hideTitle) ...headerActions,
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
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 44,
                              decoration: BoxDecoration(
                                color: selected
                                    ? PosTheme.kiotBlue
                                    : SboxColors.slate100,
                                borderRadius: BorderRadius.circular(10),
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
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: selected
                                          ? Colors.white
                                          : SboxColors.text,
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
                      color: SboxColors.brand50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    // Số liệu CÙNG phạm vi đang xem (ngày / tháng) — trước đây số lịch theo ngày nhưng cọc /
                    // tạm tính lại cộng cả 7 ngày, cọc mất của khách không đến không hiện.
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          tr(_items.isEmpty
                              ? 'Chưa có lịch'
                              : [
                                  '${_items.where((e) => !e.isCancelled).length} lịch',
                                  if (_bookedCount > 0) '$_bookedCount chưa đến',
                                  if (_items.any((e) => e.isSeated)) '${_items.where((e) => e.isSeated).length} đã nhận bàn',
                                  if (_items.any((e) => e.isNoShow)) '${_items.where((e) => e.isNoShow).length} không đến',
                                ].join(' · ')),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        Text(
                          tr('Cọc đang giữ ${_moneyFmt.format(_depositHeldSum)}đ'),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        if (_depositForfeitedSum > 0)
                          Text(
                            tr('Cọc mất (không đến) ${_moneyFmt.format(_depositForfeitedSum)}đ'),
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFFC2410C), fontWeight: FontWeight.w600),
                          ),
                        Text(
                          tr('Tạm tính ${_moneyFmt.format(_expectedRevenueSum)}đ'),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_showMonth && _upcomingBooked > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tr('6 ngày tiếp theo còn $_upcomingBooked lịch chờ đến'),
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
                        filterChip('booked', 'Chưa đến ($_bookedCount)'),
                        filterChip(
                            'seated',
                            'Đã nhận bàn (${_items.where((e) => e.isSeated).length})'),
                        filterChip(
                            'cancelled',
                            'Đã hủy (${_items.where((e) => e.isCancelled).length})'),
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
                                size: 48, color: SboxColors.slate400),
                            const SizedBox(height: 12),
                            Text(
                                tr(_items.isEmpty
                                    ? 'Chưa có lịch trong ngày'
                                    : 'Không có lịch theo bộ lọc'),
                                style: TextStyle(
                                    color: PosTheme.textSecondary)),
                            const SizedBox(height: 12),
                            if (_canBook)
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
                          itemBuilder: (_, i) => _bookingCard(visible[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// Thẻ một lịch: cột giờ gọn (giờ đến lớn, giờ kết thúc nhỏ), tên 1 dòng + trạng thái bên phải,
  /// thông tin dạng biểu tượng ngắn (bàn · khách · thời lượng · SĐT · NV), dịp / cọc / hóa đơn.
  Widget _bookingCard(PosResourceReservationDto b) {
    final start = b.reservedAt?.toLocal();
    final end = b.reservedUntil?.toLocal();
    final accent = reservationAccent(b);
    final table = b.areaName == null || b.areaName!.isEmpty ? b.resourceName : '${b.areaName} · ${b.resourceName}';
    final duration = b.durationMinutes == null
        ? null
        : b.durationMinutes! >= 1440
            ? '${(b.durationMinutes! / 1440).round()} đêm'
            : b.durationMinutes! >= 60 && b.durationMinutes! % 60 == 0
                ? '${b.durationMinutes! ~/ 60} giờ'
                : '${b.durationMinutes} phút';
    Widget info(IconData icon, String text, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color ?? SboxColors.slate500),
          const SizedBox(width: 3),
          Flexible(
            child: Text(tr(text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: color ?? PosTheme.textSecondary)),
          ),
        ]);
    final occasion = PosReservationOccasion.label(b.occasion);
    final money = <String>[
      if (b.depositPaid > 0) 'Cọc ${_moneyFmt.format(b.depositPaid)}đ (${reservationDepositLabel(b.depositStatus)})',
      if (b.preOrderValue > 0) 'Món ${_moneyFmt.format(b.preOrderValue)}đ',
    ];
    final order = <String>[
      if ((b.orderNo ?? '').isNotEmpty) 'HĐ ${b.orderNo}',
      if (b.orderTotal > 0) '${_moneyFmt.format(b.orderTotal)}đ',
      if (b.orderPaid > 0) 'Đã trả ${_moneyFmt.format(b.orderPaid)}đ',
    ];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => unawaited(_openBooking(b)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 54,
              child: Column(children: [
                Text(start == null ? '—' : DateFormat('HH:mm').format(start),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: accent)),
                if (end != null)
                  Text(DateUtils.isSameDay(start, end) ? DateFormat('HH:mm').format(end) : DateFormat('dd/MM').format(end),
                      style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(tr(b.customerName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(tr(reservationStatusLabel(b)),
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: accent)),
                  ),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 10, runSpacing: 3, children: [
                  info(Icons.table_restaurant_outlined, table),
                  if (b.guestCount > 0) info(Icons.people_outline, '${b.guestCount} khách'),
                  if ((b.serviceProductName ?? '').isNotEmpty) info(Icons.spa_outlined, b.serviceProductName!),
                  if (duration != null) info(Icons.timelapse, duration),
                  if ((b.phone ?? '').isNotEmpty) info(Icons.call_outlined, b.phone!),
                  if ((b.assignedEmployeeName ?? '').isNotEmpty) info(Icons.badge_outlined, b.assignedEmployeeName!),
                ]),
                if (occasion.isNotEmpty ||
                    (b.createdAt != null && b.reservedAt != null &&
                        !DateUtils.isSameDay(b.createdAt!.toLocal(), b.reservedAt!.toLocal()))) ...[
                  const SizedBox(height: 5),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (occasion.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: SboxColors.violet.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(tr('🎉 $occasion'),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: SboxColors.violet)),
                      ),
                    if (b.createdAt != null && b.reservedAt != null &&
                        !DateUtils.isSameDay(b.createdAt!.toLocal(), b.reservedAt!.toLocal()))
                      Text(tr('Đặt từ ${DateFormat('dd/MM').format(b.createdAt!.toLocal())}'),
                          style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                  ]),
                ],
                if (money.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  info(
                    Icons.savings_outlined,
                    money.join(' · '),
                    color: b.depositStatus.toLowerCase() == 'forfeited'
                        ? const Color(0xFFC2410C)
                        : b.depositStatus.toLowerCase() == 'refunded'
                            ? SboxColors.slate500
                            : const Color(0xFF0F766E),
                  ),
                ],
                if (order.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  info(Icons.receipt_long_outlined, order.join(' · '),
                      color: b.isOrderCompleted ? const Color(0xFF15803D) : const Color(0xFF0F766E)),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right, color: SboxColors.slate400),
          ]),
        ),
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
            : '${DateFormat('HH:mm').format(start)} – ${DateFormat('HH:mm').format(end)}';
    final useDay = start == null ? '' : DateFormat('EEE, dd/MM/yyyy', 'vi_VN').format(start);
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
              width: 100,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                        fontWeight: FontWeight.w700,
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
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
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    row('Giờ', time, emphasize: true),
                    row('Ngày dùng', useDay),
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
                          fontWeight: FontWeight.w700,
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
              // Nút chính rộng cả hàng, ba thao tác phụ chia đều bên dưới (không còn xếp lệch 2 hàng).
              child: b.isBooked
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(context, 'seat'),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                        icon: const Icon(Icons.login, size: 18),
                        label: Text(tr('Nhận $noun')),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        for (final (value, icon, label, danger) in [
                          ('deposit', Icons.payments_outlined, 'Thu cọc', false),
                          ('edit', Icons.edit_outlined, 'Sửa', false),
                          ('cancel', Icons.delete_outline, 'Xóa lịch', true),
                        ]) ...[
                          if (value != 'deposit') const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context, value),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 42),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                foregroundColor: danger ? Colors.red.shade700 : null,
                              ),
                              icon: Icon(icon, size: 17),
                              label: Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                      ]),
                    ])
                  : FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      child: Text(tr('Đóng')),
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
          .showError(title: 'Thiếu $_noun', message: tr('Chọn $_noun'));
      return;
    }
    if (_nameCtrl.text.trim().isEmpty && _customerId == null) {
      NotificationOverlayManager()
          .showError(title: 'Thiếu khách', message: tr('Nhập tên hoặc chọn CRM'));
      return;
    }
    if (_requireService && _serviceProductId == null) {
      NotificationOverlayManager()
          .showError(title: 'Thiếu dịch vụ', message: tr('Chọn dịch vụ'));
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
    final phone = MediaQuery.sizeOf(context).width < 600;
    final nounCap = '${_noun[0].toUpperCase()}${_noun.substring(1)}';
    const field = OutlineInputBorder();

    Widget section(String title, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(children: [
            Expanded(
              child: Text(tr(title),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SboxColors.slate700)),
            ),
            if (trailing != null) trailing,
          ]),
        );

    // Nút chọn ngày / giờ: 1 dòng, không xuống chữ khi hẹp.
    Widget pickBox(IconData icon, String label, String value, VoidCallback? onTap) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(labelText: tr(label), border: field, isDense: true),
            child: Row(children: [
              Icon(icon, size: 18, color: SboxColors.slate500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr(value),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        );

    final datePick = pickBox(Icons.event, 'Ngày', (_usageDay.year == DateTime.now().year
            ? DateFormat('EEE, dd/MM', 'vi_VN').format(_usageDay)
            : DateFormat('dd/MM/yyyy').format(_usageDay)),
        _saving
            ? null
            : () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _usageDay,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 180)),
                );
                if (d != null) setState(() => _usageDay = DateTime(d.year, d.month, d.day));
              });
    final timePick = pickBox(
        Icons.access_time,
        'Giờ đến',
        '${_slotTime.hour.toString().padLeft(2, '0')}:${_slotTime.minute.toString().padLeft(2, '0')}',
        _saving
            ? null
            : () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _slotTime,
                  builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
                if (t != null) setState(() => _slotTime = t);
              });

    final mins = <int>{30, 45, 60, 90, 120, 150, 180, 240, _durationMinutes}.toList()..sort();
    final durationPick = _isHotel
        ? DropdownButtonFormField<int>(
            initialValue: _stayNights,
            decoration: InputDecoration(labelText: tr('Số đêm'), border: field, isDense: true),
            items: List.generate(14, (i) => DropdownMenuItem(value: i + 1, child: Text(tr('${i + 1} đêm')))),
            onChanged: _saving ? null : (v) => v == null ? null : setState(() => _stayNights = v),
          )
        : DropdownButtonFormField<int>(
            initialValue: _durationMinutes,
            decoration: InputDecoration(labelText: tr('Thời lượng'), border: field, isDense: true),
            items: [
              for (final m in mins)
                DropdownMenuItem(
                  value: m,
                  child: Text(tr(m % 60 == 0 ? '${m ~/ 60} giờ' : m > 60 ? '${m ~/ 60} giờ ${m % 60}′' : '$m phút')),
                ),
            ],
            onChanged: _saving ? null : (v) => v == null ? null : setState(() => _durationMinutes = v),
          );

    final guests = InputDecorator(
      decoration: InputDecoration(
        labelText: tr('Số khách'),
        border: field,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _saving || _guestCount <= 1 ? null : () => setState(() => _guestCount--),
          icon: const Icon(Icons.remove, size: 18),
        ),
        Expanded(
          child: Text('$_guestCount',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _saving || _guestCount >= 200 ? null : () => setState(() => _guestCount++),
          icon: const Icon(Icons.add, size: 18),
        ),
      ]),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        section(
          'Khách hàng',
          trailing: TextButton.icon(
            onPressed: _saving ? null : () => unawaited(_pickCustomer()),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.person_search_outlined, size: 18),
            label: Text(tr(_customerId == null ? 'Chọn từ danh bạ' : 'Đổi khách')),
          ),
        ),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Tên khách *'), border: field, isDense: true),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: tr('Số điện thoại'),
            border: field,
            isDense: true,
            prefixIcon: const Icon(Icons.call_outlined, size: 18),
          ),
        ),
        section('Thời gian'),
        Row(children: [
          Expanded(flex: 3, child: datePick),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: timePick),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: durationPick),
          const SizedBox(width: 8),
          Expanded(child: guests),
        ]),
        section('$nounCap & dịch vụ'),
        DropdownButtonFormField<String>(
          initialValue: resourceIds.contains(_resourceId) ? _resourceId : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('$nounCap *'), border: field, isDense: true),
          items: widget.resources
              .map((r) => DropdownMenuItem(
                    value: r.id,
                    child: Text(tr(r.areaName.trim().isEmpty ? r.name : '${r.areaName} · ${r.name}'),
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: _saving ? null : (v) => setState(() => _resourceId = v),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: serviceIds.contains(_serviceProductId) ? _serviceProductId : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: tr(_requireService ? 'Dịch vụ *' : 'Dịch vụ (tuỳ chọn)'),
            border: field,
            isDense: true,
          ),
          items: [
            if (!_requireService) DropdownMenuItem<String?>(value: null, child: Text(tr('— Không chọn —'))),
            ..._services.map((p) => DropdownMenuItem<String?>(
                  value: p.id,
                  child: Text(
                      tr('${p.name}${p.defaultDurationMinutes != null ? ' (${p.defaultDurationMinutes}′)' : ''}'),
                      overflow: TextOverflow.ellipsis),
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
        if (_showStaffPicker) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: employeeIds.contains(_employeeId) ? _employeeId : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Nhân viên phụ trách'), border: field, isDense: true),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(tr('— Không chọn —'))),
              ..._employees.map((e) => DropdownMenuItem(value: e.id, child: Text(tr(e.label)))),
            ],
            onChanged: _saving ? null : (v) => setState(() => _employeeId = v),
          ),
        ],
        section('Dịp'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in PosReservationOccasion.options)
            ChoiceChip(
              label: Text(tr(o.$2)),
              selected: _occasion == o.$1,
              onSelected: _saving ? null : (v) => setState(() => _occasion = v ? o.$1 : null),
            ),
        ]),
        section('Yêu cầu thêm'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final chip in PosReservationOccasion.requestChips)
            FilterChip(
              label: Text(tr(chip)),
              selected: _requestTags.contains(chip),
              onSelected: _saving
                  ? null
                  : (v) => setState(() => v ? _requestTags.add(chip) : _requestTags.remove(chip)),
            ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _requestCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: tr('Yêu cầu khác'),
            hintText: tr('VD: không cay, bàn gần cửa sổ…'),
            border: field,
            isDense: true,
          ),
        ),
        if (widget.existing == null) ...[
          section('Đặt cọc'),
          TextField(
            controller: _depositPaidCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr('Thu cọc ngay (không bắt buộc)'),
              border: field,
              isDense: true,
              suffixText: tr('đ'),
            ),
          ),
          const SizedBox(height: 8),
          PosDepositPaymentPicker(
            compact: true,
            value: _depositPay,
            onChanged: (v) => setState(() => _depositPay = v),
          ),
        ],
        section('Ghi chú'),
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(labelText: tr('Ghi chú nội bộ'), border: field, isDense: true),
        ),
        const SizedBox(height: 4),
      ],
    );

    return Dialog(
      insetPadding: phone
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 20)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(children: [
              Icon(widget.existing == null ? Icons.event_available_outlined : Icons.edit_calendar_outlined,
                  color: PosTheme.kiotBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr(widget.existing == null ? _profile.bookActionLabel : 'Sửa lịch đặt'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          Flexible(
            child: _loadingMeta
                ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
                : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: body),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  child: Text(tr('Huỷ')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _saving || _loadingMeta ? null : () => unawaited(_submit()),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check, size: 18),
                  label: Text(tr(widget.existing == null ? _profile.bookActionLabel : 'Lưu thay đổi')),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _EmpOpt {
  _EmpOpt({required this.id, required this.label});
  final String id;
  final String label;
}
