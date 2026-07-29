/// Global UI locale for [tr] without BuildContext.
/// Vietnamese remains default; English applies when user selects it in Settings.
class AppLocale {
  AppLocale._();

  static String languageCode = 'vi';

  static bool get isEnglish => languageCode == 'en';

  static void setLanguageCode(String code) {
    languageCode = (code == 'en') ? 'en' : 'vi';
  }
}
