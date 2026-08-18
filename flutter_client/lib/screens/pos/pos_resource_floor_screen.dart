import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_customer.dart';
import '../../models/pos_product.dart';
import '../../models/pos_sale_order.dart';
import '../../models/pos_sell_industry.dart';
import '../../widgets/pos/pos_split_bill_sheet.dart';
import '../../services/api_service.dart';
import '../../utils/pos_device_identity.dart';
import '../../utils/pos_floor_realtime.dart';
import '../../utils/pos_kitchen_print.dart';
import '../../utils/pos_sell_print_settings.dart';
import '../../utils/pos_table_label.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/safe_navigator.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_numeric_keypad.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_appointment_day_screen.dart';
import 'pos_kitchen_void_list_screen.dart';
import 'pos_kds_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';
import '../../widgets/hrm_page_chrome.dart';

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
    this.promptGuestCountOnOpen = false,
    this.allowProvisionalBill = true,
    this.onActiveTotalsChanged,
    this.searchQuery = '',
    this.pendingOpenCode,
    this.pendingOpenToken = 0,
    this.paneActive = true,
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

  /// Tổng tạm tính + số bàn đang có đơn (nhúng top bar bán hàng).
  final void Function(double subtotal, int activeCount)? onActiveTotalsChanged;

  /// Bàn vừa báo bếp xong — ép badge chờ bếp = 0 đến khi server khớp.
  final Set<String> zeroPendingKitchenResourceIds;

  /// Bàn vừa in tạm tính — ép màu vàng cam đến khi server khớp.
  final Set<String> billRequestedResourceIds;

  /// Đơn máy này vừa nhả khóa khi về sơ đồ — không hiện «đang giữ».
  final Set<String> releasedOrderIds;

  /// Hỏi số khách khi mở bàn trống (Thiết lập ngành POS).
  final bool promptGuestCountOnOpen;

  /// Cho phép tạm tính (Thiết lập ngành POS).
  final bool allowProvisionalBill;

  /// Lọc bàn theo tên / mã / khu (từ thanh tìm màn bán).
  final String searchQuery;

  /// Mã quét/submit từ thanh tìm — tăng [pendingOpenToken] để mở bàn khớp.
  final String? pendingOpenCode;
  final int pendingOpenToken;

  /// false khi pane Offstage — không poll/rebuild đồng hồ.
  final bool paneActive;

  @override
  State<PosResourceFloorScreen> createState() => PosResourceFloorScreenState();
}

class PosResourceFloorScreenState extends State<PosResourceFloorScreen> {
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
  final _floorRealtime = PosFloorRealtimeSubscription();

  bool get _isFnB => widget.sellProfile == PosSellProfile.restaurant;
  bool get _isHourly => widget.sellProfile == PosSellProfile.roomHourly;
  bool get _isSalon => widget.sellProfile == PosSellProfile.salon;
  String get _bookingChipLabel {
    if (_isFnB) return 'Đặt hôm nay';
    final p = widget.sellProfile;
    if (p == null) return 'Lịch đặt';
    return p.bookingCalendarTitle;
  }
  bool get _warnMissingTimed =>
      widget.sellProfile == PosSellProfile.roomHourly ||
      widget.sellProfile == PosSellProfile.salon;

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
    // Bán hàng: poll 8–12s làm fallback; SignalR PosFloorChanged reload tức thì.
    // manageMode giữ autoRefreshSeconds (mặc định 20).
    final pollSec = widget.manageMode
        ? widget.autoRefreshSeconds
        : (widget.autoRefreshSeconds > 0
            ? widget.autoRefreshSeconds.clamp(8, 12)
            : 10);
    if (pollSec > 0) {
      _poll = Timer.periodic(
        Duration(seconds: pollSec),
        (_) {
          if (mounted && !_layoutEdit && widget.paneActive) {
            _reload(silent: true);
          }
        },
      );
    }
    _floorRealtime.start((_) {
      if (mounted && !_layoutEdit && widget.paneActive) _reload(silent: true);
    });
    // Đồng hồ bàn: 15s đủ (hiển thị phút), tránh rebuild toàn sơ đồ mỗi giây.
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _layoutEdit || !widget.paneActive) return;
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
        defaultServiceProductId: r.defaultServiceProductId,
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
        reservationDepositPaid: r.reservationDepositPaid,
        reservationDepositAmount: r.reservationDepositAmount,
        reservationDepositStatus: r.reservationDepositStatus,
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
          defaultServiceProductId: out.defaultServiceProductId,
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
          reservationDepositPaid: out.reservationDepositPaid,
          reservationDepositAmount: out.reservationDepositAmount,
          reservationDepositStatus: out.reservationDepositStatus,
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
      _notifyActiveTotals();
    }
    if (widget.paneActive && !oldWidget.paneActive) {
      unawaited(_reload(silent: true));
    }
    if (widget.pendingOpenToken != oldWidget.pendingOpenToken &&
        (widget.pendingOpenCode ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ok = tryOpenByCode(widget.pendingOpenCode!);
        if (!ok && mounted) {
          NotificationOverlayManager().showWarning(
            title: tr('Không tìm thấy bàn'),
            message: tr(widget.pendingOpenCode!.trim()),
          );
        }
      });
    }
  }

  double _lastEmittedSubtotal = -1;
  int _lastEmittedCount = -1;

  void _notifyActiveTotals() {
    if (!widget.paneActive) return;
    final s = _activeTablesSubtotal;
    final n = _activeTableCount;
    if (s == _lastEmittedSubtotal && n == _lastEmittedCount) return;
    _lastEmittedSubtotal = s;
    _lastEmittedCount = n;
    final cb = widget.onActiveTotalsChanged;
    if (cb == null) return;
    // Tránh setState parent trong lúc build sơ đồ.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb(s, n);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    _floorRealtime.dispose();
    super.dispose();
  }

  void refreshQuiet() {
    if (!mounted) return;
    unawaited(_reload(silent: true));
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final areaRes = await _api.getPosServiceAreas();
    final resRes = await _api.getPosServiceResources(
      heal: !silent,
    );
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
    _notifyActiveTotals();
  }

  void _emitSelect(Map<String, dynamic> result) {
    if (widget.onSelect != null) {
      widget.onSelect!(result);
      return;
    }
    // Hub / nhúng sơ đồ: không pop shell (MainLayout).
    if (widget.embedded || HrmPageChrome.isEmbedded) return;
    SafeNavigator.popPageIfPushed(context, result);
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
      defaultServiceProductId: r.defaultServiceProductId,
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
      reservationDepositPaid: r.reservationDepositPaid,
      reservationDepositAmount: r.reservationDepositAmount,
      reservationDepositStatus: r.reservationDepositStatus,
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
    _emitSelect(_tableSelectPayload(r));
  }

  Future<String?> _chooseDraftBillId(PosServiceResourceDto r) async {
    final bills = r.draftBills
        .where((b) => b.id.isNotEmpty && !(b.isSplit && b.lineCount <= 0))
        .toList();
    if (bills.length <= 1) return r.openOrderId;
    return showModalBottomSheet<String>(
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
                tr('Hóa đơn trên ${r.name}'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(tr('${bills.length} hóa đơn — chọn để mở')),
            ),
            const Divider(height: 1),
            for (final b in bills)
              ListTile(
                leading: Icon(
                  b.isSplit ? Icons.call_split : Icons.receipt_long,
                  color: PosTheme.kiotBlue,
                ),
                title: Text(tr(b.orderNo.isEmpty ? 'Hóa đơn' : b.orderNo)),
                subtitle: Text(tr(
                    '${b.lineCount} món · ${_moneyFmt.format(b.subtotal)}đ'
                    '${b.isSplit ? ' · Tách bill' : ''}')),
                onTap: () => Navigator.pop(ctx, b.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _payloadForBill(
    PosServiceResourceDto r,
    String billId, {
    Map<String, dynamic>? extra,
  }) {
    final split = r.draftBills.any((b) => b.id == billId && b.isSplit);
    return _tableSelectPayload(r, extra: {
      'saleOrderId': billId,
      if (split) 'sessionId': '',
      if (split) 'isSplitBill': true,
      if (split && (r.openOrderId ?? '').isNotEmpty)
        'splitFromOrderId': r.openOrderId,
      if (extra != null) ...extra,
    });
  }

  Map<String, dynamic> _tableSelectPayload(
    PosServiceResourceDto r, {
    Map<String, dynamic>? extra,
  }) =>
      {
        'saleOrderId': r.openOrderId,
        'sessionId': r.openSessionId,
        'resourceId': r.id,
        'resourceName': r.name,
        'areaName': r.areaName,
        'startedAt': r.sessionStartedAt?.toUtc().toIso8601String(),
        'guestCount': r.guestCount,
        'accumulatedPauseMinutes': r.accumulatedPauseMinutes,
        'pausedAt': r.pausedAt?.toUtc().toIso8601String(),
        'isPaused': r.isPaused,
        'defaultHourlyRate': r.defaultHourlyRate,
        if ((r.reservationDepositStatus ?? '').toLowerCase() == 'applied' &&
            r.reservationDepositPaid > 0) ...{
          'paidAmount': r.reservationDepositPaid,
          'depositApplied': r.reservationDepositPaid,
        },
        if (extra != null) ...extra,
      };

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

      // Bàn chờ / tạm rời (không ai đang sửa): vào thẳng + lấy quyền — không dialog.
      if (r.hasParkedBill && !r.isActivelyOpen) {
        if (r.openOrderId != null && r.openOrderId!.isNotEmpty) {
          final billId = await _chooseDraftBillId(r);
          if (!mounted || billId == null || billId.isEmpty) return;
          _emitSelect(_payloadForBill(r, billId, extra: {'forceClaim': true}));
          return;
        }
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
        final billId = await _chooseDraftBillId(r);
        if (!mounted || billId == null || billId.isEmpty) return;
        _emitSelect(_payloadForBill(r, billId));
      } else {
        // Occupied/Holding không có openOrderId (draft mồ côi) → OpenSession gắn lại.
        await _startResourceSession(r);
      }
      return;
    }

    final guests = widget.promptGuestCountOnOpen
        ? await _promptGuestCount(r)
        : 1;
    if (guests == null || !mounted) return;
    await _startResourceSession(r, guestCount: guests);
  }

  Future<int?> _promptGuestCount(PosServiceResourceDto r) async {
    final maxGuests = r.capacity > 0 ? r.capacity : 99;
    var guests = maxGuests < 2 ? 1 : 2;
    final ctrl = TextEditingController(text: '$guests');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr('Mở ${r.name}')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(r.capacity > 0
                    ? 'Số khách (tối đa $maxGuests)'
                    : 'Số khách'),
                style: const TextStyle(
                    fontSize: 13, color: PosTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in const [1, 2, 4, 6, 8])
                    if (n <= maxGuests)
                      ChoiceChip(
                        label: Text('$n'),
                        selected: guests == n,
                        onSelected: (_) => setLocal(() {
                          guests = n;
                          ctrl.text = '$n';
                        }),
                      ),
                ],
              ),
              const SizedBox(height: 8),
              PosNoSoftKeyboardField(
                controller: ctrl,
                allowDecimal: false,
                keypadTitle: 'Số khách',
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: tr('Số khác'),
                  isDense: true,
                ),
                onChanged: (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null) setLocal(() => guests = n.clamp(1, maxGuests));
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Huỷ'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Mở bàn'))),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    final n = int.tryParse(ctrl.text.trim()) ?? guests;
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
    _emitSelect(_tableSelectPayload(
      r,
      extra: {
        'saleOrderId': data['saleOrderId']?.toString(),
        'sessionId': data['sessionId']?.toString(),
        'orderNo': data['orderNo']?.toString(),
        'startedAt': data['startedAt']?.toString(),
        'guestCount': (data['guestCount'] as num?)?.toInt() ?? guestCount,
        'accumulatedPauseMinutes': 0,
        'isPaused': false,
        'pausedAt': null,
      },
    ));
  }

  Future<void> _showReservedActions(PosServiceResourceDto r) async {
    final depositHeld = (r.reservationDepositStatus ?? '').toLowerCase() == 'held' &&
        r.reservationDepositPaid > 0;
    final tableLabel =
        formatPosTableLabel(areaName: r.areaName, tableName: r.name);
    final summary = [
      r.reservationCustomerName ?? 'Khách đặt',
      if ((r.reservationPhone ?? '').isNotEmpty) r.reservationPhone!,
      if (r.reservationGuestCount > 0) '${r.reservationGuestCount} khách',
      if (r.reservationReservedUntil != null)
        'Đến ${DateFormat('dd/MM HH:mm').format(r.reservationReservedUntil!.toLocal())}',
      if (r.reservationPreOrderCount > 0)
        '${r.reservationPreOrderCount} món đặt trước',
      if (r.reservationDepositPaid > 0)
        'Cọc ${_moneyFmt.format(r.reservationDepositPaid)}đ'
            '${r.reservationDepositStatus != null ? ' (${r.reservationDepositStatus})' : ''}',
    ].join(' · ');
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(tableLabel)),
        content: Text(tr(summary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(tr('Hủy đặt'),
                style: const TextStyle(color: Colors.red)),
          ),
          if (!depositHeld)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'deposit'),
              child: Text(tr('Thu cọc')),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'seat'),
            child: Text(tr('Nhận bàn')),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'deposit') {
      await _collectDepositForResource(r);
      return;
    }
    if (action == 'cancel') {
      final rid = r.reservationId;
      if (rid == null || rid.isEmpty) return;
      var refund = false;
      var forfeit = true;
      if (depositHeld) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Hủy đặt — xử lý cọc')),
            content: Text(tr(
                'Đã thu cọc ${_moneyFmt.format(r.reservationDepositPaid)}đ. '
                'Hoàn lại cho khách hay giữ (mất cọc)?')),
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
        rid,
        forfeitDeposit: forfeit,
        refundDeposit: refund,
      );
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
      _emitSelect(_tableSelectPayload(
        r,
        extra: {
          'saleOrderId': data['saleOrderId']?.toString(),
          'sessionId': data['sessionId']?.toString(),
          'orderNo': data['orderNo']?.toString(),
          'startedAt': data['startedAt']?.toString(),
          'guestCount': data['guestCount'],
          'paidAmount': data['paidAmount'],
          'depositApplied': data['depositApplied'],
          'customerId': data['customerId']?.toString(),
          'accumulatedPauseMinutes': 0,
          'isPaused': false,
          'pausedAt': null,
          'defaultHourlyRate':
              data['defaultHourlyRate'] ?? r.defaultHourlyRate,
        },
      ));
    }
  }

  Future<void> _collectDepositForResource(PosServiceResourceDto r) async {
    final rid = r.reservationId;
    if (rid == null || rid.isEmpty) return;
    final amountCtrl = TextEditingController(
      text: r.reservationDepositAmount > r.reservationDepositPaid
          ? '${(r.reservationDepositAmount - r.reservationDepositPaid).round()}'
          : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thu cọc — ${r.name}')),
        content: TextField(
          controller: amountCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('Số tiền cọc'),
            border: OutlineInputBorder(),
            suffixText: 'đ',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Thu cọc'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final amount =
        double.tryParse(amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
    if (amount <= 0) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu số tiền',
        message: tr('Nhập số tiền cọc > 0'),
      );
      return;
    }
    final res = await _api.collectPosResourceReservationDeposit(rid, {
      'amount': amount,
      'paymentMethod': 'Tiền mặt',
    });
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã thu cọc',
        message: '${_moneyFmt.format(amount)}đ · ${r.name}',
      );
      await _reload();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không thu được cọc',
      );
    }
  }

  Future<void> _openAppointmentCalendar({String? resourceId}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PosAppointmentDayScreen(
          initialResourceId: resourceId,
          sellProfile: widget.sellProfile,
          onSeated: (payload) {
            final rid = payload['resourceId']?.toString();
            final match = _resources.where((x) => x.id == rid).toList();
            if (match.isEmpty) {
              _emitSelect(payload);
              return;
            }
            _emitSelect(_tableSelectPayload(match.first, extra: payload));
          },
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _showTodayReservations() async {
    final now = DateTime.now();
    final day = DateTime.utc(now.year, now.month, now.day);
    final res = await _api.getPosResourceReservations(day: day);
    if (!mounted) return;
    final raw = res['data'];
    final list = <PosResourceReservationDto>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(PosResourceReservationDto.fromJson(
              Map<String, dynamic>.from(e)));
        }
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Đặt trước hôm nay (${list.length})'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(tr('Chưa có đặt trước trong ngày'),
                          style: TextStyle(color: PosTheme.textSecondary)))
                  : ListView.separated(
                      controller: scroll,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final b = list[i];
                        final start = b.reservedAt?.toLocal();
                        final until = b.reservedUntil?.toLocal();
                        final table = b.areaName == null || b.areaName!.isEmpty
                            ? b.resourceName
                            : '${b.areaName} · ${b.resourceName}';
                        final timeLabel = start == null
                            ? (until == null
                                ? null
                                : DateFormat('HH:mm').format(until))
                            : until == null
                                ? DateFormat('HH:mm').format(start)
                                : '${DateFormat('HH:mm').format(start)}–${DateFormat('HH:mm').format(until)}';
                        return ListTile(
                          title: Text(tr('${b.customerName} — $table')),
                          subtitle: Text(tr([
                            if (timeLabel != null) timeLabel,
                            if ((b.serviceProductName ?? '').isNotEmpty)
                              b.serviceProductName!,
                            if ((b.assignedEmployeeName ?? '').isNotEmpty)
                              b.assignedEmployeeName!,
                            if ((b.phone ?? '').isNotEmpty) b.phone!,
                            if (!b.isTimedSlot) '${b.guestCount} khách',
                            if (b.preOrderCount > 0)
                              '${b.preOrderCount} món',
                            if (b.depositPaid > 0)
                              'Cọc ${_moneyFmt.format(b.depositPaid)}đ',
                          ].join(' · '))),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(ctx);
                            final table = _resources
                                .where((x) => x.id == b.resourceId)
                                .firstOrNull;
                            if (table != null && table.isReserved) {
                              unawaited(_showReservedActions(table));
                            } else {
                              unawaited(_openAppointmentCalendar(
                                  resourceId: b.resourceId));
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showReserveDialog(PosServiceResourceDto r) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final guestCtrl = TextEditingController(text: '2');
    final noteCtrl = TextEditingController();
    final depositCtrl = TextEditingController();
    final depositPaidCtrl = TextEditingController();
    String? customerId;
    final preItems = <Map<String, dynamic>>[];
    var guests = 2;
    final now = DateTime.now();
    var arriveDate = DateTime(now.year, now.month, now.day);
    var arriveTime = () {
      var h = now.hour;
      var m = now.minute;
      if (m == 0) {
        m = 30;
      } else if (m <= 30) {
        m = 30;
      } else {
        m = 0;
        h = (h + 1) % 24;
      }
      return TimeOfDay(hour: h, minute: m);
    }();
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final c = await _pickCustomerForReserve();
                        if (c == null) return;
                        setLocal(() {
                          customerId = c.id;
                          nameCtrl.text = c.name;
                          if ((c.phone ?? '').isNotEmpty) {
                            phoneCtrl.text = c.phone!;
                          }
                        });
                      },
                      icon: const Icon(Icons.person_search_outlined, size: 18),
                      label: Text(tr(customerId == null
                          ? 'Chọn khách CRM'
                          : 'Đổi khách CRM')),
                    ),
                  ),
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('Số khách'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final n in const [2, 4, 6, 8])
                        ChoiceChip(
                          label: Text('$n'),
                          selected: guests == n,
                          onSelected: (_) => setLocal(() {
                            guests = n;
                            guestCtrl.text = '$n';
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('Ngày đến'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text(tr('Hôm nay')),
                        selected: arriveDate ==
                            DateTime(now.year, now.month, now.day),
                        onSelected: (_) => setLocal(() => arriveDate =
                            DateTime(now.year, now.month, now.day)),
                      ),
                      ChoiceChip(
                        label: Text(tr('Ngày mai')),
                        selected: arriveDate ==
                            DateTime(now.year, now.month, now.day)
                                .add(const Duration(days: 1)),
                        onSelected: (_) => setLocal(() => arriveDate =
                            DateTime(now.year, now.month, now.day)
                                .add(const Duration(days: 1))),
                      ),
                      ActionChip(
                        label: Text(
                          tr(DateFormat('dd/MM').format(arriveDate)),
                        ),
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('Giờ đến'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in [
                        arriveTime,
                        const TimeOfDay(hour: 18, minute: 0),
                        const TimeOfDay(hour: 18, minute: 30),
                        const TimeOfDay(hour: 19, minute: 0),
                        const TimeOfDay(hour: 19, minute: 30),
                        const TimeOfDay(hour: 20, minute: 0),
                      ].fold<List<TimeOfDay>>([], (acc, t) {
                        if (acc.any(
                            (x) => x.hour == t.hour && x.minute == t.minute)) {
                          return acc;
                        }
                        acc.add(t);
                        return acc;
                      }))
                        ChoiceChip(
                          label: Text(
                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                          ),
                          selected: arriveTime.hour == t.hour &&
                              arriveTime.minute == t.minute,
                          onSelected: (_) =>
                              setLocal(() => arriveTime = t),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.schedule, size: 16),
                        label: Text(tr('Khác')),
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: depositCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr('Cọc yêu cầu'),
                            border: OutlineInputBorder(),
                            isDense: true,
                            suffixText: 'đ',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: depositPaidCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr('Đã thu ngay'),
                            border: OutlineInputBorder(),
                            isDense: true,
                            suffixText: 'đ',
                          ),
                        ),
                      ),
                    ],
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
    guests = int.tryParse(guestCtrl.text.trim()) ?? guests;
    if (guests < 1) guests = 1;
    final arriveLocal = DateTime(
      arriveDate.year,
      arriveDate.month,
      arriveDate.day,
      arriveTime.hour,
      arriveTime.minute,
    );
    final depositAmount =
        double.tryParse(depositCtrl.text.trim().replaceAll(',', '')) ?? 0;
    final depositPaid =
        double.tryParse(depositPaidCtrl.text.trim().replaceAll(',', '')) ?? 0;
    final res = await _api.createPosResourceReservation({
      'resourceId': r.id,
      'customerName': name,
      'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      if (customerId != null) 'customerId': customerId,
      'guestCount': guests < 1 ? 1 : guests,
      'reservedUntil': arriveLocal.toUtc().toIso8601String(),
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      if (preItems.isNotEmpty) 'preOrderItems': preItems,
      if (depositAmount > 0) 'depositAmount': depositAmount,
      if (depositPaid > 0) 'depositPaid': depositPaid,
      if (depositPaid > 0) 'depositPaymentMethod': 'Tiền mặt',
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

  Future<PosCustomer?> _pickCustomerForReserve() async {
    final searchCtrl = TextEditingController();
    var hits = <PosCustomer>[];
    var loading = false;

    return showDialog<PosCustomer>(
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
                  next.add(PosCustomer.fromJson(Map<String, dynamic>.from(e)));
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
                      border: OutlineInputBorder(),
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
                        : hits.isEmpty
                            ? Center(
                                child: Text(tr('Nhập từ khóa rồi tìm'),
                                    style: TextStyle(
                                        color: PosTheme.textSecondary)))
                            : ListView.builder(
                                itemCount: hits.length,
                                itemBuilder: (_, i) {
                                  final c = hits[i];
                                  return ListTile(
                                    dense: true,
                                    title: Text(tr(c.name)),
                                    subtitle: Text(tr(
                                        [c.phone, c.customerCode]
                                            .where((e) =>
                                                (e ?? '').trim().isNotEmpty)
                                            .join(' · '))),
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
                  child: Text(tr('Đóng'))),
            ],
          );
        },
      ),
    );
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
                if (r.draftBillCount > 1) '${r.draftBillCount} hóa đơn',
              ].join(' · '))),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: Text(tr('Vào chọn món / dịch vụ')),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            ListTile(
              leading: Icon(Icons.event_seat_outlined,
                  color: Colors.red.shade700),
              title: Text(tr('Trả về bàn trống')),
              subtitle: Text(tr(_isWaitingTable(r)
                  ? 'Đóng phiên — bàn chưa gọi món'
                  : r.lineCount > 0
                      ? 'Xóa ${r.lineCount} món trên đơn tạm và đóng phiên'
                      : 'Đóng phiên — trả bàn về trống')),
              onTap: () => Navigator.pop(ctx, 'free'),
            ),
            if (_isFnB)
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
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(tr('Tách bill')),
              subtitle: Text(tr('Khách trả một phần — bàn giữ món còn lại')),
              onTap: () => Navigator.pop(ctx, 'splitBill'),
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
            if (widget.allowProvisionalBill)
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
      await _returnTableToEmpty(r);
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
    if (action == 'splitBill') {
      await _splitBill(r);
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
          defaultServiceProductId: x.defaultServiceProductId,
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
            reservationDepositPaid: x.reservationDepositPaid,
            reservationDepositAmount: x.reservationDepositAmount,
            reservationDepositStatus: x.reservationDepositStatus,
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
        // Silent — báo chế biến OK không toast che sơ đồ.
        debugPrint('Floor kitchen send OK: $n · ${r.name}');
        unawaited(_printFloorKitchenSlip(r, data));
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

  /// Báo bếp từ sơ đồ bàn cũng phải ra phiếu. Trước đây màn này chỉ gọi API
  /// đánh dấu đã gửi: bếp không nhận được gì, mà vì đã đánh dấu nên mở bàn ra
  /// bấm Báo bếp lại cũng báo «không có món mới» — món chìm luôn.
  /// Màn sơ đồ không giữ giỏ hàng nên dựng phiếu từ `sentItems` server trả về.
  Future<void> _printFloorKitchenSlip(
    PosServiceResourceDto r,
    Map data,
  ) async {
    try {
      final settings = await PosSellPrintSettings.load();
      if (!settings.kitchenSlipPrintMode.shouldPrintOnBaoBep) return;

      final raw = data['sentItems'];
      if (raw is! List || raw.isEmpty) return;
      final lines = <KitchenTicketLine>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final qty = (e['qty'] as num?)?.toDouble() ?? 0;
        if (qty <= 0) continue;
        lines.add(KitchenTicketLine(
          productName: e['productName']?.toString() ?? '',
          qty: qty,
          unitName: e['unitName']?.toString(),
          note: e['note']?.toString(),
          productId: e['productId']?.toString(),
          sentBefore: (e['sentBefore'] as num?)?.toDouble(),
          lineKey: e['lineId']?.toString(),
        ));
      }
      if (lines.isEmpty) return;

      await printKitchenCompactSlip(
        tableName: formatPosTableLabel(
          areaName: r.areaName,
          tableName: r.name,
        ),
        isCancel: false,
        lines: lines,
        senderName: (await PosDeviceIdentity.get()).name,
        orderNo: data['orderNo']?.toString(),
        waitForCompletion: false,
        showFeedback: false,
      );
    } catch (e) {
      debugPrint('Floor kitchen print: $e');
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
          defaultServiceProductId: x.defaultServiceProductId,
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
          defaultServiceProductId: x.defaultServiceProductId,
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
        _emitSelect(_tableSelectPayload(
          target,
          extra: {
            'saleOrderId': newOrderId,
            'sessionId': data2['newSessionId']?.toString(),
          },
        ));
      }
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tách được',
      );
    }
  }

  Future<void> _splitBill(PosServiceResourceDto r) async {
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
        message: tr('Không tải được đơn để tách bill'),
      );
      return;
    }
    final order = PosSaleOrder.fromJson(
        Map<String, dynamic>.from(orderRes['data'] as Map));
    if (order.lines.isEmpty) return;
    final picks = await showPosSplitBillSheet(
      context: context,
      lines: order.lines,
    );
    if (!mounted || picks == null || picks.isEmpty) return;

    final res = await _api.splitPosBill(
      sid,
      items: [
        for (final p in picks) {'lineId': p.lineId, 'qty': p.qty},
      ],
      deviceId: _deviceId,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không tách được',
        message: posSplitBillErrorMessage(res['message']?.toString()),
      );
      return;
    }
    final data2 = res['data'] as Map? ?? {};
    final newOrderId = data2['newSaleOrderId']?.toString();
    widget.onResourceFreed?.call(r.id);
    NotificationOverlayManager().showSuccess(
      title: 'Đã tách bill',
      message: tr('Thanh toán phần này — món còn lại giữ ${r.name}'),
    );
    await _reload();
    if (!mounted || newOrderId == null || newOrderId.isEmpty) return;
    _emitSelect(_tableSelectPayload(
      r,
      extra: {
        'saleOrderId': newOrderId,
        'sessionId': '',
        'isSplitBill': true,
        'splitFromOrderId': data2['splitFromOrderId']?.toString() ?? oid,
      },
    ));
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
          defaultServiceProductId: x.defaultServiceProductId,
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
          defaultServiceProductId: x.defaultServiceProductId,
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
        content: PosNoSoftKeyboardField(
          controller: ctrl,
          allowDecimal: false,
          autofocus: true,
          keypadTitle: 'Số khách',
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
    if (!widget.allowProvisionalBill && !r.isBillRequested) return;
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

  List<PosServiceResourceDto> get _busyTables => _resources
      .where((r) => r.isOccupied || r.isHolding || r.isParked)
      .toList();

  int get busyTableCount => _busyTables.length;

  Future<void> returnAllTablesToEmpty() => _returnAllTablesToEmpty();

  /// Trả bàn về trống. Bàn còn món: xóa đơn tạm rồi đóng phiên.
  Future<bool> _returnTableToEmpty(
    PosServiceResourceDto r, {
    bool confirmIfBusy = true,
  }) async {
    final busy = r.lineCount > 0 || r.subtotal > 0;
    if (confirmIfBusy && busy) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Trả ${r.name} về trống?')),
          content: Text(tr(
            'Bàn còn ${r.lineCount} món'
            '${r.subtotal > 0 ? ' · ${_moneyFmt.format(r.subtotal)}đ' : ''}.\n'
            'Xóa đơn tạm, không thu tiền, đóng phiên.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Trả về trống')),
            ),
          ],
        ),
      );
      if (ok != true) return false;
    }

    final orderId = (r.openOrderId ?? '').trim();
    if (orderId.isNotEmpty && busy) {
      final del = await _api.deletePosSale(orderId);
      if (!mounted) return false;
      if (del['isSuccess'] != true) {
        NotificationOverlayManager().showError(
          title: 'Không xóa được đơn',
          message: del['message']?.toString() ??
              'Không trả được bàn còn món. Mở bàn → xóa món hoặc hủy đơn.',
        );
        return false;
      }
    }

    await _freeHoldingTable(r, quiet: !confirmIfBusy);
    return true;
  }

  Future<void> _returnAllTablesToEmpty() async {
    final busy = _busyTables;
    if (busy.isEmpty) return;
    final withItems = busy.where((r) => r.lineCount > 0 || r.subtotal > 0).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Trả hết bàn về trống?')),
        content: Text(tr(
          '${busy.length} ${(widget.sellProfile ?? PosSellProfile.restaurant).resourceNoun} đang dùng'
          '${withItems > 0 ? ' (trong đó $withItems còn món)' : ''}.\n'
          'Xóa đơn tạm, không thu tiền, đóng mọi phiên.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Trả hết trống')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    var done = 0;
    var fail = 0;
    for (final r in List<PosServiceResourceDto>.from(busy)) {
      final okOne = await _returnTableToEmpty(r, confirmIfBusy: false);
      if (okOne) {
        done++;
      } else {
        fail++;
      }
      if (!mounted) return;
    }
    if (!mounted) return;
    if (fail == 0) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã trả hết về trống',
        message: tr('$done ${(widget.sellProfile ?? PosSellProfile.restaurant).resourceNoun}'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Trả bàn chưa xong',
        message: tr('Được $done · lỗi $fail. Thử lại bàn còn món.'),
      );
    }
    await _reload();
  }

  /// Bàn Holding (chưa gọi món) → đóng mọi phiên, trả về trống.
  Future<void> _freeHoldingTable(
    PosServiceResourceDto r, {
    bool quiet = false,
  }) async {
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
          defaultServiceProductId: x.defaultServiceProductId,
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
          reservationDepositPaid: x.reservationDepositPaid,
          reservationDepositAmount: x.reservationDepositAmount,
          reservationDepositStatus: x.reservationDepositStatus,
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
    if (!quiet) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã trả về trống',
        message: r.name,
      );
    }

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
                          const SizedBox(width: 4),
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _showQuickCreateTables();
                            },
                            icon: const Icon(Icons.playlist_add),
                            label: Text(tr('Tạo nhanh')),
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

  /// Tạo nhanh: nhập tên nhóm + số bàn → tự sinh mã/tên Bàn 1…N.
  Future<void> _showQuickCreateTables() async {
    var initialGroup = '';
    if (_areaFilter != null) {
      for (final a in _areas) {
        if (a.id == _areaFilter) {
          initialGroup = a.name;
          break;
        }
      }
    }
    final groupCtrl = TextEditingController(text: tr(initialGroup));
    var count = 8;
    var startNo = 1;
    var capacity = 4;
    var kind = switch (widget.sellProfile) {
      PosSellProfile.salon => PosResourceKind.chair,
      PosSellProfile.roomHourly => PosResourceKind.room,
      PosSellProfile.hotel => PosResourceKind.room,
      _ => PosResourceKind.table,
    };
    final countCtrl = TextEditingController(text: '$count');
    final startCtrl = TextEditingController(text: '$startNo');
    final capacityCtrl = TextEditingController(text: '$capacity');

    String kindLabel(PosResourceKind k) => switch (k) {
          PosResourceKind.chair => 'Ghế',
          PosResourceKind.room => 'Phòng',
          PosResourceKind.other => 'Ô',
          PosResourceKind.table => 'Bàn',
        };

    List<({String code, String name, int no})> previewFor(
      String groupName,
      int n,
      int start,
      PosResourceKind k,
    ) {
      final label = kindLabel(k);
      final prefix = _quickTableCodePrefix(groupName);
      final existingCodes = {
        for (final r in _resources) r.code.trim().toUpperCase(),
      };
      final out = <({String code, String name, int no})>[];
      var no = start < 1 ? 1 : start;
      var safety = 0;
      while (out.length < n && safety < 500) {
        safety++;
        final code = '$prefix${no.toString().padLeft(2, '0')}';
        if (existingCodes.contains(code.toUpperCase()) ||
            out.any((e) => e.code.toUpperCase() == code.toUpperCase())) {
          no++;
          continue;
        }
        out.add((code: code, name: '$label $no', no: no));
        no++;
      }
      return out;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final groupName = groupCtrl.text.trim();
          final preview = groupName.isEmpty
              ? const <({String code, String name, int no})>[]
              : previewFor(groupName, count, startNo, kind);
          return AlertDialog(
            title: Text(tr('Tạo bàn nhanh')),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: groupCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: tr('Tên nhóm'),
                        hintText: tr('VD: Tầng 1, Khu A, Sân thượng…'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(tr('Số bàn trong nhóm'),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final n in const [4, 6, 8, 10, 12, 16, 20])
                          ChoiceChip(
                            label: Text('$n'),
                            selected: count == n,
                            onSelected: (_) {
                              setLocal(() {
                                count = n;
                                countCtrl.text = '$n';
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: countCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: tr('Hoặc nhập số'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              final n = int.tryParse(v.trim());
                              if (n != null && n >= 1 && n <= 99) {
                                setLocal(() => count = n);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: startCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: tr('Số bắt đầu'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              final n = int.tryParse(v.trim());
                              if (n != null && n >= 1 && n <= 999) {
                                setLocal(() => startNo = n);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<PosResourceKind>(
                      value: kind,
                      decoration: InputDecoration(
                        labelText: tr('Loại'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: PosResourceKind.values
                          .map((k) => DropdownMenuItem(
                                value: k,
                                child: Text(tr(k.label)),
                              ))
                          .toList(),
                      onChanged: (v) => setLocal(() => kind = v ?? kind),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: capacityCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('Sức chứa mỗi bàn'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        tr('Sẽ tạo ${preview.length} bàn'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 140),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            preview
                                .map((e) => '${e.name}  (${e.code})')
                                .join('\n'),
                            style: const TextStyle(
                                fontSize: 13, height: 1.35),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Huỷ')),
              ),
              FilledButton(
                onPressed: groupName.isEmpty || preview.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(tr('Tạo')),
              ),
            ],
          );
        },
      ),
    );

    final groupName = groupCtrl.text.trim();
    count = int.tryParse(countCtrl.text.trim()) ?? count;
    startNo = int.tryParse(startCtrl.text.trim()) ?? startNo;
    capacity = int.tryParse(capacityCtrl.text.trim()) ?? capacity;
    if (capacity < 1) capacity = 1;
    if (count < 1) count = 1;
    if (count > 99) count = 99;
    if (ok != true || groupName.isEmpty) return;

    final preview = previewFor(groupName, count, startNo, kind);
    if (preview.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không tạo được',
        message: tr('Không sinh được mã bàn — thử đổi số bắt đầu'),
      );
      return;
    }

    // Nhóm trùng tên (không phân biệt hoa thường) → dùng lại; không thì tạo mới.
    PosServiceAreaDto? area;
    final groupKey = groupName.toLowerCase();
    for (final a in _areas) {
      if (a.name.trim().toLowerCase() == groupKey) {
        area = a;
        break;
      }
    }
    if (area == null) {
      final areaRes = await _api.createPosServiceArea({'name': groupName});
      if (!mounted) return;
      if (areaRes['isSuccess'] != true || areaRes['data'] is! Map) {
        NotificationOverlayManager().showError(
          title: 'Lỗi tạo nhóm',
          message: areaRes['message']?.toString() ?? 'Không tạo được nhóm',
        );
        return;
      }
      area = PosServiceAreaDto.fromJson(
          Map<String, dynamic>.from(areaRes['data'] as Map));
    }
    final targetArea = area!;

    const tileW = 120.0;
    const tileH = 100.0;
    const gap = 16.0;
    const stepX = tileW + gap;
    const stepY = tileH + gap;
    final baseIndex = _resources.length;
    var created = 0;
    String? lastErr;
    for (var i = 0; i < preview.length; i++) {
      final item = preview[i];
      final col = (baseIndex + i) % 4;
      final row = (baseIndex + i) ~/ 4;
      final body = <String, dynamic>{
        'areaId': targetArea.id,
        'code': item.code,
        'name': item.name,
        'resourceKind': kind.apiValue,
        'capacity': capacity,
        'sortOrder': baseIndex + i,
        'isActive': true,
        'layoutX': col * stepX,
        'layoutY': row * stepY,
        'layoutW': tileW,
        'layoutH': tileH,
      };
      final res = await _api.createPosServiceResource(body);
      if (res['isSuccess'] == true) {
        created++;
      } else {
        lastErr = res['message']?.toString();
        break;
      }
    }

    if (!mounted) return;
    _areaFilter = targetArea.id;
    await _reload();
    if (created > 0) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã tạo bàn nhanh',
        message: tr('$created bàn trong «${targetArea.name}»'),
      );
    }
    if (created < preview.length) {
      NotificationOverlayManager().showError(
        title: 'Tạo chưa đủ',
        message: lastErr ??
            tr('Chỉ tạo được $created/${preview.length} bàn'),
      );
    }
  }

  /// Tiền tố mã bàn từ tên nhóm (VD: "Tầng 1" → "T1", "Khu A" → "KA").
  String _quickTableCodePrefix(String groupName) {
    final raw = groupName.trim();
    if (raw.isEmpty) return 'B';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)!).join();
    final letters = raw
        .replaceAll(RegExp(r'[^a-zA-ZÀ-ỹ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .join();
    var prefix = '$letters$digits';
    if (prefix.isEmpty) {
      prefix = raw.length <= 3 ? raw.toUpperCase() : raw.substring(0, 3).toUpperCase();
    }
    if (prefix.length > 6) prefix = prefix.substring(0, 6);
    return prefix;
  }

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
          PosSellProfile.hotel => PosResourceKind.room,
          _ => PosResourceKind.table,
        };
    var capacity = existing?.capacity ?? 4;
    var isActive = existing?.isActive ?? true;
    final codeCtrl = TextEditingController(text: tr(existing?.code ?? ''));
    final nameCtrl = TextEditingController(text: tr(existing?.name ?? ''));
    final capacityCtrl =
        TextEditingController(text: tr(capacity.toString()));
    final rateCtrl = TextEditingController(
      text: existing?.defaultHourlyRate == null
          ? ''
          : '${existing!.defaultHourlyRate!.round()}',
    );
    String? defaultServiceProductId = existing?.defaultServiceProductId;
    List<PosProduct> timedProducts = [];
    final timedRes = await _api.getPosProducts(
      productType: PosProductType.service,
      pageSize: 200,
      sortBy: PosProductSortBy.name,
      sortDesc: false,
    );
    if (!mounted) return;
    final timedRaw = timedRes['data'];
    final timedItems = timedRaw is Map
        ? (timedRaw['items'] ?? timedRaw['Items'])
        : timedRaw is List
            ? timedRaw
            : null;
    if (timedItems is List) {
      for (final e in timedItems) {
        if (e is! Map) continue;
        final p = PosProduct.fromJson(Map<String, dynamic>.from(e));
        if (p.isTimedService) timedProducts.add(p);
      }
    }
    if (defaultServiceProductId != null &&
        !timedProducts.any((p) => p.id == defaultServiceProductId)) {
      defaultServiceProductId = null;
    }

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
                const SizedBox(height: 10),
                TextField(
                  controller: rateCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('Giá giờ mặc định (bi-a / karaoke)'),
                    hintText: tr('Khi SP theo giờ chưa có giá'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: defaultServiceProductId,
                  decoration: InputDecoration(
                    labelText: tr('SP tính giờ khi mở bàn'),
                    hintText: tr('Ghi đè SP mặc định cửa hàng'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(tr('— Dùng mặc định cửa hàng —')),
                    ),
                    ...timedProducts.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(tr(p.name), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setLocal(() => defaultServiceProductId = v),
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
    final rate = double.tryParse(rateCtrl.text.trim().replaceAll(',', ''));

    final body = <String, dynamic>{
      'areaId': areaId,
      'code': code,
      'name': name,
      'resourceKind': kind.apiValue,
      'capacity': capacity,
      'sortOrder': existing?.sortOrder ?? _resources.length,
      'isActive': isActive,
      'defaultHourlyRate': (rate != null && rate > 0) ? rate : null,
      'defaultServiceProductId': defaultServiceProductId,
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
      final missingTimed = _warnMissingTimed;
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(tr(missingTimed ? 'Thiếu SP giờ' : 'Bàn chờ'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: missingTimed ? const Color(0xFFC2410C) : accent,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Icon(
              missingTimed
                  ? Icons.timer_off_outlined
                  : _kindIcon(r.resourceKind),
              size: 26,
              color: (missingTimed ? const Color(0xFFC2410C) : accent)
                  .withValues(alpha: 0.75),
            ),
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

  double _floorTileAspectRatio(double tileW, {bool compact = false}) {
    // Ô hẹp (phone / nhiều cột): cân đối hơn.
    if (compact || tileW < 110) {
      if (tileW < 100) return 0.86;
      if (tileW < 120) return 0.90;
      return 0.94;
    }
    // Ô rộng: cao hơn một chút để vừa tên · tiền · khách.
    if (tileW < 140) return 0.80;
    return 0.86;
  }

  /// Số cột lưới bàn theo bề rộng **ô chứa** (pane trái tablet ≠ full screen).
  /// Không dùng breakpoint 768 — pane F&B thường 500–700px vẫn đủ 4–6 cột.
  int _floorGridColumns(double usable, {double gap = 8}) {
    if (usable < 300) return 2;
    if (usable < 380) return 3;
    // Mục tiêu ô ~100–112px → tablet nửa màn ~5–6 cột, full ~7–8.
    const minTile = 104.0;
    return ((usable + gap) / (minTile + gap)).floor().clamp(3, 8);
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
    if (r.reservationDepositPaid > 0) {
      parts.add('Cọc ${_moneyFmt.format(r.reservationDepositPaid)}');
    }
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

  bool _resourceMatchesSearch(PosServiceResourceDto r) {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.name.toLowerCase().contains(q) ||
        r.code.toLowerCase().contains(q) ||
        r.areaName.toLowerCase().contains(q);
  }

  List<PosServiceResourceDto> get _searchFilteredResources {
    Iterable<PosServiceResourceDto> list = _resources;
    final area = _areaFilter;
    if (area != null) list = list.where((r) => r.areaId == area);
    return list.where(_resourceMatchesSearch).toList();
  }

  /// Quét mã / gõ mã bàn → mở bàn khớp chính xác (code hoặc tên).
  bool tryOpenByCode(String raw) {
    final code = raw.trim().toLowerCase();
    if (code.isEmpty) return false;
    final exact = _resources
        .where((r) =>
            r.code.toLowerCase() == code || r.name.toLowerCase() == code)
        .toList();
    final hit = exact.length == 1
        ? exact.first
        : _searchFilteredResources.length == 1
            ? _searchFilteredResources.first
            : null;
    if (hit == null) return false;
    unawaited(_openResource(hit));
    return true;
  }

  /// Bán hàng / xem: lưới theo bề rộng pane (tablet ≥4–6 cột khi đủ chỗ).
  /// Chỉ khi sắp xếp (_layoutEdit) mới dùng canvas kéo thả.
  List<PosServiceResourceDto> get _resourcesByFloorOrder {
    final list = List<PosServiceResourceDto>.from(_searchFilteredResources);
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

  /// Số cột theo bề rộng ô chứa. Khi lọc «Tất cả»: chia nhóm theo khu vực.
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
    for (final r in _searchFilteredResources) {
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
        const gap = 8.0;
        final usable = w.clamp(200.0, 4000.0);
        final cols = _floorGridColumns(usable, gap: gap);
        final tileW = (usable - gap * (cols - 1)) / cols;
        final ratio = _floorTileAspectRatio(tileW, compact: cols >= 5);
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
        const gap = 8.0;
        const pad = 8.0;
        final usable = (w - pad * 2).clamp(200.0, 4000.0);
        final cols = _floorGridColumns(usable, gap: gap);
        final tileW = (usable - gap * (cols - 1)) / cols;
        final ratio = _floorTileAspectRatio(tileW, compact: cols >= 5);

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
    // Đồng bộ tổng tạm tính lên top bar màn bán (embedded).
    _notifyActiveTotals();
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
                              if (_areaFilter == null) return;
                              setState(() => _areaFilter = null);
                            },
                          ),
                          const SizedBox(width: 8),
                          ..._areas.map((a) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _AreaChip(
                                  label: a.name,
                                  selected: _areaFilter == a.id,
                                  onTap: () {
                                    if (_areaFilter == a.id) return;
                                    setState(() => _areaFilter = a.id);
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
                            const SizedBox(width: 4),
                            ActionChip(
                              avatar:
                                  const Icon(Icons.playlist_add, size: 18),
                              label: Text(tr('Tạo nhanh'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              onPressed: () =>
                                  unawaited(_showQuickCreateTables()),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              visualDensity: VisualDensity.standard,
                            ),
                          ] else ...[
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 18),
                              label: Text(
                                  tr(_bookingChipLabel),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              onPressed: () => unawaited(
                                _isSalon || _isHourly
                                    ? _openAppointmentCalendar()
                                    : _showTodayReservations(),
                              ),
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
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    tr(widget.manageMode
                                        ? 'Chưa có bàn/phòng.\nDùng «Tạo bàn nhanh» hoặc thêm từng bàn.'
                                        : 'Chưa có bàn/phòng.\nVào Nhiều hơn → Quản lý bàn/phòng để thiết lập.'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: PosTheme.textSecondary),
                                  ),
                                  if (widget.manageMode) ...[
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: () =>
                                          unawaited(_showQuickCreateTables()),
                                      icon: const Icon(Icons.playlist_add),
                                      label: Text(tr('Tạo bàn nhanh')),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        // Bán hàng + xem quản lý: lưới theo bề rộng pane.
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
                IconButton(
                  tooltip: tr('Màn hình bếp (KDS)'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PosKdsScreen()),
                    );
                  },
                  icon: const Icon(Icons.kitchen_outlined),
                ),
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
                    tooltip: tr('Tạo bàn nhanh'),
                    onPressed: () => unawaited(_showQuickCreateTables()),
                    icon: const Icon(Icons.playlist_add),
                  ),
                  IconButton(
                    tooltip: tr('Thêm bàn'),
                    onPressed: _addResource,
                    icon: const Icon(Icons.add),
                  ),
                ],
                IconButton(
                  tooltip: tr(_bookingChipLabel),
                  onPressed: () => unawaited(
                    _isSalon || _isHourly
                        ? _openAppointmentCalendar()
                        : _showTodayReservations(),
                  ),
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
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
              if (allowSellActions)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_showSellTileActions(r)),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: _tileBorder(r).withValues(alpha: 0.85),
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
              text: tr(r.draftBillCount > 1
                  ? '${_moneyFmt.format(r.subtotal)}đ · ${r.draftBillCount} HĐ'
                  : '${_moneyFmt.format(r.subtotal)}đ'),
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
    if (!allowSellActions && !allowManageActions) {
      return RepaintBoundary(child: body);
    }

    return RepaintBoundary(
      child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: allowManageActions
            ? () => unawaited(_showManageResourceActions(r))
            : () => unawaited(_openResource(r)),
        onLongPress: allowManageActions
            ? () => unawaited(_showManageResourceActions(r))
            : () => unawaited(_showSellTileActions(r)),
        child: body,
      ),
    ),
    );
  }

  /// Menu thao tác bàn (⋯ hoặc long-press) — không chỉ dựa vào giữ lâu.
  Future<void> _showSellTileActions(PosServiceResourceDto r) async {
    if (r.isOccupied || r.isHolding) {
      await _showOccupiedActions(r);
    } else if (r.isReserved) {
      await _showReservedActions(r);
    } else if (r.isFree) {
      if (_isSalon) {
        await _openAppointmentCalendar(resourceId: r.id);
      } else {
        await _showReserveDialog(r);
      }
    }
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
