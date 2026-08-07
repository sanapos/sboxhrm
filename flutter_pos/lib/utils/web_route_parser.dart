import 'package:flutter/foundation.dart' show kIsWeb;

import 'initial_route_capture_stub.dart'
    if (dart.library.html) 'initial_route_capture_web.dart' as initial_route_capture;

/// Parse query params from both standard URL and hash routes (`/#/register?x=1`).
Map<String, String> parseWebRouteQueryParams() {
  final params = <String, String>{};
  try {
    final uri = Uri.base;
    params.addAll(uri.queryParameters);
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      final frag = fragment.startsWith('/') ? fragment : '/$fragment';
      final fragUri = Uri.parse(frag);
      params.addAll(fragUri.queryParameters);
    }
  } catch (_) {}
  return params;
}

/// Extract path segments from hash route, e.g. `#/agent-register/AGT-TOKEN` → `['agent-register', 'AGT-TOKEN']`.
List<String> parseWebHashPathSegments() {
  try {
    final fragment = Uri.base.fragment;
    if (fragment.isEmpty) return const [];
    final frag = fragment.startsWith('/') ? fragment.substring(1) : fragment;
    final path = frag.split('?').first;
    return path.split('/').where((s) => s.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

String? parseAgentRegistrationToken() {
  final segments = parseWebHashPathSegments();
  if (segments.length >= 2 && segments[0] == 'agent-register') {
    return segments[1].trim().isEmpty ? null : segments[1].trim();
  }
  return null;
}

String webAppBaseUrl(String apiBaseUrl) =>
    apiBaseUrl.replaceFirst(RegExp(r'/api$'), '');

bool get isAgentRegisterDeepLink {
  if (!kIsWeb) return false;
  return parseAgentRegistrationToken() != null;
}

bool get isPublicRegisterDeepLink {
  if (!kIsWeb) return false;
  final segs = parseWebHashPathSegments();
  if (segs.isNotEmpty && segs.first == 'register') return true;
  return Uri.base.path.contains('/register');
}

bool get isLoginDeepLink {
  if (!kIsWeb) return false;
  final path = Uri.base.path;
  if (path == '/login-app' || path.endsWith('/login-app')) return true;
  final segs = parseWebHashPathSegments();
  if (segs.isEmpty) return false;
  return segs.first == 'login-app' || segs.first == 'login';
}

bool get isForgotPasswordDeepLink {
  if (!kIsWeb) return false;
  final path = Uri.base.path;
  if (path.contains('/forgot-password')) return true;
  final segs = parseWebHashPathSegments();
  return segs.isNotEmpty && segs.first == 'forgot-password';
}

/// The static homepage links to `/guide`; share links instead carry the step in
/// the query, as `/guide?guide=basic&step=register`.
bool get isGuideDeepLink {
  if (!kIsWeb) return false;
  final path = Uri.base.path;
  if (path == '/guide' || path.endsWith('/guide')) return true;
  final segs = parseWebHashPathSegments();
  if (segs.isNotEmpty && segs.first == 'guide') return true;
  final params = parseWebRouteQueryParams();
  final section = params['guide'];
  return (section == 'basic' || section == 'advanced') &&
      (params['step']?.trim().isNotEmpty ?? false);
}

/// Giữ deep link web đọc một lần lúc khởi động (tránh mất hash sau Flutter bootstrap).
class InitialWebRoute {
  InitialWebRoute._();

  static bool _captured = false;
  static bool showRegister = false;
  static bool showAgentRegister = false;
  static bool showLogin = false;
  static bool showForgotPassword = false;
  static bool showGuide = false;
  static String? agentRegisterToken;
  static Map<String, String> queryParams = const {};

  static void capture() {
    if (!kIsWeb || _captured) return;
    _captured = true;
    queryParams = Map<String, String>.from(parseWebRouteQueryParams());
    showAgentRegister = isAgentRegisterDeepLink;
    agentRegisterToken = parseAgentRegistrationToken();
    showRegister = isPublicRegisterDeepLink;
    showLogin = isLoginDeepLink;
    showForgotPassword = isForgotPasswordDeepLink;
    showGuide = isGuideDeepLink;

    // Fallback: index.html lưu vào sessionStorage trước khi Flutter có thể xóa hash.
    initial_route_capture.captureInitialRouteFromStorage();
  }

  static String? get agentCode =>
      queryParams['agentCode'] ?? queryParams['agent'] ?? queryParams['ref'];
}
