import 'package:flutter/foundation.dart';

String normalizeLandingPublicUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  if (kIsWeb && value.startsWith('http://')) {
    return 'https://${value.substring(7)}';
  }
  return value;
}
