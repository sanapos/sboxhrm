import 'package:web/web.dart' as web;

/// True when the visitor should see the static marketing page instead of Flutter.
bool shouldRedirectToStaticHome() {
  final uri = Uri.base;
  final path = uri.path;

  if (path.contains('home.html') || path.contains('privacy-policy')) {
    return false;
  }

  // Legacy Flutter landing → static homepage
  if (path == '/landing' || path.startsWith('/landing/')) {
    return true;
  }

  const appPaths = [
    '/login-app',
    '/register',
    '/agent-register',
    '/forgot-password',
    '/admin',
    '/guide',
    '/customer-display',
  ];
  for (final p in appPaths) {
    if (path == p || path.startsWith('$p/')) return false;
  }
  if (path.startsWith('/reset-password')) return false;

  final frag = uri.fragment;
  if (frag.isNotEmpty) {
    final normalized = frag.startsWith('/') ? frag : '/$frag';
    if (normalized.startsWith('/guide/') ||
        normalized == '/guide' ||
        normalized.startsWith('/guide?')) {
      return false;
    }
    // Old hash route /#/landing → homepage
    if (normalized == '/landing' ||
        normalized.startsWith('/landing?') ||
        normalized.startsWith('/landing/')) {
      return true;
    }
    const hashRoutes = [
      '/login-app',
      '/register',
      '/agent-register',
      '/forgot-password',
      '/reset-password',
      '/admin',
      '/guide',
      '/customer-display',
    ];
    for (final r in hashRoutes) {
      if (normalized == r ||
          normalized.startsWith('$r?') ||
          normalized.startsWith('$r/')) {
        return false;
      }
    }
    if (normalized != '/' && normalized.isNotEmpty) return false;
  }

  return path == '/' ||
      path.isEmpty ||
      path.endsWith('/index.html') ||
      path.endsWith('/');
}

/// Navigate browser to static homepage (`/`), optionally with `?section=`.
void redirectToStaticHome({String? section}) {
  final uri = Uri.base;
  final origin = web.window.location.origin;
  final fromArg = section?.trim();
  final fromQuery = uri.queryParameters['section']?.trim();
  final chosen = (fromArg != null && fromArg.isNotEmpty)
      ? fromArg
      : (fromQuery != null && fromQuery.isNotEmpty ? fromQuery : null);
  if (chosen != null) {
    web.window.location
        .replace('$origin/?section=${Uri.encodeQueryComponent(chosen)}');
    return;
  }
  web.window.location.replace('$origin/');
}
