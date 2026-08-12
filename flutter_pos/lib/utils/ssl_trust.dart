import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bổ sung CA Let's Encrypt vào trust store của Dart HttpClient.
///
/// Sunmi T1 / Android cũ đôi khi thiếu ISRG Root X1 (hoặc chain YR2 mới),
/// khiến login HTTPS `sboxhrm.com` fail trong khi Android 11+ vẫn OK.
class _TrustedRootsHttpOverrides extends HttpOverrides {
  _TrustedRootsHttpOverrides(this._context);

  final SecurityContext _context;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(_context);
    // Giữ xác thực chứng chỉ — chỉ thêm root tin cậy, không bỏ verify.
    return client;
  }
}

Future<void> installPosSslTrust() async {
  if (kIsWeb) return;
  try {
    final ctx = SecurityContext(withTrustedRoots: true);
    const assets = <String>[
      'assets/certs/isrgrootx1.pem',
      'assets/certs/isrg-root-yr.pem',
      'assets/certs/lets-encrypt-yr2.pem',
    ];
    for (final path in assets) {
      try {
        final data = await rootBundle.load(path);
        ctx.setTrustedCertificatesBytes(data.buffer.asUint8List());
      } catch (e) {
        debugPrint('SSL trust skip $path: $e');
      }
    }
    HttpOverrides.global = _TrustedRootsHttpOverrides(ctx);
    debugPrint('✅ POS SSL trust: ISRG/LE roots installed');
  } catch (e) {
    debugPrint('⚠️ POS SSL trust setup failed: $e');
  }
}
