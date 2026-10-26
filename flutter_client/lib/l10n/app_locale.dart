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
}
