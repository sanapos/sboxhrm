import 'package:web/web.dart' as web;

void syncGuideUrlToBrowser(String section, String stepId) {
  final origin = web.window.location.origin;
  final target =
      '$origin/guide?guide=${Uri.encodeComponent(section)}&step=${Uri.encodeComponent(stepId)}';
  if (web.window.location.href != target) {
    web.window.history.replaceState(null, '', target);
  }
}

void clearGuideUrlFromBrowser() {
  final path = web.window.location.pathname;
  if (web.window.location.search.isNotEmpty) {
    // Keep /guide (or current path) without the step query.
    web.window.history.replaceState(null, '', path.isEmpty ? '/guide' : path);
  }
}
