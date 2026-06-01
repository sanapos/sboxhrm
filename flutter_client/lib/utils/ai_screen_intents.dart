import 'package:flutter/foundation.dart';

/// Signals target screens to open a "create" form (from AI assistant actions).
class AiScreenIntents {
  AiScreenIntents._();

  static final ValueNotifier<Map<String, String>?> leave =
      ValueNotifier<Map<String, String>?>(null);
  static final ValueNotifier<Map<String, String>?> advance =
      ValueNotifier<Map<String, String>?>(null);
  static final ValueNotifier<Map<String, String>?> feedback =
      ValueNotifier<Map<String, String>?>(null);
  static final ValueNotifier<Map<String, String>?> attendanceCorrection =
      ValueNotifier<Map<String, String>?>(null);
  static final ValueNotifier<Map<String, String>?> overtime =
      ValueNotifier<Map<String, String>?>(null);
  static final ValueNotifier<Map<String, String>?> meal =
      ValueNotifier<Map<String, String>?>(null);
  static final ValueNotifier<Map<String, String>?> fieldCheckin =
      ValueNotifier<Map<String, String>?>(null);
  static final ValueNotifier<Map<String, String>?> shiftSwap =
      ValueNotifier<Map<String, String>?>(null);

  static void scheduleLeaveCreate([Map<String, String> params = const {}]) {
    leave.value = Map<String, String>.from(params);
  }

  static void scheduleAdvanceCreate([Map<String, String> params = const {}]) {
    advance.value = Map<String, String>.from(params);
  }

  static void scheduleFeedbackCreate([Map<String, String> params = const {}]) {
    feedback.value = Map<String, String>.from(params);
  }

  static void scheduleAttendanceCorrectionCreate(
      [Map<String, String> params = const {}]) {
    attendanceCorrection.value = Map<String, String>.from(params);
  }

  static void scheduleOvertimeCreate([Map<String, String> params = const {}]) {
    overtime.value = Map<String, String>.from(params);
  }

  static void scheduleMealCreate([Map<String, String> params = const {}]) {
    meal.value = Map<String, String>.from(params);
  }

  static void scheduleFieldCheckinCreate(
      [Map<String, String> params = const {}]) {
    fieldCheckin.value = Map<String, String>.from(params);
  }

  static void scheduleShiftSwapCreate([Map<String, String> params = const {}]) {
    shiftSwap.value = Map<String, String>.from(params);
  }

  static Map<String, String>? consumeLeave() => _consume(leave);
  static Map<String, String>? consumeAdvance() => _consume(advance);
  static Map<String, String>? consumeFeedback() => _consume(feedback);
  static Map<String, String>? consumeAttendanceCorrection() =>
      _consume(attendanceCorrection);
  static Map<String, String>? consumeOvertime() => _consume(overtime);
  static Map<String, String>? consumeMeal() => _consume(meal);
  static Map<String, String>? consumeFieldCheckin() => _consume(fieldCheckin);
  static Map<String, String>? consumeShiftSwap() => _consume(shiftSwap);

  static Map<String, String>? _consume(
      ValueNotifier<Map<String, String>?> notifier) {
    final v = notifier.value;
    if (v == null) return null;
    notifier.value = null;
    return Map<String, String>.from(v);
  }

  /// Parse key=value pairs from CREATE tag body (after type prefix).
  static Map<String, String> parseParams(String createTag) {
    final parts = createTag.split(',');
    final params = <String, String>{};
    String? textAccumKey;
    for (final p in parts.skip(1)) {
      final idx = p.indexOf('=');
      if (idx > 0) {
        final key = p.substring(0, idx).trim();
        final val = p.substring(idx + 1).trim();
        if (key == 'reason' || key == 'title' || key == 'content' || key == 'note') {
          textAccumKey = key;
          params[key] = val;
        } else {
          textAccumKey = null;
          params[key] = val;
        }
      } else if (textAccumKey != null) {
        params[textAccumKey] = '${params[textAccumKey]},$p';
      }
    }
    return params;
  }
}
