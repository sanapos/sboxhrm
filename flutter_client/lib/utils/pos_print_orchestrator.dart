import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../models/hrm.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../services/pos_print_agent_service.dart';
import '../services/signalr_service.dart';
import '../widgets/notification_overlay.dart';
import 'pos_device_identity.dart';
import 'pos_label_printer_service.dart';
import 'pos_local_printers_store.dart';
import 'pos_print_agent_settings.dart';
import 'pos_print_config_session.dart';
import 'pos_print_role.dart';
import 'pos_print_template_renderer.dart';
import 'pos_print_template_runtime.dart';
import 'pos_sell_store_settings.dart';
import 'pos_printer_readiness.dart';
import 'pos_printer_transport.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_sunmi_native_print.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_usb_printer.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'pos_print_template_v2_codec.dart';
import 'pos_print_template_compiler.dart';

String _kdsCutRef(String? base, int i, String name) {
  var s = '${base ?? 'k'}|i$i|${name.trim()}';
  if (s.length <= 64) return s;
  return s.substring(s.length - 64);
}

String _hhmm(DateTime t) {
  final l = t.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

void _notifyPrintDedupSkip({String? detail}) {
  NotificationOverlayManager().showWarning(
    title: 'Bỏ qua lệnh trùng',
    message: tr(
      detail ??
          'Lệnh gần đây đang chờ máy in — không gửi trùng (tránh bấm nhiều lần)',
    ),
    relatedEntityType: kPosPrintNotifyKind,
    duration: const Duration(seconds: 3),
  );
}
/// Job cloud chưa xong sau [PosPrintOrchestrator.hangAfterDefault] → phiếu treo.
typedef PosPrintHangCallback = void Function({
  required String jobId,
  required String documentType,
  required String printerId,
  required String printerName,
  String? referenceNo,
});

/// Điều phối in cloud qua Máy in cửa hàng + Print Agent.
/// In LAN/BT cục bộ: dùng [dispatchLocalEscPos] / [dispatchLocalEscPosByRole].
class PosPrintOrchestrator {
  PosPrintOrchestrator._();
  static final PosPrintOrchestrator instance = PosPrintOrchestrator._();

  /// Thời gian chờ Agent in trước khi đưa phiếu vào hàng treo (máy gửi).
  static const hangAfterDefault = Duration(seconds: 60);

  /// Job còn Claimed/Printing thì kiểm tra lại sau chừng này thay vì bỏ theo dõi.
  static const hangWatchRecheck = Duration(seconds: 20);

  /// Trần theo dõi — dài hơn mốc server hủy job kẹt (180s) để bắt được Cancelled.
  static const hangWatchMaxWait = Duration(seconds: 240);

  final _api = ApiService();
  final _signalR = SignalRService();
  final _pendingJobs = <String, Completer<_JobOutcome>>{};
  /// True = server-side Cancelled (operator cancel / idempotency dedup / replaced).
  /// Distinguishes Cancelled from Failed so caller can suppress re-queue.
  final _cancelledJobs = <String>{};
  /// Policy chờ Completed (false = không coi Claimed/Printing là thành công).
  final _acceptClaimedByJob = <String, bool>{};
  /// showFeedback khi SignalR cập nhật status (tránh báo đỏ phiếu bếp fire-and-forget).
  final _showFeedbackByJob = <String, bool>{};
  final _jobMeta = <String, _JobFeedbackMeta>{};
  final _feedbackSent = <String>{};
  final _hangTimers = <String, Timer>{};
  /// Callback phiếu treo theo job — giữ khi fire-and-forget để Failed/Expired vẫn treo.
  final _hangCallbacks = <String, _HangWatch>{};

  List<PosStorePrinter> _printers = [];
  List<PosPrinterRoute> _routes = [];
  DateTime? _cacheAt;
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  bool _listening = false;

  static const _cacheTtl = Duration(seconds: 60);
  static const _jobTimeout = Duration(seconds: 120);

  StreamSubscription<bool>? _connSub;

  Future<void> ensureListening() async {
    if (_listening && _statusSub != null) return;
    _listening = true;
    _statusSub = _signalR.onPrintJobStatusChanged.listen(_onJobStatus);
    _connSub?.cancel();
    _connSub = _signalR.onConnectionStateChanged.listen((connected) {
      if (connected) {
        debugPrint('📡 Print orchestrator: SignalR reconnected — re-arming status subscription');
        _statusSub?.cancel();
        _statusSub = _signalR.onPrintJobStatusChanged.listen(_onJobStatus);
        PosPrintAgentService.instance.nudgeClaim();
      }
    });
  }

  void dispose() {
    _statusSub?.cancel();
    _connSub?.cancel();
    _listening = false;
    for (final t in _hangTimers.values) {
      t.cancel();
    }
    _hangTimers.clear();
    _hangCallbacks.clear();
    for (final c in _pendingJobs.values) {
      if (!c.isCompleted) {
        c.complete(const _JobOutcome(false, 'Đã hủy'));
      }
    }
    _pendingJobs.clear();
    _acceptClaimedByJob.clear();
    _showFeedbackByJob.clear();
    _jobMeta.clear();
    _feedbackSent.clear();
  }

  void _cancelHangWatch(String jobId, {bool clearCallback = true}) {
    _hangTimers.remove(jobId)?.cancel();
    if (clearCallback) _hangCallbacks.remove(jobId);
  }

  void _armHangWatch({
    required String jobId,
    required String documentType,
    required PosStorePrinter printer,
    String? referenceNo,
    bool acceptClaimedAsSuccess = true,
    Duration hangAfter = hangAfterDefault,
    PosPrintHangCallback? onHang,
  }) {
    // Trước đây thiếu onHang là bỏ theo dõi luôn: tem ly, phiếu kho, tạm tính,
    // in lại từ danh sách… gửi lên cloud xong coi như xong. Agent chết là mất
    // giấy mà không ai biết. Giờ vẫn theo dõi, chỉ khác cách xử lý khi treo.
    _cancelHangWatch(jobId);
    _hangCallbacks[jobId] = _HangWatch(
      documentType: documentType,
      printerId: printer.id,
      printerName: printer.name,
      referenceNo: referenceNo,
      onHang: onHang,
    );
    _armHangTimer(
      jobId: jobId,
      hangAfter: hangAfter,
      acceptClaimedAsSuccess: acceptClaimedAsSuccess,
      deadline: DateTime.now().add(hangWatchMaxWait),
    );
  }

  /// Agent nhận job rồi treo là trường hợp mất phiếu tệ nhất: server dọn bằng
  /// Cancelled sau ~3 phút, còn máy gửi thì đã bỏ theo dõi từ giây thứ 60 vì
  /// thấy trạng thái Claimed. Thu ngân không thấy lỗi, không có phiếu chờ, và
  /// hóa đơn/phiếu bếp biến mất. Vì vậy vẫn còn Claimed/Printing thì hẹn lại
  /// giờ kiểm tra thay vì bỏ, và Cancelled cũng tính là treo để in lại được.
  void _armHangTimer({
    required String jobId,
    required Duration hangAfter,
    required bool acceptClaimedAsSuccess,
    required DateTime deadline,
  }) {
    _hangTimers[jobId] = Timer(hangAfter, () {
      _hangTimers.remove(jobId);
      unawaited(() async {
        String status;
        try {
          final res = await _api.getPosPrintJob(jobId);
          status = (res['data'] is Map)
              ? (res['data'] as Map)['status']?.toString() ?? ''
              : '';
        } catch (_) {
          // Lỗi mạng khi poll — giữ callback; SignalR Failed vẫn có thể treo.
          return;
        }

        if (status == 'Completed') {
          _hangCallbacks.remove(jobId);
          return;
        }
        if (status == 'Claimed' || status == 'Printing') {
          if (acceptClaimedAsSuccess && DateTime.now().isAfter(deadline)) {
            // Hết hạn theo dõi mà Agent vẫn giữ job: coi như đã in xong để
            // không dựng phiếu chờ gây in trùng.
            _hangCallbacks.remove(jobId);
            return;
          }
          if (DateTime.now().isAfter(deadline)) {
            _invokeHangCallback(jobId);
            return;
          }
          if (_hangCallbacks.containsKey(jobId)) {
            _armHangTimer(
              jobId: jobId,
              hangAfter: hangWatchRecheck,
              acceptClaimedAsSuccess: acceptClaimedAsSuccess,
              deadline: deadline,
            );
          }
          return;
        }

        // Queued / Failed / Expired / Cancelled / không rõ → chắc chắn chưa ra giấy.
        _invokeHangCallback(jobId);
      }());
    });
  }

  void _invokeHangCallback(String jobId) {
    final watch = _hangCallbacks.remove(jobId);
    if (watch == null) return;
    final onHang = watch.onHang;
    if (onHang == null) {
      _notifyHangWithoutQueue(watch);
      return;
    }
    onHang(
      jobId: jobId,
      documentType: watch.documentType,
      printerId: watch.printerId,
      printerName: watch.printerName,
      referenceNo: watch.referenceNo,
    );
  }

  /// Caller không có hàng chờ riêng: ít nhất phải nói cho thu ngân biết tờ giấy
  /// đó chưa ra, kèm tên máy in để còn kiểm tra hoặc in lại.
  void _notifyHangWithoutQueue(_HangWatch watch) {
    final ref = watch.referenceNo?.trim() ?? '';
    NotificationOverlayManager().showError(
      title: '${_documentLabel(watch.documentType)} chưa in',
      message: ref.isEmpty
          ? 'Máy ${watch.printerName} không phản hồi — kiểm tra máy in rồi in lại'
          : '$ref → ${watch.printerName} không phản hồi — in lại nếu cần',
      relatedEntityType: kPosPrintNotifyKind,
    );
  }

  static String _documentLabel(String documentType) => switch (documentType) {
        'SaleInvoice' => 'Hóa đơn',
        'SaleReturn' => 'Phiếu trả',
        'KitchenSlip' => 'Phiếu bếp',
        'KitchenVoid' => 'Phiếu hủy bếp',
        'KitchenLabel' => 'Tem',
        'BarcodeLabel' => 'Tem mã vạch',
        'StockIssue' => 'Phiếu kho',
        _ => 'Chứng từ',
      };

  void _finishJob(String jobId, _JobOutcome outcome, {bool showFeedback = true}) {
    _hangTimers.remove(jobId)?.cancel();
    // Thành công / Cancelled: bỏ treo. Failed/Expired: gọi onHang (fire-and-forget
    // trước đây cancel hang → mất phiếu treo dù job đã Failed).
    if (outcome.ok || outcome.isCancelled) {
      _hangCallbacks.remove(jobId);
    } else {
      _invokeHangCallback(jobId);
    }
    final completer = _pendingJobs[jobId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(outcome);
    }
    _pendingJobs.remove(jobId);
    _acceptClaimedByJob.remove(jobId);
    _showFeedbackByJob.remove(jobId);
    final queueExpired = _isQueueExpiredError(outcome.error);
    if (_feedbackSent.contains(jobId)) {
      _jobMeta.remove(jobId);
      return;
    }
    if (!showFeedback && !queueExpired) {
      _jobMeta.remove(jobId);
      return;
    }
    _feedbackSent.add(jobId);
    _jobMeta.remove(jobId);

    if (outcome.ok) {
      final name = outcome.printerName?.trim() ?? '';
      NotificationOverlayManager().showSuccess(
        title: 'In thành công',
        message: name.isNotEmpty ? name : 'Đã in xong trên Print Agent',
        relatedEntityType: kPosPrintNotifyKind,
      );
      return;
    }
    if (outcome.isCancelled && !queueExpired) {
      return;
    }
    NotificationOverlayManager().showError(
      title: queueExpired ? 'Phiếu in chưa ra giấy' : 'In thất bại',
      message: outcome.error ?? 'Không in được chứng từ',
      relatedEntityType: kPosPrintNotifyKind,
    );
  }

  static bool _isQueueExpiredError(String? error) {
    final e = (error ?? '').toLowerCase();
    return e.contains('quá hạn hàng đợi') ||
        e.contains('stale_queued') ||
        e.contains('offline quá 5') ||
        e.contains('stuck_no_requeue') ||
        e.contains('max_attempts');
  }

  void _onJobStatus(Map<String, dynamic> data) {
    final jobId = data['jobId']?.toString() ?? data['id']?.toString() ?? '';
    if (jobId.isEmpty) return;
    if (!_pendingJobs.containsKey(jobId)) return;

    final status = data['status']?.toString() ?? '';
    final printerName = data['printerName']?.toString() ?? '';
    final error = data['errorMessage']?.toString();
    final errorCode = data['errorCode']?.toString();
    final acceptClaimed = _acceptClaimedByJob[jobId] ?? true;
    final showFeedback = _showFeedbackByJob[jobId] ?? true;

    // Agent nhả job (Queued lại) — tiếp tục chờ, không báo thất bại.
    if (status == 'Queued') return;

    if (status == 'Completed' ||
        (acceptClaimed && (status == 'Claimed' || status == 'Printing'))) {
      // Claimed/Printing chỉ OK khi caller cho phép (hóa đơn thường).
      // Phiếu bếp: bắt Completed — tránh báo thành công rồi Agent fail → sót bếp.
      _finishJob(
        jobId,
        _JobOutcome(true, null, printerName: printerName),
        showFeedback: showFeedback,
      );
    } else if (status == 'Cancelled') {
      // Cancelled = server-side cancel (operator / idempotency / replaced).
      // Không đưa vào pending queue — không báo thất bại giả.
      // Trừ hủy vì Agent treo / hết hạn hàng đợi: giấy KHÔNG ra mà im lặng thì
      // bếp mất món. Coi như thất bại để thu ngân thấy phiếu chờ và in lại.
      if (_isNothingPrintedCancel(errorCode)) {
        _finishJob(
          jobId,
          _JobOutcome(
            false,
            'Phiếu chưa in — máy in/Agent offline quá 5 phút. In lại từ hàng chờ.',
            printerName: printerName,
          ),
          showFeedback: true,
        );
        return;
      }
      _cancelledJobs.add(jobId);
      _finishJob(
        jobId,
        _JobOutcome(false, error ?? 'Lệnh in đã bị hủy phía máy chủ',
            printerName: printerName, isCancelled: true),
        showFeedback: showFeedback,
      );
    } else if (status == 'Failed' || status == 'Expired') {
      _finishJob(
        jobId,
        _JobOutcome(false, error ?? 'In thất bại', printerName: printerName),
        showFeedback: showFeedback,
      );
    }
  }

  /// Hủy do server dọn hàng đợi — chắc chắn chưa có giấy nào ra.
  static bool _isNothingPrintedCancel(String? errorCode) {
    final code = (errorCode ?? '').toUpperCase();
    return code == 'STUCK_NO_REQUEUE' ||
        code == 'STALE_QUEUED' ||
        code == 'MAX_ATTEMPTS';
  }

  /// True if the job was cancelled server-side (operator / idempotency / replaced).
  bool isServerCancelled(String jobId) => _cancelledJobs.contains(jobId);

  /// Remove a jobId from the cancelled set (used when re-dispatching a new job).
  void clearServerCancelled(String jobId) => _cancelledJobs.remove(jobId);

  Future<void> invalidateCache() async {
    _cacheAt = null;
    _printers = [];
    _routes = [];
  }

  Future<bool> refreshConfig({bool force = false}) async {
    if (!force &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < _cacheTtl &&
        _printers.isNotEmpty) {
      return true;
    }
    try {
      final printersRes = await _api.getPosStorePrinters();
      if (printersRes['isSuccess'] != true) return false;
      final routesRes = await _api.getPosPrinterRoutes();
      _printers = (printersRes['data'] as List? ?? [])
          .map((e) => PosStorePrinter.fromJson(e as Map<String, dynamic>))
          .where((p) => p.isActive)
          .toList();
      _routes = (routesRes['data'] as List? ?? [])
          .map((e) => PosPrinterRoute.fromJson(e as Map<String, dynamic>))
          .toList();
      _cacheAt = DateTime.now();
      return _printers.isNotEmpty;
    } catch (e) {
      debugPrint('PosPrintOrchestrator.refreshConfig: $e');
      return false;
    }
  }

  List<PosStorePrinter> get printers => List.unmodifiable(_printers);

  /// Đánh dấu outbound chỉ khi máy này KHÔNG phải Agent của [printerId].
  /// A6 vừa gửi vừa Agent: mark → OUTBOUND_SKIP → không ra giấy.
  Future<void> _registerCloudJobForAgent({
    required String jobId,
    required String printerId,
  }) async {
    if (jobId.isEmpty) return;
    final selfAgent =
        !kIsWeb && await PosPrintRole.isAgentForPrinter(printerId);
    if (!selfAgent) {
      PosPrintSessionRegistry.markOutbound(jobId);
    }
    PosPrintAgentService.instance.nudgeClaim();
  }

  /// Đổi máy device-local → bản cloud/Agent cùng cổng (USB/LAN/BT/Sunmi).
  /// Job gửi ID nội bộ sẽ không được Agent claim.
  PosStorePrinter preferCloudAgentPrinter(PosStorePrinter printer) {
    if (!printer.isDeviceLocal) return printer;
    final cloud = _printers
        .where((p) =>
            !p.isDeviceLocal &&
            p.isActive &&
            p.connectionType.toLowerCase() ==
                printer.connectionType.toLowerCase())
        .toList();
    PosStorePrinter? twin;
    if (printer.isUsb) {
      final usb = _normPort(printer.usbDeviceName);
      if (usb.isNotEmpty) {
        for (final p in cloud) {
          final o = _normPort(p.usbDeviceName);
          if (o.isNotEmpty &&
              (o == usb || o.startsWith(usb) || usb.startsWith(o))) {
            twin = p;
            break;
          }
        }
      }
      if (twin == null) {
        final want = _stripLocalName(printer.name);
        for (final p in cloud) {
          if (_stripLocalName(p.name) == want) {
            twin = p;
            break;
          }
        }
      }
    } else if (printer.isLan) {
      final host = (printer.lanHost ?? '').trim().toLowerCase();
      if (host.isNotEmpty) {
        for (final p in cloud) {
          if ((p.lanHost ?? '').trim().toLowerCase() == host) {
            twin = p;
            break;
          }
        }
      }
      if (twin == null) {
        final want = _stripLocalName(printer.name);
        for (final p in cloud) {
          if (_stripLocalName(p.name) == want) {
            twin = p;
            break;
          }
        }
      }
    } else if (printer.isBluetooth) {
      final bt = (printer.bluetoothAddress ?? '').trim().toLowerCase();
      if (bt.isNotEmpty) {
        for (final p in cloud) {
          if ((p.bluetoothAddress ?? '').trim().toLowerCase() == bt) {
            twin = p;
            break;
          }
        }
      }
    } else if (printer.isSunmi) {
      // Chỉ map sang twin Sunmi cùng tên — không lấy máy Agent/LAN bất kỳ.
      final want = _stripLocalName(printer.name);
      final sunmiCloud = cloud.where((p) => p.isSunmi).toList();
      for (final p in sunmiCloud) {
        if (_stripLocalName(p.name) == want) {
          twin = p;
          break;
        }
      }
      twin ??= sunmiCloud.length == 1 ? sunmiCloud.first : null;
    }
    if (twin != null) {
      debugPrint(
        'Print remap device-local ${printer.id} → cloud ${twin.id} (${twin.name})',
      );
      return twin;
    }
    return printer;
  }

  PosStorePrinter? printerById(String? id) {
    final want = (id ?? '').trim().toLowerCase();
    if (want.isEmpty) return null;
    final p = _printers.where((x) => x.id.toLowerCase() == want).firstOrNull;
    return p == null ? null : preferCloudAgentPrinter(p);
  }

  static String _normPort(String? raw) {
    var t = (raw ?? '').trim();
    final pipe = t.indexOf('|');
    if (pipe > 0) t = t.substring(0, pipe);
    return t.toLowerCase();
  }

  static String _stripLocalName(String name) {
    var n = name.trim();
    if (n.toLowerCase().startsWith('[nội bộ]')) {
      n = n.substring('[nội bộ]'.length).trim();
    }
    return n.toLowerCase();
  }

  PosStorePrinter? resolvePrinter(String documentType) {
    final list = resolvePrinters(documentType);
    return list.isEmpty ? null : list.first;
  }

  /// Tất cả máy in gán cho loại chứng từ (in đa máy).
  /// Không fallback máy mặc định / máy duy nhất — tránh hóa đơn nhận báo bếp.
  List<PosStorePrinter> resolvePrinters(String documentType) {
    if (_printers.isEmpty) return const [];

    final routed = _routes
        .where((r) => r.documentType == documentType)
        .map((r) => _printers.where((p) => p.id == r.printerId).firstOrNull)
        .whereType<PosStorePrinter>()
        .toList();
    final raw = routed.isNotEmpty
        ? routed
        : _printers
            .where((p) => p.documentTypes.contains(documentType))
            .toList();
    final remapped = [for (final p in raw) preferCloudAgentPrinter(p)];
    final unique = _dedupePrintersById(remapped);
    unique.sort((a, b) {
      final al = a.isDeviceLocal ? 1 : 0;
      final bl = b.isDeviceLocal ? 1 : 0;
      return al.compareTo(bl);
    });
    // Hóa đơn: chỉ 1 máy (tránh 2 bản ghi «sunmi» cùng SaleInvoice → in 2 liên).
    if (documentType == PosCloudDocumentTypes.saleInvoice &&
        unique.length > 1) {
      final defaults = unique.where((p) => p.isDefault).toList();
      if (defaults.isNotEmpty) return [defaults.first];
      debugPrint(
        'SaleInvoice: ${unique.length} máy → chỉ in «${unique.first.name}» '
        '(${unique.first.id})',
      );
      return [unique.first];
    }
    return unique;
  }

  List<PosStorePrinter> _dedupePrintersById(List<PosStorePrinter> list) {
    final seen = <String>{};
    final out = <PosStorePrinter>[];
    for (final p in list) {
      final id = p.id.trim().toLowerCase();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(p);
    }
    return out;
  }

  int copiesFor(String documentType, {String? printerId, int fallback = 1}) {
    if (printerId != null && printerId.isNotEmpty) {
      final perPrinter = _routes
          .where((r) =>
              r.documentType == documentType && r.printerId == printerId)
          .firstOrNull;
      if (perPrinter != null) return perPrinter.defaultCopies;
    }
    final route =
        _routes.where((r) => r.documentType == documentType).firstOrNull;
    return route?.defaultCopies ?? fallback;
  }

  /// Gửi byte ESC/POS qua cloud (Máy in cửa hàng → Print Agent).
  ///
  /// [forceCloud]: bỏ qua in trực tiếp trên Agent — luôn enqueue cloud
  /// (dùng cho «Test in qua cloud» trên chính máy Sunmi).
  Future<bool> dispatchEscPos({
    required String documentType,
    required List<int> bytes,
    int copies = 1,
    String? referenceNo,
    String? referenceId,
    String? printerId,
    bool showFeedback = true,
    String? successTitle,
    bool waitForCompletion = true,
    bool skipDedup = false,
    bool forceCloud = false,
    bool acceptClaimedAsSuccess = true,
    PosPrintHangCallback? onHang,
    Duration hangAfter = hangAfterDefault,
  }) async {
    if (!skipDedup &&
        PosPrintDedup.shouldSkip(
          documentType: documentType,
          referenceId: referenceId,
          referenceNo: referenceNo,
          printerId: printerId,
        )) {
      debugPrint(
        'Kitchen DBG dispatchEscPos: SKIPPED by dedup doc=$documentType ref=$referenceNo printerId=$printerId',
      );
      if (showFeedback) _notifyPrintDedupSkip();
      return true;
    }

    await ensureListening();
    final hasCloud = await refreshConfig();
    PosStorePrinter? printer = printerId != null
        ? _printers.where((p) => p.id == printerId).firstOrNull
        : null;
    printer ??= resolvePrinter(documentType);
    debugPrint(
      'Kitchen DBG dispatchEscPos: doc=$documentType printerId=$printerId '
      'resolvedPrinter=${printer?.name} hasCloud=$hasCloud forceCloud=$forceCloud',
    );

    if (printer != null) {
      final n = copies.clamp(1, 10);

      // Có cổng thật trên máy này → in local (không cần bật Agent).
      // A7/web không cắm máy → false → cloud cho Agent.
      if (!kIsWeb &&
          !forceCloud &&
          await _canDispatchLocallyNow(printer)) {
        return _printDirectOnStorePrinter(
          printer: printer,
          bytes: bytes,
          copies: n,
          referenceNo: referenceNo,
          showFeedback: showFeedback,
          successTitle: successTitle,
        );
      }

      if (!hasCloud) {
        debugPrint('Kitchen DBG dispatchEscPos: ABORT — hasCloud=false');
        return false;
      }

      // Test qua cloud trên chính máy Agent (Zywell USB/LAN/BT): pause claim
      // NGAY trước khi tạo job — tránh SignalR/timer claim job này song song
      // với nhánh in nội bộ bên dưới (in ra 2 bản cùng lúc).
      final localTestOnAgent = forceCloud &&
          !kIsWeb &&
          await PosPrintRole.isAgentForPrinter(printer.id) &&
          await _canDispatchLocallyNow(printer);
      if (localTestOnAgent) {
        PosPrintAgentService.instance.pauseClaims();
      }

      final payload = base64Encode(bytes);
      final res = await _api.createPosPrintJob(
        documentType: documentType,
        payloadFormat: 'EscPosBase64',
        payload: payload,
        copies: n,
        referenceNo: referenceNo,
        referenceId: referenceId,
        printerId: printer.id,
      );
      debugPrint('Kitchen DBG dispatchEscPos: createPosPrintJob res=$res');
      if (res['isSuccess'] != true) {
        if (localTestOnAgent) PosPrintAgentService.instance.resumeClaims();
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'Không gửi lệnh in',
            message: res['message']?.toString() ?? 'Lỗi máy chủ',
            relatedEntityType: kPosPrintNotifyKind,
          );
        }
        return false;
      }

      final data = res['data'] as Map<String, dynamic>?;
      final jobId = data?['jobId']?.toString() ?? '';
      if (jobId.isEmpty) {
        if (localTestOnAgent) PosPrintAgentService.instance.resumeClaims();
        return false;
      }

      // Fail nhanh khi chắc chắn không có Agent nào online cho máy in này —
      // tránh báo "Đã gửi lệnh in" giả khi job sẽ nằm hàng đợi rồi tự hủy
      // sau 20 phút mà không ai biết (trang lưu hóa đơn "in không ra").
      if (_failFastNoAgent(printer, data, jobId, showFeedback: showFeedback)) {
        if (localTestOnAgent) PosPrintAgentService.instance.resumeClaims();
        return false;
      }

      if (localTestOnAgent) {
        return _completeEscPosCloudTestOnLocalAgent(
          jobId: jobId,
          printer: printer,
          bytes: bytes,
          copies: n,
          showFeedback: showFeedback,
          successTitle: successTitle,
        );
      }

      // A6 vừa gửi vừa Agent: không mark outbound (OUTBOUND_SKIP).
      await _registerCloudJobForAgent(jobId: jobId, printerId: printer.id);

      _jobMeta[jobId] = _JobFeedbackMeta(
        referenceNo: referenceNo,
        printerName: printer.name,
      );

      if (showFeedback) {
        final ref = referenceNo?.trim() ?? '';
        NotificationOverlayManager().show(
          title: 'Đã gửi lệnh in',
          message: ref.isNotEmpty
              ? 'Đơn $ref → ${printer.name}'
              : 'Đã gửi tới Print Agent (${printer.name})',
          type: NotificationType.success,
          duration: const Duration(seconds: 3),
          relatedEntityType: kPosPrintNotifyKind,
        );
      }

      if (!waitForCompletion) {
        _armHangWatch(
          jobId: jobId,
          documentType: documentType,
          printer: printer,
          referenceNo: referenceNo,
          acceptClaimedAsSuccess: acceptClaimedAsSuccess,
          hangAfter: hangAfter,
          onHang: onHang,
        );
        // Không chặn UI. Không toast lỗi nền — trước đây showFeedback:true khiến
        // báo «In thất bại» dù Agent đã in (race reclaim/DUP/timeout sau giấy ra).
        unawaited(
          _waitJob(
            jobId,
            showFeedback: false,
            acceptClaimedAsSuccess: acceptClaimedAsSuccess,
          ).whenComplete(
            () => PosPrintSessionRegistry.clearOutbound(jobId),
          ),
        );
        return true;
      }

      final outcome = await _waitJob(
        jobId,
        showFeedback: showFeedback,
        acceptClaimedAsSuccess: acceptClaimedAsSuccess,
      );
      PosPrintSessionRegistry.clearOutbound(jobId);
      return outcome.ok;
    }

    return false;
  }

  /// In cùng lúc lên mọi máy in được gán cho [documentType].
  Future<bool> dispatchEscPosToAll({
    required String documentType,
    required Future<List<int>> Function(PosStorePrinter printer) buildBytes,
    int copies = 1,
    String? referenceNo,
    String? referenceId,
    bool showFeedback = true,
    String? successTitle,
    bool skipDedup = false,
  }) async {
    if (!skipDedup &&
        PosPrintDedup.shouldSkip(
          documentType: documentType,
          referenceId: referenceId,
          referenceNo: referenceNo,
        )) {
      if (showFeedback) _notifyPrintDedupSkip();
      return true;
    }

    await ensureListening();
    await refreshConfig();
    final printers = resolvePrinters(documentType);
    if (printers.isEmpty) return false;

    var okCount = 0;
    var failCount = 0;
    final okNames = <String>[];

    for (final printer in printers) {
      try {
        final bytes = await buildBytes(printer);
        final n =
            copiesFor(documentType, printerId: printer.id, fallback: copies);
        final isAgent =
            !kIsWeb && await PosPrintRole.isAgentForPrinter(printer.id);
        final ok = await dispatchEscPos(
          documentType: documentType,
          bytes: bytes,
          copies: n,
          referenceNo: referenceNo,
          referenceId: referenceId,
          printerId: printer.id,
          showFeedback: false,
          successTitle: successTitle,
          waitForCompletion: isAgent ||
              (!kIsWeb && await _canDispatchLocallyNow(printer)),
          acceptClaimedAsSuccess: false,
          skipDedup: true,
        );
        if (ok) {
          okCount++;
          okNames.add(printer.name);
        } else {
          failCount++;
        }
      } catch (e, st) {
        failCount++;
        debugPrint('dispatchEscPosToAll ${printer.name}: $e\n$st');
      }
    }

    if (showFeedback) {
      final ref = referenceNo?.trim() ?? '';
      if (okCount > 0) {
        final names = okNames.join(', ');
        NotificationOverlayManager().show(
          title: okCount > 1 ? 'Đã gửi lệnh in ($okCount máy)' : 'Đã gửi lệnh in',
          message: ref.isNotEmpty ? 'Đơn $ref → $names' : names,
          type: NotificationType.success,
          duration: const Duration(seconds: 4),
        );
      }
      if (failCount > 0) {
        NotificationOverlayManager().showError(
          title: 'In thất bại',
          message: failCount == printers.length
              ? 'Không in được trên máy in đã chọn'
              : '$failCount/${printers.length} máy in không in được',
        );
      }
    }

    return okCount > 0;
  }

  /// In hóa đơn qua cloud — Sunmi dùng native (giống máy in nội bộ), máy khác ESC/POS.
  Future<bool> dispatchSaleOrder({
    required PosSaleOrder order,
    required Future<List<int>> Function(PosStorePrinter printer) buildEscPos,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    bool mergeSameItems = true,
    String? documentTitle,
    int copies = 1,
    String? referenceNo,
    String? referenceId,
    bool showFeedback = true,
    String? successTitle,
    bool skipDedup = false,
    /// In lại chọn máy — chỉ gửi đúng máy này (bỏ route mặc định).
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
    PosPrintHangCallback? onHang,
    Duration hangAfter = hangAfterDefault,
    bool? vatIncludedInPrice,
  }) async {
    if (!skipDedup &&
        PosPrintDedup.shouldSkip(
          documentType: PosCloudDocumentTypes.saleInvoice,
          referenceId: referenceId,
          referenceNo: referenceNo,
          printerId: overridePrinter?.id ?? overridePrinterId,
        )) {
      if (showFeedback) _notifyPrintDedupSkip();
      return true;
    }

    await ensureListening();
    await refreshConfig();
    List<PosStorePrinter> printers;
    if (overridePrinter != null) {
      printers = [overridePrinter];
    } else if ((overridePrinterId ?? '').trim().isNotEmpty) {
      final want = overridePrinterId!.trim().toLowerCase();
      final hit = _printers
          .where((p) => p.id.toLowerCase() == want)
          .firstOrNull;
      printers = hit != null ? [hit] : const [];
    } else {
      printers = resolvePrinters(PosCloudDocumentTypes.saleInvoice);
      // Sau TT: 1 máy đủ — tránh Sunmi + USB cùng role → lúc 1 lúc 2 bill.
      if (printers.length > 1) {
        final defaults = printers.where((p) => p.isDefault).toList();
        printers = [defaults.isNotEmpty ? defaults.first : printers.first];
      }
    }
    if (printers.isEmpty) return false;

    var okCount = 0;
    var failCount = 0;
    final okNames = <String>[];

    for (final printer in printers) {
      try {
        final routeN = copiesFor(
          PosCloudDocumentTypes.saleInvoice,
          printerId: printer.id,
          fallback: copies,
        );
        // Tránh in 2 lần: settings copies=1 nhưng route defaultCopies=2 (hoặc ngược).
        final n = (routeN < copies ? routeN : copies).clamp(1, 10);
        // Web: luôn enqueue cloud (Agent Android nhận in). Không native/local.
        final onSunmiHw =
            !kIsWeb && await PosPrinterTransport.isSunmiDevice();
        final canLocal = !kIsWeb && await _canDispatchLocallyNow(printer);

        bool ok;
        if (printer.isSunmi && onSunmiHw && canLocal) {
          ok = await _printSaleNativeOnThisDevice(
            printer: printer,
            order: order,
            copies: n,
            storeName: storeName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            mergeSameItems: mergeSameItems,
            documentTitle: documentTitle,
            referenceNo: referenceNo,
            showFeedback: false,
            successTitle: successTitle,
          );
        } else if (printer.isSunmi) {
          // A7/web → Agent Sunmi: JSON native. EscPosBase64 bị Agent từ chối
          // (UNSUPPORTED_ON_SUNMI) — máy «nhận lệnh» nhưng không ra giấy.
          ok = await _enqueueSaleOrderJson(
            printer: printer,
            order: order,
            copies: n,
            storeName: storeName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            mergeSameItems: mergeSameItems,
            documentTitle: documentTitle,
            referenceNo: referenceNo,
            referenceId: referenceId,
            showFeedback: false,
            waitForCompletion: true,
            onHang: onHang,
            hangAfter: hangAfter,
            vatIncludedInPrice: vatIncludedInPrice,
          );
        } else {
          final bytes = await buildEscPos(printer);
          ok = await dispatchEscPos(
            documentType: PosCloudDocumentTypes.saleInvoice,
            bytes: bytes,
            copies: n,
            referenceNo: referenceNo,
            referenceId: referenceId,
            printerId: printer.id,
            showFeedback: false,
            successTitle: successTitle,
            waitForCompletion: canLocal,
            skipDedup: true,
            onHang: onHang,
            hangAfter: hangAfter,
          );
        }

        if (ok) {
          okCount++;
          okNames.add(printer.name);
        } else {
          failCount++;
        }
      } catch (e, st) {
        failCount++;
        debugPrint('dispatchSaleOrder ${printer.name}: $e\n$st');
      }
    }

    if (showFeedback) {
      final ref = referenceNo?.trim() ?? '';
      if (okCount > 0) {
        final names = okNames.join(', ');
        NotificationOverlayManager().show(
          title: okCount > 1 ? 'Đã gửi lệnh in ($okCount máy)' : 'Đã gửi lệnh in',
          message: ref.isNotEmpty ? 'Đơn $ref → $names' : names,
          type: NotificationType.success,
          duration: const Duration(seconds: 3),
          relatedEntityType: kPosPrintNotifyKind,
        );
      }
      if (failCount > 0) {
        NotificationOverlayManager().showError(
          title: 'In thất bại',
          message: failCount == printers.length
              ? 'Không in được trên máy in đã chọn'
              : '$failCount/${printers.length} máy in không in được',
          relatedEntityType: kPosPrintNotifyKind,
        );
      }
    }

    return okCount > 0;
  }

  Future<bool> _printSaleNativeOnThisDevice({
    required PosStorePrinter printer,
    required PosSaleOrder order,
    required int copies,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    bool mergeSameItems = true,
    String? documentTitle,
    String? referenceNo,
    bool showFeedback = true,
    String? successTitle,
  }) async {
    final settings = toThermalSettings(printer);
    final ref = referenceNo?.trim() ?? '';
    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'Đã nhận lệnh in',
        message: ref.isNotEmpty
            ? 'Đơn $ref — đang in trên ${printer.name}…'
            : 'Đang in trên ${printer.name}…',
        duration: const Duration(seconds: 4),
      );
    }

    var ok = true;
    final template = await resolvePosPrintTemplate(
      documentType: PosPrintDocumentTypes.saleInvoice,
    );
    final v2 = PosPrintTemplateRuntime.resolveOrPreset(
      template: template,
      documentType: PosPrintDocumentTypes.saleInvoice,
      paperSize: template?.paperSize ??
          (settings.paperWidthMm <= 58
              ? PosPrintPaperSizes.k58
              : PosPrintPaperSizes.k80),
      printerProfile: settings.paperWidthMm <= 58
          ? PosPrintPrinterProfiles.sunmiK58
          : PosPrintPrinterProfiles.sunmiK80,
    );
    for (var i = 0; i < copies.clamp(1, 10); i++) {
      final output = PosPrintTemplateRuntime.compileSaleOrder(
        template: v2,
        order: order,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        mergeSameItems: mergeSameItems,
        titleOverride: documentTitle,
      );
      final sent = await PosPrintTemplateRuntime.printCompiledSunmi(
        output: output,
        settings: settings,
        copies: 1,
      );
      if (!sent) {
        ok = false;
        break;
      }
    }

    if (ok) {
      unawaited(_api.reportPosPrinterHealth(printer.id, status: 'Online'));
      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'In xong',
          message: ref.isNotEmpty ? 'Đơn $ref — ${printer.name}' : printer.name,
        );
      }
      return true;
    }
    unawaited(_api.reportPosPrinterHealth(
      printer.id,
      status: 'Offline',
      errorMessage: 'Sunmi native print failed',
    ));
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'In thất bại',
        message: tr('Không in được trên ${printer.name}'),
      );
    }
    return false;
  }

  Future<bool> _enqueueSaleOrderJson({
    required PosStorePrinter printer,
    required PosSaleOrder order,
    required int copies,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    bool mergeSameItems = true,
    String? documentTitle,
    String? referenceNo,
    String? referenceId,
    bool showFeedback = true,
    bool waitForCompletion = true,
    PosPrintHangCallback? onHang,
    Duration hangAfter = hangAfterDefault,
    bool? vatIncludedInPrice,
  }) async {
    // Gửi kèm full order — Agent in native giống Oppo, không phụ thuộc getPosSale.
    final included = vatIncludedInPrice ??
        (await PosSellStoreSettings.load()).taxMode ==
            PosSellTaxMode.includedInPrice;
    final payload = jsonEncode({
      'orderId': order.id,
      'order': order.toPrintAgentJson(),
      'storeName': storeName,
      'storeAddress': storeAddress,
      'storePhone': storePhone,
      'mergeSameItems': mergeSameItems,
      'documentTitle': documentTitle,
      'vatIncludedInPrice': included,
    });
    final res = await _api.createPosPrintJob(
      documentType: PosCloudDocumentTypes.saleInvoice,
      payloadFormat: 'SaleOrderJson',
      payload: payload,
      copies: copies.clamp(1, 10),
      referenceNo: referenceNo,
      referenceId: referenceId ?? order.id,
      printerId: printer.id,
    );
    if (res['isSuccess'] != true) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không gửi lệnh in',
          message: res['message']?.toString() ?? 'Lỗi máy chủ',
          relatedEntityType: kPosPrintNotifyKind,
        );
      }
      return false;
    }
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return false;

    if (_failFastNoAgent(printer, data, jobId, showFeedback: showFeedback)) {
      return false;
    }

    await _registerCloudJobForAgent(jobId: jobId, printerId: printer.id);
    if (showFeedback) {
      final ref = referenceNo?.trim() ?? '';
      NotificationOverlayManager().show(
        title: 'Đã gửi lệnh in',
        message: ref.isNotEmpty
            ? 'Đơn $ref → ${printer.name}'
            : 'Đã gửi tới Print Agent (${printer.name})',
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
        relatedEntityType: kPosPrintNotifyKind,
      );
    }
    if (!waitForCompletion) {
      _armHangWatch(
        jobId: jobId,
        documentType: PosCloudDocumentTypes.saleInvoice,
        printer: printer,
        referenceNo: referenceNo,
        acceptClaimedAsSuccess: false,
        hangAfter: hangAfter,
        onHang: onHang,
      );
      unawaited(
        _waitJob(
          jobId,
          showFeedback: false,
          acceptClaimedAsSuccess: false,
        ).whenComplete(
          () => PosPrintSessionRegistry.clearOutbound(jobId),
        ),
      );
      return true;
    }
    final outcome = await _waitJob(
      jobId,
      showFeedback: showFeedback,
      acceptClaimedAsSuccess: false,
    );
    PosPrintSessionRegistry.clearOutbound(jobId);
    return outcome.ok;
  }

  /// Không hủy job khi heartbeat Agent «lệch» — demopos tái hiện:
  /// `agentOnlineForPrinter=0` nhưng Agent vẫn Claim + in trong vài giây.
  /// Fail-fast cũ → UI «Đã báo bếp — chưa in phiếu» dù giấy đã ra.
  bool _failFastNoAgent(
    PosStorePrinter printer,
    Map<String, dynamic>? data,
    String jobId, {
    bool showFeedback = true,
  }) {
    final agentsOnline = data?['agentOnlineForPrinter'];
    if (!printer.requiresAgent ||
        agentsOnline is! num ||
        agentsOnline.toInt() > 0) {
      return false;
    }
    // Chỉ cảnh báo mềm — vẫn chờ Claimed/Printing/Completed.
    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'Đang chờ Print Agent…',
        message: tr(
            '${printer.name}: chưa thấy heartbeat tươi — vẫn gửi lệnh, mở app Agent nếu lâu không in.'),
        duration: const Duration(seconds: 4),
        relatedEntityType: kPosPrintNotifyKind,
      );
    }
    return false;
  }

  /// Phiếu xuất kho / báo chế biến kho → Agent Sunmi native (không ESC/POS).
  Future<bool> enqueueWarehouseSlipJson({
    required PosStorePrinter printer,
    required PosSaleOrder order,
    required List<PosSaleOrderLine> lines,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    String? slipTitle,
    bool showFeedback = false,
    bool waitForCompletion = true,
  }) async {
    final payload = jsonEncode({
      'orderId': order.id,
      'order': order.toPrintAgentJson(),
      'linesOverride': lines.map((l) => l.toPrintAgentJson()).toList(),
      'warehouseSlip': true,
      'slipTitle': slipTitle,
      'documentTitle': slipTitle,
      'storeName': storeName,
      'storeAddress': storeAddress,
      'storePhone': storePhone,
      'mergeSameItems': false,
    });
    final res = await _api.createPosPrintJob(
      documentType: PosCloudDocumentTypes.stockIssue,
      payloadFormat: 'SaleOrderJson',
      payload: payload,
      copies: 1,
      referenceNo: order.orderNo.isEmpty ? null : order.orderNo,
      referenceId: order.id.isEmpty ? null : order.id,
      printerId: printer.id,
    );
    if (res['isSuccess'] != true) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không gửi phiếu kho',
          message: res['message']?.toString() ?? 'Lỗi máy chủ',
        );
      }
      return false;
    }
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return false;

    if (_failFastNoAgent(printer, data, jobId, showFeedback: showFeedback)) {
      return false;
    }

    await _registerCloudJobForAgent(jobId: jobId, printerId: printer.id);
    if (!waitForCompletion) {
      _armHangWatch(
        jobId: jobId,
        documentType: PosCloudDocumentTypes.stockIssue,
        printer: printer,
        referenceNo: order.orderNo.isEmpty ? null : order.orderNo,
        acceptClaimedAsSuccess: false,
      );
      unawaited(
        _waitJob(
          jobId,
          showFeedback: false,
          acceptClaimedAsSuccess: false,
        ).whenComplete(
          () => PosPrintSessionRegistry.clearOutbound(jobId),
        ),
      );
      return true;
    }
    final outcome = await _waitJob(
      jobId,
      showFeedback: showFeedback,
      acceptClaimedAsSuccess: false,
    );
    PosPrintSessionRegistry.clearOutbound(jobId);
    return outcome.ok;
  }

  /// In phiếu báo chế biến / hủy — Sunmi dùng native (UTF-8), máy khác ESC/POS.
  ///
  /// [preferDirectPrint]: in lại / chọn máy — ưu tiên in thẳng trên thiết bị này
  /// (không bắt buộc Agent đã gán máy), rồi mới fallback cloud.
  Future<bool> dispatchKitchenSlip({
    required PosStorePrinter printer,
    required String tableName,
    required bool isCancel,
    required List<({
      String productName,
      double qty,
      String? unitName,
      String? note,
    })> lines,
    required String senderName,
    required DateTime sentAt,
    String? orderNo,
    String? referenceNo,
    bool showFeedback = false,
    String? successTitle,
    bool skipDedup = false,
    bool waitForCompletion = true,
    bool preferDirectPrint = false,
    /// A7 / máy thu ngân: luôn enqueue cloud (không thử USB/LAN local).
    bool forceCloud = false,
    PosPrintHangCallback? onHang,
    Duration hangAfter = hangAfterDefault,
  }) async {
    if (lines.isEmpty) return false;

    if (printer.cutPerItem && lines.length > 1) {
      var ok = true;
      for (var i = 0; i < lines.length; i++) {
        final one = await dispatchKitchenSlip(
          printer: printer,
          tableName: tableName,
          isCancel: isCancel,
          lines: [lines[i]],
          senderName: senderName,
          sentAt: sentAt,
          orderNo: orderNo,
          referenceNo: _kdsCutRef(referenceNo ?? orderNo, i, lines[i].productName),
          showFeedback: false,
          successTitle: successTitle,
          skipDedup: true,
          waitForCompletion: waitForCompletion,
          preferDirectPrint: preferDirectPrint,
          forceCloud: forceCloud,
          onHang: onHang,
          hangAfter: hangAfter,
        );
        ok = ok && one;
      }
      if (showFeedback) {
        if (ok) {
          NotificationOverlayManager().showSuccess(
            title: successTitle ?? (isCancel ? 'Hủy bếp' : 'Báo bếp'),
            message: '${printer.name} · ${lines.length} phiếu',
          );
        } else {
          NotificationOverlayManager().showError(
            title: 'In thất bại',
            message: tr('Không in hết món trên ${printer.name}'),
          );
        }
      }
      return ok;
    }

    if (!skipDedup &&
        PosPrintDedup.shouldSkip(
          documentType: isCancel
              ? PosCloudDocumentTypes.kitchenVoid
              : PosCloudDocumentTypes.kitchenSlip,
          referenceNo: referenceNo,
          printerId: printer.id,
        )) {
      // Báo bếp thường showFeedback=true; sau TT có thể false — vẫn cảnh báo
      // để user biết vì sao lần 2 không in.
      _notifyPrintDedupSkip();
      return true;
    }

    final isAgent =
        !kIsWeb && await PosPrintRole.isAgentForPrinter(printer.id);
    final onSunmiHw = !kIsWeb && await PosPrinterTransport.isSunmiDevice();
    final canLocal = !kIsWeb && await _canDispatchLocallyNow(printer);
    // Có cổng trên máy này → in local dù Agent tắt. forceCloud chỉ khi
    // «Test qua cloud» (máy khác in hộ). Không có cổng → JSON cho Agent.
    var effectiveForceCloud = forceCloud;
    var effectivePreferDirect = preferDirectPrint;
    if (canLocal && !forceCloud) {
      effectiveForceCloud = false;
      effectivePreferDirect = true;
    } else if (!canLocal) {
      effectiveForceCloud = true;
      effectivePreferDirect = false;
    }
    debugPrint(
      'Kitchen DBG dispatchKitchenSlip: printer=${printer.name} isSunmi=${printer.isSunmi} '
      'isAgent=$isAgent onSunmiHw=$onSunmiHw canLocal=$canLocal '
      'forceCloud=$effectiveForceCloud preferDirect=$effectivePreferDirect '
      'isDeviceLocal=${printer.isDeviceLocal}',
    );

    // Máy in trong Sunmi: chỉ khi đích thật sự là Sunmi VÀ không map sang
    // cổng USB/LAN (A6 hay gán nhầm chip sunmi → phiếu preset khác mẫu gốc).
    if (!effectiveForceCloud &&
        !kIsWeb &&
        printer.isSunmi &&
        onSunmiHw) {
      final role = isCancel
          ? PosLocalPrinterRoles.kitchenVoid
          : PosLocalPrinterRoles.kitchenSlip;
      final ownedLocal = await PosLocalPrintersStore.instance
          .resolveOnDeviceForStorePrinter(printer, documentRole: role);
      final localIsSunmi = ownedLocal == null ||
          ownedLocal.connectionType == PosThermalConnectionType.sunmi;
      if (localIsSunmi) {
        return _printKitchenNativeOnThisDevice(
          printer: printer,
          tableName: tableName,
          isCancel: isCancel,
          lines: lines,
          senderName: senderName,
          sentAt: sentAt,
          orderNo: orderNo,
          showFeedback: showFeedback,
          successTitle: successTitle,
        );
      }
      debugPrint(
        'Kitchen DBG: bỏ native Sunmi — ${printer.name} map cổng '
        '${ownedLocal!.connectionType} (${ownedLocal.name})',
      );
    }

    // In local trên thiết bị này (USB/BT/LAN nội bộ) khi không force cloud.
    // Cloud/Agent: luôn KitchenSlipJson — payload nhỏ; Agent tự dựng ESC/POS.
    // Trước đây A7 compile EscPos bitmap VN rồi gửi base64: 2+ món rất nặng →
    // Agent USB chậm/timeout → phiếu treo; hủy từng món (payload nhỏ) lại in được.
    if (!effectiveForceCloud && !kIsWeb) {
      final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
      final table = tableName.trim().isEmpty ? 'Bàn' : tableName.trim();
      final sender = senderName.trim().isEmpty ? 'admin' : senderName.trim();
      final code = (orderNo ?? '').trim().isEmpty ? '-' : orderNo!.trim();
      final kitchenDoc = isCancel
          ? PosCloudDocumentTypes.kitchenVoid
          : PosCloudDocumentTypes.kitchenSlip;
      final settings = toThermalSettings(printer).copyWith(
        openCashDrawer: false,
        compactCutFeed: true,
      );
      final tpl = await PosPrintConfigSession.instance
          .kitchenTemplate(isCancel: isCancel, force: true);
      final v2 = PosPrintTemplateRuntime.resolveOrPreset(
        template: tpl,
        documentType: isCancel
            ? PosPrintDocumentTypes.kitchenVoid
            : PosPrintDocumentTypes.kitchenSlip,
        paperSize: settings.paperSize,
        printerProfile: PosPrintPrinterProfiles.forPaperAndBrand(
          paperSize: settings.paperSize,
          isSunmi: printer.isSunmi ||
              settings.printerBrand == PosThermalPrinterBrand.sunmi,
          isZywell: settings.printerBrand == PosThermalPrinterBrand.zywell,
        ),
      );
      final output = PosPrintTemplateRuntime.compileKitchenSlip(
        template: v2,
        tableName: table,
        isCancel: isCancel,
        lines: [
          for (final l in lines)
            (
              name: l.productName,
              qty: qtyFmt.format(l.qty),
              unit: l.unitName,
              note: PosPrintTemplateRuntime.kitchenCallNote(l.note, sentAt),
            ),
        ],
        senderName: sender,
        orderNo: code == '-' ? '' : code,
        sentAt: sentAt,
      );
      final bytes = await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
        output: output,
        settings: settings,
      );
      final role = isCancel
          ? PosLocalPrinterRoles.kitchenVoid
          : PosLocalPrinterRoles.kitchenSlip;
      final ownedLocal = await PosLocalPrintersStore.instance
          .resolveOnDeviceForStorePrinter(printer, documentRole: role);
      if (ownedLocal != null) {
        final localOk = await dispatchLocalEscPos(
          bytes: bytes,
          showFeedback: showFeedback,
          successTitle: successTitle,
          settingsOverride: ownedLocal.toThermalSettings(),
          skipDedup: true,
          documentType: kitchenDoc,
          waitForCompletion: true,
        );
        if (localOk) return true;
        debugPrint(
          'Kitchen DBG: on-device local fail ${printer.name} — fallback cloud JSON',
        );
      } else if (effectivePreferDirect && canLocal) {
        final canPort = await _canDispatchLocallyNow(printer);
        if (canPort &&
            (printer.isUsb || printer.isBluetooth || printer.isSunmi)) {
          final ok = await dispatchLocalEscPos(
            bytes: bytes,
            showFeedback: showFeedback,
            successTitle: successTitle,
            settingsOverride: settings,
            skipDedup: true,
            documentType: kitchenDoc,
            waitForCompletion: true,
          );
          if (ok) return true;
          debugPrint(
            'Kitchen DBG: agent direct fail ${printer.name} — fallback cloud JSON',
          );
        }
      }
    }

    debugPrint(
      'Kitchen DBG: cloud KitchenSlipJson → ${printer.name} '
      '(${lines.length} món, forceCloud=$effectiveForceCloud)',
    );
    return _enqueueKitchenSlipJson(
      printer: printer,
      tableName: tableName,
      isCancel: isCancel,
      lines: lines,
      senderName: senderName,
      sentAt: sentAt,
      orderNo: orderNo,
      referenceNo: referenceNo,
      showFeedback: showFeedback,
      waitForCompletion: waitForCompletion,
      onHang: onHang,
      hangAfter: hangAfter,
    );
  }

  Future<bool> _printKitchenNativeOnThisDevice({
    required PosStorePrinter printer,
    required String tableName,
    required bool isCancel,
    required List<({
      String productName,
      double qty,
      String? unitName,
      String? note,
    })> lines,
    required String senderName,
    required DateTime sentAt,
    String? orderNo,
    bool showFeedback = true,
    String? successTitle,
  }) async {
    final settings = toThermalSettings(printer).copyWith(
      openCashDrawer: false,
      compactCutFeed: true,
    );
    final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
    final tpl = await PosPrintConfigSession.instance
        .kitchenTemplate(isCancel: isCancel, force: true);
    final v2 = PosPrintTemplateRuntime.resolveOrPreset(
      template: tpl,
      documentType: isCancel
          ? PosPrintDocumentTypes.kitchenVoid
          : PosPrintDocumentTypes.kitchenSlip,
      paperSize: settings.paperSize,
      printerProfile: PosPrintPrinterProfiles.forPaperAndBrand(
        paperSize: settings.paperSize,
        isSunmi: true,
        isZywell: false,
      ),
    );
    final output = PosPrintTemplateRuntime.compileKitchenSlip(
      template: v2,
      tableName: tableName.trim().isEmpty ? 'Bàn' : tableName.trim(),
      isCancel: isCancel,
      lines: [
        for (final l in lines)
          (
            name: l.productName,
            qty: qtyFmt.format(l.qty),
            unit: l.unitName,
            note: PosPrintTemplateRuntime.kitchenCallNote(l.note, sentAt),
          ),
      ],
      senderName: senderName.trim().isEmpty ? 'admin' : senderName.trim(),
      orderNo: (orderNo ?? '').trim(),
      sentAt: sentAt,
    );
    final ok = await PosPrintTemplateRuntime.printCompiledSunmi(
      output: output,
      settings: settings.copyWith(
        connectionType: PosThermalConnectionType.sunmi,
        printerBrand: PosThermalPrinterBrand.sunmi,
      ),
      kitchenFeed: true,
    );
    if (ok) {
      unawaited(_api.reportPosPrinterHealth(printer.id, status: 'Online'));
      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? (isCancel ? 'Hủy bếp' : 'Báo bếp'),
          message: printer.name,
        );
      }
      return true;
    }
    unawaited(_api.reportPosPrinterHealth(
      printer.id,
      status: 'Offline',
      errorMessage: 'Sunmi kitchen native failed',
    ));
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'In thất bại',
        message: tr('Không in được trên ${printer.name}'),
      );
    }
    return false;
  }

  Future<bool> _enqueueKitchenSlipJson({
    required PosStorePrinter printer,
    required String tableName,
    required bool isCancel,
    required List<({
      String productName,
      double qty,
      String? unitName,
      String? note,
    })> lines,
    required String senderName,
    required DateTime sentAt,
    String? orderNo,
    String? referenceNo,
    bool showFeedback = true,
    bool waitForCompletion = true,
    PosPrintHangCallback? onHang,
    Duration hangAfter = hangAfterDefault,
  }) async {
    await ensureListening();
    final payload = jsonEncode({
      'tableName': tableName,
      'isCancel': isCancel,
      'senderName': senderName,
      'orderNo': orderNo ?? '',
      'sentAt': sentAt.toUtc().toIso8601String(),
      'cutPerItem': printer.cutPerItem,
      'lines': [
        for (final l in lines)
          {
            'productName': l.productName,
            'qty': l.qty,
            if (l.unitName != null && l.unitName!.trim().isNotEmpty)
              'unitName': l.unitName!.trim(),
            'note': PosPrintTemplateRuntime.kitchenCallNote(l.note, sentAt),
            'calledAt': sentAt.toUtc().toIso8601String(),
          },
      ],
    });
    final kitchenDoc = isCancel
        ? PosCloudDocumentTypes.kitchenVoid
        : PosCloudDocumentTypes.kitchenSlip;
    final res = await _api.createPosPrintJob(
      documentType: kitchenDoc,
      payloadFormat: 'KitchenSlipJson',
      payload: payload,
      copies: 1,
      referenceNo: referenceNo,
      // Idempotency server (ReferenceNo + active job) — chống bấm nhiều lần.
      referenceId: null,
      printerId: printer.id,
    );
    if (res['isSuccess'] != true) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không gửi lệnh in',
          message: res['message']?.toString() ?? 'Lỗi máy chủ',
          relatedEntityType: kPosPrintNotifyKind,
        );
      }
      return false;
    }
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return false;

    if (_failFastNoAgent(printer, data, jobId, showFeedback: showFeedback)) {
      return false;
    }

    await _registerCloudJobForAgent(jobId: jobId, printerId: printer.id);
    if (showFeedback) {
      final ref = referenceNo?.trim() ?? '';
      NotificationOverlayManager().show(
        title: isCancel ? 'Hủy bếp' : 'Báo bếp',
        message: ref.isNotEmpty
            ? '$ref → ${printer.name}'
            : 'Đã gửi tới Print Agent (${printer.name})',
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
        relatedEntityType: kPosPrintNotifyKind,
      );
    }
    if (!waitForCompletion) {
      // Không coi Claimed = OK: web→A6 hay kẹt Claimed rồi STUCK/Busy,
      // toast «đã in» giả + phiếu hủy không ra giấy.
      _armHangWatch(
        jobId: jobId,
        documentType: kitchenDoc,
        printer: printer,
        referenceNo: referenceNo,
        acceptClaimedAsSuccess: false,
        hangAfter: hangAfter,
        onHang: onHang,
      );
      unawaited(
        _waitJob(
          jobId,
          showFeedback: false,
          acceptClaimedAsSuccess: false,
        ).whenComplete(
          () => PosPrintSessionRegistry.clearOutbound(jobId),
        ),
      );
      return true;
    }
    // Phiếu bếp: chỉ Completed mới OK — Claimed sớm dễ để job kẹt rồi reclaim in trùng.
    final outcome = await _waitJob(
      jobId,
      showFeedback: showFeedback,
      acceptClaimedAsSuccess: false,
    );
    PosPrintSessionRegistry.clearOutbound(jobId);
    return outcome.ok;
  }

  /// Phiếu ra món / trả món KDS — layout kiểu báo chế biến, tối giản giấy.
  /// [lines] gom nhiều món cùng bàn thành 1 phiếu.
  Future<bool> dispatchKdsReadySlip({
    required PosStorePrinter printer,
    required String tableName,
    String? areaName,
    String? orderNo,
    DateTime? readyAt,
    /// Một món (tương thích cũ) — dùng khi [lines] rỗng.
    String? productName,
    double qty = 1,
    DateTime? calledAt,
    List<({String productName, double qty, DateTime calledAt})> lines = const [],
  }) async {
    final at = readyAt ?? DateTime.now();
    final items = lines.isNotEmpty
        ? lines
        : [
            if ((productName ?? '').trim().isNotEmpty)
              (
                productName: productName!.trim(),
                qty: qty,
                calledAt: calledAt ?? at,
              ),
          ];
    if (items.isEmpty) return false;

    DateTime earliest = items.first.calledAt;
    for (final it in items) {
      if (it.calledAt.isBefore(earliest)) earliest = it.calledAt;
    }
    final first = items.first;
    final payload = jsonEncode({
      'kind': 'kdsReady',
      'productName': first.productName,
      'qty': first.qty,
      'tableName': tableName,
      'areaName': areaName ?? '',
      'calledAt': earliest.toUtc().toIso8601String(),
      'readyAt': at.toUtc().toIso8601String(),
      'orderNo': orderNo ?? '',
      'senderName': 'KDS',
      'isCancel': false,
      'sentAt': at.toUtc().toIso8601String(),
      'lines': [
        for (final it in items)
          {
            'productName': it.productName,
            'qty': it.qty,
            'calledAt': it.calledAt.toUtc().toIso8601String(),
            'note': 'Gọi ${_hhmm(it.calledAt)} · Ra ${_hhmm(at)}',
          },
      ],
    });
    await ensureListening();
    final res = await _api.createPosPrintJob(
      documentType: PosCloudDocumentTypes.kitchenSlip,
      payloadFormat: 'KitchenSlipJson',
      payload: payload,
      copies: 1,
      referenceNo: _kdsCutRef(
        'kds|$tableName|${items.map((e) => e.productName).join('+')}',
        0,
        '${at.millisecondsSinceEpoch}',
      ),
      printerId: printer.id,
    );
    if (res['isSuccess'] != true) return false;
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return false;
    await _registerCloudJobForAgent(jobId: jobId, printerId: printer.id);
    unawaited(
      _waitJob(
        jobId,
        showFeedback: false,
        acceptClaimedAsSuccess: false,
      ).whenComplete(
        () => PosPrintSessionRegistry.clearOutbound(jobId),
      ),
    );
    return true;
  }

  /// In trực tiếp trên thiết bị Agent (máy in gắn tại đây).
  Future<bool> _printDirectOnStorePrinter({
    required PosStorePrinter printer,
    required List<int> bytes,
    required int copies,
    String? referenceNo,
    bool showFeedback = true,
    String? successTitle,
  }) async {
    // Giống Agent: ưu tiên cấu hình máy nội bộ (id hoặc khớp cổng USB/BT/LAN).
    final local =
        await PosLocalPrintersStore.instance.resolveForStorePrinter(printer);
    final settings = local != null
        ? local.toThermalSettings()
        : toThermalSettings(printer);
    final ref = referenceNo?.trim() ?? '';

    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'Đã nhận lệnh in',
        message: ref.isNotEmpty
            ? 'Đơn $ref — đang in trên ${printer.name}…'
            : 'Đang in trên ${printer.name}…',
        duration: const Duration(seconds: 4),
      );
    }

    // Tôn trọng feed cấu hình máy (không ép 4 dòng riêng cho Sunmi).
    final sunmiFeed = settings.resolvedFeedBeforeCut;

    var ok = true;
    // Tem TSPL đã có PRINT trong payload — không nhân bản theo copies job.
    final effectiveCopies = printer.isLabelPrinter ? 1 : copies.clamp(1, 10);
    for (var i = 0; i < effectiveCopies; i++) {
      final sent = await PosPrinterTransport.send(
        connectionType: settings.connectionType,
        bluetoothAddress: settings.bluetoothAddress,
        lanHost: settings.lanHost,
        lanPort: settings.lanPort,
        usbDeviceName: settings.usbDeviceName,
        bytes: bytes,
        sunmiFeedLines: sunmiFeed,
      );
      if (!sent) {
        ok = false;
        break;
      }
    }

    if (ok) {
      unawaited(_api.reportPosPrinterHealth(printer.id, status: 'Online'));
      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'In xong',
          message: ref.isNotEmpty
              ? 'Đơn $ref — ${printer.name}'
              : printer.name,
        );
      }
      return true;
    }

    unawaited(_api.reportPosPrinterHealth(
      printer.id,
      status: 'Offline',
      errorMessage: 'Không kết nối được máy in',
    ));
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'In thất bại',
        message: tr('Không kết nối được ${printer.name}'),
      );
    }
    return false;
  }

  /// In trực tiếp trên thiết bị này (Thiết lập máy in nhiệt — LAN/BT/USB cục bộ).
  ///
  /// Nếu [documentRole] có: in tới **tất cả** máy nội bộ mang vai trò đó.
  /// Không có role: dùng [settingsOverride] hoặc singleton legacy.
  Future<bool> dispatchLocalEscPos({
    required List<int> bytes,
    int copies = 1,
    bool showFeedback = true,
    String? successTitle,
    PosThermalPrinterSettings? settingsOverride,
    String? documentType,
    String? documentRole,
    String? referenceId,
    String? referenceNo,
    bool skipDedup = false,
    bool waitForCompletion = true,
  }) async {
    if (kIsWeb) return false;

    if (!skipDedup &&
        documentType != null &&
        PosPrintDedup.shouldSkip(
          documentType: documentType,
          referenceId: referenceId,
          referenceNo: referenceNo,
        )) {
      if (showFeedback) _notifyPrintDedupSkip();
      return true;
    }

    final role = documentRole ?? documentType;
    if (settingsOverride == null && role != null && role.isNotEmpty) {
      return dispatchLocalEscPosByRole(
        role: role,
        bytes: bytes,
        copies: copies,
        showFeedback: showFeedback,
        successTitle: successTitle,
        waitForCompletion: waitForCompletion,
      );
    }

    final local = settingsOverride ?? await PosThermalPrinterSettings.load();
    if (!local.enabled) return false;

    Future<bool> run() async {
      for (var c = 0; c < copies.clamp(1, 10); c++) {
        final ok = await _sendLocal(local, bytes);
        if (!ok) {
          if (showFeedback) {
            NotificationOverlayManager().showError(
              title: 'In thất bại',
              message: tr('Không kết nối được máy in cục bộ'),
            );
          }
          return false;
        }
      }
      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'In thành công',
          message: tr('Máy in cục bộ (cùng mạng)'),
        );
      }
      return true;
    }

    if (!waitForCompletion) {
      return run();
    }
    return run();
  }

  /// In tới mọi máy nội bộ có [role] (SaleInvoice / KitchenSlip / StockIssue…).
  Future<bool> dispatchLocalEscPosByRole({
    required String role,
    required List<int> bytes,
    int copies = 1,
    bool showFeedback = true,
    String? successTitle,
    bool waitForCompletion = true,
  }) async {
    if (kIsWeb) return false;
    final printers = await PosLocalPrintersStore.instance.forRole(role);
    if (printers.isEmpty) {
      // Không fallback singleton — tránh máy chỉ hóa đơn vẫn nhận báo bếp.
      return false;
    }

    Future<bool> run() async {
      var anyOk = false;
      for (final p in printers) {
        var printerOk = false;
        for (var c = 0; c < copies.clamp(1, 10); c++) {
          final ok = await _sendLocal(p.toThermalSettings(), bytes);
          if (ok) printerOk = true;
        }
        if (printerOk) {
          // Một máy đủ — tránh in đôi khi nhiều profile cùng role.
          anyOk = true;
          break;
        }
      }
      if (!anyOk && showFeedback) {
        NotificationOverlayManager().showError(
          title: 'In thất bại',
          message: tr('Không kết nối được máy in nội bộ ($role)'),
        );
      } else if (anyOk && showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'In thành công',
          message: tr('Máy in nội bộ'),
        );
      }
      return anyOk;
    }

    if (!waitForCompletion) {
      // Luôn await — soft-OK (unawaited+true) gây lúc in lúc không.
      return run();
    }
    return run();
  }

  /// In theo máy gán sản phẩm: nếu là máy nội bộ trên thiết bị này → local;
  /// ngược lại trả false để caller đi cloud/agent.
  Future<bool> dispatchLocalEscPosForStorePrinterId({
    required String storePrinterId,
    required List<int> bytes,
    int copies = 1,
    bool showFeedback = false,
  }) async {
    final p =
        await PosLocalPrintersStore.instance.byStorePrinterId(storePrinterId);
    if (p == null) return false;
    return dispatchLocalEscPos(
      bytes: bytes,
      copies: copies,
      showFeedback: showFeedback,
      settingsOverride: p.toThermalSettings(),
      skipDedup: true,
    );
  }

  Future<bool> _sendLocal(PosThermalPrinterSettings settings, List<int> bytes) async {
    if (settings.connectionType == PosThermalConnectionType.usb) {
      final resolved =
          await PosPrinterReadiness.resolveUsbForPrint(settings.usbDeviceName);
      if (resolved == null) {
        debugPrint(
          'Local print blocked: usb không khớp cổng '
          '(usb=${settings.usbDeviceName})',
        );
        return false;
      }
      if (!resolved.hasPermission) {
        final granted = await PosUsbPrinter.requestPermission(resolved);
        if (!granted) return false;
      }
      final up = await PosUsbPrinter.probeDevice(
        stableId: resolved.stableId,
        deviceName: resolved.deviceName,
        vendorId: resolved.vendorId,
        productId: resolved.productId,
        serialNumber: resolved.serialNumber,
      );
      if (!up) {
        debugPrint(
          'Local print blocked: usb open/claim fail ${resolved.displayName}',
        );
        return false;
      }
      return PosPrinterTransport.send(
        connectionType: settings.connectionType,
        bluetoothAddress: settings.bluetoothAddress,
        lanHost: settings.lanHost,
        lanPort: settings.lanPort,
        usbDeviceName: resolved.savedRef,
        usbStableId: resolved.stableId,
        usbVendorId: resolved.vendorId,
        usbProductId: resolved.productId,
        usbSerial: resolved.serialNumber,
        bytes: bytes,
        sunmiFeedLines: settings.resolvedFeedBeforeCut,
      );
    }
    if (settings.connectionType == PosThermalConnectionType.sunmi) {
      final usbList = await PosPrinterReadiness.listUsbDevices();
      final up = await PosPrinterReadiness.probePort(
        connectionType: settings.connectionType,
        usbDeviceName: settings.usbDeviceName,
        lanHost: settings.lanHost,
        lanPort: settings.lanPort,
        bluetoothAddress: settings.bluetoothAddress,
        usbList: usbList,
      );
      if (!up) {
        debugPrint('Local print blocked: sunmi mat ket noi');
        return false;
      }
    }
    return PosPrinterTransport.send(
      connectionType: settings.connectionType,
      bluetoothAddress: settings.bluetoothAddress,
      lanHost: settings.lanHost,
      lanPort: settings.lanPort,
      usbDeviceName: settings.usbDeviceName,
      bytes: bytes,
      sunmiFeedLines: settings.resolvedFeedBeforeCut,
    );
  }

  Future<_JobOutcome> _waitJob(
    String jobId, {
    bool showFeedback = true,
    bool acceptClaimedAsSuccess = true,
  }) async {
    final completer = Completer<_JobOutcome>();
    _pendingJobs[jobId] = completer;
    _acceptClaimedByJob[jobId] = acceptClaimedAsSuccess;
    _showFeedbackByJob[jobId] = showFeedback;

    Timer(_jobTimeout, () {
      if (!completer.isCompleted) {
        // Soft-timeout: nếu Agent đã nhận (Claimed/Printing) thì coi OK —
        // tránh báo lỗi sau khi giấy đã ra mà Complete chậm.
        unawaited(() async {
          try {
            final res = await _api.getPosPrintJob(jobId);
            final status = (res['data'] is Map)
                ? (res['data'] as Map)['status']?.toString()
                : null;
            if (status == 'Completed' ||
                (acceptClaimedAsSuccess &&
                    (status == 'Claimed' || status == 'Printing'))) {
              _finishJob(
                jobId,
                const _JobOutcome(true, null),
                showFeedback: showFeedback,
              );
              return;
            }
          } catch (_) {}
          if (!completer.isCompleted) {
            _finishJob(
              jobId,
              const _JobOutcome(
                false,
                'Print Agent không nhận lệnh trong 120 giây. '
                'Kiểm tra Sunmi: Agent BẬT + đã chọn chip máy in + app đang mở.',
              ),
              showFeedback: showFeedback,
            );
          }
        }());
      }
    });

    unawaited(_pollJobUntilDone(
      jobId,
      showFeedback: showFeedback,
      acceptClaimedAsSuccess: acceptClaimedAsSuccess,
    ));
    return completer.future;
  }

  Future<void> _pollJobUntilDone(
    String jobId, {
    bool showFeedback = true,
    bool acceptClaimedAsSuccess = true,
  }) async {
    for (var i = 0; i < 24; i++) {  // 24 × 5s = 120s, match _jobTimeout
      if (!_pendingJobs.containsKey(jobId)) return;
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!_pendingJobs.containsKey(jobId)) return;
      try {
        final res = await _api.getPosPrintJob(jobId);
        if (res['isSuccess'] != true || res['data'] is! Map) continue;
        final data = res['data'] as Map;
        final status = data['status']?.toString() ?? '';
        if (status == 'Completed') {
          _finishJob(
            jobId,
            const _JobOutcome(true, null),
            showFeedback: showFeedback,
          );
        } else if (status == 'Cancelled') {
          final err = data['errorMessage']?.toString();
          if (_isNothingPrintedCancel(data['errorCode']?.toString())) {
            _finishJob(
              jobId,
              _JobOutcome(false,
                  'Phiếu chưa in — máy in/Agent offline quá 5 phút. In lại từ hàng chờ.'),
              showFeedback: true,
            );
            continue;
          }
          _cancelledJobs.add(jobId);
          _finishJob(
            jobId,
            _JobOutcome(false, err ?? 'Lệnh in đã bị hủy phía máy chủ',
                isCancelled: true),
            showFeedback: showFeedback,
          );
        } else if (status == 'Failed' || status == 'Expired') {
          final err = data['errorMessage']?.toString();
          _finishJob(
            jobId,
            _JobOutcome(false, err ?? status),
            showFeedback: showFeedback,
          );
        } else if (acceptClaimedAsSuccess &&
            (status == 'Claimed' || status == 'Printing')) {
          // Agent đã nhận — coi thành công ngay (không chờ i>=2 ~15s).
          _finishJob(
            jobId,
            const _JobOutcome(true, null),
            showFeedback: showFeedback,
          );
        }
      } catch (_) {}
    }
  }

  Future<bool> dispatchLabelJobs({
    required List<List<int>> jobs,
    String? referenceNo,
    bool showFeedback = true,
    bool skipDedup = true,
  }) async {
    if (jobs.isEmpty) return false;
    for (var i = 0; i < jobs.length; i++) {
      final ok = await dispatchEscPos(
        documentType: PosCloudDocumentTypes.barcodeLabel,
        bytes: jobs[i],
        referenceNo: referenceNo,
        showFeedback: showFeedback && i == jobs.length - 1,
        successTitle: 'In tem thành công',
        skipDedup: skipDedup,
        // Không coi Claimed = OK — tem USB/TSPL hay kẹt rồi timeout.
        waitForCompletion: false,
        acceptClaimedAsSuccess: false,
      );
      if (!ok) return false;
    }
    return true;
  }

  /// [forceRemote]: bỏ qua in native cục bộ — gửi cloud như máy thu ngân (Oppo).

  /// In thử mẫu V2 qua Agent (Sunmi native / ESC) — gửi đúng draft editor.
  Future<bool> dispatchTemplatePreview({
    required PosPrintTemplateV2 template,
    required PosStorePrinter printer,
    required Map<String, String> data,
    List<Map<String, String>> lineItems = const [],
    String mode = 'sale',
    Map<String, dynamic>? kitchen,
    bool kitchenFeed = false,
    bool showFeedback = true,
    String? successTitle,
  }) async {
    await ensureListening();
    final hasCloud = await refreshConfig();

    // Cổng local trên máy này → in thẳng, không qua cloud.
    if (!kIsWeb && await _canDispatchLocallyNow(printer)) {
      final settings = toThermalSettings(printer).copyWith(
        enabled: true,
        paperSize: template.paperSize,
      );
      late final PosPrintCompiledOutput output;
      if (mode == 'kitchenSlip') {
        final km = kitchen ?? {};
        final linesRaw = km['lines'];
        final lines = <({String name, String qty, String? unit, String? note})>[];
        if (linesRaw is List) {
          for (final e in linesRaw) {
            if (e is! Map) continue;
            lines.add((
              name: e['name']?.toString() ?? '',
              qty: e['qty']?.toString() ?? '1',
              unit: e['unit']?.toString(),
              note: e['note']?.toString(),
            ));
          }
        }
        output = PosPrintTemplateRuntime.compileKitchenSlip(
          template: template,
          tableName: km['tableName']?.toString() ?? 'Bàn',
          isCancel: km['isCancel'] == true,
          lines: lines,
          senderName: km['senderName']?.toString() ?? 'NV',
          orderNo: km['orderNo']?.toString() ?? 'DH0001',
          sentAt: DateTime.now(),
        );
      } else {
        output = PosPrintTemplateCompiler.compile(
          template: template,
          data: data,
          lineItems: lineItems,
        );
      }
      if (printer.isSunmi && await PosPrinterTransport.isSunmiDevice()) {
        return PosPrintTemplateRuntime.printCompiledSunmi(
          output: output,
          settings: settings.copyWith(
            connectionType: PosThermalConnectionType.sunmi,
            printerBrand: PosThermalPrinterBrand.sunmi,
          ),
          kitchenFeed: kitchenFeed || mode == 'kitchenSlip',
        );
      }
      final bytes = await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
        output: output,
        settings: settings,
      );
      return _printDirectOnStorePrinter(
        printer: printer,
        bytes: bytes,
        copies: 1,
        showFeedback: showFeedback,
        successTitle: successTitle ?? 'In thử',
      );
    }

    if (!hasCloud) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'In thử thất bại',
          message: tr('Chưa cấu hình in cloud / Print Agent'),
        );
      }
      return false;
    }

    final payload = jsonEncode({
      'templateContent': PosPrintTemplateV2Codec.encode(template),
      'documentType': template.documentType,
      'paperSize': template.paperSize,
      'mode': mode,
      'data': data,
      'lineItems': lineItems,
      if (kitchen != null) 'kitchen': kitchen,
      'kitchenFeed': kitchenFeed || mode == 'kitchenSlip',
    });

    final res = await _api.createPosPrintJob(
      documentType: template.documentType,
      payloadFormat: 'TemplatePreviewJson',
      payload: payload,
      copies: 1,
      referenceNo: 'TPL-${DateTime.now().millisecondsSinceEpoch}',
      printerId: printer.id,
    );
    if (res['isSuccess'] != true) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không gửi lệnh in',
          message: res['message']?.toString() ?? 'Lỗi máy chủ',
        );
      }
      return false;
    }
    final jobData = res['data'] as Map<String, dynamic>?;
    final jobId = jobData?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return false;

    if (_failFastNoAgent(printer, jobData, jobId, showFeedback: showFeedback)) {
      return false;
    }

    await _registerCloudJobForAgent(jobId: jobId, printerId: printer.id);
    _armHangWatch(
      jobId: jobId,
      documentType: template.documentType,
      printer: printer,
      referenceNo: 'TPL',
      acceptClaimedAsSuccess: false,
    );
    if (showFeedback) {
      NotificationOverlayManager().show(
        title: successTitle ?? 'In thử',
        message: tr('Đã gửi mẫu → Agent (${printer.name})'),
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
      );
    }
    unawaited(
      _waitJob(
        jobId,
        showFeedback: false,
        acceptClaimedAsSuccess: false,
      ).whenComplete(
        () => PosPrintSessionRegistry.clearOutbound(jobId),
      ),
    );
    return true;
  }

  Future<bool> testPrinter(
    PosStorePrinter printer, {
    bool forceRemote = false,
  }) async {
    if (printer.isLabelPrinter) {
      final settings = toLabelSettings(printer);
      // A7 «Test qua cloud» / không gắn USB tem → đẩy Agent (TSPL), không in local.
      if (!forceRemote && await _canDispatchLocallyNow(printer)) {
        return PosLabelPrinterService.testPrint(settings);
      }
      final bytes = await PosLabelPrinterService.buildTestBytes(settings);
      if (bytes == null || bytes.isEmpty) return false;
      return dispatchEscPos(
        documentType: PosCloudDocumentTypes.barcodeLabel,
        bytes: bytes,
        printerId: printer.id,
        referenceNo: 'TEST-LABEL-${DateTime.now().millisecondsSinceEpoch}',
        showFeedback: true,
        successTitle: 'Test tem OK',
        skipDedup: true,
        forceCloud: forceRemote,
      );
    }

    // Sunmi trên chính máy → in native cục bộ (không qua cloud).
    if (!forceRemote &&
        printer.isSunmi &&
        await PosPrinterTransport.isSunmiDevice()) {
      final settings = toThermalSettings(printer);
      final ok = await PosSunmiNativePrint.printTest(
        storeLabel: printer.name,
        feedLines: settings.resolvedFeedBeforeCut,
        paperWidthMm: settings.paperWidthMm,
      );
      if (ok) {
        NotificationOverlayManager().showSuccess(
          title: 'Test in OK',
          message: '${printer.name} (Sunmi native)',
        );
      }
      return ok;
    }

    // Chip Sunmi (Oppo / hoặc «Test qua cloud» trên V2s) → JSON native trên Agent.
    // Tránh ESC/POS (lỗi font / in ra lệnh ESC @… / lần 2 bị dedup).
    if (printer.isSunmi) {
      return _enqueueTestPrintJson(
        printer: printer,
        forceCloud: forceRemote,
        showFeedback: true,
      );
    }

    final settings = toThermalSettings(printer);
    final bytes = await PosThermalPrinterService.buildTestEscPosBytes(settings);

    return dispatchEscPos(
      documentType: PosCloudDocumentTypes.saleInvoice,
      bytes: bytes,
      printerId: printer.id,
      referenceNo: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
      showFeedback: true,
      successTitle: 'Test in OK',
      skipDedup: true,
      forceCloud: forceRemote,
    );
  }

  /// Test in Sunmi qua cloud — Agent in native UTF-8.
  Future<bool> _enqueueTestPrintJson({
    required PosStorePrinter printer,
    bool forceCloud = false,
    bool showFeedback = true,
  }) async {
    await ensureListening();
    final hasCloud = await refreshConfig();

    // Agent trên chính máy + không forceCloud → native trực tiếp.
    if (!forceCloud && await PosPrinterTransport.isSunmiDevice()) {
      final settings = toThermalSettings(printer);
      final ok = await PosSunmiNativePrint.printTest(
        storeLabel: printer.name,
        feedLines: settings.resolvedFeedBeforeCut,
        paperWidthMm: settings.paperWidthMm,
      );
      if (ok && showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: 'Test in OK',
          message: '${printer.name} (Sunmi native)',
        );
      }
      return ok;
    }

    if (!hasCloud) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Test thất bại',
          message: tr('Chưa cấu hình in cloud / Print Agent'),
        );
      }
      return false;
    }

    final settings = toThermalSettings(printer);
    final refNo = 'TEST-${DateTime.now().millisecondsSinceEpoch}';
    final payload = jsonEncode({
      'storeLabel': printer.name,
      'paperWidthMm': settings.paperWidthMm,
      'feedLines': settings.resolvedFeedBeforeCut,
    });

    // Trên chính máy Agent (V2s): pause claim NGAY trước khi tạo job —
    // tránh SignalR/timer claim + in song song với nhánh in nội bộ bên dưới
    // (in ra 2 bản cùng lúc).
    final localTestOnAgent = await PosPrintRole.isAgentForPrinter(printer.id);
    if (localTestOnAgent) {
      PosPrintAgentService.instance.pauseClaims();
    }

    var res = await _api.createPosPrintJob(
      documentType: PosCloudDocumentTypes.saleInvoice,
      payloadFormat: 'TestPrintJson',
      payload: payload,
      copies: 1,
      referenceNo: refNo,
      printerId: printer.id,
    );

    // Server cũ chưa có TestPrintJson → EscPos; Agent Sunmi vẫn in native theo prefix TEST-.
    if (res['isSuccess'] != true) {
      final bytes =
          await PosThermalPrinterService.buildTestEscPosBytes(settings);
      res = await _api.createPosPrintJob(
        documentType: PosCloudDocumentTypes.saleInvoice,
        payloadFormat: 'EscPosBase64',
        payload: base64Encode(bytes),
        copies: 1,
        referenceNo: refNo,
        printerId: printer.id,
      );
    }
    if (res['isSuccess'] != true) {
      if (localTestOnAgent) PosPrintAgentService.instance.resumeClaims();
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không gửi lệnh in',
          message: res['message']?.toString() ?? 'Lỗi máy chủ',
        );
      }
      return false;
    }

    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) {
      if (localTestOnAgent) PosPrintAgentService.instance.resumeClaims();
      return false;
    }

    // Trên chính máy Agent (V2s): tự claim + in native ngay.
    // Không chờ SignalR/timer — hay bị kẹt Claimed khiến «test cloud không ra».
    if (localTestOnAgent) {
      return _completeCloudTestOnLocalAgent(
        jobId: jobId,
        printer: printer,
        settings: settings,
        showFeedback: showFeedback,
      );
    }

    // Không hủy job khi heartbeat DB lệch — Agent vẫn Claim được (demopos).
    _failFastNoAgent(printer, data, jobId, showFeedback: showFeedback);

    await _registerCloudJobForAgent(jobId: jobId, printerId: printer.id);
    _jobMeta[jobId] = _JobFeedbackMeta(
      referenceNo: 'TEST',
      printerName: printer.name,
    );

    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'Đã gửi lệnh in',
        message: 'Test → Print Agent (${printer.name})',
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
      );
    }

    final outcome = await _waitJob(
      jobId,
      showFeedback: showFeedback,
      acceptClaimedAsSuccess: false,
    );
    PosPrintSessionRegistry.clearOutbound(jobId);
    return outcome.ok;
  }

  /// V2s vừa là máy gửi vừa là Agent — in ngay, claim/complete nhanh (không chờ 5–10s).
  Future<bool> _completeCloudTestOnLocalAgent({
    required String jobId,
    required PosStorePrinter printer,
    required PosThermalPrinterSettings settings,
    bool showFeedback = true,
  }) async {
    final agent = PosPrintAgentService.instance;
    // Heartbeat nhẹ — không refresh toàn bộ máy in.
    await agent.forceRegister(refreshPrinters: false);
    if (!agent.isRegistered || agent.agentId == null) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Test cloud thất bại',
          message: agent.lastRegisterError ??
              'Agent chưa đăng ký server — bật Agent + chọn chip máy in',
        );
      }
      return false;
    }

    final agentId = agent.agentId!;
    bool sameId(String a, String b) =>
        a.trim().toLowerCase() == b.trim().toLowerCase();

    agent.pauseClaims();
    try {
      // In native trước — người dùng thấy giấy ngay (~1s).
      final ok = await PosSunmiNativePrint.printTest(
        storeLabel: printer.name,
        feedLines: settings.resolvedFeedBeforeCut,
        paperWidthMm: settings.paperWidthMm,
      );
      if (!ok) {
        await _api.failPosPrintJob(
          jobId,
          agentId,
          errorCode: 'PRINT_FAILED',
          errorMessage: 'Sunmi native test thất bại',
        );
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'Test cloud thất bại',
            message: tr('Không in được trên Sunmi'),
          );
        }
        return false;
      }

      // Claim đúng job test — KHÔNG claimNext generic (tránh fail SUPERSEDED
      // đè hóa đơn/phiếu bếp đang chờ → sót bill).
      Map<String, dynamic>? claimed;
      for (var i = 0; i < 5 && claimed == null; i++) {
        final byId = await _api.claimPosPrintJobById(jobId, agentId);
        final byIdData = byId['data'];
        if (byIdData is Map) {
          final map = Map<String, dynamic>.from(byIdData);
          final id = map['jobId']?.toString() ?? map['JobId']?.toString() ?? '';
          if (sameId(id, jobId)) {
            claimed = map;
            break;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      if (claimed != null) {
        await _api.markPosPrintJobPrinting(jobId, agentId);
        await _api.completePosPrintJob(jobId, agentId);
      } else {
        // Đánh Failed để không bị Agent in lần 2.
        await _api.failPosPrintJob(
          jobId,
          agentId,
          errorCode: 'LOCAL_TEST_DONE',
          errorMessage: 'Đã in trên máy Agent (claim bỏ qua)',
        );
      }
      await _api.reportPosPrinterHealth(printer.id, status: 'Online');

      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: 'Test cloud OK',
          message: '${printer.name} (qua cloud → Agent)',
        );
      }
      return true;
    } finally {
      agent.resumeClaims();
    }
  }

  /// Test EscPos qua cloud trên máy Agent (Zywell USB/LAN/BT) — in cổng nội bộ rồi complete job.
  Future<bool> _completeEscPosCloudTestOnLocalAgent({
    required String jobId,
    required PosStorePrinter printer,
    required List<int> bytes,
    required int copies,
    bool showFeedback = true,
    String? successTitle,
  }) async {
    final agent = PosPrintAgentService.instance;
    await agent.forceRegister(refreshPrinters: false);
    if (!agent.isRegistered || agent.agentId == null) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Test cloud thất bại',
          message: agent.lastRegisterError ??
              'Agent chưa đăng ký — bật Agent + chọn chip máy in',
        );
      }
      return false;
    }

    final agentId = agent.agentId!;
    bool sameId(String a, String b) =>
        a.trim().toLowerCase() == b.trim().toLowerCase();

    agent.pauseClaims();
    try {
      final local =
          await PosLocalPrintersStore.instance.resolveForStorePrinter(printer);
      final settings = local != null
          ? local.toThermalSettings()
          : toThermalSettings(printer);
      final sunmiFeed = settings.resolvedFeedBeforeCut;
      final n = copies.clamp(1, 10);
      var ok = true;
      for (var i = 0; i < n; i++) {
        final sent = await PosPrinterTransport.send(
          connectionType: settings.connectionType,
          bluetoothAddress: settings.bluetoothAddress,
          lanHost: settings.lanHost,
          lanPort: settings.lanPort,
          usbDeviceName: settings.usbDeviceName,
          bytes: bytes,
          sunmiFeedLines: sunmiFeed,
        );
        if (!sent) {
          ok = false;
          break;
        }
      }

      if (!ok) {
        await _api.failPosPrintJob(
          jobId,
          agentId,
          errorCode: 'PRINT_FAILED',
          errorMessage: 'Không kết nối được ${printer.name} (USB/LAN/BT)',
        );
        await _api.reportPosPrinterHealth(
          printer.id,
          status: 'Offline',
          errorMessage: 'Test cloud thất bại',
        );
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'Test cloud thất bại',
            message: tr('Không kết nối được ${printer.name}'),
          );
        }
        return false;
      }

      Map<String, dynamic>? claimed;
      for (var i = 0; i < 5 && claimed == null; i++) {
        final byId = await _api.claimPosPrintJobById(jobId, agentId);
        final byIdData = byId['data'];
        if (byIdData is Map) {
          final map = Map<String, dynamic>.from(byIdData);
          final id = map['jobId']?.toString() ?? map['JobId']?.toString() ?? '';
          if (sameId(id, jobId)) {
            claimed = map;
            break;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      if (claimed != null) {
        await _api.markPosPrintJobPrinting(jobId, agentId);
        await _api.completePosPrintJob(jobId, agentId);
      } else {
        await _api.failPosPrintJob(
          jobId,
          agentId,
          errorCode: 'LOCAL_TEST_DONE',
          errorMessage: 'Đã in trên máy Agent (claim bỏ qua)',
        );
      }
      await _api.reportPosPrinterHealth(printer.id, status: 'Online');

      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'Test cloud OK',
          message: '${printer.name} (qua cloud → Agent)',
        );
      }
      return true;
    } finally {
      agent.resumeClaims();
    }
  }

  /// Cổng in thẳng từ máy gửi lệnh: phải có profile nội bộ khớp máy
  /// (USB/BT/LAN/Sunmi). Không dùng lanHost/USB cloud khi máy này không cắm.
  /// Sunmi built-in: in native nếu đây là máy Sunmi.
  /// Public cho màn Mẫu in — quyết định In thử local vs Agent.
  Future<bool> canProbeLocalPortForTest(PosStorePrinter printer) =>
      _canDispatchLocallyNow(printer);

  Future<bool> _canDispatchLocallyNow(PosStorePrinter printer) async {
    if (kIsWeb) return false;
    final local =
        await PosLocalPrintersStore.instance.resolveForStorePrinter(printer);
    if (local == null ||
        !PosLocalPrintersStore.profileAllowsDirectLocal(local)) {
      return printer.isSunmi && await PosPrinterTransport.isSunmiDevice();
    }
    if (printer.isLan ||
        local.connectionType == PosThermalConnectionType.lan) {
      return local.connectionType == PosThermalConnectionType.lan &&
          (local.lanHost ?? '').trim().isNotEmpty;
    }
    final settings = local.toThermalSettings();
    if (settings.connectionType == PosThermalConnectionType.bluetooth) {
      return (settings.bluetoothAddress ?? '').trim().isNotEmpty;
    }
    if (settings.connectionType == PosThermalConnectionType.sunmi) {
      return PosPrinterTransport.isSunmiDevice();
    }
    final usbList = await PosPrinterReadiness.listUsbDevices();
    return PosPrinterReadiness.probePort(
      connectionType: settings.connectionType,
      usbDeviceName: settings.usbDeviceName,
      lanHost: settings.lanHost,
      lanPort: settings.lanPort,
      bluetoothAddress: settings.bluetoothAddress,
      usbList: usbList,
    );
  }

  static Future<String> stableDeviceId() async {
    final settings = await PosPrintAgentSettings.load();
    final existing = settings.deviceId?.trim() ?? '';
    // Bỏ android.id ngắn kiểu "235" — dùng UUID ổn định.
    if (existing.length >= 16) return existing;

    final identity = await PosDeviceIdentity.get();
    final id = identity.id;
    await settings.copyWith(deviceId: id).save();
    return id;
  }
}

class _HangWatch {
  const _HangWatch({
    required this.documentType,
    required this.printerId,
    required this.printerName,
    required this.onHang,
    this.referenceNo,
  });

  final String documentType;
  final String printerId;
  final String printerName;
  final String? referenceNo;

  /// Null = caller không dựng phiếu chờ riêng; orchestrator chỉ báo lỗi.
  final PosPrintHangCallback? onHang;
}

class _JobOutcome {
  const _JobOutcome(this.ok, this.error,
      {this.printerName, this.isCancelled = false});
  final bool ok;
  final String? error;
  final String? printerName;
  /// True when server-side Cancelled — caller can suppress re-queue.
  final bool isCancelled;
}

class _JobFeedbackMeta {
  const _JobFeedbackMeta({this.referenceNo, this.printerName});
  final String? referenceNo;
  final String? printerName;
}
