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
    title: 'Bá» qua lá»‡nh trÃ¹ng',
    message: tr(
      detail ??
          'Lá»‡nh gáº§n Ä‘Ã¢y Ä‘ang chá» mÃ¡y in â€” khÃ´ng gá»­i trÃ¹ng (trÃ¡nh báº¥m nhiá»u láº§n)',
    ),
    relatedEntityType: kPosPrintNotifyKind,
    duration: const Duration(seconds: 3),
  );
}
/// Job cloud chÆ°a xong sau [PosPrintOrchestrator.hangAfterDefault] â†’ phiáº¿u treo.
typedef PosPrintHangCallback = void Function({
  required String jobId,
  required String documentType,
  required String printerId,
  required String printerName,
  String? referenceNo,
});

/// Äiá»u phá»‘i in cloud qua MÃ¡y in cá»­a hÃ ng + Print Agent.
/// In LAN/BT cá»¥c bá»™: dÃ¹ng [dispatchLocalEscPos] / [dispatchLocalEscPosByRole].
class PosPrintOrchestrator {
  PosPrintOrchestrator._();
  static final PosPrintOrchestrator instance = PosPrintOrchestrator._();

  /// Thá»i gian chá» Agent in trÆ°á»›c khi Ä‘Æ°a phiáº¿u vÃ o hÃ ng treo (mÃ¡y gá»­i).
  static const hangAfterDefault = Duration(seconds: 60);

  /// Job cÃ²n Claimed/Printing thÃ¬ kiá»ƒm tra láº¡i sau chá»«ng nÃ y thay vÃ¬ bá» theo dÃµi.
  static const hangWatchRecheck = Duration(seconds: 20);

  /// Tráº§n theo dÃµi â€” dÃ i hÆ¡n má»‘c server há»§y job káº¹t (180s) Ä‘á»ƒ báº¯t Ä‘Æ°á»£c Cancelled.
  static const hangWatchMaxWait = Duration(seconds: 240);

  final _api = ApiService();
  final _signalR = SignalRService();
  final _pendingJobs = <String, Completer<_JobOutcome>>{};
  /// True = server-side Cancelled (operator cancel / idempotency dedup / replaced).
  /// Distinguishes Cancelled from Failed so caller can suppress re-queue.
  final _cancelledJobs = <String>{};
  /// Policy chá» Completed (false = khÃ´ng coi Claimed/Printing lÃ  thÃ nh cÃ´ng).
  final _acceptClaimedByJob = <String, bool>{};
  /// showFeedback khi SignalR cáº­p nháº­t status (trÃ¡nh bÃ¡o Ä‘á» phiáº¿u báº¿p fire-and-forget).
  final _showFeedbackByJob = <String, bool>{};
  final _jobMeta = <String, _JobFeedbackMeta>{};
  final _feedbackSent = <String>{};
  final _hangTimers = <String, Timer>{};
  /// Callback phiáº¿u treo theo job â€” giá»¯ khi fire-and-forget Ä‘á»ƒ Failed/Expired váº«n treo.
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
        debugPrint('ðŸ“¡ Print orchestrator: SignalR reconnected â€” re-arming status subscription');
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
        c.complete(const _JobOutcome(false, 'ÄÃ£ há»§y'));
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
    // TrÆ°á»›c Ä‘Ã¢y thiáº¿u onHang lÃ  bá» theo dÃµi luÃ´n: tem ly, phiáº¿u kho, táº¡m tÃ­nh,
    // in láº¡i tá»« danh sÃ¡châ€¦ gá»­i lÃªn cloud xong coi nhÆ° xong. Agent cháº¿t lÃ  máº¥t
    // giáº¥y mÃ  khÃ´ng ai biáº¿t. Giá» váº«n theo dÃµi, chá»‰ khÃ¡c cÃ¡ch xá»­ lÃ½ khi treo.
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

  /// Agent nháº­n job rá»“i treo lÃ  trÆ°á»ng há»£p máº¥t phiáº¿u tá»‡ nháº¥t: server dá»n báº±ng
  /// Cancelled sau ~3 phÃºt, cÃ²n mÃ¡y gá»­i thÃ¬ Ä‘Ã£ bá» theo dÃµi tá»« giÃ¢y thá»© 60 vÃ¬
  /// tháº¥y tráº¡ng thÃ¡i Claimed. Thu ngÃ¢n khÃ´ng tháº¥y lá»—i, khÃ´ng cÃ³ phiáº¿u chá», vÃ 
  /// hÃ³a Ä‘Æ¡n/phiáº¿u báº¿p biáº¿n máº¥t. VÃ¬ váº­y váº«n cÃ²n Claimed/Printing thÃ¬ háº¹n láº¡i
  /// giá» kiá»ƒm tra thay vÃ¬ bá», vÃ  Cancelled cÅ©ng tÃ­nh lÃ  treo Ä‘á»ƒ in láº¡i Ä‘Æ°á»£c.
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
          // Lá»—i máº¡ng khi poll â€” giá»¯ callback; SignalR Failed váº«n cÃ³ thá»ƒ treo.
          return;
        }

        if (status == 'Completed') {
          _hangCallbacks.remove(jobId);
          return;
        }
        if (status == 'Claimed' || status == 'Printing') {
          if (acceptClaimedAsSuccess && DateTime.now().isAfter(deadline)) {
            // Háº¿t háº¡n theo dÃµi mÃ  Agent váº«n giá»¯ job: coi nhÆ° Ä‘Ã£ in xong Ä‘á»ƒ
            // khÃ´ng dá»±ng phiáº¿u chá» gÃ¢y in trÃ¹ng.
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

        // Queued / Failed / Expired / Cancelled / khÃ´ng rÃµ â†’ cháº¯c cháº¯n chÆ°a ra giáº¥y.
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

  /// Caller khÃ´ng cÃ³ hÃ ng chá» riÃªng: Ã­t nháº¥t pháº£i nÃ³i cho thu ngÃ¢n biáº¿t tá» giáº¥y
  /// Ä‘Ã³ chÆ°a ra, kÃ¨m tÃªn mÃ¡y in Ä‘á»ƒ cÃ²n kiá»ƒm tra hoáº·c in láº¡i.
  void _notifyHangWithoutQueue(_HangWatch watch) {
    final ref = watch.referenceNo?.trim() ?? '';
    NotificationOverlayManager().showError(
      title: '${_documentLabel(watch.documentType)} chÆ°a in',
      message: ref.isEmpty
          ? 'MÃ¡y ${watch.printerName} khÃ´ng pháº£n há»“i â€” kiá»ƒm tra mÃ¡y in rá»“i in láº¡i'
          : '$ref â†’ ${watch.printerName} khÃ´ng pháº£n há»“i â€” in láº¡i náº¿u cáº§n',
      relatedEntityType: kPosPrintNotifyKind,
    );
  }

  static String _documentLabel(String documentType) => switch (documentType) {
        'SaleInvoice' => 'HÃ³a Ä‘Æ¡n',
        'SaleReturn' => 'Phiáº¿u tráº£',
        'KitchenSlip' => 'Phiáº¿u báº¿p',
        'KitchenVoid' => 'Phiáº¿u há»§y báº¿p',
        'KitchenLabel' => 'Tem',
        'BarcodeLabel' => 'Tem mÃ£ váº¡ch',
        'StockIssue' => 'Phiáº¿u kho',
        _ => 'Chá»©ng tá»«',
      };

  void _finishJob(String jobId, _JobOutcome outcome, {bool showFeedback = true}) {
    _hangTimers.remove(jobId)?.cancel();
    // ThÃ nh cÃ´ng / Cancelled: bá» treo. Failed/Expired: gá»i onHang (fire-and-forget
    // trÆ°á»›c Ä‘Ã¢y cancel hang â†’ máº¥t phiáº¿u treo dÃ¹ job Ä‘Ã£ Failed).
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
        title: 'In thÃ nh cÃ´ng',
        message: name.isNotEmpty ? name : 'ÄÃ£ in xong trÃªn Print Agent',
        relatedEntityType: kPosPrintNotifyKind,
      );
      return;
    }
    if (outcome.isCancelled && !queueExpired) {
      return;
    }
    NotificationOverlayManager().showError(
      title: queueExpired ? 'Phiáº¿u in chÆ°a ra giáº¥y' : 'In tháº¥t báº¡i',
      message: outcome.error ?? 'KhÃ´ng in Ä‘Æ°á»£c chá»©ng tá»«',
      relatedEntityType: kPosPrintNotifyKind,
    );
  }

  static bool _isQueueExpiredError(String? error) {
    final e = (error ?? '').toLowerCase();
    return e.contains('quÃ¡ háº¡n hÃ ng Ä‘á»£i') ||
        e.contains('stale_queued') ||
        e.contains('offline quÃ¡ 5') ||
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

    // Agent nháº£ job (Queued láº¡i) â€” tiáº¿p tá»¥c chá», khÃ´ng bÃ¡o tháº¥t báº¡i.
    if (status == 'Queued') return;

    if (status == 'Completed' ||
        (acceptClaimed && (status == 'Claimed' || status == 'Printing'))) {
      // Claimed/Printing chá»‰ OK khi caller cho phÃ©p (hÃ³a Ä‘Æ¡n thÆ°á»ng).
      // Phiáº¿u báº¿p: báº¯t Completed â€” trÃ¡nh bÃ¡o thÃ nh cÃ´ng rá»“i Agent fail â†’ sÃ³t báº¿p.
      _finishJob(
        jobId,
        _JobOutcome(true, null, printerName: printerName),
        showFeedback: showFeedback,
      );
    } else if (status == 'Cancelled') {
      // Cancelled = server-side cancel (operator / idempotency / replaced).
      // KhÃ´ng Ä‘Æ°a vÃ o pending queue â€” khÃ´ng bÃ¡o tháº¥t báº¡i giáº£.
      // Trá»« há»§y vÃ¬ Agent treo / háº¿t háº¡n hÃ ng Ä‘á»£i: giáº¥y KHÃ”NG ra mÃ  im láº·ng thÃ¬
      // báº¿p máº¥t mÃ³n. Coi nhÆ° tháº¥t báº¡i Ä‘á»ƒ thu ngÃ¢n tháº¥y phiáº¿u chá» vÃ  in láº¡i.
      if (_isNothingPrintedCancel(errorCode)) {
        _finishJob(
          jobId,
          _JobOutcome(
            false,
            'Phiáº¿u chÆ°a in â€” mÃ¡y in/Agent offline quÃ¡ 5 phÃºt. In láº¡i tá»« hÃ ng chá».',
            printerName: printerName,
          ),
          showFeedback: true,
        );
        return;
      }
      _cancelledJobs.add(jobId);
      _finishJob(
        jobId,
        _JobOutcome(false, error ?? 'Lá»‡nh in Ä‘Ã£ bá»‹ há»§y phÃ­a mÃ¡y chá»§',
            printerName: printerName, isCancelled: true),
        showFeedback: showFeedback,
      );
    } else if (status == 'Failed' || status == 'Expired') {
      _finishJob(
        jobId,
        _JobOutcome(false, error ?? 'In tháº¥t báº¡i', printerName: printerName),
        showFeedback: showFeedback,
      );
    }
  }

  /// Há»§y do server dá»n hÃ ng Ä‘á»£i â€” cháº¯c cháº¯n chÆ°a cÃ³ giáº¥y nÃ o ra.
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

  /// ÄÃ¡nh dáº¥u outbound chá»‰ khi mÃ¡y nÃ y KHÃ”NG pháº£i Agent cá»§a [printerId].
  /// A6 vá»«a gá»­i vá»«a Agent: mark â†’ OUTBOUND_SKIP â†’ khÃ´ng ra giáº¥y.
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

  /// Äá»•i mÃ¡y device-local â†’ báº£n cloud/Agent cÃ¹ng cá»•ng (USB/LAN/BT/Sunmi).
  /// Job gá»­i ID ná»™i bá»™ sáº½ khÃ´ng Ä‘Æ°á»£c Agent claim.
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
      // Chá»‰ map sang twin Sunmi cÃ¹ng tÃªn â€” khÃ´ng láº¥y mÃ¡y Agent/LAN báº¥t ká»³.
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
        'Print remap device-local ${printer.id} â†’ cloud ${twin.id} (${twin.name})',
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
    if (n.toLowerCase().startsWith('[ná»™i bá»™]')) {
      n = n.substring('[ná»™i bá»™]'.length).trim();
    }
    return n.toLowerCase();
  }

  PosStorePrinter? resolvePrinter(String documentType) {
    final list = resolvePrinters(documentType);
    return list.isEmpty ? null : list.first;
  }

  /// Táº¥t cáº£ mÃ¡y in gÃ¡n cho loáº¡i chá»©ng tá»« (in Ä‘a mÃ¡y).
  /// KhÃ´ng fallback mÃ¡y máº·c Ä‘á»‹nh / mÃ¡y duy nháº¥t â€” trÃ¡nh hÃ³a Ä‘Æ¡n nháº­n bÃ¡o báº¿p.
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
    // HÃ³a Ä‘Æ¡n: chá»‰ 1 mÃ¡y (trÃ¡nh 2 báº£n ghi Â«sunmiÂ» cÃ¹ng SaleInvoice â†’ in 2 liÃªn).
    if (documentType == PosCloudDocumentTypes.saleInvoice &&
        unique.length > 1) {
      final defaults = unique.where((p) => p.isDefault).toList();
      if (defaults.isNotEmpty) return [defaults.first];
      debugPrint(
        'SaleInvoice: ${unique.length} mÃ¡y â†’ chá»‰ in Â«${unique.first.name}Â» '
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

  /// Gá»­i byte ESC/POS qua cloud (MÃ¡y in cá»­a hÃ ng â†’ Print Agent).
  ///
  /// [forceCloud]: bá» qua in trá»±c tiáº¿p trÃªn Agent â€” luÃ´n enqueue cloud
  /// (dÃ¹ng cho Â«Test in qua cloudÂ» trÃªn chÃ­nh mÃ¡y Sunmi).
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

      // CÃ³ cá»•ng tháº­t trÃªn mÃ¡y nÃ y â†’ in local (khÃ´ng cáº§n báº­t Agent).
      // A7/web khÃ´ng cáº¯m mÃ¡y â†’ false â†’ cloud cho Agent.
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
        debugPrint('Kitchen DBG dispatchEscPos: ABORT â€” hasCloud=false');
        return false;
      }

      // Test qua cloud trÃªn chÃ­nh mÃ¡y Agent (Zywell USB/LAN/BT): pause claim
      // NGAY trÆ°á»›c khi táº¡o job â€” trÃ¡nh SignalR/timer claim job nÃ y song song
      // vá»›i nhÃ¡nh in ná»™i bá»™ bÃªn dÆ°á»›i (in ra 2 báº£n cÃ¹ng lÃºc).
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
            title: 'KhÃ´ng gá»­i lá»‡nh in',
            message: res['message']?.toString() ?? 'Lá»—i mÃ¡y chá»§',
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

      // Fail nhanh khi cháº¯c cháº¯n khÃ´ng cÃ³ Agent nÃ o online cho mÃ¡y in nÃ y â€”
      // trÃ¡nh bÃ¡o "ÄÃ£ gá»­i lá»‡nh in" giáº£ khi job sáº½ náº±m hÃ ng Ä‘á»£i rá»“i tá»± há»§y
      // sau 20 phÃºt mÃ  khÃ´ng ai biáº¿t (trang lÆ°u hÃ³a Ä‘Æ¡n "in khÃ´ng ra").
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

      // A6 vá»«a gá»­i vá»«a Agent: khÃ´ng mark outbound (OUTBOUND_SKIP).
      await _registerCloudJobForAgent(jobId: jobId, printerId: printer.id);

      _jobMeta[jobId] = _JobFeedbackMeta(
        referenceNo: referenceNo,
        printerName: printer.name,
      );

      if (showFeedback) {
        final ref = referenceNo?.trim() ?? '';
        NotificationOverlayManager().show(
          title: 'ÄÃ£ gá»­i lá»‡nh in',
          message: ref.isNotEmpty
              ? 'ÄÆ¡n $ref â†’ ${printer.name}'
              : 'ÄÃ£ gá»­i tá»›i Print Agent (${printer.name})',
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
        // KhÃ´ng cháº·n UI. KhÃ´ng toast lá»—i ná»n â€” trÆ°á»›c Ä‘Ã¢y showFeedback:true khiáº¿n
        // bÃ¡o Â«In tháº¥t báº¡iÂ» dÃ¹ Agent Ä‘Ã£ in (race reclaim/DUP/timeout sau giáº¥y ra).
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

  /// In cÃ¹ng lÃºc lÃªn má»i mÃ¡y in Ä‘Æ°á»£c gÃ¡n cho [documentType].
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
          title: okCount > 1 ? 'ÄÃ£ gá»­i lá»‡nh in ($okCount mÃ¡y)' : 'ÄÃ£ gá»­i lá»‡nh in',
          message: ref.isNotEmpty ? 'ÄÆ¡n $ref â†’ $names' : names,
          type: NotificationType.success,
          duration: const Duration(seconds: 4),
        );
      }
      if (failCount > 0) {
        NotificationOverlayManager().showError(
          title: 'In tháº¥t báº¡i',
          message: failCount == printers.length
              ? 'KhÃ´ng in Ä‘Æ°á»£c trÃªn mÃ¡y in Ä‘Ã£ chá»n'
              : '$failCount/${printers.length} mÃ¡y in khÃ´ng in Ä‘Æ°á»£c',
        );
      }
    }

    return okCount > 0;
  }

  /// In hÃ³a Ä‘Æ¡n qua cloud â€” Sunmi dÃ¹ng native (giá»‘ng mÃ¡y in ná»™i bá»™), mÃ¡y khÃ¡c ESC/POS.
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
    /// In láº¡i chá»n mÃ¡y â€” chá»‰ gá»­i Ä‘Ãºng mÃ¡y nÃ y (bá» route máº·c Ä‘á»‹nh).
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
      // Sau TT: 1 mÃ¡y Ä‘á»§ â€” trÃ¡nh Sunmi + USB cÃ¹ng role â†’ lÃºc 1 lÃºc 2 bill.
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
        // TrÃ¡nh in 2 láº§n: settings copies=1 nhÆ°ng route defaultCopies=2 (hoáº·c ngÆ°á»£c).
        final n = (routeN < copies ? routeN : copies).clamp(1, 10);
        // Web: luÃ´n enqueue cloud (Agent Android nháº­n in). KhÃ´ng native/local.
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
          // A7/web â†’ Agent Sunmi: JSON native. EscPosBase64 bá»‹ Agent tá»« chá»‘i
          // (UNSUPPORTED_ON_SUNMI) â€” mÃ¡y Â«nháº­n lá»‡nhÂ» nhÆ°ng khÃ´ng ra giáº¥y.
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
          title: okCount > 1 ? 'ÄÃ£ gá»­i lá»‡nh in ($okCount mÃ¡y)' : 'ÄÃ£ gá»­i lá»‡nh in',
          message: ref.isNotEmpty ? 'ÄÆ¡n $ref â†’ $names' : names,
          type: NotificationType.success,
          duration: const Duration(seconds: 3),
          relatedEntityType: kPosPrintNotifyKind,
        );
      }
      if (failCount > 0) {
        NotificationOverlayManager().showError(
          title: 'In tháº¥t báº¡i',
          message: failCount == printers.length
              ? 'KhÃ´ng in Ä‘Æ°á»£c trÃªn mÃ¡y in Ä‘Ã£ chá»n'
              : '$failCount/${printers.length} mÃ¡y in khÃ´ng in Ä‘Æ°á»£c',
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
        title: 'ÄÃ£ nháº­n lá»‡nh in',
        message: ref.isNotEmpty
            ? 'ÄÆ¡n $ref â€” Ä‘ang in trÃªn ${printer.name}â€¦'
            : 'Äang in trÃªn ${printer.name}â€¦',
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
          message: ref.isNotEmpty ? 'ÄÆ¡n $ref â€” ${printer.name}' : printer.name,
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
        title: 'In tháº¥t báº¡i',
        message: tr('KhÃ´ng in Ä‘Æ°á»£c trÃªn ${printer.name}'),
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
    // Gá»­i kÃ¨m full order â€” Agent in native giá»‘ng Oppo, khÃ´ng phá»¥ thuá»™c getPosSale.
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
          title: 'KhÃ´ng gá»­i lá»‡nh in',
          message: res['message']?.toString() ?? 'Lá»—i mÃ¡y chá»§',
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
        title: 'ÄÃ£ gá»­i lá»‡nh in',
        message: ref.isNotEmpty
            ? 'ÄÆ¡n $ref â†’ ${printer.name}'
            : 'ÄÃ£ gá»­i tá»›i Print Agent (${printer.name})',
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

  /// KhÃ´ng há»§y job khi heartbeat Agent Â«lá»‡chÂ» â€” demopos tÃ¡i hiá»‡n:
  /// `agentOnlineForPrinter=0` nhÆ°ng Agent váº«n Claim + in trong vÃ i giÃ¢y.
  /// Fail-fast cÅ© â†’ UI Â«ÄÃ£ bÃ¡o báº¿p â€” chÆ°a in phiáº¿uÂ» dÃ¹ giáº¥y Ä‘Ã£ ra.
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
    // Chá»‰ cáº£nh bÃ¡o má»m â€” váº«n chá» Claimed/Printing/Completed.
    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'Äang chá» Print Agentâ€¦',
        message: tr(
            '${printer.name}: chÆ°a tháº¥y heartbeat tÆ°Æ¡i â€” váº«n gá»­i lá»‡nh, má»Ÿ app Agent náº¿u lÃ¢u khÃ´ng in.'),
        duration: const Duration(seconds: 4),
        relatedEntityType: kPosPrintNotifyKind,
      );
    }
    return false;
  }

  /// Phiáº¿u xuáº¥t kho / bÃ¡o cháº¿ biáº¿n kho â†’ Agent Sunmi native (khÃ´ng ESC/POS).
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
          title: 'KhÃ´ng gá»­i phiáº¿u kho',
          message: res['message']?.toString() ?? 'Lá»—i mÃ¡y chá»§',
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

  /// In phiáº¿u bÃ¡o cháº¿ biáº¿n / há»§y â€” Sunmi dÃ¹ng native (UTF-8), mÃ¡y khÃ¡c ESC/POS.
  ///
  /// [preferDirectPrint]: in láº¡i / chá»n mÃ¡y â€” Æ°u tiÃªn in tháº³ng trÃªn thiáº¿t bá»‹ nÃ y
  /// (khÃ´ng báº¯t buá»™c Agent Ä‘Ã£ gÃ¡n mÃ¡y), rá»“i má»›i fallback cloud.
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
    /// A7 / mÃ¡y thu ngÃ¢n: luÃ´n enqueue cloud (khÃ´ng thá»­ USB/LAN local).
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
            title: successTitle ?? (isCancel ? 'Há»§y báº¿p' : 'BÃ¡o báº¿p'),
            message: '${printer.name} Â· ${lines.length} phiáº¿u',
          );
        } else {
          NotificationOverlayManager().showError(
            title: 'In tháº¥t báº¡i',
            message: tr('KhÃ´ng in háº¿t mÃ³n trÃªn ${printer.name}'),
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
      // BÃ¡o báº¿p thÆ°á»ng showFeedback=true; sau TT cÃ³ thá»ƒ false â€” váº«n cáº£nh bÃ¡o
      // Ä‘á»ƒ user biáº¿t vÃ¬ sao láº§n 2 khÃ´ng in.
      _notifyPrintDedupSkip();
      return true;
    }

    final isAgent =
        !kIsWeb && await PosPrintRole.isAgentForPrinter(printer.id);
    final onSunmiHw = !kIsWeb && await PosPrinterTransport.isSunmiDevice();
    final canLocal = !kIsWeb && await _canDispatchLocallyNow(printer);
    // CÃ³ cá»•ng trÃªn mÃ¡y nÃ y â†’ in local dÃ¹ Agent táº¯t. forceCloud chá»‰ khi
    // Â«Test qua cloudÂ» (mÃ¡y khÃ¡c in há»™). KhÃ´ng cÃ³ cá»•ng â†’ JSON cho Agent.
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

    // MÃ¡y in trong Sunmi: chá»‰ khi Ä‘Ã­ch tháº­t sá»± lÃ  Sunmi VÃ€ khÃ´ng map sang
    // cá»•ng USB/LAN (A6 hay gÃ¡n nháº§m chip sunmi â†’ phiáº¿u preset khÃ¡c máº«u gá»‘c).
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
        'Kitchen DBG: bá» native Sunmi â€” ${printer.name} map cá»•ng '
        '${ownedLocal!.connectionType} (${ownedLocal.name})',
      );
    }

    // In local trÃªn thiáº¿t bá»‹ nÃ y (USB/BT/LAN ná»™i bá»™) khi khÃ´ng force cloud.
    // Cloud/Agent: luÃ´n KitchenSlipJson â€” payload nhá»; Agent tá»± dá»±ng ESC/POS.
    // TrÆ°á»›c Ä‘Ã¢y A7 compile EscPos bitmap VN rá»“i gá»­i base64: 2+ mÃ³n ráº¥t náº·ng â†’
    // Agent USB cháº­m/timeout â†’ phiáº¿u treo; há»§y tá»«ng mÃ³n (payload nhá») láº¡i in Ä‘Æ°á»£c.
    if (!effectiveForceCloud && !kIsWeb) {
      final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
      final table = tableName.trim().isEmpty ? 'BÃ n' : tableName.trim();
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
          'Kitchen DBG: on-device local fail ${printer.name} â€” fallback cloud JSON',
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
            'Kitchen DBG: agent direct fail ${printer.name} â€” fallback cloud JSON',
          );
        }
      }
    }

    debugPrint(
      'Kitchen DBG: cloud KitchenSlipJson â†’ ${printer.name} '
      '(${lines.length} mÃ³n, forceCloud=$effectiveForceCloud)',
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
      tableName: tableName.trim().isEmpty ? 'BÃ n' : tableName.trim(),
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
          title: successTitle ?? (isCancel ? 'Há»§y báº¿p' : 'BÃ¡o báº¿p'),
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
        title: 'In tháº¥t báº¡i',
        message: tr('KhÃ´ng in Ä‘Æ°á»£c trÃªn ${printer.name}'),
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
      // Idempotency server (ReferenceNo + active job) â€” chá»‘ng báº¥m nhiá»u láº§n.
      referenceId: null,
      printerId: printer.id,
    );
    if (res['isSuccess'] != true) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'KhÃ´ng gá»­i lá»‡nh in',
          message: res['message']?.toString() ?? 'Lá»—i mÃ¡y chá»§',
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
        title: isCancel ? 'Há»§y báº¿p' : 'BÃ¡o báº¿p',
        message: ref.isNotEmpty
            ? '$ref â†’ ${printer.name}'
            : 'ÄÃ£ gá»­i tá»›i Print Agent (${printer.name})',
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
        relatedEntityType: kPosPrintNotifyKind,
      );
    }
    if (!waitForCompletion) {
      // KhÃ´ng coi Claimed = OK: webâ†’A6 hay káº¹t Claimed rá»“i STUCK/Busy,
      // toast Â«Ä‘Ã£ inÂ» giáº£ + phiáº¿u há»§y khÃ´ng ra giáº¥y.
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
    // Phiáº¿u báº¿p: chá»‰ Completed má»›i OK â€” Claimed sá»›m dá»… Ä‘á»ƒ job káº¹t rá»“i reclaim in trÃ¹ng.
    final outcome = await _waitJob(
      jobId,
      showFeedback: showFeedback,
      acceptClaimedAsSuccess: false,
    );
    PosPrintSessionRegistry.clearOutbound(jobId);
    return outcome.ok;
  }

  /// Phiáº¿u ra mÃ³n / tráº£ mÃ³n KDS â€” layout kiá»ƒu bÃ¡o cháº¿ biáº¿n, tá»‘i giáº£n giáº¥y.
  /// [lines] gom nhiá»u mÃ³n cÃ¹ng bÃ n thÃ nh 1 phiáº¿u.
  Future<bool> dispatchKdsReadySlip({
    required PosStorePrinter printer,
    required String tableName,
    String? areaName,
    String? orderNo,
    DateTime? readyAt,
    /// Má»™t mÃ³n (tÆ°Æ¡ng thÃ­ch cÅ©) â€” dÃ¹ng khi [lines] rá»—ng.
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
            'note': 'Gá»i ${_hhmm(it.calledAt)} Â· Ra ${_hhmm(at)}',
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

  /// In trá»±c tiáº¿p trÃªn thiáº¿t bá»‹ Agent (mÃ¡y in gáº¯n táº¡i Ä‘Ã¢y).
  Future<bool> _printDirectOnStorePrinter({
    required PosStorePrinter printer,
    required List<int> bytes,
    required int copies,
    String? referenceNo,
    bool showFeedback = true,
    String? successTitle,
  }) async {
    // Giá»‘ng Agent: Æ°u tiÃªn cáº¥u hÃ¬nh mÃ¡y ná»™i bá»™ (id hoáº·c khá»›p cá»•ng USB/BT/LAN).
    final local =
        await PosLocalPrintersStore.instance.resolveForStorePrinter(printer);
    final settings = local != null
        ? local.toThermalSettings()
        : toThermalSettings(printer);
    final ref = referenceNo?.trim() ?? '';

    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'ÄÃ£ nháº­n lá»‡nh in',
        message: ref.isNotEmpty
            ? 'ÄÆ¡n $ref â€” Ä‘ang in trÃªn ${printer.name}â€¦'
            : 'Äang in trÃªn ${printer.name}â€¦',
        duration: const Duration(seconds: 4),
      );
    }

    // TÃ´n trá»ng feed cáº¥u hÃ¬nh mÃ¡y (khÃ´ng Ã©p 4 dÃ²ng riÃªng cho Sunmi).
    final sunmiFeed = settings.resolvedFeedBeforeCut;

    var ok = true;
    // Tem TSPL Ä‘Ã£ cÃ³ PRINT trong payload â€” khÃ´ng nhÃ¢n báº£n theo copies job.
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
              ? 'ÄÆ¡n $ref â€” ${printer.name}'
              : printer.name,
        );
      }
      return true;
    }

    unawaited(_api.reportPosPrinterHealth(
      printer.id,
      status: 'Offline',
      errorMessage: 'KhÃ´ng káº¿t ná»‘i Ä‘Æ°á»£c mÃ¡y in',
    ));
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'In tháº¥t báº¡i',
        message: tr('KhÃ´ng káº¿t ná»‘i Ä‘Æ°á»£c ${printer.name}'),
      );
    }
    return false;
  }

  /// In trá»±c tiáº¿p trÃªn thiáº¿t bá»‹ nÃ y (Thiáº¿t láº­p mÃ¡y in nhiá»‡t â€” LAN/BT/USB cá»¥c bá»™).
  ///
  /// Náº¿u [documentRole] cÃ³: in tá»›i **táº¥t cáº£** mÃ¡y ná»™i bá»™ mang vai trÃ² Ä‘Ã³.
  /// KhÃ´ng cÃ³ role: dÃ¹ng [settingsOverride] hoáº·c singleton legacy.
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
              title: 'In tháº¥t báº¡i',
              message: tr('KhÃ´ng káº¿t ná»‘i Ä‘Æ°á»£c mÃ¡y in cá»¥c bá»™'),
            );
          }
          return false;
        }
      }
      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'In thÃ nh cÃ´ng',
          message: tr('MÃ¡y in cá»¥c bá»™ (cÃ¹ng máº¡ng)'),
        );
      }
      return true;
    }

    if (!waitForCompletion) {
      return run();
    }
    return run();
  }

  /// In tá»›i má»i mÃ¡y ná»™i bá»™ cÃ³ [role] (SaleInvoice / KitchenSlip / StockIssueâ€¦).
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
      // KhÃ´ng fallback singleton â€” trÃ¡nh mÃ¡y chá»‰ hÃ³a Ä‘Æ¡n váº«n nháº­n bÃ¡o báº¿p.
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
          // Má»™t mÃ¡y Ä‘á»§ â€” trÃ¡nh in Ä‘Ã´i khi nhiá»u profile cÃ¹ng role.
          anyOk = true;
          break;
        }
      }
      if (!anyOk && showFeedback) {
        NotificationOverlayManager().showError(
          title: 'In tháº¥t báº¡i',
          message: tr('KhÃ´ng káº¿t ná»‘i Ä‘Æ°á»£c mÃ¡y in ná»™i bá»™ ($role)'),
        );
      } else if (anyOk && showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'In thÃ nh cÃ´ng',
          message: tr('MÃ¡y in ná»™i bá»™'),
        );
      }
      return anyOk;
    }

    if (!waitForCompletion) {
      // LuÃ´n await â€” soft-OK (unawaited+true) gÃ¢y lÃºc in lÃºc khÃ´ng.
      return run();
    }
    return run();
  }

  /// In theo mÃ¡y gÃ¡n sáº£n pháº©m: náº¿u lÃ  mÃ¡y ná»™i bá»™ trÃªn thiáº¿t bá»‹ nÃ y â†’ local;
  /// ngÆ°á»£c láº¡i tráº£ false Ä‘á»ƒ caller Ä‘i cloud/agent.
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
          'Local print blocked: usb khÃ´ng khá»›p cá»•ng '
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
        // Soft-timeout: náº¿u Agent Ä‘Ã£ nháº­n (Claimed/Printing) thÃ¬ coi OK â€”
        // trÃ¡nh bÃ¡o lá»—i sau khi giáº¥y Ä‘Ã£ ra mÃ  Complete cháº­m.
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
                'Print Agent khÃ´ng nháº­n lá»‡nh trong 120 giÃ¢y. '
                'Kiá»ƒm tra Sunmi: Agent Báº¬T + Ä‘Ã£ chá»n chip mÃ¡y in + app Ä‘ang má»Ÿ.',
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
    for (var i = 0; i < 24; i++) {  // 24 Ã— 5s = 120s, match _jobTimeout
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
                  'Phiáº¿u chÆ°a in â€” mÃ¡y in/Agent offline quÃ¡ 5 phÃºt. In láº¡i tá»« hÃ ng chá».'),
              showFeedback: true,
            );
            continue;
          }
          _cancelledJobs.add(jobId);
          _finishJob(
            jobId,
            _JobOutcome(false, err ?? 'Lá»‡nh in Ä‘Ã£ bá»‹ há»§y phÃ­a mÃ¡y chá»§',
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
          // Agent Ä‘Ã£ nháº­n â€” coi thÃ nh cÃ´ng ngay (khÃ´ng chá» i>=2 ~15s).
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
        successTitle: 'In tem thÃ nh cÃ´ng',
        skipDedup: skipDedup,
        // KhÃ´ng coi Claimed = OK â€” tem USB/TSPL hay káº¹t rá»“i timeout.
        waitForCompletion: false,
        acceptClaimedAsSuccess: false,
      );
      if (!ok) return false;
    }
    return true;
  }

  /// [forceRemote]: bá» qua in native cá»¥c bá»™ â€” gá»­i cloud nhÆ° mÃ¡y thu ngÃ¢n (Oppo).

  /// In thá»­ máº«u V2 qua Agent (Sunmi native / ESC) â€” gá»­i Ä‘Ãºng draft editor.
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

    // Cá»•ng local trÃªn mÃ¡y nÃ y â†’ in tháº³ng, khÃ´ng qua cloud.
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
          tableName: km['tableName']?.toString() ?? 'BÃ n',
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
        successTitle: successTitle ?? 'In thá»­',
      );
    }

    if (!hasCloud) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'In thá»­ tháº¥t báº¡i',
          message: tr('ChÆ°a cáº¥u hÃ¬nh in cloud / Print Agent'),
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
          title: 'KhÃ´ng gá»­i lá»‡nh in',
          message: res['message']?.toString() ?? 'Lá»—i mÃ¡y chá»§',
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
        title: successTitle ?? 'In thá»­',
        message: tr('ÄÃ£ gá»­i máº«u â†’ Agent (${printer.name})'),
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
      // A7 Â«Test qua cloudÂ» / khÃ´ng gáº¯n USB tem â†’ Ä‘áº©y Agent (TSPL), khÃ´ng in local.
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

    // Sunmi trÃªn chÃ­nh mÃ¡y â†’ in native cá»¥c bá»™ (khÃ´ng qua cloud).
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

    // Chip Sunmi (Oppo / hoáº·c Â«Test qua cloudÂ» trÃªn V2s) â†’ JSON native trÃªn Agent.
    // TrÃ¡nh ESC/POS (lá»—i font / in ra lá»‡nh ESC @â€¦ / láº§n 2 bá»‹ dedup).
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

  /// Test in Sunmi qua cloud â€” Agent in native UTF-8.
  Future<bool> _enqueueTestPrintJson({
    required PosStorePrinter printer,
    bool forceCloud = false,
    bool showFeedback = true,
  }) async {
    await ensureListening();
    final hasCloud = await refreshConfig();

    // Agent trÃªn chÃ­nh mÃ¡y + khÃ´ng forceCloud â†’ native trá»±c tiáº¿p.
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
          title: 'Test tháº¥t báº¡i',
          message: tr('ChÆ°a cáº¥u hÃ¬nh in cloud / Print Agent'),
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

    // TrÃªn chÃ­nh mÃ¡y Agent (V2s): pause claim NGAY trÆ°á»›c khi táº¡o job â€”
    // trÃ¡nh SignalR/timer claim + in song song vá»›i nhÃ¡nh in ná»™i bá»™ bÃªn dÆ°á»›i
    // (in ra 2 báº£n cÃ¹ng lÃºc).
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

    // Server cÅ© chÆ°a cÃ³ TestPrintJson â†’ EscPos; Agent Sunmi váº«n in native theo prefix TEST-.
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
          title: 'KhÃ´ng gá»­i lá»‡nh in',
          message: res['message']?.toString() ?? 'Lá»—i mÃ¡y chá»§',
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

    // TrÃªn chÃ­nh mÃ¡y Agent (V2s): tá»± claim + in native ngay.
    // KhÃ´ng chá» SignalR/timer â€” hay bá»‹ káº¹t Claimed khiáº¿n Â«test cloud khÃ´ng raÂ».
    if (localTestOnAgent) {
      return _completeCloudTestOnLocalAgent(
        jobId: jobId,
        printer: printer,
        settings: settings,
        showFeedback: showFeedback,
      );
    }

    // KhÃ´ng há»§y job khi heartbeat DB lá»‡ch â€” Agent váº«n Claim Ä‘Æ°á»£c (demopos).
    _failFastNoAgent(printer, data, jobId, showFeedback: showFeedback);

    await _registerCloudJobForAgent(jobId: jobId, printerId: printer.id);
    _jobMeta[jobId] = _JobFeedbackMeta(
      referenceNo: 'TEST',
      printerName: printer.name,
    );

    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'ÄÃ£ gá»­i lá»‡nh in',
        message: 'Test â†’ Print Agent (${printer.name})',
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

  /// V2s vá»«a lÃ  mÃ¡y gá»­i vá»«a lÃ  Agent â€” in ngay, claim/complete nhanh (khÃ´ng chá» 5â€“10s).
  Future<bool> _completeCloudTestOnLocalAgent({
    required String jobId,
    required PosStorePrinter printer,
    required PosThermalPrinterSettings settings,
    bool showFeedback = true,
  }) async {
    final agent = PosPrintAgentService.instance;
    // Heartbeat nháº¹ â€” khÃ´ng refresh toÃ n bá»™ mÃ¡y in.
    await agent.forceRegister(refreshPrinters: false);
    if (!agent.isRegistered || agent.agentId == null) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Test cloud tháº¥t báº¡i',
          message: agent.lastRegisterError ??
              'Agent chÆ°a Ä‘Äƒng kÃ½ server â€” báº­t Agent + chá»n chip mÃ¡y in',
        );
      }
      return false;
    }

    final agentId = agent.agentId!;
    bool sameId(String a, String b) =>
        a.trim().toLowerCase() == b.trim().toLowerCase();

    agent.pauseClaims();
    try {
      // In native trÆ°á»›c â€” ngÆ°á»i dÃ¹ng tháº¥y giáº¥y ngay (~1s).
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
          errorMessage: 'Sunmi native test tháº¥t báº¡i',
        );
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'Test cloud tháº¥t báº¡i',
            message: tr('KhÃ´ng in Ä‘Æ°á»£c trÃªn Sunmi'),
          );
        }
        return false;
      }

      // Claim Ä‘Ãºng job test â€” KHÃ”NG claimNext generic (trÃ¡nh fail SUPERSEDED
      // Ä‘Ã¨ hÃ³a Ä‘Æ¡n/phiáº¿u báº¿p Ä‘ang chá» â†’ sÃ³t bill).
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
        // ÄÃ¡nh Failed Ä‘á»ƒ khÃ´ng bá»‹ Agent in láº§n 2.
        await _api.failPosPrintJob(
          jobId,
          agentId,
          errorCode: 'LOCAL_TEST_DONE',
          errorMessage: 'ÄÃ£ in trÃªn mÃ¡y Agent (claim bá» qua)',
        );
      }
      await _api.reportPosPrinterHealth(printer.id, status: 'Online');

      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: 'Test cloud OK',
          message: '${printer.name} (qua cloud â†’ Agent)',
        );
      }
      return true;
    } finally {
      agent.resumeClaims();
    }
  }

  /// Test EscPos qua cloud trÃªn mÃ¡y Agent (Zywell USB/LAN/BT) â€” in cá»•ng ná»™i bá»™ rá»“i complete job.
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
          title: 'Test cloud tháº¥t báº¡i',
          message: agent.lastRegisterError ??
              'Agent chÆ°a Ä‘Äƒng kÃ½ â€” báº­t Agent + chá»n chip mÃ¡y in',
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
          errorMessage: 'KhÃ´ng káº¿t ná»‘i Ä‘Æ°á»£c ${printer.name} (USB/LAN/BT)',
        );
        await _api.reportPosPrinterHealth(
          printer.id,
          status: 'Offline',
          errorMessage: 'Test cloud tháº¥t báº¡i',
        );
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'Test cloud tháº¥t báº¡i',
            message: tr('KhÃ´ng káº¿t ná»‘i Ä‘Æ°á»£c ${printer.name}'),
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
          errorMessage: 'ÄÃ£ in trÃªn mÃ¡y Agent (claim bá» qua)',
        );
      }
      await _api.reportPosPrinterHealth(printer.id, status: 'Online');

      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'Test cloud OK',
          message: '${printer.name} (qua cloud â†’ Agent)',
        );
      }
      return true;
    } finally {
      agent.resumeClaims();
    }
  }

  /// Cá»•ng in tháº³ng tá»« mÃ¡y gá»­i lá»‡nh: pháº£i cÃ³ profile ná»™i bá»™ khá»›p mÃ¡y
  /// (USB/BT/LAN/Sunmi). KhÃ´ng dÃ¹ng lanHost/USB cloud khi mÃ¡y nÃ y khÃ´ng cáº¯m.
  /// Sunmi built-in: in native náº¿u Ä‘Ã¢y lÃ  mÃ¡y Sunmi.
  /// Public cho mÃ n Máº«u in â€” quyáº¿t Ä‘á»‹nh In thá»­ local vs Agent.
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
    // Bá» android.id ngáº¯n kiá»ƒu "235" â€” dÃ¹ng UUID á»•n Ä‘á»‹nh.
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

  /// Null = caller khÃ´ng dá»±ng phiáº¿u chá» riÃªng; orchestrator chá»‰ bÃ¡o lá»—i.
  final PosPrintHangCallback? onHang;
}

class _JobOutcome {
  const _JobOutcome(this.ok, this.error,
      {this.printerName, this.isCancelled = false});
  final bool ok;
  final String? error;
  final String? printerName;
  /// True when server-side Cancelled â€” caller can suppress re-queue.
  final bool isCancelled;
}

class _JobFeedbackMeta {
  const _JobFeedbackMeta({this.referenceNo, this.printerName});
  final String? referenceNo;
  final String? printerName;
}
