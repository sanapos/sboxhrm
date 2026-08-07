import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_customer.dart';
import '../../models/pos_product.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/safe_navigator.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';
import 'package:sbox_pos/l10n/app_ui_locale.dart';

/// Lịch hẹn theo ngày (salon): multi-slot, dịch vụ, NV, ghế.
class PosAppointmentDayScreen extends StatefulWidget {
  const PosAppointmentDayScreen({
    super.key,
    this.onSeated,
    this.initialDay,
    this.initialResourceId,
  });

  /// Khi nhận khách (seat) — payload giống sơ đồ bàn.
  final void Function(Map<String, dynamic> result)? onSeated;
  final DateTime? initialDay;
  final String? initialResourceId;

  @override
  State<PosAppointmentDayScreen> createState() =>
      _PosAppointmentDayScreenState();
}

class _PosAppointmentDayScreenState extends State<PosAppointmentDayScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

  late DateTime _day;
  bool _loading = true;
  String? _error;
  List<PosResourceReservationDto> _items = [];
  List<PosServiceResourceDto> _resources = [];

  @override
  void initState() {
    super.initState();
    final now = widget.initialDay ?? DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final dayUtc = DateTime.utc(_day.year, _day.month, _day.day);
    try {
      final results = await Future.wait([
        _api.getPosResourceReservations(day: dayUtc),
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

      setState(() {
        _items = list;
        _resources = resources.where((r) => r.isActive).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
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
    setState(() => _day = DateTime(d.year, d.month, d.day));
    await _reload();
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
      ),
    );
    if (ok == true && mounted) await _reload();
  }

  Future<void> _openBooking(PosResourceReservationDto b) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final start = b.reservedAt?.toLocal();
        final end = b.reservedUntil?.toLocal();
        final time = start == null
            ? ''
            : end == null
                ? DateFormat('HH:mm').format(start)
                : '${DateFormat('HH:mm').format(start)}–${DateFormat('HH:mm').format(end)}';
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(tr(b.customerName),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr([
                  if (time.isNotEmpty) time,
                  if ((b.serviceProductName ?? '').isNotEmpty)
                    b.serviceProductName!,
                  if (b.durationMinutes != null) '${b.durationMinutes}′',
                  '${b.areaName == null || b.areaName!.isEmpty ? b.resourceName : '${b.areaName} · ${b.resourceName}'}',
                  if ((b.assignedEmployeeName ?? '').isNotEmpty)
                    b.assignedEmployeeName!,
                  if (b.depositPaid > 0)
                    'Cọc ${_moneyFmt.format(b.depositPaid)}đ',
                ].join(' · '))),
              ),
              const Divider(height: 1),
              if (b.isBooked) ...[
                ListTile(
                  leading:
                      const Icon(Icons.login, color: PosTheme.kiotBlue),
                  title: Text(tr('Khách đến — nhận ghế')),
                  onTap: () => Navigator.pop(ctx, 'seat'),
                ),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: Text(tr('Hủy lịch hẹn')),
                  onTap: () => Navigator.pop(ctx, 'cancel'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
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
          title: 'Không nhận ghế',
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
          title: 'Đã nhận ghế',
          message: b.customerName,
        );
        await _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayLabel = DateFormat('EEEE, dd/MM/yyyy', 'vi_VN').format(_day);
    final isToday = DateUtils.isSameDay(_day, DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(tr('Lịch hẹn')),
        actions: [
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
        label: Text(tr('Đặt lịch')),
        backgroundColor: PosTheme.kiotBlue,
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => unawaited(_shiftDay(-1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => unawaited(_pickDay()),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            Text(
                              tr(dayLabel),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            if (isToday)
                              Text(tr('Hôm nay'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: PosTheme.kiotBlue)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => unawaited(_shiftDay(1)),
                    icon: const Icon(Icons.chevron_right),
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
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available_outlined,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(tr('Chưa có lịch hẹn trong ngày'),
                                style: TextStyle(
                                    color: PosTheme.textSecondary)),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () =>
                                  unawaited(_bookAppointment()),
                              icon: const Icon(Icons.add),
                              label: Text(tr('Đặt lịch mới')),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final b = _items[i];
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
                            final accent = b.isTimedSlot
                                ? const Color(0xFF7C3AED)
                                : PosTheme.kiotBlue;
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
                                            Text(
                                              tr(b.customerName),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
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
                                                  '${b.durationMinutes} phút',
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

class _BookAppointmentDialog extends StatefulWidget {
  const _BookAppointmentDialog({
    required this.day,
    required this.resources,
    this.initialResourceId,
    this.slotHint,
  });

  final DateTime day;
  final List<PosServiceResourceDto> resources;
  final String? initialResourceId;
  final TimeOfDay? slotHint;

  @override
  State<_BookAppointmentDialog> createState() => _BookAppointmentDialogState();
}

class _BookAppointmentDialogState extends State<_BookAppointmentDialog> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _depositPaidCtrl = TextEditingController();

  String? _customerId;
  String? _resourceId;
  String? _serviceProductId;
  String? _employeeId;
  late TimeOfDay _slotTime;
  int _durationMinutes = 60;
  bool _saving = false;
  bool _loadingMeta = true;

  List<PosProduct> _services = [];
  List<_EmpOpt> _employees = [];

  @override
  void initState() {
    super.initState();
    _resourceId = widget.initialResourceId ??
        (widget.resources.isNotEmpty ? widget.resources.first.id : null);
    final now = DateTime.now();
    _slotTime = widget.slotHint ??
        TimeOfDay(
          hour: DateUtils.isSameDay(widget.day, now)
              ? ((now.hour + 1) % 24)
              : 9,
          minute: 0,
        );
    unawaited(_loadMeta());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    _depositPaidCtrl.dispose();
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
      if (_serviceProductId == null && services.isNotEmpty) {
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
          .showError(title: 'Thiếu ghế', message: 'Chọn ghế / bàn');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty && _customerId == null) {
      NotificationOverlayManager()
          .showError(title: 'Thiếu khách', message: 'Nhập tên hoặc chọn CRM');
      return;
    }
    if (_serviceProductId == null) {
      NotificationOverlayManager()
          .showError(title: 'Thiếu dịch vụ', message: 'Chọn dịch vụ');
      return;
    }

    final slotLocal = DateTime(
      widget.day.year,
      widget.day.month,
      widget.day.day,
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
      'guestCount': 1,
      'slotStart': slotLocal.toUtc().toIso8601String(),
      'durationMinutes': _durationMinutes,
      'serviceProductId': _serviceProductId,
      'assignedEmployeeId': _employeeId,
      'note':
          _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      if (depositPaid > 0) ...{
        'depositAmount': depositPaid,
        'depositPaid': depositPaid,
        'depositPaymentMethod': 'Tiền mặt',
      },
    };
    final res = await _api.createPosResourceReservation(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã đặt lịch',
        message:
            '${DateFormat('HH:mm').format(slotLocal)} · ${_nameCtrl.text.trim()}',
      );
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Không đặt được',
        message: res['message']?.toString() ?? 'Lỗi',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Đặt lịch hẹn')),
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
                    DropdownButtonFormField<String>(
                      value: _resourceId,
                      decoration: InputDecoration(
                        labelText: tr('Ghế / bàn *'),
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
                    DropdownButtonFormField<String>(
                      value: _serviceProductId,
                      decoration: InputDecoration(
                        labelText: tr('Dịch vụ *'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _services
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(tr(
                                    '${p.name}${p.defaultDurationMinutes != null ? ' (${p.defaultDurationMinutes}′)' : ''}')),
                              ))
                          .toList(),
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
                          child: Builder(builder: (ctx) {
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
                                        setState(() => _durationMinutes = v);
                                      }
                                    },
                            );
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: _employeeId,
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
              : Text(tr('Đặt lịch')),
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
