import 'package:flutter/foundation.dart';

import 'landing_guide_url_sync_stub.dart'
    if (dart.library.html) 'landing_guide_url_sync_web.dart' as url_sync;

/// Deep link tới một mục hướng dẫn trên landing.
class GuideDeepLink {
  const GuideDeepLink({required this.section, required this.stepId});

  /// `basic` hoặc `advanced`
  final String section;
  final String stepId;

  bool get isBasic => section == 'basic';
  int get sectionIndex => isBasic ? 0 : 1;
}

class LandingGuideUrl {
  LandingGuideUrl._();

  static const productionOrigin = 'https://sbox.sana.vn';

  /// Link chia sẻ — query param (giữ được khi gửi Zalo), không dùng hash.
  /// Ví dụ: https://sbox.sana.vn/?guide=advanced&step=kpi
  static String buildLink({
    required String section,
    required String stepId,
  }) {
    final origin =
        kIsWeb && Uri.base.origin.isNotEmpty ? Uri.base.origin : productionOrigin;
    final q = Uri(queryParameters: {
      'guide': section,
      'step': stepId,
    }).query;
    return '$origin/?$q';
  }

  static GuideDeepLink? parse(Uri uri) {
    final fromQuery = _parseQuery(uri.queryParameters);
    if (fromQuery != null) return fromQuery;

    var frag = uri.fragment.trim();
    if (frag.startsWith('/')) frag = frag.substring(1);
    final hashMatch =
        RegExp(r'^guide/(basic|advanced)/([a-z0-9_]+)$').firstMatch(frag);
    if (hashMatch != null) {
      return GuideDeepLink(
        section: hashMatch.group(1)!,
        stepId: hashMatch.group(2)!,
      );
    }
    return null;
  }

  static GuideDeepLink? _parseQuery(Map<String, String> params) {
    final section = params['guide']?.trim();
    final stepId = params['step']?.trim();
    if (section != null &&
        stepId != null &&
        (section == 'basic' || section == 'advanced') &&
        stepId.isNotEmpty) {
      return GuideDeepLink(section: section, stepId: stepId);
    }
    return null;
  }

  static GuideDeepLink? parseCurrent() => parse(Uri.base);

  static void syncToBrowser({
    required String section,
    required String stepId,
  }) {
    url_sync.syncGuideUrlToBrowser(section, stepId);
  }

  static void clearFromBrowser() {
    url_sync.clearGuideUrlFromBrowser();
  }

  static String? extractYouTubeVideoId(String url) {
    try {
      final uri = Uri.parse(url.trim());
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      if (uri.host.contains('youtube.com')) {
        if (uri.pathSegments.contains('embed') ||
            uri.pathSegments.contains('shorts')) {
          return uri.pathSegments.last;
        }
        return uri.queryParameters['v'];
      }
    } catch (_) {}
    return null;
  }
}
