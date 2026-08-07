import 'lunar_converter.dart';

/// Preset khoảng thời gian kiểu KiotViet.
enum PosKiotTimePreset {
  allTime,
  today,
  yesterday,
  thisWeek,
  lastWeek,
  last7Days,
  thisMonth,
  lastMonth,
  thisLunarMonth,
  lastLunarMonth,
  last30Days,
  thisQuarter,
  lastQuarter,
  thisYear,
  lastYear,
  thisLunarYear,
  lastLunarYear,
}

extension PosKiotTimePresetLabel on PosKiotTimePreset {
  String get label => switch (this) {
        PosKiotTimePreset.allTime => 'Toàn thời gian',
        PosKiotTimePreset.today => 'Hôm nay',
        PosKiotTimePreset.yesterday => 'Hôm qua',
        PosKiotTimePreset.thisWeek => 'Tuần này',
        PosKiotTimePreset.lastWeek => 'Tuần trước',
        PosKiotTimePreset.last7Days => '7 ngày qua',
        PosKiotTimePreset.thisMonth => 'Tháng này',
        PosKiotTimePreset.lastMonth => 'Tháng trước',
        PosKiotTimePreset.thisLunarMonth => 'Tháng này (âm lịch)',
        PosKiotTimePreset.lastLunarMonth => 'Tháng trước (âm lịch)',
        PosKiotTimePreset.last30Days => '30 ngày qua',
        PosKiotTimePreset.thisQuarter => 'Quý này',
        PosKiotTimePreset.lastQuarter => 'Quý trước',
        PosKiotTimePreset.thisYear => 'Năm nay',
        PosKiotTimePreset.lastYear => 'Năm trước',
        PosKiotTimePreset.thisLunarYear => 'Năm nay (âm lịch)',
        PosKiotTimePreset.lastLunarYear => 'Năm trước (âm lịch)',
      };
}

class PosKiotTimeFilterState {
  final PosKiotTimePreset preset;
  final bool isCustom;
  final DateTime? customFrom;
  final DateTime? customTo;

  const PosKiotTimeFilterState({
    this.preset = PosKiotTimePreset.thisMonth,
    this.isCustom = false,
    this.customFrom,
    this.customTo,
  });

  factory PosKiotTimeFilterState.thisMonth() =>
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);

  factory PosKiotTimeFilterState.allTime() =>
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.allTime);

  DateTime? get from => resolvedRange.$1;
  DateTime? get to => resolvedRange.$2;

  (DateTime?, DateTime?) get resolvedRange {
    if (isCustom) {
      return (
        customFrom != null ? _startOfDay(customFrom!) : null,
        customTo != null ? _endOfDay(customTo!) : null,
      );
    }
    return resolvePosKiotTimePreset(preset);
  }

  String get displayLabel {
    if (isCustom) {
      if (customFrom == null && customTo == null) return 'Tùy chỉnh';
      final f = customFrom;
      final t = customTo;
      if (f != null && t != null) {
        return '${_fmt(f)} – ${_fmt(t)}';
      }
      if (f != null) return 'Từ ${_fmt(f)}';
      if (t != null) return 'Đến ${_fmt(t)}';
      return 'Tùy chỉnh';
    }
    return preset.label;
  }

  PosKiotTimeFilterState copyWith({
    PosKiotTimePreset? preset,
    bool? isCustom,
    DateTime? customFrom,
    DateTime? customTo,
    bool clearCustomFrom = false,
    bool clearCustomTo = false,
  }) =>
      PosKiotTimeFilterState(
        preset: preset ?? this.preset,
        isCustom: isCustom ?? this.isCustom,
        customFrom: clearCustomFrom ? null : (customFrom ?? this.customFrom),
        customTo: clearCustomTo ? null : (customTo ?? this.customTo),
      );

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

(DateTime?, DateTime?) resolvePosKiotTimePreset(PosKiotTimePreset preset,
    [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = _startOfDay(n);

  switch (preset) {
    case PosKiotTimePreset.allTime:
      return (null, null);
    case PosKiotTimePreset.today:
      return (today, _endOfDay(n));
    case PosKiotTimePreset.yesterday:
      final y = today.subtract(const Duration(days: 1));
      return (y, _endOfDay(y));
    case PosKiotTimePreset.thisWeek:
      final monday = today.subtract(Duration(days: (n.weekday + 6) % 7));
      final sunday = monday.add(const Duration(days: 6));
      return (monday, _endOfDay(sunday));
    case PosKiotTimePreset.lastWeek:
      final thisMon = today.subtract(Duration(days: (n.weekday + 6) % 7));
      final lastMon = thisMon.subtract(const Duration(days: 7));
      final lastSun = lastMon.add(const Duration(days: 6));
      return (lastMon, _endOfDay(lastSun));
    case PosKiotTimePreset.last7Days:
      return (today.subtract(const Duration(days: 6)), _endOfDay(n));
    case PosKiotTimePreset.thisMonth:
      return (
        DateTime(n.year, n.month, 1),
        _endOfDay(DateTime(n.year, n.month + 1, 0)),
      );
    case PosKiotTimePreset.lastMonth:
      final firstThis = DateTime(n.year, n.month, 1);
      final lastDayPrev = firstThis.subtract(const Duration(days: 1));
      return (
        DateTime(lastDayPrev.year, lastDayPrev.month, 1),
        _endOfDay(lastDayPrev),
      );
    case PosKiotTimePreset.last30Days:
      return (today.subtract(const Duration(days: 29)), _endOfDay(n));
    case PosKiotTimePreset.thisQuarter:
      final q = ((n.month - 1) ~/ 3) + 1;
      final qStart = DateTime(n.year, (q - 1) * 3 + 1, 1);
      final qEnd = DateTime(n.year, q * 3 + 1, 0);
      return (qStart, _endOfDay(qEnd));
    case PosKiotTimePreset.lastQuarter:
      final q = ((n.month - 1) ~/ 3) + 1;
      if (q == 1) {
        return (
          DateTime(n.year - 1, 10, 1),
          _endOfDay(DateTime(n.year - 1, 12, 31)),
        );
      }
      final pq = q - 1;
      return (
        DateTime(n.year, (pq - 1) * 3 + 1, 1),
        _endOfDay(DateTime(n.year, pq * 3 + 1, 0)),
      );
    case PosKiotTimePreset.thisYear:
      return (DateTime(n.year, 1, 1), _endOfDay(DateTime(n.year, 12, 31)));
    case PosKiotTimePreset.lastYear:
      return (
        DateTime(n.year - 1, 1, 1),
        _endOfDay(DateTime(n.year - 1, 12, 31)),
      );
    case PosKiotTimePreset.thisLunarMonth:
      return _lunarMonthRange(LunarConverter.solarToLunar(n));
    case PosKiotTimePreset.lastLunarMonth:
      final ld = LunarConverter.solarToLunar(n);
      var ly = ld.year;
      var lm = ld.month - 1;
      if (lm < 1) {
        lm = 12;
        ly--;
      }
      return _lunarMonthRangeByYm(ly, lm);
    case PosKiotTimePreset.thisLunarYear:
      final ly = LunarConverter.solarToLunar(n).year;
      return _lunarYearRange(ly);
    case PosKiotTimePreset.lastLunarYear:
      final ly = LunarConverter.solarToLunar(n).year - 1;
      return _lunarYearRange(ly);
  }
}

(DateTime, DateTime) _lunarMonthRange(LunarDate ld) =>
    _lunarMonthRangeByYm(ld.year, ld.month);

(DateTime, DateTime) _lunarMonthRangeByYm(int lunarYear, int lunarMonth) {
  final start = LunarConverter.lunarToSolar(lunarYear, lunarMonth, 1);
  final days = LunarConverter.lunarMonthDays(lunarYear, lunarMonth);
  final end = LunarConverter.lunarToSolar(lunarYear, lunarMonth, days);
  return (_startOfDay(start), _endOfDay(end));
}

(DateTime, DateTime) _lunarYearRange(int lunarYear) {
  final start = LunarConverter.lunarToSolar(lunarYear, 1, 1);
  final days12 = LunarConverter.lunarMonthDays(lunarYear, 12);
  final end = LunarConverter.lunarToSolar(lunarYear, 12, days12);
  return (_startOfDay(start), _endOfDay(end));
}

/// Nhóm preset cho popover KiotViet.
class PosKiotTimePresetGroup {
  const PosKiotTimePresetGroup(this.title, this.presets);
  final String title;
  final List<PosKiotTimePreset> presets;
}

const kPosKiotTimePresetGroups = [
  PosKiotTimePresetGroup('Theo ngày', [
    PosKiotTimePreset.today,
    PosKiotTimePreset.yesterday,
  ]),
  PosKiotTimePresetGroup('Theo tuần', [
    PosKiotTimePreset.thisWeek,
    PosKiotTimePreset.lastWeek,
    PosKiotTimePreset.last7Days,
  ]),
  PosKiotTimePresetGroup('Theo tháng', [
    PosKiotTimePreset.thisMonth,
    PosKiotTimePreset.lastMonth,
    PosKiotTimePreset.thisLunarMonth,
    PosKiotTimePreset.lastLunarMonth,
    PosKiotTimePreset.last30Days,
  ]),
  PosKiotTimePresetGroup('Theo quý', [
    PosKiotTimePreset.thisQuarter,
    PosKiotTimePreset.lastQuarter,
  ]),
  PosKiotTimePresetGroup('Theo năm', [
    PosKiotTimePreset.thisYear,
    PosKiotTimePreset.lastYear,
    PosKiotTimePreset.thisLunarYear,
    PosKiotTimePreset.lastLunarYear,
    PosKiotTimePreset.allTime,
  ]),
];
