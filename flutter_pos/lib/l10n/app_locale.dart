import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global UI locale for [tr] without BuildContext.
/// Vietnamese remains default; English applies when user selects it in Settings.
class AppLocale {
  AppLocale._();

  static const _prefsKey = 'pos_ui_lang';
  static final ValueNotifier<String> listenable = ValueNotifier<String>('vi');

  static String languageCode = 'vi';

  static bool get isEnglish => languageCode == 'en';

  static Locale get locale => Locale(languageCode);

  static Future<void> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setLanguageCode(prefs.getString(_prefsKey) ?? 'vi');
    } catch (_) {
      setLanguageCode('vi');
    }
  }

  static Future<void> persist(String code) async {
    setLanguageCode(code);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, languageCode);
    } catch (_) {}
  }

  static void setLanguageCode(String code) {
    languageCode = (code == 'en') ? 'en' : 'vi';
    if (listenable.value != languageCode) {
      listenable.value = languageCode;
    }
  }
}
