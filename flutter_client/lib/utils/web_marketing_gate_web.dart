import 'package:web/web.dart' as web;

/// True when the visitor should see the static marketing page instead of Flutter.
bool shouldRedirectToStaticHome() {
  final uri = Uri.base;
  final path = uri.path;

  if (path.contains('home.html') || path.contains('privacy-policy')) {
    return false;
  }

  const appPaths = [
    '/login-app',
    '/register',
    '/agent-register',
    '/forgot-password',
    '/admin',
    '/landing',
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
    const hashRoutes = [
      '/login-app',
      '/register',
      '/agent-register',
      '/forgot-password',
      '/reset-password',
      '/admin',
      '/landing',
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

void redirectToStaticHome() {
  final origin = web.window.location.origin;
  web.window.location.replace('$origin/home.html');
}
