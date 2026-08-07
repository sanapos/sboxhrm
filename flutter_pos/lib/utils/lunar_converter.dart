/// Chuyển đổi dương lịch / âm lịch Việt Nam (1900–2049).
class LunarDate {
  final int day, month, year;
  final bool isLeapMonth;
  LunarDate(this.day, this.month, this.year, {this.isLeapMonth = false});

  String toShortString() =>
      '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}${isLeapMonth ? ' (nhuận)' : ''}';

  @override
  String toString() =>
      '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year${isLeapMonth ? ' (nhuận)' : ''}';
}

class LunarConverter {
  static const List<int> _lunarMonthDays = [
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
    0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
    0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
    0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
    0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,
    0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
    0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
    0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60, 0x096d5, 0x092e0,
    0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
    0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
    0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d25f, 0x0d520, 0x0dd45,
    0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
  ];

  static const int _baseYear = 1900;
  static final DateTime _baseDate = DateTime(1900, 1, 31);

  static int _leapMonth(int year) {
    if (year - _baseYear < 0 || year - _baseYear >= _lunarMonthDays.length) return 0;
    return _lunarMonthDays[year - _baseYear] & 0xf;
  }

  static int _leapDays(int year) {
    if (_leapMonth(year) != 0) {
      return (_lunarMonthDays[year - _baseYear] & 0x10000) != 0 ? 30 : 29;
    }
    return 0;
  }

  static int _monthDays(int year, int month) {
    if (year - _baseYear < 0 || year - _baseYear >= _lunarMonthDays.length) return 29;
    return (_lunarMonthDays[year - _baseYear] & (0x10000 >> month)) != 0 ? 30 : 29;
  }

  static int lunarMonthDays(int year, int month) => _monthDays(year, month);

  static int _yearDays(int year) {
    int sum = 348;
    if (year - _baseYear < 0 || year - _baseYear >= _lunarMonthDays.length) return sum;
    for (int i = 0x8000; i > 0x8; i >>= 1) {
      sum += (_lunarMonthDays[year - _baseYear] & i) != 0 ? 1 : 0;
    }
    return sum + _leapDays(year);
  }

  static LunarDate solarToLunar(DateTime solar) {
    int offset = solar.difference(_baseDate).inDays;
    if (offset < 0) return LunarDate(solar.day, solar.month, solar.year);

    int lunarYear = _baseYear;
    int temp = 0;
    for (lunarYear = _baseYear; lunarYear < 2050 && offset > 0; lunarYear++) {
      temp = _yearDays(lunarYear);
      offset -= temp;
    }
    if (offset < 0) {
      offset += _yearDays(--lunarYear);
    }

    int leapMon = _leapMonth(lunarYear);
    bool isLeap = false;
    int lunarMonth = 1;

    for (lunarMonth = 1; lunarMonth < 13 && offset > 0; lunarMonth++) {
      if (leapMon > 0 && lunarMonth == (leapMon + 1) && !isLeap) {
        --lunarMonth;
        isLeap = true;
        temp = _leapDays(lunarYear);
      } else {
        temp = _monthDays(lunarYear, lunarMonth);
      }
      if (isLeap && lunarMonth == (leapMon + 1)) isLeap = false;
      offset -= temp;
    }
    if (offset < 0) {
      offset += temp;
      --lunarMonth;
    }
    if (offset == 0 && leapMon > 0 && lunarMonth == leapMon + 1) {
      if (isLeap) {
        isLeap = false;
      } else {
        isLeap = true;
        --lunarMonth;
      }
    }

    int lunarDay = offset + 1;
    return LunarDate(lunarDay, lunarMonth, lunarYear, isLeapMonth: isLeap);
  }

  static DateTime lunarToSolar(int lunarYear, int lunarMonth, int lunarDay,
      {bool isLeapMonth = false}) {
    if (lunarYear < _baseYear || lunarYear - _baseYear >= _lunarMonthDays.length) {
      return DateTime(lunarYear, lunarMonth, lunarDay);
    }

    int offset = 0;
    for (int y = _baseYear; y < lunarYear; y++) {
      offset += _yearDays(y);
    }

    int leapMon = _leapMonth(lunarYear);
    bool afterLeap = false;
    for (int m = 1; m < lunarMonth; m++) {
      if (leapMon > 0 && m == leapMon && !afterLeap) {
        offset += _leapDays(lunarYear);
        afterLeap = true;
      }
      offset += _monthDays(lunarYear, m);
    }

    if (isLeapMonth && lunarMonth == leapMon) {
      offset += _monthDays(lunarYear, lunarMonth);
    }
    if (!isLeapMonth && leapMon > 0 && leapMon < lunarMonth && !afterLeap) {
      offset += _leapDays(lunarYear);
    }

    offset += lunarDay - 1;
    return _baseDate.add(Duration(days: offset));
  }
}
