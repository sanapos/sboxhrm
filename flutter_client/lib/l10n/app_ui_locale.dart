import 'package:flutter/material.dart';

import 'app_locale.dart';

/// Locale for date/time pickers and intl formatting — follows Settings language.
Locale appUiLocale() => switch (AppLocale.languageCode) {
      'en' => const Locale('en'),
      'ko' => const Locale('ko', 'KR'),
      'ja' => const Locale('ja', 'JP'),
      'zh' => const Locale('zh', 'CN'),
      _ => const Locale('vi', 'VN'),
    };

String appIntlLocaleName() => switch (AppLocale.languageCode) {
      'en' => 'en',
      'ko' => 'ko_KR',
      'ja' => 'ja_JP',
      'zh' => 'zh_CN',
      _ => 'vi_VN',
    };
