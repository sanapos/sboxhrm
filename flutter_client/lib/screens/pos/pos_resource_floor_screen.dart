import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/pos_device_identity.dart';
import '../../utils/pos_table_label.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_kitchen_void_list_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';

/// Kết quả chọn bàn/phòng từ sơ đồ.
typedef PosFloorSelectCallback = void Function(Map<String, dynamic> result);

/// Bàn vừa trả về trống (để màn bán hủy draft gắn bàn đó).
typedef PosFloorResourceFreedCallback = void Function(String resourceId);

/// Sơ đồ khu vực — ô bàn/ghế/phòng với màu trạng thái, giờ, tạm tính.
///
/// [manageMode] = true: thêm/sửa khu–bàn, kéo sắp xếp vị trí (vào từ Nhiều hơn).
/// [manageMode] = false: chỉ chọn bàn / thao tác bán (nhúng trong Bán hàng).
class PosResourceFloorScreen extends StatefulWidget {
  const PosResourceFloorScreen({
    super.key,
    this.embedded = false,
    this.onSelect,
    this.onResourceFreed,
    this.showAppBar = true,
    this.autoRefreshSeconds = 20,
    this.sellProfile,
    this.manageMode = true,
    this.onHome,
    this.zeroPendingKitchenResourceIds = const {},
    this.billRequestedResourceIds = const {},
    this.releasedOrderIds = const {},
  });

  /// Nhúng trong màn bán hàng (không push route).
  final bool embedded;
  final PosFloorSelectCallback? onSelect;
  final PosFloorResourceFreedCallback? onResourceFreed;
  final bool showAppBar;
  final int autoRefreshSeconds;
  final PosSellProfile? sellProfile;

  /// true = quản lý mặt bằng; false = chỉ bán / chọn bàn.
  final bool manageMode;

  /// Nút về trang chủ (khi nhúng bán hàng).
  final VoidCallback? onHome;

  /// Bàn vừa báo bếp xong — ép badge chờ bếp = 0 đến khi server khớp.
  final Set<String> zeroPendingKitchenResourceIds;

  /// Bàn vừa in tạm tính — ép màu vàng cam đến khi server khớp.
  final Set<String> billRequestedResourceIds;

  /// Đơn máy này vừa nhả khóa khi về sơ đồ — không hiện «đang giữ».
  final Set<String> releasedOrderIds;

  @override
  State<PosResourceFloorScreen> createState() => _PosResourceFloorScreenState();
}

class _PosResourceFloorScreenState extends State<PosResourceFloorScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  List<PosServiceAreaDto> _areas = [];
  List<PosServiceResourceDto> _resources = [];
  String? _areaFilter;
  bool _loading = true;
  String? _error;
  bool _layoutEdit = false;
  bool _draggingLayout = false;
  int? _dragIndex;
  int? _dragPointer;
  Timer? _poll;
  Timer? _clock;
  String? _deviceId;

  bool get _isFnB => widget.sellProfile == PosSellProfile.restaurant;
  bool get _isHourly => widget.sellProfile == PosSellProfile.roomHourly;

  /// Bàn máy này đang **sửa** (có khóa), không tính bàn tạm rời.
  List<PosServiceResourceDto> get _tablesHeldByMe => _resources
      .where((r) =>
          r.isActivelyOpen &&
          r.isLockedByDevice(_deviceId) &&
          (r.openOrderId == null ||
              !widget.releasedOrderIds.contains(r.openOrderId)))
      .toList();

  @override
  void initState() {
    super.initState();
    unawaited(_loadDeviceId());
    _reload();
    // Bán hàng: poll nhanh để badge «chờ bếp» cập nhật kịp.
    final pollSec = widget.manageMode
        ? widget.autoRefreshSeconds
        : (widget.autoRefreshSeconds > 0
            ? widget.autoRefreshSeconds.clamp(1, 1)
            : 1);
    if (pollSec > 0) {
      _poll = Timer.periodic(
        Duration(seconds: pollSec),
        (_) {
          if (mounted && !_layoutEdit) _reload(silent: true);
        },
      );
    }
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _layoutEdit) return;
      if (_resources.any((r) => r.liveElapsedMinutes > 0)) {
        setState(() {});
      }
    });
  }

  Future<void> _loadDeviceId() async {
    final device = await PosDeviceIdentity.get();
    if (!mounted) return;
    setState(() => _deviceId = device.id);
  }

  PosServiceResourceDto _patchResourceFlags(PosServiceResourceDto r) {
    final rid = r.id.toLowerCase();
    final zeroKitchen =
        widget.zeroPendingKitchenResourceIds.any((e) => e.toLowerCase() == rid) &&
            r.pendingKitchenCount > 0;
    final forceBill =
        widget.billRequestedResourceIds.any((e) => e.toLowerCase() == rid) &&
            !r.billRequested &&
            !r.isBillRequested &&
            (r.hasOpenSession ||
                r.lineCount > 0 ||
                (r.occupancyStatus != 'Free' &&
                    r.occupancyStatus != 'Available'));
    var out = r;
    if (zeroKitchen || forceBill) {
      out = PosServiceResourceDto(
        id: r.id,
        areaId: r.areaId,
        areaName: r.areaName,
        code: r.code,
        name: r.name,
        resourceKind: r.resourceKind,
        capacity: r.capacity,
        sortOrder: r.sortOrder,
        defaultHourlyRate: r.defaultHourlyRate,
        isActive: r.isActive,
        occupancyStatus: forceBill ? 'BillRequested' : r.occupancyStatus,
        openSessionId: r.openSessionId,
        openOrderId: r.openOrderId,
        sessionStartedAt: r.sessionStartedAt,
        elapsedMinutes: r.elapsedMinutes,
        subtotal: r.subtotal,
        lineCount: r.lineCount,
        pendingKitchenCount: zeroKitchen ? 0 : r.pendingKitchenCount,
        guestCount: r.guestCount,
        billRequested: forceBill ? true : r.billRequested,
        needsCleaning: r.needsCleaning,
        orderNo: r.orderNo,
        layoutX: r.layoutX,
        layoutY: r.layoutY,
        layoutW: r.layoutW,
        layoutH: r.layoutH,
        reservationId: r.reservationId,
        reservationCustomerName: r.reservationCustomerName,
        reservationPhone: r.reservationPhone,
        reservationGuestCount: r.reservationGuestCount,
        reservationPreOrderCount: r.reservationPreOrderCount,
        reservationReservedUntil: r.reservationReservedUntil,
        lockedByDeviceId: r.lockedByDeviceId,
        lockedByDeviceName: r.lockedByDeviceName,
        lockedByDisplayName: r.lockedByDisplayName,
        lockExpiresAt: r.lockExpiresAt,
        tableSessionOpen: r.tableSessionOpen,
        hasParkedBill: r.hasParkedBill,
      );
    }
    // Máy này vừa về sơ đồ — hiện «tạm rời» ngay nếu server chưa cập nhật.
    // Máy khác đã lấy quyền → giữ theo server (đỏ / chỉ xem).
    final oid = out.openOrderId;
    if (oid != null &&
        oid.isNotEmpty &&
        widget.releasedOrderIds.contains(oid)) {
      if (out.tableSessionOpen && !out.isLockedByDevice(_deviceId)) {
        return out;
      }
      if (!out.tableSessionOpen || out.isLockedByDevice(_deviceId)) {
        return PosServiceResourceDto(
          id: out.id,
          areaId: out.areaId,
          areaName: out.areaName,
          code: out.code,
          name: out.name,
          resourceKind: out.resourceKind,
          capacity: out.capacity,
          sortOrder: out.sortOrder,
          defaultHourlyRate: out.defaultHourlyRate,
          isActive: out.isActive,
          occupancyStatus: out.lineCount > 0 ? 'Occupied' : 'Parked',
          openSessionId: out.openSessionId,
          openOrderId: out.openOrderId,
          sessionStartedAt: out.sessionStartedAt,
          elapsedMinutes: out.elapsedMinutes,
          subtotal: out.subtotal,
          lineCount: out.lineCount,
          pendingKitchenCount: out.pendingKitchenCount,
          guestCount: out.guestCount,
          billRequested: out.billRequested,
          needsCleaning: out.needsCleaning,
          orderNo: out.orderNo,
          layoutX: out.layoutX,
          layoutY: out.layoutY,
          layoutW: out.layoutW,
          layoutH: out.layoutH,
          reservationId: out.reservationId,
          reservationCustomerName: out.reservationCustomerName,
          reservationPhone: out.reservationPhone,
          reservationGuestCount: out.reservationGuestCount,
          reservationPreOrderCount: out.reservationPreOrderCount,
          reservationReservedUntil: out.reservationReservedUntil,
          lockedByDeviceId: null,
          lockedByDeviceName: null,
          lockedByDisplayName: null,
          lockExpiresAt: null,
          tableSessionOpen: false,
          hasParkedBill: true,
        );
      }
    }
    return out;
  }

  @override
  void didUpdateWidget(covariant PosResourceFloorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final kitchenChanged = oldWidget.zeroPendingKitchenResourceIds !=
        widget.zeroPendingKitchenResourceIds;
    final billChanged =
        oldWidget.billRequestedResourceIds != widget.billRequestedResourceIds;
    final releasedChanged =
        oldWidget.releasedOrderIds != widget.releasedOrderIds;
    if ((kitchenChanged || billChanged || releasedChanged) &&
        _resources.isNotEmpty) {
      setState(() {
        _resources = _resources.map(_patchResourceFlags).toList();
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final areaRes = await _api.getPosServiceAreas();
    final resRes = await _api.getPosServiceResources(areaId: _areaFilter);
    if (!mounted) return;
    if (areaRes['isSuccess'] != true || resRes['isSuccess'] != true) {
      if (!silent) {
        setState(() {
          _error = areaRes['message']?.toString() ??
              resRes['message']?.toString() ??
              'Không tải được sơ đồ';
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _areas = ((areaRes['data'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => PosServiceAreaDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      var resources = ((resRes['data'] as List?) ?? [])
          .whereType<Map>()
          .map((e) =>
              PosServiceResourceDto.fromJson(Map<String, dynamic>.from(e)))
          .map(_patchResourceFlags)
          .toList();
      _resources = resources;
      _loading = false;
      _error = null;
    });
  }

  void _emitSelect(Map<String, dynamic> result) {
    if (widget.onSelect != null) {
      widget.onSelect!(result);
      return;
    }
    Navigator.pop(context, result);
  }

  Future<PosServiceResourceDto> _probeResourceLock(PosServiceResourceDto r) async {
    final oid = r.openOrderId;
    if (oid == null || oid.isEmpty) return r;
    final device = await PosDeviceIdentity.get();
    final res = await _api.getPosSale(
      oid,
      deviceId: device.id,
      deviceName: device.name,
    );
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return r;
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final isLocked = data['isLocked'] == true || data['IsLocked'] == true;
    final lockedDev =
        (data['lockedByDeviceId'] ?? data['LockedByDeviceId'])?.toString();
    final lockedName =
        (data['lockedByDeviceName'] ?? data['LockedByDeviceName'])?.toString();
    final lockedWho =
        (data['lockedByDisplayName'] ?? data['LockedByDisplayName'])?.toString();
    final expRaw = data['lockExpiresAt'] ?? data['LockExpiresAt'];
    final atRaw = data['lockedAt'] ?? data['LockedAt'];
    final exp = expRaw != null
        ? DateTime.tryParse(expRaw.toString())?.toUtc()
        : null;
    final at =
        atRaw != null ? DateTime.tryParse(atRaw.toString())?.toUtc() : null;
    final now = DateTime.now().toUtc();
    var sessionOpen = false;
    if (isLocked && exp != null && exp.isAfter(now)) {
      if (at == null) {
        sessionOpen = true;
      } else {
        sessionOpen = now.difference(at).inSeconds <= 45;
      }
    }
    final updated = PosServiceResourceDto(
      id: r.id,
      areaId: r.areaId,
      areaName: r.areaName,
      code: r.code,
      name: r.name,
      resourceKind: r.resourceKind,
      capacity: r.capacity,
      sortOrder: r.sortOrder,
      defaultHourlyRate: r.defaultHourlyRate,
      isActive: r.isActive,
      occupancyStatus: r.occupancyStatus,
      openSessionId: r.openSessionId,
      openOrderId: r.openOrderId,
      sessionStartedAt: r.sessionStartedAt,
      elapsedMinutes: r.elapsedMinutes,
      subtotal: r.subtotal,
      lineCount: r.lineCount,
      pendingKitchenCount: r.pendingKitchenCount,
      guestCount: r.guestCount,
      billRequested: r.billRequested,
      needsCleaning: r.needsCleaning,
      orderNo: r.orderNo,
      layoutX: r.layoutX,
      layoutY: r.layoutY,
      layoutW: r.layoutW,
      layoutH: r.layoutH,
      reservationId: r.reservationId,
      reservationCustomerName: r.reservationCustomerName,
      reservationPhone: r.reservationPhone,
      reservationGuestCount: r.reservationGuestCount,
      reservationPreOrderCount: r.reservationPreOrderCount,
      reservationReservedUntil: r.reservationReservedUntil,
      lockedByDeviceId: sessionOpen ? lockedDev : null,
      lockedByDeviceName: sessionOpen ? lockedName : null,
      lockedByDisplayName: sessionOpen ? lockedWho : null,
      lockExpiresAt: sessionOpen ? exp : null,
      tableSessionOpen: sessionOpen,
      hasParkedBill: !sessionOpen && r.hasOpenSession,
    );
    final patched = _patchResourceFlags(updated);
    final idx = _resources.indexWhere((x) => x.id == r.id);
    if (idx >= 0 && mounted) {
      setState(() => _resources[idx] = patched);
    }
    return patched;
  }

  void _emitViewOnlyTable(PosServiceResourceDto r) {
    if (r.openOrderId == null || r.openOrderId!.isEmpty) return;
    _emitSelect({
      'saleOrderId': r.openOrderId,
      'sessionId': r.openSessionId,
      'resourceId': r.id,
      'resourceName': r.name,
      'areaName': r.areaName,
      'startedAt': r.sessionStartedAt?.toUtc().toIso8601String(),
      'guestCount': r.guestCount,
    });
  }

  Future<void> _openResource(
    PosServiceResourceDto r, {
    bool skipHoldingPrompt = false,
  }) async {
    if (r.isReserved) {
      await _showReservedActions(r);
      return;
    }

    // Đang dùng / tạm rời / holding → vào lại đơn.
    if (r.isOccupied || r.isHolding || r.isParked) {
      // Luôn probe trước khi hỏi «Lấy quyền» — máy khác có thể vừa claim.
      if (r.hasParkedBill || (r.isParked && !r.isActivelyOpen)) {
        r = await _probeResourceLock(r);
        if (!mounted) return;
      }

      // Máy khác đang sửa → chỉ xem, không hỏi «Lấy quyền».
      if (r.isLockedByOtherDevice(_deviceId)) {
        _emitViewOnlyTable(r);
        return;
      }

      if (r.hasParkedBill && !r.isActivelyOpen) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr(r.name)),
            content: Text(
              tr(r.lineCount > 0
                  ? 'Bàn có đơn tạm (${r.lineCount} món) — không ai đang sửa.\n'
                      'Bấm «Lấy quyền» để tiếp tục.'
                  : 'Bàn đã mở nhưng tạm rời — bấm «Lấy quyền» để chọn món.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Đóng')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'view'),
                child: Text(tr('Chỉ xem')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'take'),
                child: Text(tr('Lấy quyền')),
              ),
            ],
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'view') {
          // Vào chỉ xem — sell screen mở im lặng.
        } else if (choice != 'take') {
          return;
        }
        if (choice == 'take' && r.openOrderId != null && r.openOrderId!.isNotEmpty) {
          _emitSelect({
            'saleOrderId': r.openOrderId,
            'sessionId': r.openSessionId,
            'resourceId': r.id,
            'resourceName': r.name,
            'areaName': r.areaName,
            'startedAt': r.sessionStartedAt?.toUtc().toIso8601String(),
            'guestCount': r.guestCount,
            'forceClaim': true,
          });
          return;
        }
      } else if (r.isHolding && !skipHoldingPrompt) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr(r.name)),
            content: Text(
              tr('Bàn đã mở nhưng chưa gọi món.\n'
              'Bạn muốn vào chọn món hay trả bàn về trống?'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Đóng')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'free'),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                child: Text(tr('Trả về trống')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'open'),
                child: Text(tr('Vào chọn món')),
              ),
            ],
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'free') {
          await _freeHoldingTable(r);
          return;
        }
        // Tiếp tục mở đơn — không hỏi lại.
      }
      if (r.openOrderId != null && r.openOrderId!.isNotEmpty) {
        // Đơn đã TT / hủy nhưng phiên còn sót → giải phóng rồi mở bàn mới ngay.
        final probe = await _api.getPosSale(r.openOrderId!);
        if (!mounted) return;
        if (probe['isSuccess'] == true && probe['data'] is Map) {
          final st = (probe['data']['status'] ?? probe['data']['Status'] ?? '')
              .toString()
              .toLowerCase();
          if (st != 'draft') {
            if (r.openSessionId != null && r.openSessionId!.isNotEmpty) {
              await _api.closePosResourceSession(r.openSessionId!);
            }
            if (!mounted) return;
            await _reload();
            if (!mounted) return;
            final freed =
                _resources.where((x) => x.id == r.id).firstOrNull ?? r;
            // Còn Occupied (draft mồ côi) → OpenSession heal; Free → mở mới.
            await _startResourceSession(freed);
            return;
          }
        } else if (probe['isSuccess'] != true) {
          // Không tải được đơn (đã xóa/lỗi) — đóng phiên sót rồi mở mới.
          if (r.openSessionId != null && r.openSessionId!.isNotEmpty) {
            await _api.closePosResourceSession(r.openSessionId!);
          }
          if (!mounted) return;
          await _reload();
          if (!mounted) return;
          final freed = _resources.where((x) => x.id == r.id).firstOrNull ?? r;
          await _startResourceSession(freed);
          return;
        }
        _emitSelect({
          'saleOrderId': r.openOrderId,
          'sessionId': r.openSessionId,
          'resourceId': r.id,
          'resourceName': r.name,
          'areaName': r.areaName,
          'startedAt': r.sessionStartedAt?.toUtc().toIso8601String(),
          'guestCount': r.guestCount,
        });
      } else {
        // Occupied/Holding không có openOrderId (draft mồ côi) → OpenSession gắn lại.
        await _startResourceSession(r);
      }
      return;
    }

    final guests = await _promptGuestCount(r);
    if (guests == null || !mounted) return;
    await _startResourceSession(r, guestCount: guests);
  }

  Future<int?> _promptGuestCount(PosServiceResourceDto r) async {
    final maxGuests = r.capacity > 0 ? r.capacity : 99;
    final ctrl = TextEditingController(text: tr('2'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Mở ${r.name}')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(r.capacity > 0 ? 'Số khách (tối đa $maxGuests)' : 'Số khách'),
              style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: tr('VD: 4'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Mở bàn'))),
        ],
      ),
    );
    if (ok != true) return null;
    final n = int.tryParse(ctrl.text.trim()) ?? 2;
    return n.clamp(1, maxGuests);
  }

  Future<void> _startResourceSession(
    PosServiceResourceDto r, {
    int guestCount = 1,
  }) async {
    final device = await PosDeviceIdentity.get();
    final res = await _api.openPosResourceSession({
      'resourceId': r.id,
      'deviceId': device.id,
      'deviceName': device.name,
      'guestCount': guestCount,
    });
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không mở được',
        message: res['message']?.toString() ?? 'Lỗi',
      );
      return;
    }
    final data = res['data'] as Map? ?? {};
    _emitSelect({
      'saleOrderId': data['saleOrderId']?.toString(),
      'sessionId': data['sessionId']?.toString(),
      'resourceId': r.id,
      'resourceName': r.name,
      'areaName': r.areaName,
      'orderNo': data['orderNo']?.toString(),
      'startedAt': data['startedAt']?.toString(),
      'guestCount': (data['guestCount'] as num?)?.toInt() ?? guestCount,
    });
  }

  Future<void> _showReservedActions(PosServiceResourceDto r) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                tr(formatPosTableLabel(areaName: r.areaName, tableName: r.name)),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(tr([
                r.reservationCustomerName ?? 'Khách đặt',
                if ((r.reservationPhone ?? '').isNotEmpty) r.reservationPhone!,
                if (r.reservationGuestCount > 0)
                  '${r.reservationGuestCount} khách',
                if (r.reservationReservedUntil != null)
                  'Đến ${DateFormat('dd/MM HH:mm').format(r.reservationReservedUntil!.toLocal())}',
                if (r.reservationPreOrderCount > 0)
                  '${r.reservationPreOrderCount} món đặt trước',
              ].join(' · '))),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.login, color: PosTheme.kiotBlue),
              title: Text(tr('Khách đến — nhận bàn')),
              subtitle: Text(tr('Mở bàn + đưa món đặt trước vào đơn')),
              onTap: () => Navigator.pop(ctx, 'seat'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: Colors.red),
              title: Text(tr('Hủy đặt bàn')),
              onTap: () => Navigator.pop(ctx, 'cancel'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'cancel') {
      final rid = r.reservationId;
      if (rid == null || rid.isEmpty) return;
      final res = await _api.cancelPosResourceReservation(rid);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(
          title: 'Đã hủy đặt',
          message: r.name,
        );
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
      final rid = r.reservationId;
      if (rid == null || rid.isEmpty) return;
      final res = await _api.seatPosResourceReservation(rid);
      if (!mounted) return;
      if (res['isSuccess'] != true) {
        NotificationOverlayManager().showError(
          title: 'Không nhận bàn',
          message: res['message']?.toString() ?? 'Lỗi',
        );
        return;
      }
      final data = res['data'] as Map? ?? {};
      _emitSelect({
        'saleOrderId': data['saleOrderId']?.toString(),
        'sessionId': data['sessionId']?.toString(),
        'resourceId': r.id,
        'resourceName': r.name,
        'areaName': r.areaName,
        'orderNo': data['orderNo']?.toString(),
        'startedAt': data['startedAt']?.toString(),
        'guestCount': data['guestCount'],
      });
    }
  }

  Future<void> _showReserveDialog(PosServiceResourceDto r) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final guestCtrl = TextEditingController(text: tr('2'));
    final noteCtrl = TextEditingController();
    final preItems = <Map<String, dynamic>>[];
    // Mặc định: hôm nay, giờ hiện tại làm tròn +1 giờ.
    final now = DateTime.now();
    var arriveDate = DateTime(now.year, now.month, now.day);
    var arriveTime = TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
    final tableLabel = r.areaName.trim().isEmpty
        ? r.name
        : '${r.areaName} · ${r.name}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr('Đặt bàn — $tableLabel')),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: tr('Tên khách *'),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    decoration: InputDecoration(
                      labelText: tr('SĐT'),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: guestCtrl,
                    decoration: InputDecoration(
                      labelText: tr('Số khách'),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: arriveDate,
                              firstDate: DateTime(now.year, now.month, now.day),
                              lastDate: now.add(const Duration(days: 365)),
                              locale: appUiLocale(),
                            );
                            if (d != null) {
                              setLocal(() => arriveDate =
                                  DateTime(d.year, d.month, d.day));
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            tr(DateFormat('dd/MM/yyyy').format(arriveDate)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: arriveTime,
                              builder: (c, child) => MediaQuery(
                                data: MediaQuery.of(c).copyWith(
                                  alwaysUse24HourFormat: true,
                                ),
                                child: child ?? const SizedBox.shrink(),
                              ),
                            );
                            if (t != null) setLocal(() => arriveTime = t);
                          },
                          icon: const Icon(Icons.access_time, size: 18),
                          label: Text(
                            tr('${arriveTime.hour.toString().padLeft(2, '0')}:'
                            '${arriveTime.minute.toString().padLeft(2, '0')}'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('Ngày / giờ khách đến'),
                      style: TextStyle(
                          fontSize: 12, color: PosTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: tr('Ghi chú'),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(tr('Món đặt trước'),
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final item = await _pickPreOrderProduct();
                          if (item == null) return;
                          setLocal(() => preItems.add(item));
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(tr('Chọn từ menu')),
                      ),
                    ],
                  ),
                  if (preItems.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(tr('Chưa chọn món (có thể thêm sau khi nhận bàn)'),
                        style: TextStyle(
                            fontSize: 12, color: PosTheme.textSecondary),
                      ),
                    )
                  else
                    ...preItems.asMap().entries.map((e) {
                      final i = e.key;
                      final it = e.value;
                      final qty = (it['qty'] as num?)?.toDouble() ?? 1;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr('${it['name']}')),
                        subtitle: Text(tr('SL: ${qty % 1 == 0 ? qty.toInt() : qty}')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 20),
                              onPressed: () => setLocal(() {
                                final q =
                                    ((it['qty'] as num?)?.toDouble() ?? 1) - 1;
                                if (q <= 0) {
                                  preItems.removeAt(i);
                                } else {
                                  it['qty'] = q;
                                }
                              }),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 20),
                              onPressed: () => setLocal(() {
                                final q =
                                    ((it['qty'] as num?)?.toDouble() ?? 1) + 1;
                                it['qty'] = q;
                              }),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  setLocal(() => preItems.removeAt(i)),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Hủy'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Lưu đặt bàn'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu tên khách',
        message: tr('Nhập tên khách đặt bàn'),
      );
      return;
    }
    final guests = int.tryParse(guestCtrl.text.trim()) ?? 1;
    final arriveLocal = DateTime(
      arriveDate.year,
      arriveDate.month,
      arriveDate.day,
      arriveTime.hour,
      arriveTime.minute,
    );
    final res = await _api.createPosResourceReservation({
      'resourceId': r.id,
      'customerName': name,
      'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      'guestCount': guests < 1 ? 1 : guests,
      'reservedUntil': arriveLocal.toUtc().toIso8601String(),
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      if (preItems.isNotEmpty) 'preOrderItems': preItems,
    });
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã đặt bàn',
        message:
            '$tableLabel · $name · ${DateFormat('dd/MM HH:mm').format(arriveLocal)}',
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Không đặt được',
        message: res['message']?.toString() ?? 'Lỗi',
      );
    }
  }

  /// Chọn món từ menu (danh mục + tìm kiếm) — gắn productId để nhận bàn đưa vào đơn.
  Future<Map<String, dynamic>?> _pickPreOrderProduct() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> categories = [];
    List<Map<String, dynamic>> hits = [];
    String? categoryId;
    var loading = true;
    String? err;
    var bootstrapped = false;

    Future<void> loadProducts(
      void Function(void Function()) setLocal, {
      String? search,
      String? catId,
    }) async {
      setLocal(() {
        loading = true;
        err = null;
      });
      final res = await _api.getPosProducts(
        search: (search ?? '').trim().isEmpty ? null : search!.trim(),
        categoryId: catId,
        isDirectSale: true,
        pageSize: 80,
        sortBy: PosProductSortBy.name,
        sortDesc: false,
      );
      if (!mounted) return;
      if (res['isSuccess'] != true) {
        setLocal(() {
          loading = false;
          err = res['message']?.toString() ?? 'Không tải được menu';
          hits = [];
        });
        return;
      }
      final data = res['data'];
      final raw = data is Map
          ? ((data['items'] as List?) ??
              (data['Items'] as List?) ??
              const [])
          : ((data as List?) ?? const []);
      final list = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setLocal(() {
        loading = false;
        hits = list;
      });
    }

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.78;
        return SafeArea(
          child: SizedBox(
            height: h,
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                if (!bootstrapped) {
                  bootstrapped = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    final catRes = await _api.getPosProductCategories();
                    if (!ctx.mounted) return;
                    final raw = (catRes['data'] as List?) ?? const [];
                    final cats = raw
                        .whereType<Map>()
                        .map((e) => Map<String, dynamic>.from(e))
                        .toList();
                    setLocal(() => categories = cats);
                    await loadProducts(setLocal);
                  });
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text(tr('Chọn món từ menu'),
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          hintText: tr('Tìm món…'),
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (q) {
                          Future<void>.delayed(
                            const Duration(milliseconds: 280),
                            () {
                              if (searchCtrl.text != q) return;
                              loadProducts(setLocal,
                                  search: q, catId: categoryId);
                            },
                          );
                        },
                      ),
                    ),
                    if (categories.isNotEmpty)
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(tr('Tất cả')),
                                selected: categoryId == null,
                                onSelected: (_) {
                                  setLocal(() => categoryId = null);
                                  loadProducts(setLocal,
                                      search: searchCtrl.text, catId: null);
                                },
                              ),
                            ),
                            ...categories.map((c) {
                              final id =
                                  (c['id'] ?? c['Id'] ?? '').toString();
                              final name =
                                  (c['name'] ?? c['Name'] ?? '').toString();
                              if (id.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(tr(name)),
                                  selected: categoryId == id,
                                  onSelected: (_) {
                                    setLocal(() => categoryId = id);
                                    loadProducts(setLocal,
                                        search: searchCtrl.text, catId: id);
                                  },
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    const Divider(height: 12),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : err != null
                              ? Center(child: Text(tr(err!)))
                              : hits.isEmpty
                                  ? Center(
                                      child: Text(tr('Không có món trong menu')))
                                  : ListView.builder(
                                      itemCount: hits.length,
                                      itemBuilder: (_, i) {
                                        final p = hits[i];
                                        final id = (p['id'] ?? p['Id'] ?? '')
                                            .toString();
                                        final name =
                                            (p['name'] ?? p['Name'] ?? '')
                                                .toString();
                                        final price = (p['basePrice'] ??
                                                    p['BasePrice'] as num?)
                                                ?.toDouble() ??
                                            0;
                                        final unit = (p['baseUnitName'] ??
                                                p['BaseUnitName'] ??
                                                '')
                                            .toString();
                                        return ListTile(
                                          title: Text(tr(name)),
                                          subtitle: Text(
                                              tr('${_moneyFmt.format(price)}đ'
                                              '${unit.isEmpty ? '' : ' / $unit'}')),
                                          onTap: () {
                                            if (id.isEmpty) return;
                                            Navigator.pop(ctx, {
                                              'productId': id,
                                              'name': name,
                                              'qty': 1,
                                              'unitPrice': price,
                                              'unitName': unit,
                                            });
                                          },
                                        );
                                      },
                                    ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(tr('Đóng')),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showOccupiedActions(PosServiceResourceDto r) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                tr(formatPosTableLabel(areaName: r.areaName, tableName: r.name)),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(tr([
                if (r.guestCount > 0) '${r.guestCount} khách',
                if (r.elapsedLabel.isNotEmpty) r.elapsedLabel,
                if (r.subtotal > 0) '${_moneyFmt.format(r.subtotal)}đ',
                if (r.lineCount > 0) '${r.lineCount} món',
              ].join(' · '))),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: Text(tr('Vào chọn món / dịch vụ')),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            if (_isWaitingTable(r))
              ListTile(
                leading: Icon(Icons.event_seat_outlined,
                    color: Colors.red.shade700),
                title: Text(tr('Trả về bàn trống')),
                subtitle: Text(tr('Đóng phiên — bàn chưa gọi món')),
                onTap: () => Navigator.pop(ctx, 'free'),
              ),
            if (_isFnB || r.pendingKitchenCount > 0)
              ListTile(
                leading: const Icon(Icons.soup_kitchen_outlined),
                title: Text(
                  tr(r.pendingKitchenCount > 0
                      ? 'Báo chế biến (${r.pendingKitchenCount} món)'
                      : 'Báo chế biến'),
                ),
                onTap: () => Navigator.pop(ctx, 'kitchen'),
              ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(tr('Chuyển bàn')),
              onTap: () => Navigator.pop(ctx, 'transfer'),
            ),
            ListTile(
              leading: const Icon(Icons.call_split),
              title: Text(tr('Tách bàn')),
              subtitle: Text(tr('Chọn món chuyển sang bàn trống')),
              onTap: () => Navigator.pop(ctx, 'split'),
            ),
            ListTile(
              leading: const Icon(Icons.merge_type),
              title: Text(tr('Gộp bàn vào đây')),
              onTap: () => Navigator.pop(ctx, 'merge'),
            ),
            if (_isHourly) ...[
              if (r.isPaused)
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(tr('Tiếp tục tính giờ')),
                  onTap: () => Navigator.pop(ctx, 'resume'),
                )
              else
                ListTile(
                  leading: const Icon(Icons.pause),
                  title: Text(tr('Tạm dừng tính giờ')),
                  onTap: () => Navigator.pop(ctx, 'pause'),
                ),
            ],
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(tr('Số khách')),
              onTap: () => Navigator.pop(ctx, 'guests'),
            ),
            ListTile(
              leading: Icon(
                r.isBillRequested
                    ? Icons.request_quote
                    : Icons.request_quote_outlined,
              ),
              title: Text(
                  tr(r.isBillRequested ? 'Huỷ tạm tính' : 'Tạm tính')),
              onTap: () => Navigator.pop(ctx, 'bill'),
            ),
            if (widget.manageMode)
              ListTile(
                leading:
                    const Icon(Icons.stop_circle_outlined, color: Colors.red),
                title: Text(tr('Đóng phiên (giữ đơn)')),
                onTap: () => Navigator.pop(ctx, 'close'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    // Từng nhánh return — tránh chạy nhầm nhiều thao tác.
    if (action == 'open') {
      await _openResource(r, skipHoldingPrompt: true);
      return;
    }
    if (action == 'free') {
      await _freeHoldingTable(r);
      return;
    }
    if (action == 'kitchen') {
      await _kitchenSend(r);
      return;
    }
    if (action == 'transfer') {
      await _transfer(r);
      return;
    }
    if (action == 'split') {
      await _split(r);
      return;
    }
    if (action == 'merge') {
      await _merge(r);
      return;
    }
    if (action == 'pause') {
      await _pause(r);
      return;
    }
    if (action == 'resume') {
      await _resume(r);
      return;
    }
    if (action == 'guests') {
      await _setGuests(r);
      return;
    }
    if (action == 'bill') {
      await _toggleBill(r);
      return;
    }
    if (action == 'close') {
      await _closeSession(r);
    }
  }

  Future<void> _kitchenSend(PosServiceResourceDto r) async {
    final sid = r.openSessionId;
    if (sid == null) return;
    // Optimistic: xóa badge chờ bếp ngay trên ô bàn.
    if (r.pendingKitchenCount > 0) {
      setState(() {
        _resources = _resources.map((x) {
          if (x.id != r.id) return x;
          return PosServiceResourceDto(
            id: x.id,
            areaId: x.areaId,
            areaName: x.areaName,
            code: x.code,
            name: x.name,
            resourceKind: x.resourceKind,
            capacity: x.capacity,
            sortOrder: x.sortOrder,
            defaultHourlyRate: x.defaultHourlyRate,
            isActive: x.isActive,
            occupancyStatus: x.occupancyStatus,
            openSessionId: x.openSessionId,
            openOrderId: x.openOrderId,
            sessionStartedAt: x.sessionStartedAt,
            elapsedMinutes: x.elapsedMinutes,
            subtotal: x.subtotal,
            lineCount: x.lineCount,
            pendingKitchenCount: 0,
            guestCount: x.guestCount,
            billRequested: x.billRequested,
            needsCleaning: x.needsCleaning,
            orderNo: x.orderNo,
            layoutX: x.layoutX,
            layoutY: x.layoutY,
            layoutW: x.layoutW,
            layoutH: x.layoutH,
            reservationId: x.reservationId,
            reservationCustomerName: x.reservationCustomerName,
            reservationPhone: x.reservationPhone,
            reservationGuestCount: x.reservationGuestCount,
            reservationPreOrderCount: x.reservationPreOrderCount,
            reservationReservedUntil: x.reservationReservedUntil,
          );
        }).toList();
      });
    }
    final device = await PosDeviceIdentity.get();
    final res = await _api.kitchenSendPosResourceSession(
      sid,
      deviceId: device.id,
      deviceName: device.name,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'] is Map ? res['data'] as Map : const {};
      final n = (data['sentLines'] as num?)?.toInt() ?? 0;
      if (n <= 0 || data['alreadyAllSent'] == true) {
        NotificationOverlayManager().showWarning(
          title: 'Không có món mới',
          message: data['message']?.toString() ??
              'Các món đã báo bếp rồi — tránh in trùng',
        );
      } else {
        NotificationOverlayManager().showSuccess(
          title: 'Đã báo chế biến',
          message: data['message']?.toString() ?? '$n dòng · ${r.name}',
        );
      }
      await _reload(silent: true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không gửi được',
      );
      await _reload(silent: true);
    }
  }

  Future<PosServiceResourceDto?> _pickFreeResource({
    required String title,
    String? excludeId,
    String? preferredAreaId,
  }) async {
    final free = _resources
        .where((x) => x.isFree && x.id != excludeId)
        .toList()
      ..sort((a, b) {
        final aa = a.areaName.compareTo(b.areaName);
        if (aa != 0) return aa;
        return a.sortOrder != b.sortOrder
            ? a.sortOrder.compareTo(b.sortOrder)
            : a.code.compareTo(b.code);
      });
    if (free.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không có bàn trống',
        message: tr('Tất cả bàn đang dùng hoặc đang mở phiên'),
      );
      return null;
    }

    final areaIds = <String>{};
    for (final t in free) {
      if (t.areaId.isNotEmpty) areaIds.add(t.areaId);
    }
    final areaOptions = _areas.where((a) => areaIds.contains(a.id)).toList();
    // Ưu tiên khu bàn nguồn / bộ lọc sơ đồ / khu đầu có bàn trống.
    String? areaFilter = preferredAreaId;
    if (areaFilter == null ||
        areaFilter.isEmpty ||
        !areaIds.contains(areaFilter)) {
      areaFilter = (_areaFilter != null && areaIds.contains(_areaFilter))
          ? _areaFilter
          : (areaOptions.isNotEmpty ? areaOptions.first.id : null);
    }

    return showModalBottomSheet<PosServiceResourceDto>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.62;
        return SafeArea(
          child: SizedBox(
            height: h,
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                final filtered = areaFilter == null
                    ? free
                    : free.where((t) => t.areaId == areaFilter).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(tr(title),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    if (areaOptions.length > 1)
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(tr('Tất cả (${free.length})')),
                                selected: areaFilter == null,
                                onSelected: (_) =>
                                    setLocal(() => areaFilter = null),
                              ),
                            ),
                            ...areaOptions.map((a) {
                              final n =
                                  free.where((t) => t.areaId == a.id).length;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(tr('${a.name} ($n)')),
                                  selected: areaFilter == a.id,
                                  onSelected: (_) =>
                                      setLocal(() => areaFilter = a.id),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(tr('Không có bàn trống trong nhóm này')))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final t = filtered[i];
                                return ListTile(
                                  title: Text(tr(t.name)),
                                  subtitle:
                                      Text(tr('${t.code} · ${t.areaName}')),
                                  onTap: () => Navigator.pop(ctx, t),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _transfer(PosServiceResourceDto r) async {
    final sid = r.openSessionId;
    if (sid == null || sid.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không chuyển được',
        message: tr('Bàn chưa có phiên mở'),
      );
      return;
    }
    final target = await _pickFreeResource(
      title: 'Chuyển sang bàn…',
      excludeId: r.id,
      preferredAreaId: r.areaId,
    );
    if (target == null) return;
    // Ưu tiên theo resourceId — tránh session orphan / id lệch trên sơ đồ.
    var res = await _api.transferPosResource(r.id, target.id);
    if (res['isSuccess'] != true) {
      res = await _api.transferPosResourceSession(sid, target.id);
    }
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      // Optimistic: cập nhật sơ đồ ngay — không nhảy sang màn bán (để thấy đổi).
      setState(() {
        _resources = _resources.map((x) {
          if (x.id == r.id) {
            return PosServiceResourceDto(
              id: x.id,
              areaId: x.areaId,
              areaName: x.areaName,
              code: x.code,
              name: x.name,
              resourceKind: x.resourceKind,
              capacity: x.capacity,
              sortOrder: x.sortOrder,
              defaultHourlyRate: x.defaultHourlyRate,
              isActive: x.isActive,
              occupancyStatus: 'Free',
              openSessionId: null,
              openOrderId: null,
              sessionStartedAt: null,
              elapsedMinutes: 0,
              subtotal: 0,
              lineCount: 0,
              pendingKitchenCount: 0,
              guestCount: 0,
              billRequested: false,
              needsCleaning: false,
              orderNo: null,
              layoutX: x.layoutX,
              layoutY: x.layoutY,
              layoutW: x.layoutW,
              layoutH: x.layoutH,
            );
          }
          if (x.id == target.id) {
            return PosServiceResourceDto(
              id: x.id,
              areaId: x.areaId,
              areaName: x.areaName,
              code: x.code,
              name: x.name,
              resourceKind: x.resourceKind,
              capacity: x.capacity,
              sortOrder: x.sortOrder,
              defaultHourlyRate: x.defaultHourlyRate,
              isActive: x.isActive,
              occupancyStatus:
                  r.lineCount > 0 || r.subtotal > 0 ? 'Occupied' : 'Holding',
              openSessionId: sid,
              openOrderId: r.openOrderId,
              sessionStartedAt: r.sessionStartedAt ?? DateTime.now().toUtc(),
              elapsedMinutes: r.elapsedMinutes,
              subtotal: r.subtotal,
              lineCount: r.lineCount,
              pendingKitchenCount: r.pendingKitchenCount,
              guestCount: r.guestCount,
              billRequested: r.billRequested,
              needsCleaning: false,
              orderNo: r.orderNo,
              layoutX: x.layoutX,
              layoutY: x.layoutY,
              layoutW: x.layoutW,
              layoutH: x.layoutH,
            );
          }
          return x;
        }).toList();
      });
      widget.onResourceFreed?.call(r.id);
      NotificationOverlayManager().showSuccess(
        title: 'Đã chuyển',
        message:
            '${formatPosTableLabel(areaName: r.areaName, tableName: r.name)} → '
            '${formatPosTableLabel(areaName: target.areaName, tableName: target.name)}',
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi chuyển bàn',
        message: res['message']?.toString() ?? 'Không chuyển được',
      );
    }
  }

  Future<void> _split(PosServiceResourceDto r) async {
    final sid = r.openSessionId;
    final oid = r.openOrderId;
    if (sid == null || sid.isEmpty || oid == null || oid.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không tách được',
        message: tr('Bàn chưa có phiên / đơn'),
      );
      return;
    }

    final orderRes = await _api.getPosSale(oid);
    if (!mounted) return;
    if (orderRes['isSuccess'] != true || orderRes['data'] is! Map) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: tr('Không tải được đơn để tách'),
      );
      return;
    }
    final data = Map<String, dynamic>.from(orderRes['data'] as Map);
    final rawLines = (data['lines'] ?? data['Lines']) as List? ?? [];
    final lines = <Map<String, dynamic>>[];
    for (final e in rawLines) {
      if (e is Map) lines.add(Map<String, dynamic>.from(e));
    }
    if (lines.length < 2) {
      NotificationOverlayManager().showWarning(
        title: 'Không tách được',
        message: tr('Cần ít nhất 2 dòng món'),
      );
      return;
    }

    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr('Chọn món tách bàn')),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: lines.map((l) {
                final id = (l['id'] ?? l['Id'])?.toString() ?? '';
                final name = (l['productName'] ?? l['ProductName'] ?? '').toString();
                final qty = (l['qty'] ?? l['Qty'] as num?)?.toDouble() ?? 0;
                return CheckboxListTile(
                  value: selected.contains(id),
                  title: Text(tr(name)),
                  subtitle: Text(tr('SL $qty')),
                  onChanged: (v) => setLocal(() {
                    if (v == true) {
                      selected.add(id);
                    } else {
                      selected.remove(id);
                    }
                  }),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Huỷ'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Tiếp'))),
          ],
        ),
      ),
    );
    if (ok != true || selected.isEmpty) return;

    final target =
        await _pickFreeResource(
          title: 'Tách sang bàn…',
          excludeId: r.id,
          preferredAreaId: r.areaId,
        );
    if (target == null) return;

    final res = await _api.splitPosResourceSession(
      sid,
      targetResourceId: target.id,
      lineIds: selected.toList(),
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      // Chặn autosave giỏ cũ ghi món đã tách trở lại bàn nguồn.
      widget.onResourceFreed?.call(r.id);
      NotificationOverlayManager().showSuccess(
        title: 'Đã tách bàn',
        message: '→ ${formatPosTableLabel(areaName: target.areaName, tableName: target.name)}',
      );
      await _reload();
      final data2 = res['data'] as Map? ?? {};
      final newOrderId = data2['newSaleOrderId']?.toString();
      if (newOrderId != null && newOrderId.isNotEmpty) {
        _emitSelect({
          'saleOrderId': newOrderId,
          'sessionId': data2['newSessionId']?.toString(),
          'resourceId': target.id,
          'resourceName': target.name,
          'areaName': target.areaName,
        });
      }
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tách được',
      );
    }
  }

  Future<void> _merge(PosServiceResourceDto r) async {
    final sid = r.openSessionId;
    if (sid == null || sid.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không gộp được',
        message: tr('Bàn đích chưa có phiên mở'),
      );
      return;
    }
    // Gộp từ bàn đang dùng HOẶC đang holding (đã mở phiên).
    final others = _resources
        .where((x) =>
            x.id != r.id &&
            x.openSessionId != null &&
            x.openSessionId!.isNotEmpty &&
            (x.isOccupied || x.isHolding))
        .toList();
    if (others.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không có bàn khác',
        message: tr('Cần bàn đang dùng để gộp vào đây'),
      );
      return;
    }
    final source = await showModalBottomSheet<PosServiceResourceDto>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.5;
        return SafeArea(
          child: SizedBox(
            height: h,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(tr('Gộp bàn nào vào đây?'),
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: others
                        .map((t) => ListTile(
                              title: Text(tr(t.name)),
                              subtitle: Text(tr('${_moneyFmt.format(t.subtotal)}đ · ${t.lineCount} món')),
                              onTap: () => Navigator.pop(ctx, t),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (source?.openSessionId == null) return;
    final res =
        await _api.mergePosResourceSession(sid, source!.openSessionId!);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'] as Map? ?? {};
      final mergedLines =
          (data['mergedLines'] as num?)?.toInt() ?? source.lineCount;
      final mergedSub = r.subtotal + source.subtotal;
      final mergedGuests = (data['guestCount'] as num?)?.toInt() ??
          (r.guestCount + source.guestCount);
      setState(() {
        _resources = _resources.map((x) {
          if (x.id == source.id) {
            return PosServiceResourceDto(
              id: x.id,
              areaId: x.areaId,
              areaName: x.areaName,
              code: x.code,
              name: x.name,
              resourceKind: x.resourceKind,
              capacity: x.capacity,
              sortOrder: x.sortOrder,
              defaultHourlyRate: x.defaultHourlyRate,
              isActive: x.isActive,
              occupancyStatus: 'Free',
              openSessionId: null,
              openOrderId: null,
              sessionStartedAt: null,
              elapsedMinutes: 0,
              subtotal: 0,
              lineCount: 0,
              pendingKitchenCount: 0,
              guestCount: 0,
              billRequested: false,
              needsCleaning: false,
              orderNo: null,
              layoutX: x.layoutX,
              layoutY: x.layoutY,
              layoutW: x.layoutW,
              layoutH: x.layoutH,
            );
          }
          if (x.id == r.id) {
            return PosServiceResourceDto(
              id: x.id,
              areaId: x.areaId,
              areaName: x.areaName,
              code: x.code,
              name: x.name,
              resourceKind: x.resourceKind,
              capacity: x.capacity,
              sortOrder: x.sortOrder,
              defaultHourlyRate: x.defaultHourlyRate,
              isActive: x.isActive,
              occupancyStatus: 'Occupied',
              openSessionId: sid,
              openOrderId: r.openOrderId,
              sessionStartedAt: r.sessionStartedAt,
              elapsedMinutes: r.elapsedMinutes,
              subtotal: mergedSub,
              lineCount: r.lineCount + mergedLines,
              pendingKitchenCount:
                  r.pendingKitchenCount + source.pendingKitchenCount,
              guestCount: mergedGuests,
              billRequested: r.billRequested,
              needsCleaning: false,
              orderNo: r.orderNo,
              layoutX: x.layoutX,
              layoutY: x.layoutY,
              layoutW: x.layoutW,
              layoutH: x.layoutH,
            );
          }
          return x;
        }).toList();
      });
      widget.onResourceFreed?.call(source.id);
      NotificationOverlayManager().showSuccess(
        title: 'Đã gộp',
        message:
            '${formatPosTableLabel(areaName: source.areaName, tableName: source.name)} → '
            '${formatPosTableLabel(areaName: r.areaName, tableName: r.name)}',
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi gộp bàn',
        message: res['message']?.toString() ?? 'Không gộp được',
      );
    }
  }

  Future<void> _pause(PosServiceResourceDto r) async {
    final sid = r.openSessionId;
    if (sid == null) return;
    final res = await _api.pausePosResourceSession(sid);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager()
          .showSuccess(title: 'Đã tạm dừng', message: r.name);
      await _reload();
    }
  }

  Future<void> _resume(PosServiceResourceDto r) async {
    final sid = r.openSessionId;
    if (sid == null) return;
    final res = await _api.resumePosResourceSession(sid);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager()
          .showSuccess(title: 'Tiếp tục giờ', message: r.name);
      await _reload();
    }
  }

  Future<void> _setGuests(PosServiceResourceDto r) async {
    final sid = r.openSessionId;
    if (sid == null) return;
    final ctrl = TextEditingController(text: tr('${r.guestCount > 0 ? r.guestCount : 1}'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Số khách')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok != true) return;
    final n = int.tryParse(ctrl.text.trim()) ?? 1;
    await _api.setPosResourceSessionGuests(sid, n);
    await _reload();
  }

  Future<void> _toggleBill(PosServiceResourceDto r) async {
    final sid = r.openSessionId;
    if (sid == null) return;
    await _api.requestPosResourceBill(sid, requested: !r.isBillRequested);
    await _reload();
  }

  Future<void> _closeSession(PosServiceResourceDto r) async {
    final sid = r.openSessionId;
    if (sid == null || sid.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đóng ${r.name}?')),
        content: Text(tr('Đóng phiên sẽ dừng tính giờ. Đơn Draft vẫn giữ để thanh toán.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Đóng phiên'))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.closePosResourceSession(sid);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager()
          .showSuccess(title: 'Đã đóng phiên', message: r.name);
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không đóng được',
      );
    }
  }

  /// Bàn Holding (chưa gọi món) → đóng mọi phiên, trả về trống.
  Future<void> _freeHoldingTable(PosServiceResourceDto r) async {
    // Hủy autosave / draft local trước — tránh race mở lại phiên trống.
    widget.onResourceFreed?.call(r.id);

    PosServiceResourceDto asFree(PosServiceResourceDto x) => PosServiceResourceDto(
          id: x.id,
          areaId: x.areaId,
          areaName: x.areaName,
          code: x.code,
          name: x.name,
          resourceKind: x.resourceKind,
          capacity: x.capacity,
          sortOrder: x.sortOrder,
          defaultHourlyRate: x.defaultHourlyRate,
          isActive: x.isActive,
          occupancyStatus: 'Free',
          openSessionId: null,
          openOrderId: null,
          sessionStartedAt: null,
          elapsedMinutes: 0,
          subtotal: 0,
          lineCount: 0,
          pendingKitchenCount: 0,
          guestCount: 0,
          billRequested: false,
          needsCleaning: false,
          orderNo: null,
          layoutX: x.layoutX,
          layoutY: x.layoutY,
          layoutW: x.layoutW,
          layoutH: x.layoutH,
          reservationId: x.reservationId,
          reservationCustomerName: x.reservationCustomerName,
          reservationPhone: x.reservationPhone,
          reservationGuestCount: x.reservationGuestCount,
          reservationPreOrderCount: x.reservationPreOrderCount,
          reservationReservedUntil: x.reservationReservedUntil,
        );

    void markFreeLocal() {
      setState(() {
        _resources =
            _resources.map((x) => x.id == r.id ? asFree(x) : x).toList();
      });
    }

    var res = await _api.freePosServiceResource(r.id);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không trả được bàn',
        message: res['message']?.toString() ?? 'Lỗi',
      );
      return;
    }

    markFreeLocal();
    NotificationOverlayManager().showSuccess(
      title: 'Đã trả về trống',
      message: r.name,
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _reload(silent: true);
    if (!mounted) return;
    var still = _resources.where((x) => x.id == r.id).firstOrNull;
    // Còn Holding/Occupied nhưng không món → free lần 2 rồi ép Free trên UI.
    if (still != null &&
        (still.isHolding || still.isOccupied) &&
        still.lineCount <= 0) {
      res = await _api.freePosServiceResource(r.id);
      if (!mounted) return;
      await _reload(silent: true);
      if (!mounted) return;
      still = _resources.where((x) => x.id == r.id).firstOrNull;
      if (still != null &&
          (still.isHolding || still.isOccupied) &&
          still.lineCount <= 0) {
        markFreeLocal();
      }
    }
  }

  Future<void> _addArea() async {
    await _showAreaEditor();
  }

  Future<void> _showAreaEditor({PosServiceAreaDto? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: tr(existing?.name ?? ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(isEdit ? 'Sửa tên nhóm' : 'Thêm khu vực')),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('Tên khu (Tầng 1, Khu A…)'),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(isEdit ? 'Lưu' : 'Thêm'))),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final name = nameCtrl.text.trim();
    final res = isEdit
        ? await _api.updatePosServiceArea(existing.id, {
            'name': name,
            'code': existing.code,
            'sortOrder': existing.sortOrder,
            'areaType': existing.areaType,
            'isActive': existing.isActive,
          })
        : await _api.createPosServiceArea({'name': name});
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: isEdit ? 'Đã đổi tên nhóm' : 'Đã thêm khu',
        message: name,
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ??
            (isEdit ? 'Không sửa được nhóm' : 'Không thêm được'),
      );
    }
  }

  Future<void> _deleteArea(PosServiceAreaDto a) async {
    final tableCount = _resources.where((r) => r.areaId == a.id).length;
    // Khi đang lọc nhóm khác, đếm từ API không có — hỏi xác nhận chung.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa nhóm / khu vực?')),
        content: Text(
          tr(tableCount > 0
              ? 'Xóa «${a.name}» và $tableCount bàn/ghế/phòng trong nhóm?\n'
                  'Bàn đang dùng sẽ chặn xóa.'
              : 'Xóa «${a.name}»?\n'
                  'Các bàn trống trong nhóm (nếu có) cũng sẽ bị xóa.'),
        ),
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
    if (ok != true) return;
    final res = await _api.deletePosServiceArea(a.id);
    if (!mounted) return;
    final deleted = res['data'] is Map
        ? (res['data']['deleted'] == true || res['data']['Deleted'] == true)
        : false;
    if (res['isSuccess'] == true && deleted) {
      if (_areaFilter == a.id) _areaFilter = null;
      NotificationOverlayManager().showSuccess(
        title: 'Đã xóa nhóm',
        message: a.name,
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi xóa nhóm',
        message: res['message']?.toString() ?? 'Không xóa được',
      );
    }
  }

  Future<void> _manageAreas() async {
    if (_areas.isEmpty) {
      await _addArea();
      return;
    }
    var local = List<PosServiceAreaDto>.from(_areas);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.55,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(tr('Nhóm / khu vực'),
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(tr('Kéo để sắp xếp · chạm Sửa để đổi tên')),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: local.length,
                        onReorder: (oldIndex, newIndex) {
                          setLocal(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = local.removeAt(oldIndex);
                            local.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, i) {
                          final a = local[i];
                          return ListTile(
                            key: ValueKey(a.id),
                            leading: const Icon(Icons.drag_handle),
                            title: Text(tr(a.name)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: tr('Đổi tên'),
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await _showAreaEditor(existing: a);
                                  },
                                ),
                                IconButton(
                                  tooltip: tr('Xóa'),
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await _deleteArea(a);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _addArea();
                            },
                            icon: const Icon(Icons.add),
                            label: Text(tr('Thêm')),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () async {
                              final items = <Map<String, dynamic>>[];
                              for (var i = 0; i < local.length; i++) {
                                items.add({
                                  'id': local[i].id,
                                  'sortOrder': i,
                                });
                              }
                              final res =
                                  await _api.sortPosServiceAreas(items);
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              if (res['isSuccess'] == true) {
                                NotificationOverlayManager().showSuccess(
                                  title: 'Đã sắp xếp nhóm',
                                  message: '${items.length} khu',
                                );
                                await _reload();
                              } else {
                                NotificationOverlayManager().showError(
                                  title: 'Lỗi',
                                  message: res['message']?.toString() ??
                                      'Không lưu thứ tự',
                                );
                              }
                            },
                            child: Text(tr('Lưu thứ tự')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addResource() => _showResourceEditor();

  Future<void> _showManageResourceActions(PosServiceResourceDto r) async {
    if (_layoutEdit) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(tr(r.name),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('${r.code} · ${r.areaName} · ${r.resourceKind.label}')),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('Sửa bàn / phòng')),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(tr('Xóa bàn / phòng')),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _showResourceEditor(existing: r);
    } else if (action == 'delete') {
      await _deleteResource(r);
    }
  }

  Future<void> _deleteResource(PosServiceResourceDto r) async {
    if (r.isOccupied || r.isHolding) {
      NotificationOverlayManager().showWarning(
        title: 'Không xóa được',
        message: tr('Bàn đang có phiên — đóng / thanh toán trước'),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa bàn / phòng?')),
        content: Text(tr('Xóa «${r.name}» (${r.code})?\nKhông thể hoàn tác.'),
        ),
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
    if (ok != true) return;
    final res = await _api.deletePosServiceResource(r.id);
    if (!mounted) return;
    final deleted = res['data'] is Map
        ? (res['data']['deleted'] == true || res['data']['Deleted'] == true)
        : res['isSuccess'] == true;
    if (res['isSuccess'] == true && deleted) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã xóa',
        message: r.name,
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi xóa',
        message: res['message']?.toString() ?? 'Không xóa được',
      );
    }
  }

  Future<void> _showResourceEditor({PosServiceResourceDto? existing}) async {
    if (_areas.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu khu vực',
        message: tr('Thêm khu vực trước khi tạo bàn/ghế/phòng'),
      );
      return;
    }
    final isEdit = existing != null;
    var areaId = existing?.areaId ??
        (_areaFilter != null && _areas.any((a) => a.id == _areaFilter)
            ? _areaFilter!
            : _areas.first.id);
    var kind = existing?.resourceKind ??
        switch (widget.sellProfile) {
          PosSellProfile.salon => PosResourceKind.chair,
          PosSellProfile.roomHourly => PosResourceKind.room,
          _ => PosResourceKind.table,
        };
    var capacity = existing?.capacity ?? 4;
    var isActive = existing?.isActive ?? true;
    final codeCtrl = TextEditingController(text: tr(existing?.code ?? ''));
    final nameCtrl = TextEditingController(text: tr(existing?.name ?? ''));
    final capacityCtrl =
        TextEditingController(text: tr(capacity.toString()));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr(isEdit ? 'Sửa bàn / phòng' : 'Thêm bàn / ghế / phòng')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: areaId,
                  decoration: InputDecoration(
                    labelText: tr('Khu vực'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _areas
                      .map((a) =>
                          DropdownMenuItem(value: a.id, child: Text(tr(a.name))))
                      .toList(),
                  onChanged: (v) => setLocal(() => areaId = v ?? areaId),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PosResourceKind>(
                  value: kind,
                  decoration: InputDecoration(
                    labelText: tr('Loại'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: PosResourceKind.values
                      .map((k) => DropdownMenuItem(
                            value: k,
                            child: Row(
                              children: [
                                Icon(
                                  switch (k) {
                                    PosResourceKind.chair =>
                                      Icons.chair_outlined,
                                    PosResourceKind.room =>
                                      Icons.meeting_room_outlined,
                                    PosResourceKind.other =>
                                      Icons.category_outlined,
                                    PosResourceKind.table =>
                                      Icons.table_restaurant_outlined,
                                  },
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(tr(k.label)),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setLocal(() => kind = v ?? kind),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Mã (B01, P02…)'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Tên hiển thị'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: capacityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('Sức chứa (số khách)'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Đang hoạt động')),
                  value: isActive,
                  onChanged: (v) => setLocal(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Huỷ'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr(isEdit ? 'Lưu' : 'Thêm'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final code = codeCtrl.text.trim();
    final name = nameCtrl.text.trim().isEmpty ? code : nameCtrl.text.trim();
    if (code.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu mã',
        message: tr('Nhập mã bàn / phòng'),
      );
      return;
    }
    capacity = int.tryParse(capacityCtrl.text.trim()) ?? capacity;
    if (capacity < 1) capacity = 1;

    final body = <String, dynamic>{
      'areaId': areaId,
      'code': code,
      'name': name,
      'resourceKind': kind.apiValue,
      'capacity': capacity,
      'sortOrder': existing?.sortOrder ?? _resources.length,
      'isActive': isActive,
      if (existing?.layoutX != null) 'layoutX': existing!.layoutX,
      if (existing?.layoutY != null) 'layoutY': existing!.layoutY,
      'layoutW': existing?.layoutW ?? 120,
      'layoutH': existing?.layoutH ?? 100,
    };

    final res = isEdit
        ? await _api.updatePosServiceResource(existing.id, body)
        : await _api.createPosServiceResource(body);
    if (!mounted) return;
    final updated = (res['data'] is Map)
        ? ((res['data']['updated'] ?? res['data']['Updated']) as num?)?.toInt()
        : null;
    if (res['isSuccess'] == true && (updated == null || updated > 0)) {
      NotificationOverlayManager().showSuccess(
        title: isEdit ? 'Đã cập nhật' : 'Đã thêm',
        message: name,
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ??
            (isEdit ? 'Không sửa được' : 'Không thêm được'),
      );
    }
  }

  Future<void> _saveLayoutPositions() async {
    // Bàn 120×100, bước lưới có khoảng cách giữa các ô.
    const tileW = 120.0;
    const tileH = 100.0;
    const gap = 16.0;
    const stepX = tileW + gap;
    const stepY = tileH + gap;
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _resources.length; i++) {
      final r = _resources[i];
      final rawX = r.layoutX ?? ((i % 3) * stepX);
      final rawY = r.layoutY ?? ((i ~/ 3) * stepY);
      final sx = _snapToGrid(rawX, stepX);
      final sy = _snapToGrid(rawY, stepY);
      items.add({
        'id': r.id,
        'layoutX': sx,
        'layoutY': sy,
        'layoutW': tileW,
        'layoutH': tileH,
      });
      _resources[i] = r.copyWithLayout(
        layoutX: sx,
        layoutY: sy,
        layoutW: tileW,
        layoutH: tileH,
      );
    }
    final res = await _api.savePosResourceLayout(items);
    if (!mounted) return;
    final saved = (res['data'] is Map)
        ? ((res['data']['saved'] ?? res['data']['Saved']) as num?)?.toInt()
        : null;
    if (res['isSuccess'] == true && (saved == null || saved > 0)) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã lưu sơ đồ',
        message: tr('${saved ?? items.length} ô'),
      );
      setState(() {
        _layoutEdit = false;
        _draggingLayout = false;
        _dragIndex = null;
      });
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi lưu sơ đồ',
        message: res['message']?.toString() ??
            (saved == 0
                ? 'Máy chủ không ghi được vị trí (0 bàn).'
                : 'Không lưu layout'),
      );
    }
  }

  static double _snapToGrid(double v, double cell) {
    if (cell <= 0) return v;
    return (v / cell).round() * cell;
  }

  bool _tableInUse(PosServiceResourceDto r) {
    if (_isWaitingTable(r)) return false;
    return r.isOccupied ||
        r.isActivelyOpen ||
        (r.isParked && r.lineCount > 0);
  }

  static const _waitingTileBg = Color.fromRGBO(32, 178, 170, 1);
  static const _waitingTileBorder = Color.fromRGBO(26, 150, 144, 1);
  static const _waitingTileAccent = Colors.white;

  Color _tileBg(PosServiceResourceDto r) {
    // Tạm tính: cam đậm dễ nhận (ưu tiên trước Occupied).
    if (r.billRequested || r.isBillRequested) return const Color(0xFFFFCC80);
    if (r.isReserved) return const Color(0xFFE0F2FE);
    if (r.isPaused) return const Color(0xFFFEF3C7);
    // Máy khác đang sửa — đỏ nhạt.
    if (r.isActivelyOpen && r.isLockedByOtherDevice(_deviceId)) {
      return const Color(0xFFFEE2E2);
    }
    // Bàn chờ khách — xám nhạt.
    if (_isWaitingTable(r)) return _waitingTileBg;
    // Bàn đang dùng / chọn món — xanh Edge.
    if (_tableInUse(r)) return PosTheme.edgeBlueLight;
    return Colors.white;
  }

  Color _tileBorder(PosServiceResourceDto r) {
    if (r.billRequested || r.isBillRequested) return const Color(0xFFEA580C);
    if (r.isReserved) return const Color(0xFF0284C7);
    if (r.isPaused) return const Color(0xFFD97706);
    if (r.isActivelyOpen && r.isLockedByOtherDevice(_deviceId)) {
      return const Color(0xFFDC2626);
    }
    if (_isWaitingTable(r)) return _waitingTileBorder;
    if (_tableInUse(r)) return PosTheme.edgeBlue;
    return const Color(0xFFD1D5DB);
  }

  // Trạng thái "Tạm tính"/"Máy khác" thể hiện bằng màu nền + icon giữa ô,
  // không gắn chip chữ cạnh tên bàn.

  bool _isWaitingTable(PosServiceResourceDto r) =>
      r.isHolding && r.lineCount <= 0;

  Color _tileAccent(PosServiceResourceDto r) {
    if (r.isLockedByOtherDevice(_deviceId)) return const Color(0xFFB91C1C);
    if (r.billRequested || r.isBillRequested) return const Color(0xFFEA580C);
    if (r.isReserved) return const Color(0xFF0284C7);
    if (r.isPaused) return const Color(0xFFD97706);
    if (_isWaitingTable(r)) return _waitingTileAccent;
    if (_tableInUse(r)) return PosTheme.edgeBlue;
    return PosTheme.textSecondary;
  }

  Widget _tileMiniRow({
    required IconData icon,
    required String text,
    required Color color,
    double iconSize = 14,
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return Row(
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            tr(text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTileCenter(PosServiceResourceDto r, Color accent) {
    if (r.isFree) {
      return Center(
        child: Text(tr('Trống'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: accent.withValues(alpha: 0.85),
          ),
        ),
      );
    }

    if (_isWaitingTable(r)) {
      final guests = r.guestCount > 0 ? '${r.guestCount}' : '–';
      return Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_outline, size: 18, color: accent),
                const SizedBox(height: 2),
                Text(
                  tr(guests),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(tr('Bàn chờ'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          Expanded(
            child: Icon(_kindIcon(r.resourceKind), size: 26, color: accent.withValues(alpha: 0.75)),
          ),
        ],
      );
    }

    if (r.isReserved) {
      final meta = _tileReservedMeta(r);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_seat_outlined, size: 22, color: accent),
            const SizedBox(height: 4),
            Text(
              tr(meta ?? 'Đặt bàn'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent),
            ),
          ],
        ),
      );
    }

    if (r.isPaused) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pause_circle_outline, size: 22, color: accent),
            const SizedBox(height: 2),
            Text(tr('Tạm dừng'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent)),
          ],
        ),
      );
    }

    if (r.isActivelyOpen && r.isLockedByOtherDevice(_deviceId)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phonelink_lock, size: 22, color: accent),
            const SizedBox(height: 2),
            Text(tr('Máy khác'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
          ],
        ),
      );
    }

    final time = r.elapsedLabel.isNotEmpty ? r.elapsedLabel : '--';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 22, color: accent),
          const SizedBox(height: 2),
          Text(
            tr(time),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: accent,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  double _floorTileAspectRatio(double tileW, {bool isPhone = false}) {
    // Mobile: ô cân đối hơn — đỡ dài quá mức so với chiều rộng.
    if (isPhone) {
      if (tileW < 115) return 0.82;
      if (tileW < 140) return 0.88;
      return 0.94;
    }
    // Ô cao hơn để vừa: tên · giữa · tiền · khách/mã.
    if (tileW < 115) return 0.72;
    if (tileW < 140) return 0.78;
    return 0.84;
  }

  String? _tileReservedMeta(PosServiceResourceDto r) {
    if (!r.isReserved) return null;
    final parts = <String>[];
    final guest = r.reservationGuestCount;
    if (guest > 0) parts.add('$guest kh');
    if (r.reservationReservedUntil != null) {
      parts.add(DateFormat('HH:mm').format(r.reservationReservedUntil!.toLocal()));
    } else if ((r.reservationCustomerName ?? '').trim().isNotEmpty) {
      parts.add(r.reservationCustomerName!.trim());
    }
    if (r.reservationPreOrderCount > 0) parts.add('${r.reservationPreOrderCount} món');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Color _tileNameColor(PosServiceResourceDto r) {
    if (r.isActivelyOpen && r.isLockedByOtherDevice(_deviceId)) {
      return const Color(0xFFB91C1C);
    }
    if (r.billRequested || r.isBillRequested) return const Color(0xFF9A3412);
    if (_isWaitingTable(r)) return _waitingTileAccent;
    if (_tableInUse(r)) return PosTheme.edgeBlue;
    if (r.isParked) return const Color(0xFF475569);
    return PosTheme.textPrimary;
  }

  /// Tổng tạm tính các bàn đang dùng / holding / đã xin tạm tính.
  double get _activeTablesSubtotal {
    var s = 0.0;
    for (final r in _resources) {
      if (r.isOccupied ||
          r.isHolding ||
          r.billRequested ||
          r.isBillRequested) {
        s += r.subtotal;
      }
    }
    return s;
  }

  int get _activeTableCount {
    var n = 0;
    for (final r in _resources) {
      if (r.isOccupied ||
          r.isHolding ||
          r.billRequested ||
          r.isBillRequested) {
        n++;
      }
    }
    return n;
  }

  /// Bán hàng / xem: lưới 3 cột theo thứ tự sơ đồ đã lưu ở Quản lý.
  /// Chỉ khi sắp xếp (_layoutEdit) mới dùng canvas kéo thả.
  List<PosServiceResourceDto> get _resourcesByFloorOrder {
    final list = List<PosServiceResourceDto>.from(_resources);
    list.sort((a, b) {
      final ay = a.layoutY ?? (a.sortOrder * 1000.0);
      final by = b.layoutY ?? (b.sortOrder * 1000.0);
      final cy = ay.compareTo(by);
      if (cy != 0) return cy;
      final ax = a.layoutX ?? (a.sortOrder * 10.0);
      final bx = b.layoutX ?? (b.sortOrder * 10.0);
      final cx = ax.compareTo(bx);
      if (cx != 0) return cx;
      final cs = a.sortOrder.compareTo(b.sortOrder);
      if (cs != 0) return cs;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// Mobile: luôn 3 cột. Tablet/desktop: số cột theo bề rộng ô chứa dụng.
  /// Khi lọc «Tất cả»: chia nhóm theo khu vực.
  Widget _buildSellFloorGrid() {
    if (_areaFilter == null && _areas.isNotEmpty) {
      return _buildGroupedFloorList();
    }
    return _buildFlatFloorGrid(_resourcesByFloorOrder);
  }

  Widget _buildGroupedFloorList() {
    final areas = List<PosServiceAreaDto>.from(_areas)
      ..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        if (c != 0) return c;
        return a.name.compareTo(b.name);
      });
    final byArea = <String, List<PosServiceResourceDto>>{};
    for (final r in _resources) {
      byArea.putIfAbsent(r.areaId, () => []).add(r);
    }
    for (final list in byArea.values) {
      list.sort((a, b) {
        final cs = a.sortOrder.compareTo(b.sortOrder);
        if (cs != 0) return cs;
        return a.name.compareTo(b.name);
      });
    }
    // Khu không còn trong danh sách areas (hiếm) — vẫn hiện cuối.
    final orphanIds = byArea.keys
        .where((id) => areas.every((a) => a.id != id))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
      children: [
        for (final a in areas) ...[
          if ((byArea[a.id] ?? const []).isNotEmpty) ...[
            _buildAreaSectionHeader(a.name, byArea[a.id]!),
            _buildFloorGridSliver(byArea[a.id]!),
          ],
        ],
        for (final oid in orphanIds) ...[
          _buildAreaSectionHeader(
            byArea[oid]!.first.areaName.isNotEmpty
                ? byArea[oid]!.first.areaName
                : 'Khác',
            byArea[oid]!,
          ),
          _buildFloorGridSliver(byArea[oid]!),
        ],
      ],
    );
  }

  /// Header khu khi xem «Tất cả»: tên · tổng tạm tính · bàn mở/tổng khu.
  Widget _buildAreaSectionHeader(
      String name, List<PosServiceResourceDto> tables) {
    var open = 0;
    var money = 0.0;
    for (final r in tables) {
      if (r.isOccupied ||
          r.isHolding ||
          r.billRequested ||
          r.isBillRequested) {
        open++;
        money += r.subtotal;
      }
    }
    final total = tables.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr(name),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: PosTheme.textPrimary,
              ),
            ),
          ),
          Text(tr('${_moneyFmt.format(money)}đ · $open/$total bàn'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: PosTheme.kiotBlue,
            ),
          ),
        ],
      ),
    );
  }

  /// Lưới cố định chiều cao theo số hàng — dùng trong ListView nhóm khu.
  Widget _buildFloorGridSliver(List<PosServiceResourceDto> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isPhone = w < Responsive.mobileBreakpoint;
        const gap = 8.0;
        const minTile = 120.0;
        final usable = w.clamp(200.0, 4000.0);
        int cols;
        if (isPhone) {
          cols = 3;
        } else {
          cols = ((usable + gap) / (minTile + gap)).floor().clamp(3, 8);
        }
        final tileW = (usable - gap * (cols - 1)) / cols;
        final ratio = _floorTileAspectRatio(tileW, isPhone: isPhone);
        final tileH = tileW / ratio;
        final rows = (items.length / cols).ceil().clamp(1, 9999);
        final gridH = rows * tileH + (rows - 1) * gap;

        return SizedBox(
          height: gridH,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
              childAspectRatio: ratio,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _buildTile(items[i]),
          ),
        );
      },
    );
  }

  Widget _buildFlatFloorGrid(List<PosServiceResourceDto> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isPhone = w < Responsive.mobileBreakpoint;
        // Mục tiêu: mỗi ô bàn ~120–140px (đủ tên + tiền), gap 8.
        const gap = 8.0;
        const pad = 10.0;
        const minTile = 120.0;
        final usable = (w - pad * 2).clamp(200.0, 4000.0);
        int cols;
        if (isPhone) {
          cols = 3;
        } else {
          cols = ((usable + gap) / (minTile + gap)).floor();
          cols = cols.clamp(3, 8);
        }
        // Trên pane hẹp (F&B desktop nửa trái ~500–700px) vẫn ≥3, thường 4–5.
        final tileW = (usable - gap * (cols - 1)) / cols;
        // Giữ tỉ lệ gần bàn (rộng hơn cao một chút khi ô lớn).
        final ratio = _floorTileAspectRatio(tileW, isPhone: isPhone);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(pad, 4, pad, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: ratio,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => _buildTile(items[i]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr(_error!), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _reload, child: Text(tr('Thử lại'))),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Thanh nhóm / khu vực — to hơn để dễ bấm trên POS.
                  Material(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                      child: Row(
                        children: [
                          _AreaChip(
                            label: 'Tất cả',
                            selected: _areaFilter == null,
                            onTap: () {
                              setState(() => _areaFilter = null);
                              _reload();
                            },
                          ),
                          const SizedBox(width: 8),
                          ..._areas.map((a) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _AreaChip(
                                  label: a.name,
                                  selected: _areaFilter == a.id,
                                  onTap: () {
                                    setState(() => _areaFilter = a.id);
                                    _reload();
                                  },
                                  onLongPress: widget.manageMode
                                      ? () => unawaited(
                                          _showAreaEditor(existing: a))
                                      : null,
                                ),
                              )),
                          if (widget.manageMode) ...[
                            const SizedBox(width: 4),
                            ActionChip(
                              avatar: const Icon(Icons.tune, size: 18),
                              label: Text(tr('Sắp nhóm'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              onPressed: () => unawaited(_manageAreas()),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              visualDensity: VisualDensity.standard,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!widget.manageMode && _tablesHeldByMe.isNotEmpty)
                    Material(
                      color: const Color(0xFFECFDF5),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 16, color: Color(0xFF166534)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(tr('${tr('Máy này đang giữ')}: ${_tablesHeldByMe.map((e) => e.name).join(', ')}'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF166534),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Chú thích màu chỉ khi quản lý — bán hàng giữ UI gọn.
                  if (widget.manageMode)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _LegendDot(color: Color(0xFFD1D5DB), label: 'Trống'),
                          _LegendDot(
                              color: PosTheme.kiotBlue, label: 'Đang dùng'),
                          _LegendDot(
                              color: Color(0xFFEA580C), label: 'Tạm tính'),
                          _LegendDot(
                              color: Color(0xFF9CA3AF), label: 'Chưa gọi'),
                          _LegendDot(
                              color: Color(0xFF0284C7), label: 'Đã đặt'),
                        ],
                      ),
                    ),
                  if (_layoutEdit)
                    Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Text(tr('Kéo bàn — thả ra dính ô (cách nhau 16px), rồi Lưu.'),
                        style: TextStyle(
                            fontSize: 12, color: PosTheme.textSecondary),
                      ),
                    )
                  else if (widget.manageMode)
                    Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Text(tr('Chạm bàn → Sửa/Xóa · giữ nhóm → đổi tên · «Sắp nhóm» để kéo thứ tự.'),
                        style: TextStyle(
                            fontSize: 12, color: PosTheme.textSecondary),
                      ),
                    ),
                  Expanded(
                    child: _resources.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                tr(widget.manageMode
                                    ? 'Chưa có bàn/phòng.\nThêm khu vực rồi thêm bàn.'
                                    : 'Chưa có bàn/phòng.\nVào Nhiều hơn → Quản lý bàn/phòng để thiết lập.'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: PosTheme.textSecondary),
                              ),
                            ),
                          )
                        // Bán hàng + xem quản lý: lưới 3 cột theo thứ tự đã sắp.
                        // Chỉ chế độ sắp xếp mới dùng canvas kéo.
                        : _layoutEdit
                            ? _buildLayoutCanvas(editable: true)
                            : _buildSellFloorGrid(),
                  ),
                ],
              );

    if (widget.embedded && !widget.showAppBar) {
      return ColoredBox(color: PosTheme.background, child: body);
    }

    final activeTotal = _activeTablesSubtotal;
    final totalLabel = _resources.isNotEmpty
        ? 'Tổng: ${_moneyFmt.format(activeTotal)}đ'
        : null;

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: widget.showAppBar
          ? AppBar(
              // Bán hàng: chỉ tổng tạm tính (không hiện số bàn).
              title: widget.manageMode
                  ? Text(tr('Quản lý bàn / phòng'))
                  : totalLabel != null
                      ? Text(
                          tr(totalLabel),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: PosTheme.kiotBlue,
                          ),
                        )
                      : const SizedBox.shrink(),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0.5,
              leading: widget.onHome != null
                  ? IconButton(
                      tooltip: tr('Về trang chủ'),
                      icon: const Icon(Icons.home_outlined),
                      onPressed: widget.onHome,
                    )
                  : null,
              actions: [
                if (widget.manageMode) ...[
                  IconButton(
                    tooltip: tr('Phiếu hủy bếp'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PosKitchenVoidListScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.cancel_presentation_outlined),
                  ),
                  IconButton(
                    tooltip: tr(_layoutEdit ? 'Lưu vị trí' : 'Sắp xếp sơ đồ'),
                    onPressed: () async {
                      if (_layoutEdit) {
                        await _saveLayoutPositions();
                      } else {
                        setState(() => _layoutEdit = true);
                      }
                    },
                    icon: Icon(_layoutEdit
                        ? Icons.save_outlined
                        : Icons.dashboard_customize_outlined),
                  ),
                  IconButton(
                    tooltip: tr('Quản lý nhóm'),
                    onPressed: () => unawaited(_manageAreas()),
                    icon: const Icon(Icons.layers_outlined),
                  ),
                  IconButton(
                    tooltip: tr('Thêm bàn'),
                    onPressed: _addResource,
                    icon: const Icon(Icons.add),
                  ),
                ],
                IconButton(
                  tooltip: tr('Tải lại'),
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      body: body,
    );
  }

  Widget _buildLayoutCanvas({required bool editable}) {
    // Bàn 120×100, cách nhau 16px (bước lưới 136×116).
    const tileW = 120.0;
    const tileH = 100.0;
    const gap = 16.0;
    const stepX = tileW + gap;
    const stepY = tileH + gap;
    const cols = 8;
    const rows = 10;
    final maxX = cols * stepX;
    final maxY = rows * stepY;

    final positions = <({double x, double y})>[];
    for (var i = 0; i < _resources.length; i++) {
      final r = _resources[i];
      final rawX = r.layoutX ?? ((i % 3) * stepX);
      final rawY = r.layoutY ?? ((i ~/ 3) * stepY);
      // Snap khi hiển thị — bàn cũ sát nhau sẽ tách đúng khoảng gap.
      final x = editable ? _snapToGrid(rawX, stepX) : rawX;
      final y = editable ? _snapToGrid(rawY, stepY) : rawY;
      positions.add((x: x, y: y));
    }

    void endDrag(int i) {
      final cur = _resources[i];
      final pos = positions[i];
      final sx =
          _snapToGrid(cur.layoutX ?? pos.x, stepX).clamp(0.0, maxX - tileW);
      final sy =
          _snapToGrid(cur.layoutY ?? pos.y, stepY).clamp(0.0, maxY - tileH);
      _resources[i] = cur.copyWithLayout(
        layoutX: sx,
        layoutY: sy,
        layoutW: tileW,
        layoutH: tileH,
      );
      _draggingLayout = false;
      _dragIndex = null;
      _dragPointer = null;
    }

    final canvas = SizedBox(
      width: maxX,
      height: maxY,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FloorGridPainter(
                cellW: stepX,
                cellH: stepY,
                tileW: tileW,
                tileH: tileH,
                show: editable,
              ),
            ),
          ),
          ...List.generate(_resources.length, (i) {
            final r = _resources[i];
            final pos = positions[i];
            final tile = editable
                ? Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      if (_dragPointer != null) return;
                      _dragPointer = e.pointer;
                      _dragIndex = i;
                      _draggingLayout = true;
                      final cur = _resources[i];
                      if (cur.layoutX == null || cur.layoutY == null) {
                        _resources[i] = cur.copyWithLayout(
                          layoutX: pos.x,
                          layoutY: pos.y,
                          layoutW: tileW,
                          layoutH: tileH,
                        );
                      }
                      setState(() {});
                    },
                    onPointerMove: (e) {
                      if (_dragPointer != e.pointer || _dragIndex != i) return;
                      setState(() {
                        final cur = _resources[i];
                        final cx = cur.layoutX ?? pos.x;
                        final cy = cur.layoutY ?? pos.y;
                        _resources[i] = cur.copyWithLayout(
                          layoutX: (cx + e.delta.dx).clamp(0.0, maxX - tileW),
                          layoutY: (cy + e.delta.dy).clamp(0.0, maxY - tileH),
                          layoutW: tileW,
                          layoutH: tileH,
                        );
                      });
                    },
                    onPointerUp: (e) {
                      if (_dragPointer != e.pointer) return;
                      setState(() => endDrag(i));
                    },
                    onPointerCancel: (e) {
                      if (_dragPointer != e.pointer) return;
                      setState(() => endDrag(i));
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: PosTheme.kiotBlue, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x440070F4),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: _buildTile(r, interactive: false),
                    ),
                  )
                : _buildTile(r);
            return Positioned(
              left: pos.x,
              top: pos.y,
              width: tileW,
              height: tileH,
              child: tile,
            );
          }),
        ],
      ),
    );

    if (editable) {
      return Stack(
        children: [
          ColoredBox(
            color: const Color(0xFFE8EEF5),
            child: InteractiveViewer(
              panEnabled: !_draggingLayout,
              scaleEnabled: false,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(80),
              minScale: 1,
              maxScale: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 28),
                child: canvas,
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 6,
            child: Text(tr('Chạm kéo bàn · kéo nền trống để xem thêm · thả ra dính ô'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: PosTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: FilledButton.icon(
              onPressed: _saveLayoutPositions,
              icon: const Icon(Icons.save),
              label: Text(tr('Lưu vị trí')),
            ),
          ),
        ],
      );
    }

    return ColoredBox(
      color: const Color(0xFFF0F4F8),
      child: InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(48),
        minScale: 0.5,
        maxScale: 1.8,
        child: canvas,
      ),
    );
  }


  IconData _kindIcon(PosResourceKind kind) => switch (kind) {
        PosResourceKind.chair => Icons.chair_outlined,
        PosResourceKind.room => Icons.meeting_room_outlined,
        PosResourceKind.other => Icons.category_outlined,
        PosResourceKind.table => Icons.table_restaurant_outlined,
      };

  Widget _buildTile(PosServiceResourceDto r, {bool interactive = true}) {
    // Bán hàng: chạm/giữ = thao tác bán. Quản lý (không sắp xếp): sửa/xóa.
    final allowSellActions =
        interactive && !_layoutEdit && !widget.manageMode;
    final allowManageActions =
        interactive && !_layoutEdit && widget.manageMode;

    final kindIcon = _kindIcon(r.resourceKind);
    final accent = _tileAccent(r);
    final showMoney = r.subtotal > 0 &&
        !_isWaitingTable(r) &&
        !r.isFree &&
        !r.isReserved;
    final showGuestsFooter = !_isWaitingTable(r) && !r.isFree;
    final guestText = r.guestCount > 0 ? '${r.guestCount}' : '–';

    final body = Container(
      decoration: BoxDecoration(
        color: _tileBg(r),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _tileBorder(r), width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chỉ tên bàn — không gắn chip "Tạm tính"/"Máy khác" cạnh tên
          // (đã thể hiện bằng màu nền / icon giữa ô).
          Row(
            children: [
              Icon(kindIcon, size: 13, color: _tileBorder(r)),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  tr(r.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: _tileNameColor(r),
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
          Expanded(child: _buildTileCenter(r, accent)),
          if (showMoney) ...[
            const SizedBox(height: 2),
            _tileMiniRow(
              icon: Icons.payments_outlined,
              text: tr('${_moneyFmt.format(r.subtotal)}đ'),
              color: accent,
              iconSize: 13,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ],
          if (r.pendingKitchenCount > 0 && !_isWaitingTable(r)) ...[
            const SizedBox(height: 1),
            _tileMiniRow(
              icon: Icons.soup_kitchen_outlined,
              text: tr('${r.pendingKitchenCount} bếp'),
              color: const Color(0xFFB45309),
              iconSize: 12,
              fontSize: 10,
            ),
          ],
          const SizedBox(height: 2),
          Row(
            children: [
              if (showGuestsFooter) ...[
                Icon(Icons.person_outline, size: 12, color: accent.withValues(alpha: 0.85)),
                const SizedBox(width: 2),
                Text(
                  tr(guestText),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ] else
                const Spacer(),
              const Spacer(),
              Text(
                tr(r.code),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );

    // Sắp xếp: không InkWell. Quản lý: sửa/xóa. Bán hàng: mở bàn / menu.
    if (!allowSellActions && !allowManageActions) return body;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: allowManageActions
            ? () => unawaited(_showManageResourceActions(r))
            : () => unawaited(_openResource(r)),
        onLongPress: allowManageActions
            ? () => unawaited(_showManageResourceActions(r))
            : () {
                if (r.isOccupied || r.isHolding) {
                  unawaited(_showOccupiedActions(r));
                } else if (r.isReserved) {
                  unawaited(_showReservedActions(r));
                } else if (r.isFree) {
                  unawaited(_showReserveDialog(r));
                }
              },
        child: body,
      ),
    );
  }
}

class _FloorGridPainter extends CustomPainter {
  _FloorGridPainter({
    required this.cellW,
    required this.cellH,
    required this.tileW,
    required this.tileH,
    required this.show,
  });

  final double cellW;
  final double cellH;
  final double tileW;
  final double tileH;
  final bool show;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8EEF5),
    );
    if (!show) return;

    final slot = Paint()
      ..color = const Color(0xFFCFD8DC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fill = Paint()..color = const Color(0x33FFFFFF);

    for (double y = 0; y + tileH <= size.height + 0.5; y += cellH) {
      for (double x = 0; x + tileW <= size.width + 0.5; x += cellW) {
        final rect = Rect.fromLTWH(x, y, tileW, tileH);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          slot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FloorGridPainter old) =>
      old.cellW != cellW ||
      old.cellH != cellH ||
      old.tileW != tileW ||
      old.tileH != tileH ||
      old.show != show;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.35),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(tr(label),
            style: const TextStyle(fontSize: 10, color: PosTheme.textSecondary)),
      ],
    );
  }
}

/// Chip nhóm khu vực — to hơn ChoiceChip mặc định để dễ bấm trên máy bán hàng.
class _AreaChip extends StatelessWidget {
  const _AreaChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? PosTheme.kiotBlue : const Color(0xFFF3F4F6);
    final fg = selected ? Colors.white : const Color(0xFF374151);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          alignment: Alignment.center,
          child: Text(
            tr(label),
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
