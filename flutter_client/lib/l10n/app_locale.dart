/// Global UI locale for [tr] without BuildContext.
/// Vietnamese remains default (source language); other languages apply when the
/// user selects them in Settings / on the login screen.
class AppLocale {
  AppLocale._();

  /// Languages the UI can show, in picker order: code → native name.
  static const Map<String, String> languages = <String, String>{
    'vi': 'Tiếng Việt',
    'en': 'English',
    'ko': '한국어',
    'ja': '日本語',
    'zh': '中文（简体）',
  };

  /// Short label for compact switches (login screen).
  static const Map<String, String> shortLabels = <String, String>{
    'vi': 'VI',
    'en': 'EN',
    'ko': '한',
    'ja': '日',
    'zh': '中',
  };

  static String languageCode = 'vi';

  static bool get isVietnamese => languageCode == 'vi';
  static bool get isEnglish => languageCode == 'en';

  static bool isSupported(String code) => languages.containsKey(code);

  static void setLanguageCode(String code) {
    languageCode = isSupported(code) ? code : 'vi';
  }

  /// Thứ viết tắt theo ngôn ngữ đang chọn; [weekday] như [DateTime.weekday] (1 = T2 … 7 = CN).
  /// «T2» / «CN» không có trong gói dịch (khóa ngắn dễ trùng «tháng 2») — ko/ja/zh trước hiện «T5».
  static String weekdayShort(int weekday) {
    const labels = <String, List<String>>{
      'vi': ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'],
      'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      'ko': ['월', '화', '수', '목', '금', '토', '일'],
      'ja': ['月', '火', '水', '木', '金', '土', '日'],
      'zh': ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
    };
    return (labels[languageCode] ?? labels['vi']!)[(weekday - 1) % 7];
  }

  /// «Tháng 10 2026» theo ngôn ngữ — tr() khớp mẫu «Tháng {0}» ra «10 2026 月» (sai thứ tự).
  static String monthYear(int year, int month) => switch (languageCode) {
        'en' => '${const [
            'January', 'February', 'March', 'April', 'May', 'June', 'July',
            'August', 'September', 'October', 'November', 'December'
          ][month - 1]} $year',
        'ko' => '$year년 $month월',
        'ja' || 'zh' => '$year年$month月',
        _ => 'Tháng $month $year',
      };
}
