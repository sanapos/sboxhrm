import 'package:flutter/material.dart';

import 'app_locale.dart';

/// Locale for date/time pickers and intl formatting — follows Settings language.
Locale appUiLocale() =>
    AppLocale.isEnglish ? const Locale('en') : const Locale('vi', 'VN');

String appIntlLocaleName() => AppLocale.isEnglish ? 'en' : 'vi_VN';
