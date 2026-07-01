import 'package:flutter/foundation.dart' show kIsWeb;

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
