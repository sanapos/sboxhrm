import 'dart:async';

import 'package:flutter/foundation.dart';

import 'navigation_notifier.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Phân loại lỗi để hiển thị thông báo dễ hiểu (mạng / timeout / khác).
enum AppErrorKind {
  network,
  timeout,
  server,
  unknown,
}

class AppErrorInfo {
  final AppErrorKind kind;
  final String title;
  final String message;
  final String? technicalHint;

  const AppErrorInfo({
    required this.kind,
    required this.title,
    required this.message,
    this.technicalHint,
  });
}

class AppErrorUtils {
  AppErrorUtils._();

  static AppErrorKind classify(Object error) {
    final s = error.toString().toLowerCase();
    if (error is StackOverflowError || s.contains('stack overflow')) {
      return AppErrorKind.unknown;
    }
    if (_isNetworkErrorText(s)) return AppErrorKind.network;
    if (error is TimeoutException || s.contains('timeoutexception')) {
      return AppErrorKind.timeout;
    }
    if (s.contains('500') ||
        s.contains('502') ||
        s.contains('503') ||
        s.contains('internal server')) {
      return AppErrorKind.server;
    }
    return AppErrorKind.unknown;
  }

  static bool _isNetworkErrorText(String s) {
    return s.contains('socketexception') ||
        s.contains('clientexception') ||
        s.contains('handshakeexception') ||
        s.contains('certificate') ||
        s.contains('certificat') ||
        s.contains('ssl') ||
        s.contains('tls') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('connection refused') ||
        s.contains('connection closed') ||
        s.contains('connection reset') ||
        s.contains('connection terminated') ||
        s.contains('no address associated with hostname') ||
        s.contains('software caused connection abort') ||
        s.contains('network error') ||
        s.contains('mất kết nối') ||
        s.contains('không có mạng');
  }

  static bool _isSslErrorText(String s) =>
      s.contains('handshake') ||
      s.contains('certificate') ||
      s.contains('certificat') ||
      s.contains('ssl') ||
      s.contains('tls') ||
      s.contains('certificate_verify_failed');

  static bool isNetworkError(Object error) =>
      classify(error) == AppErrorKind.network;

  static String userMessage(Object error) => fromException(error).message;

  static String title(Object error) => fromException(error).title;

  static AppErrorInfo fromException(Object error, {String? context}) {
    final kind = classify(error);
    final hint = _technicalHint(error);
    final s = error.toString().toLowerCase();

    if (error is StackOverflowError || s.contains('stack overflow')) {
      return AppErrorInfo(
        kind: AppErrorKind.unknown,
        title: 'Giao diện quá tải',
        message: tr('Ứng dụng gặp sự cố hiển thị. Đóng app hoàn toàn (vuốt khỏi đa nhiệm) rồi mở lại.'),
        technicalHint: hint,
      );
    }

    if (_isSslErrorText(s)) {
      return AppErrorInfo(
        kind: AppErrorKind.network,
        title: 'Lỗi bảo mật HTTPS',
        message: tr(
          'Máy không xác thực được chứng chỉ máy chủ (thường gặp trên Android cũ / Sunmi T1). '
          'Kiểm tra ngày giờ máy đúng, Wi‑Fi ổn định rồi thử lại.',
        ),
        technicalHint: hint,
      );
    }

    switch (kind) {
      case AppErrorKind.network:
        return AppErrorInfo(
          kind: kind,
          title: 'Mất kết nối mạng',
          message: tr('Không thể kết nối máy chủ. Vui lòng bật Wi‑Fi hoặc 4G rồi thử lại.'),
          technicalHint: hint,
        );
      case AppErrorKind.timeout:
        return AppErrorInfo(
          kind: kind,
          title: 'Máy chủ không phản hồi',
          message: tr('Yêu cầu quá lâu không nhận được phản hồi. Kiểm tra mạng và thử lại.'),
          technicalHint: hint,
        );
      case AppErrorKind.server:
        return AppErrorInfo(
          kind: kind,
          title: 'Lỗi máy chủ',
          message: tr('Máy chủ đang gặp sự cố. Vui lòng thử lại sau.'),
          technicalHint: hint,
        );
      case AppErrorKind.unknown:
        return AppErrorInfo(
          kind: kind,
          title: 'Ứng dụng gặp sự cố',
          message: context != null && context.isNotEmpty
              ? context
              : 'Đã xảy ra lỗi không mong muốn. Vui lòng thử lại hoặc mở lại ứng dụng.',
          technicalHint: hint,
        );
    }
  }

  static String? _technicalHint(Object error) {
    var raw = error.toString().trim();
    raw = raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
    raw = raw.replaceFirst(RegExp(r'^Error:\s*'), '');
    final screen = NavigationNotifier.currentScreenLabel.value?.trim();
    if (screen != null && screen.isNotEmpty) {
      raw = raw.isEmpty ? 'Màn: $screen' : 'Màn: $screen · $raw';
    }
    if (raw.isEmpty) return null;
    const maxLen = 180;
    if (raw.length > maxLen) {
      return '${raw.substring(0, maxLen)}…';
    }
    return raw;
  }

  static void logFlutterError(FlutterErrorDetails details) {
    final ex = details.exception;
    final info = fromException(ex);
    final screen = NavigationNotifier.currentScreenLabel.value;
    debugPrint(
      '🛑 APP_ERROR [${info.kind.name}] ${details.library ?? "?"} '
      '${screen != null ? "màn=$screen " : ""}'
      '${details.context ?? ""}',
    );
    debugPrint('   → ${info.technicalHint ?? ex}');
    if (kDebugMode && details.stack != null) {
      debugPrint(details.stack.toString());
    }
  }

  static Map<String, dynamic> apiFailure(
    Object error, {
    String? fallbackMessage,
  }) {
    final info = fromException(error);
    debugPrint('🌐 API error [${info.kind.name}]: $error');
    var message = info.kind == AppErrorKind.unknown &&
            fallbackMessage != null &&
            fallbackMessage.isNotEmpty
        ? fallbackMessage
        : info.message;
    final hint = info.technicalHint;
    if (hint != null && hint.isNotEmpty && !message.contains(hint)) {
      message = '$message\n($hint)';
    }
    return {
      'isSuccess': false,
      'success': false,
      'message': message,
      'errorKind': info.kind.name,
    };
  }
}
