// Đã chuyển sang gói dùng chung payroll_engine (app + máy chủ cùng một công thức).
import 'package:flutter/painting.dart' show Color;
import 'package:payroll_engine/utils/shift_records_calculator.dart';

export 'package:payroll_engine/utils/shift_records_calculator.dart';

/// Màu trạng thái dạng Flutter (gói dùng chung lưu số ARGB, không phụ thuộc Flutter).
extension DailyShiftRecordStatusColor on DailyShiftRecord {
  Color get statusColor => Color(statusColorValue);
}
