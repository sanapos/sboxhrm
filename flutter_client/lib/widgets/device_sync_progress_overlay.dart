import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'device_sync_types.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

export 'device_sync_types.dart';
export 'device_sync_progress_dialog.dart';

/// Trạng thái một phiên tải dữ liệu từ máy (hiển thị góc dưới màn hình).
class DeviceSyncJob {
  final String id;
  final DeviceSyncKind kind;
  final List<DeviceSyncTarget> devices;

  int deviceIndex = 0;
  int stepIndex = 0;
  double progress = 0.05;
  String statusMessage = 'Đang chuẩn bị...';
  int baselineCount = 0;
  int currentCount = 0;
  int? deviceLocalCount;
  int recordsAdded = 0;
  bool isRunning = true;
  bool hasError = false;
  bool collapsed = false;
  List<DeviceSyncProgressResult> results = [];

  DeviceSyncJob({
    required this.id,
    required this.kind,
    required this.devices,
  });

  DeviceSyncTarget get currentDevice => devices[deviceIndex.clamp(0, devices.length - 1)];

  String get title => kind == DeviceSyncKind.deviceUsers
      ? 'Tải nhân viên từ máy'
      : 'Tải chấm công từ máy';

  int get commandType => kind == DeviceSyncKind.deviceUsers ? 8 : 7;
}

/// Điều phối tải dữ liệu + phát sự kiện cho overlay góc dưới.
class DeviceSyncProgressManager {
  DeviceSyncProgressManager._();
  static final DeviceSyncProgressManager instance = DeviceSyncProgressManager._();

  final List<DeviceSyncJob> _jobs = [];
  final _controller = StreamController<List<DeviceSyncJob>>.broadcast();

  Stream<List<DeviceSyncJob>> get stream => _controller.stream;
  List<DeviceSyncJob> get jobs => List.unmodifiable(_jobs);

  /// Đang tải chấm công từ máy — client không hiện popup SignalR từng lần chấm.
  static bool get suppressAttendancePopups =>
      instance._jobs.any(
        (j) => j.kind == DeviceSyncKind.attendances && j.isRunning,
      );

  /// Sau đăng nhập / reconnect: tạm không hiện thông báo chấm công (tránh nổ log cũ).
  static DateTime? _sessionQuietUntil;

  /// Sau tải log từ máy — màn Chấm công thô mở rộng bộ lọc ngày lần mở tiếp theo.
  static bool pendingWidenAttendanceDateFilter = false;

  /// Luôn mở rộng bộ lọc ngày sau sync — kể cả +0 (log đã có trên server, chỉ lệch preset).
  static void markAttendanceSyncCompleted({bool hadNewRecords = false}) {
    pendingWidenAttendanceDateFilter = true;
  }

  static void activateSessionQuietPeriod([
    Duration duration = const Duration(seconds: 45),
  ]) {
    _sessionQuietUntil = DateTime.now().add(duration);
  }

  /// Chỉ ẩn popup/thông báo hệ thống cho log cũ sau login/reconnect — chấm mới vẫn hiện.
  static bool shouldSuppressAttendancePopup(DateTime attendanceTime) {
    if (suppressAttendancePopups) return true;
    if (_sessionQuietUntil == null ||
        !DateTime.now().isBefore(_sessionQuietUntil!)) {
      return false;
    }
    return !isRecentAttendancePunch(attendanceTime);
  }

  /// Popup + FCM replay sau đăng nhập (không áp dụng lần chấm trong ~20 phút).
  static bool get shouldSuppressAttendanceNotifications {
    if (suppressAttendancePopups) return true;
    if (_sessionQuietUntil != null &&
        DateTime.now().isBefore(_sessionQuietUntil!)) {
      return true;
    }
    return false;
  }

  /// Lần chấm “sống” (máy + đồng hồ client lệch tối đa vài phút).
  static bool isRecentAttendancePunch(
    DateTime attendanceTime, {
    Duration maxAge = const Duration(minutes: 20),
    Duration futureSkew = const Duration(minutes: 3),
  }) {
    final diff = DateTime.now().difference(attendanceTime);
    if (diff.isNegative) return diff.abs() <= futureSkew;
    return diff <= maxAge;
  }

  void _emit() => _controller.add(List.unmodifiable(_jobs));

  void dismiss(String jobId) {
    _jobs.removeWhere((j) => j.id == jobId);
    _emit();
  }

  void toggleCollapsed(String jobId) {
    final job = _jobs.where((j) => j.id == jobId).firstOrNull;
    if (job == null) return;
    job.collapsed = !job.collapsed;
    _emit();
  }

  void _updateJob(DeviceSyncJob job, void Function() fn) {
    fn();
    _emit();
  }

  /// Bắt đầu tải — không chặn UI; panel hiện góc dưới phải.
  Future<List<DeviceSyncProgressResult>> startSync({
    required ApiService apiService,
    required DeviceSyncKind kind,
    required List<DeviceSyncTarget> devices,
    VoidCallback? onDataReady,
  }) async {
    if (devices.isEmpty) return [];

    final job = DeviceSyncJob(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      kind: kind,
      devices: devices,
    );
    _jobs.insert(0, job);
    _emit();

    final results = <DeviceSyncProgressResult>[];
    try {
      for (var i = 0; i < devices.length; i++) {
        _updateJob(job, () => job.deviceIndex = i);
        final r = await _runOne(job, devices[i], apiService);
        results.add(r);
        if (!r.success) {
          _updateJob(job, () => job.hasError = true);
        }
      }
    } finally {
      _updateJob(job, () {
        job.isRunning = false;
        job.stepIndex = 3;
        job.progress = 1;
        job.results = results;
      });
      if (kind == DeviceSyncKind.attendances) {
        markAttendanceSyncCompleted(
          hadNewRecords:
              results.fold<int>(0, (s, r) => s + r.recordsAdded) > 0,
        );
      }
      onDataReady?.call();
      // Tự ẩn sau 12s nếu thành công hoàn toàn (không partial)
      if (results.every((r) => r.success && !r.partialSuccess)) {
        Future.delayed(const Duration(seconds: 12), () => dismiss(job.id));
      }
    }
    return results;
  }

  static const _pollInterval = Duration(seconds: 5);
  static const _pollIntervalStable = Duration(seconds: 15);
  /// Khớp server: đóng lệnh sau 3 phút không nhận log → UI chờ tối đa ~3,5 phút.
  static const _maxWaitSeconds = 210;
  static const _maxWait = Duration(seconds: _maxWaitSeconds);
  /// Máy còn nhiều log hơn server — chỉ tải lâu hơn.
  static const _maxWaitLargeSync = Duration(seconds: 3600);

  static String _attendanceSyncIdleMessage({
    required int serverCount,
    required int baseline,
    int? deviceLocal,
  }) {
    if (deviceLocal != null && deviceLocal > serverCount) {
      final missing = deviceLocal - serverCount;
      return 'Máy lưu $deviceLocal bản ghi, server có $serverCount (thiếu ~$missing). '
          'Máy có thể chỉ gửi lại log cũ (trùng). Thử khởi động lại máy SANA hoặc chấm thử 1 lần; '
          'hệ thống sẽ tự đồng bộ lại mỗi ~2 phút.';
    }
    if (serverCount == baseline) {
      return 'Đã gửi lệnh — chưa thấy bản ghi mới (tổng $serverCount trên server). '
          'Máy có thể chậm hoặc log mới chưa được đẩy lên.';
    }
    return 'Đã gửi lệnh — tổng $serverCount trên server.';
  }

  String? _extractCommandId(Map<String, dynamic> cmdRes) {
    final data = cmdRes['data'];
    if (data is Map) {
      return data['id']?.toString();
    }
    return cmdRes['commandId']?.toString();
  }

  bool _isCommandFailed(Map<String, dynamic>? status) {
    if (status == null) return false;
    final s = status['status']?.toString().toLowerCase() ?? '';
    final ret = status['return']?.toString();
    if (ret == '-1') return true;
    return s == '3' || s == 'failed' || s.contains('failed');
  }

  bool _isCommandSuccess(Map<String, dynamic>? status) {
    if (status == null) return false;
    final s = status['status']?.toString().toLowerCase() ?? '';
    return s == '2' || s == 'success' || s.contains('success');
  }

  String _commandErrorMessage(Map<String, dynamic>? status) {
    if (status == null) return 'Máy chấm công báo lỗi khi thực hiện lệnh';
    final msg = status['errorMessage']?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
    final ret = status['return']?.toString();
    if (ret != null && ret != '0') return 'Máy trả về mã lỗi: $ret';
    return 'Máy chấm công báo lỗi khi thực hiện lệnh';
  }

  Future<int> _countRecords(
    ApiService api,
    DeviceSyncKind kind,
    String deviceId, {
    DateTime? fromTime,
    DateTime? toTime,
  }) async {
    if (kind == DeviceSyncKind.deviceUsers) {
      final users = await api.getDeviceUsers(deviceId: deviceId);
      return users.length;
    }
    return api.getAttendanceLogCount(
      deviceId,
      fromDate: fromTime,
      toDate: toTime,
    );
  }

  Future<DeviceSyncProgressResult> _runOne(
    DeviceSyncJob job,
    DeviceSyncTarget target,
    ApiService api,
  ) async {
    final name = target.deviceName;

    _updateJob(job, () {
      job.stepIndex = 0;
      job.progress = 0.1;
      job.statusMessage = '[$name] ?? Kiểm tra máy online...';
    });

    if (job.kind == DeviceSyncKind.attendances) {
      try {
        final info = await api.getDeviceInfo(target.deviceId);
        final raw = info?['attendanceCount'] ?? info?['AttendanceCount'];
        if (raw is int) {
          job.deviceLocalCount = raw;
        } else if (raw != null) {
          job.deviceLocalCount = int.tryParse(raw.toString());
        }
      } catch (_) {}
    }

    final online = await api.isDeviceOnline(target.deviceId);
    if (!online) {
      _updateJob(job, () {
        job.progress = 1;
        job.statusMessage = '[$name] ?? Máy offline.';
      });
      return DeviceSyncProgressResult(
        success: false,
        message: tr('Thiết bị "$name" đang offline.'),
      );
    }

    final baseline = await _countRecords(
      api,
      job.kind,
      target.deviceId,
      fromTime: target.fromTime,
      toTime: target.toTime,
    );
    _updateJob(job, () {
      job.baselineCount = baseline;
      job.currentCount = baseline;
      job.stepIndex = 1;
      job.progress = 0.25;
      job.statusMessage = '[$name] Đang gửi lệnh...';
    });

    // Server đã đủ so với máy — không gửi lệnh (tránh poll pageSize=1 hàng trăm lần).
    final machineCount = job.deviceLocalCount;
    final serverAlreadyFull = job.kind == DeviceSyncKind.attendances &&
        machineCount != null &&
        machineCount > 0 &&
        baseline >= (machineCount * 0.98).floor();
    if (serverAlreadyFull) {
      final doneMsg =
          'Server đã có đủ $baseline bản ghi (máy ${job.deviceLocalCount})';
      _updateJob(job, () {
        job.stepIndex = 3;
        job.progress = 1;
        job.statusMessage = '[$name] $doneMsg';
      });
      return DeviceSyncProgressResult(
        success: true,
        recordsAdded: 0,
        totalRecords: baseline,
        message: doneMsg,
      );
    }

    final Map<String, dynamic> cmd;
    if (job.kind == DeviceSyncKind.attendances &&
        (target.fromTime != null || target.toTime != null)) {
      cmd = await api.syncAttendances(
        target.deviceId,
        fromTime: target.fromTime,
        toTime: target.toTime,
      );
    } else {
      cmd = await api.sendDeviceCommand(target.deviceId, job.commandType);
    }

    if (cmd['isSuccess'] != true) {
      final msg = cmd['message']?.toString() ?? 'Gửi lệnh thất bại';
      _updateJob(job, () {
        job.progress = 1;
        job.statusMessage = '[$name] $msg';
        job.hasError = true;
      });
      return DeviceSyncProgressResult(success: false, message: msg);
    }

    final commandId = _extractCommandId(cmd);
    final stampNote = cmd['message']?.toString().trim();
    final waitingMsg = (stampNote != null && stampNote.isNotEmpty)
        ? stampNote
        : 'Chờ máy gửi dữ liệu...';

    _updateJob(job, () {
      job.stepIndex = 2;
      job.progress = 0.4;
      job.statusMessage = '[$name] $waitingMsg';
    });

    final started = DateTime.now();
    var elapsed = 0;
    var added = 0;
    var commandDone = false;
    var commandFailed = false;
    String? failMsg;
    final localGap = job.kind == DeviceSyncKind.attendances &&
        job.deviceLocalCount != null &&
        job.deviceLocalCount! > job.baselineCount;
    final maxWait = localGap ? _maxWaitLargeSync : _maxWait;
    final targetLocal = job.deviceLocalCount;
    var stablePolls = 0;
    int? lastPolledCount;

    while (DateTime.now().difference(started) < maxWait) {
      await Future.delayed(_pollInterval);
      elapsed += _pollInterval.inSeconds;

      if (commandId != null) {
        final statusData = await api.getCommandStatus(commandId);
        if (_isCommandFailed(statusData)) {
          commandFailed = true;
          failMsg = _commandErrorMessage(statusData);
          break;
        }
        if (_isCommandSuccess(statusData)) {
          commandDone = true;
        }
      }

      final count = await _countRecords(
        api,
        job.kind,
        target.deviceId,
        fromTime: target.fromTime,
        toTime: target.toTime,
      );
      added = count - job.baselineCount;
      final pct = 0.4 + (elapsed / maxWait.inSeconds) * 0.55;

      _updateJob(job, () {
        job.currentCount = count;
        job.recordsAdded = added > 0 ? added : 0;
        job.progress = pct;
        if (commandFailed) {
          job.statusMessage = '[$name] $failMsg';
        } else if (added > 0) {
          job.statusMessage = '[$name] +$added bản ghi (${elapsed}s)';
        } else if (commandDone) {
          job.statusMessage =
              '[$name] ?? Lệnh hoàn tất — đang kiểm tra dữ liệu (${elapsed}s)';
        } else {
          job.statusMessage = localGap
              ? '[$name] Đang tải lên server: $count / ${job.deviceLocalCount} (${elapsed}s)'
              : '[$name] ?? Chờ máy/ngắt phiên ${elapsed}s (tối đa $_maxWaitSeconds s)';
        }
      });

      if (commandFailed) {
        _updateJob(job, () {
          job.progress = 1;
          job.hasError = true;
        });
        return DeviceSyncProgressResult(
          success: false,
          message: failMsg ?? 'Lệnh đồng bộ thất bại',
        );
      }

      if (lastPolledCount == count) {
        stablePolls++;
      } else {
        stablePolls = 0;
        lastPolledCount = count;
      }

      // Máy và server đã bằng nhau — kết thúc sau ~10s ổn định.
      if (job.kind == DeviceSyncKind.attendances &&
          targetLocal != null &&
          targetLocal > 0 &&
          count >= targetLocal &&
          stablePolls >= 2 &&
          elapsed >= 10) {
        final doneMsg = added > 0
            ? '+$added mới (tổng $count / $targetLocal trên máy)'
            : 'Đã đủ $count bản ghi (khớp máy $targetLocal)';
        _updateJob(job, () {
          job.stepIndex = 3;
          job.progress = 1;
          job.statusMessage = '[$name] $doneMsg';
        });
        return DeviceSyncProgressResult(
          success: true,
          recordsAdded: added > 0 ? added : 0,
          totalRecords: count,
          message: doneMsg,
        );
      }

      // Log lớn trên máy: không kết thúc chỉ vì lệnh Success sớm — chờ đủ bản ghi hoặc server ổn định.
      if (localGap && targetLocal != null && targetLocal > 0) {
        final pctOnDevice = count / targetLocal;
        if (pctOnDevice >= 0.95) {
          final doneMsg =
              '+$added mới (tổng $count / ~$targetLocal trên máy)';
          _updateJob(job, () {
            job.stepIndex = 3;
            job.progress = 1;
            job.statusMessage = '[$name] $doneMsg';
          });
          return DeviceSyncProgressResult(
            success: true,
            recordsAdded: added,
            totalRecords: count,
            message: doneMsg,
          );
        }
        if (stablePolls >= 6 && elapsed >= 120) {
          break;
        }
      } else {
        if (added > 0 && (commandDone || elapsed >= 60)) {
          final doneMsg = '+$added mới (tổng $count)';
          _updateJob(job, () {
            job.stepIndex = 3;
            job.progress = 1;
            job.statusMessage = '[$name] $doneMsg';
          });
          return DeviceSyncProgressResult(
            success: true,
            recordsAdded: added,
            totalRecords: count,
            message: doneMsg,
          );
        }

        if (commandDone && added == 0 && elapsed >= 15) {
          break;
        }

        // Không thêm bản ghi, số server ổn định — xong (không phụ thuộc lệnh Success).
        if (added == 0 && stablePolls >= 2 && elapsed >= 25) {
          final doneMsg = targetLocal != null && count >= targetLocal
              ? 'Đã đủ $count bản ghi (khớp máy $targetLocal)'
              : 'Không có bản ghi mới (tổng $count)';
          _updateJob(job, () {
            job.stepIndex = 3;
            job.progress = 1;
            job.statusMessage = '[$name] $doneMsg';
          });
          return DeviceSyncProgressResult(
            success: true,
            recordsAdded: 0,
            totalRecords: count,
            message: doneMsg,
          );
        }
      }
    }

    final finalCount = await _countRecords(
      api,
      job.kind,
      target.deviceId,
      fromTime: target.fromTime,
      toTime: target.toTime,
    );
    added = finalCount - job.baselineCount;
    _updateJob(job, () {
      job.currentCount = finalCount;
      job.recordsAdded = added > 0 ? added : 0;
    });

    if (added > 0) {
      final target = job.deviceLocalCount;
      final incomplete = target != null &&
          target > 0 &&
          finalCount < (target * 0.9).round();
      final doneMsg = incomplete
          ? '+$added mới (tổng $finalCount / ~$target trên máy) — có thể còn thiếu, thử đồng bộ lại.'
          : '+$added mới (tổng $finalCount)';
      _updateJob(job, () {
        job.stepIndex = 3;
        job.progress = 1;
        job.statusMessage = '[$name] $doneMsg';
      });
      return DeviceSyncProgressResult(
        success: !incomplete,
        partialSuccess: incomplete,
        recordsAdded: added,
        totalRecords: finalCount,
        message: doneMsg,
      );
    }

    final idleMsg = job.kind == DeviceSyncKind.deviceUsers
        ? 'Đã gửi lệnh — $finalCount NV. Kiểm tra Nhân sự chấm công hoặc thử lại sau 2 phút.'
        : _attendanceSyncIdleMessage(
            deviceLocal: job.deviceLocalCount,
            serverCount: finalCount,
            baseline: job.baselineCount,
          );
    _updateJob(job, () {
      job.stepIndex = 3;
      job.progress = 1;
      job.statusMessage = idleMsg;
      job.hasError = true;
    });
    return DeviceSyncProgressResult(
      success: false,
      partialSuccess: true,
      recordsAdded: 0,
      totalRecords: finalCount,
      message: idleMsg,
    );
  }
}

/// Bọc app: panel tải dữ liệu cố định góc dưới, không chặn thao tác màn khác.
class DeviceSyncProgressOverlay extends StatefulWidget {
  final Widget child;

  const DeviceSyncProgressOverlay({super.key, required this.child});

  @override
  State<DeviceSyncProgressOverlay> createState() =>
      _DeviceSyncProgressOverlayState();
}

class _DeviceSyncProgressOverlayState extends State<DeviceSyncProgressOverlay> {
  final _manager = DeviceSyncProgressManager.instance;
  StreamSubscription<List<DeviceSyncJob>>? _sub;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _sub = _manager.stream.listen((_) => _updateOverlay());
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverlay());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  double _bottomInset(BuildContext context) {
    final padding = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    final hasBottomNav = width < 900;
    final nav = hasBottomNav ? kBottomNavigationBarHeight : 0.0;
    return padding + nav + 12;
  }

  void _updateOverlay() {
    if (!mounted) return;

    final jobs = _manager.jobs;
    if (jobs.isEmpty) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      return;
    }

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final isMobile = MediaQuery.sizeOf(overlayContext).width < 600;
        final activeJobs = _manager.jobs;
        if (activeJobs.isEmpty) return const SizedBox.shrink();

        return Positioned(
          left: isMobile ? 8 : null,
          right: 8,
          bottom: _bottomInset(overlayContext),
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children:
                  activeJobs.map((j) => _SyncJobCard(job: j)).toList(),
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SyncJobCard extends StatelessWidget {
  final DeviceSyncJob job;

  const _SyncJobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final mgr = DeviceSyncProgressManager.instance;
    final accent = job.kind == DeviceSyncKind.deviceUsers
        ? const Color(0xFF1E3A5F)
        : const Color(0xFF0284C7);
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final cardWidth = math.min(isMobile ? double.infinity : 340.0,
        MediaQuery.sizeOf(context).width - 24);

    Color statusColor;
    IconData statusIcon;
    if (job.isRunning) {
      statusColor = accent;
      statusIcon = Icons.cloud_download;
    } else if (job.hasError) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    }

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => mgr.toggleCollapsed(job.id),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(job.title),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (job.devices.length == 1)
                          Text(
                            tr(job.currentDevice.deviceName),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          )
                        else
                          Text(tr('Máy ${job.deviceIndex + 1}/${job.devices.length}: ${job.currentDevice.deviceName}'),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      job.collapsed
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                    ),
                    onPressed: () => mgr.toggleCollapsed(job.id),
                    tooltip: tr(job.collapsed ? 'Mở rộng' : 'Thu gọn'),
                  ),
                  if (!job.isRunning)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => mgr.dismiss(job.id),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: job.isRunning
                    ? (job.progress > 0 ? job.progress : null)
                    : 1,
                minHeight: 4,
                backgroundColor: Colors.grey.shade200,
                color: statusColor,
              ),
            ),
          ),
          if (!job.collapsed) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Text(
                tr(job.statusMessage),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade800,
                  height: 1.3,
                ),
              ),
            ),
            if (job.baselineCount > 0 ||
                job.currentCount > 0 ||
                job.deviceLocalCount != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (job.deviceLocalCount != null &&
                        job.kind == DeviceSyncKind.attendances)
                      _chip('Trên máy', '${job.deviceLocalCount}', blue: true),
                    _chip('Server trước', '${job.baselineCount}'),
                    _chip('Server hiện', '${job.currentCount}'),
                    if (job.deviceLocalCount != null &&
                        job.kind == DeviceSyncKind.attendances &&
                        job.deviceLocalCount! > job.currentCount)
                      _chip(
                        'Chưa lên server',
                        '~${job.deviceLocalCount! - job.currentCount}',
                        orange: true,
                      ),
                    if (job.recordsAdded > 0)
                      _chip('Mới', '+${job.recordsAdded}', green: true),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, String value,
      {bool green = false, bool blue = false, bool orange = false}) {
    Color bg = Colors.grey.shade100;
    Color fg = Colors.grey.shade700;
    if (green) {
      bg = Colors.green.withValues(alpha: 0.12);
      fg = Colors.green.shade800;
    } else if (blue) {
      bg = Colors.blue.withValues(alpha: 0.12);
      fg = Colors.blue.shade800;
    } else if (orange) {
      bg = Colors.orange.withValues(alpha: 0.15);
      fg = Colors.orange.shade900;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tr('$label: $value'),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
