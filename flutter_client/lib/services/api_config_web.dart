import 'dart:js_interop';
import 'package:web/web.dart' as web;

@JS('API_BASE_URL')
external JSString? get _jsApiBaseUrl;

String getApiBaseUrl() {
  // 1. Try meta tag from index.html (replaced by Docker entrypoint)
  try {
    final meta = web.document.querySelector('meta[name="api-base-url"]');
    if (meta != null) {
      final url = meta.getAttribute('content');
      if (url != null && url.isNotEmpty && url != '__API_BASE_URL__') {
        return url;
      }
    }
  } catch (_) {}

  // 2. Try window.API_BASE_URL from config.js (also replaced by Docker entrypoint)
  try {
    final jsUrl = _jsApiBaseUrl;
    if (jsUrl != null) {
      final url = jsUrl.toDart;
      if (url.isNotEmpty && url != '__API_BASE_URL__') {
        return url;
      }
    }
  } catch (_) {}

  // 3. Fallback to compile-time dart-define or default
  return const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:7070',
  );
}
