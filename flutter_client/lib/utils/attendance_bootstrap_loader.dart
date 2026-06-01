import '../models/attendance.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../utils/work_hours_utils.dart';
import 'attendance_load_utils.dart';

/// Dữ liệu nền cho màn tổng hợp chấm công (thô / theo ca).
class AttendanceBootstrapData {
  final List<Device> devices;
  final List<Attendance> attendances;
  final int dayEndHour;
  final int dayEndMinute;
  final String roundingRule;
  final int lunchBreakMinutes;
  final bool allowManualCorrection;
  final List<dynamic> holidays;
  final List<dynamic> salaryProfiles;
  final List<dynamic> approvedLeaves;
  final List<Map<String, dynamic>> shiftTemplates;
  final List<Map<String, dynamic>> shiftSalaryLevels;

  const AttendanceBootstrapData({
    required this.devices,
    required this.attendances,
    this.dayEndHour = 0,
    this.dayEndMinute = 0,
    this.roundingRule = WorkHoursUtils.roundingNone,
    this.lunchBreakMinutes = 60,
    this.allowManualCorrection = true,
    this.holidays = const [],
    this.salaryProfiles = const [],
    this.approvedLeaves = const [],
    this.shiftTemplates = const [],
    this.shiftSalaryLevels = const [],
  });
}

Future<String?> _appSettingValue(ApiService api, String key) async {
  try {
    final r = await api.getAppSetting(key);
    if (r['isSuccess'] == true && r['data'] is Map) {
      return (r['data'] as Map)['value']?.toString();
    }
  } catch (_) {}
  return null;
}

({int hour, int minute}) _parseDayEnd(String? value) {
  if (value == null || value.isEmpty) return (hour: 0, minute: 0);
  final parts = value.split(':');
  if (parts.length < 2) return (hour: 0, minute: 0);
  return (
    hour: int.tryParse(parts[0]) ?? 0,
    minute: int.tryParse(parts[1]) ?? 0,
  );
}

/// Tải song song thiết bị, cấu hình, log chấm công và dữ liệu phụ trợ.
Future<AttendanceBootstrapData> loadAttendanceBootstrap(
  ApiService api, {
  required DateTime fromDate,
  required DateTime toDate,
  bool loadShiftMeta = false,
  void Function(String message)? onProgress,
}) async {
  onProgress?.call('Đang tải thiết bị và cấu hình...');

  final devicesFuture = api.getDevices(storeOnly: true);
  final dayEndFuture = _appSettingValue(api, 'day_end_time');
  final roundingFuture = _appSettingValue(api, 'rounding_rule');
  final allowManualFuture = _appSettingValue(api, 'allow_manual_correction');
  final salaryFuture = api.getSalarySettings().catchError((_) => <String, dynamic>{});
  final salaryProfilesFuture =
      api.getSalaryProfiles().catchError((_) => <dynamic>[]);
  final holidaysFuture = api.getHolidaySettings(0).catchError((_) => <dynamic>[]);
  final shiftsFuture =
      loadShiftMeta ? api.getShifts().catchError((_) => <dynamic>[]) : Future.value(<dynamic>[]);
  final salaryLevelsFuture = loadShiftMeta
      ? api.getShiftSalaryLevels().catchError((_) => <String, dynamic>{})
      : Future.value(<String, dynamic>{});

  final fromStr = fromDate.toIso8601String().substring(0, 10);
  final toStr = toDate.toIso8601String().substring(0, 10);
  final leavesFuture = api
      .getAllLeaves(
        fromDate: fromStr,
        toDate: toStr,
        status: 'Approved',
        pageSize: 1000,
      )
      .catchError((_) => <String, dynamic>{'isSuccess': false});

  final devicesRaw = await devicesFuture;
  final devices = devicesRaw
      .map((d) => Device.fromJson(d as Map<String, dynamic>))
      .toList();
  final deviceIds = devices.map((d) => d.id).toList();

  final dayEnd = _parseDayEnd(await dayEndFuture);
  final roundingRule =
      await roundingFuture ?? WorkHoursUtils.roundingNone;
  final allowManual = (await allowManualFuture) != 'false';

  final salary = await salaryFuture;
  final lunchBreakMinutes = (salary['lunchBreakMinutes'] as num?)?.toInt() ?? 60;

  List<Attendance> attendances = [];
  if (deviceIds.isNotEmpty) {
    onProgress?.call('Đang tải log chấm công...');
    attendances = await loadAttendancesForPeriod(
      api,
      deviceIds: deviceIds,
      fromDate: fromDate,
      toDate: toDate,
      dayEndHour: dayEnd.hour,
      dayEndMinute: dayEnd.minute,
      onProgress: onProgress,
    );
  }

  onProgress?.call('Đang tải ngày nghỉ, lương, phép...');

  final holidays = await holidaysFuture;
  final salaryProfiles = await salaryProfilesFuture;
  final leavesResult = await leavesFuture;
  List<dynamic> approvedLeaves = [];
  if (leavesResult['isSuccess'] == true) {
    final data = leavesResult['data'];
    if (data is Map) {
      approvedLeaves = (data['items'] as List?) ?? [];
    } else if (data is List) {
      approvedLeaves = data;
    }
  }

  List<Map<String, dynamic>> shiftTemplates = [];
  List<Map<String, dynamic>> shiftSalaryLevels = [];
  if (loadShiftMeta) {
    final shiftsResult = await shiftsFuture;
    shiftTemplates =
        shiftsResult.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    final salaryLevelsResult = await salaryLevelsFuture;
    shiftSalaryLevels = ((salaryLevelsResult['data']?['items'] ??
                salaryLevelsResult['data'] ??
                []) as List)
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
  }

  onProgress?.call('Hoàn tất (${attendances.length} log)');

  return AttendanceBootstrapData(
    devices: devices,
    attendances: attendances,
    dayEndHour: dayEnd.hour,
    dayEndMinute: dayEnd.minute,
    roundingRule: roundingRule,
    lunchBreakMinutes: lunchBreakMinutes,
    allowManualCorrection: allowManual,
    holidays: holidays,
    salaryProfiles: salaryProfiles,
    approvedLeaves: approvedLeaves,
    shiftTemplates: shiftTemplates,
    shiftSalaryLevels: shiftSalaryLevels,
  );
}
