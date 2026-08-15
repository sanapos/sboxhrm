import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_config.dart';

class PosAndroidRelease {
  const PosAndroidRelease({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    this.releaseNotes,
    this.forceUpdate = false,
    this.apkBytes,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String? releaseNotes;
  final bool forceUpdate;
  final int? apkBytes;

  factory PosAndroidRelease.fromJson(Map<String, dynamic> json) {
    return PosAndroidRelease(
      versionName: json['versionName']?.toString() ?? '0',
      versionCode: (json['versionCode'] is num)
          ? (json['versionCode'] as num).toInt()
          : int.tryParse('${json['versionCode']}') ?? 0,
      apkUrl: json['apkUrl']?.toString() ?? '',
      releaseNotes: json['releaseNotes']?.toString(),
      forceUpdate: json['forceUpdate'] == true,
      apkBytes: (json['apkBytes'] is num)
          ? (json['apkBytes'] as num).toInt()
          : int.tryParse('${json['apkBytes'] ?? ''}'),
    );
  }
}

/// Kiểm tra / tải APK SBOX POS (Android 6+, không dùng Play Store).
class PosAppUpdateService {
  PosAppUpdateService._();

  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      followRedirects: true,
      maxRedirects: 5,
      // Không ép ResponseType.bytes — dio.download cần stream ghi file.
      responseType: ResponseType.stream,
      validateStatus: (s) => s != null && s >= 200 && s < 400,
      headers: const {
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Connection': 'close',
      },
    ),
  );

  static String get releaseApiUrl =>
      '${getApiBaseUrl()}/api/app/pos-android-release';

  static String get webDownloadUrl =>
      '${getApiBaseUrl()}/api/app/pos-android-apk';

  static Future<PackageInfo> currentPackage() => PackageInfo.fromPlatform();

  static Future<PosAndroidRelease?> fetchLatest() async {
    try {
      final res = await http
          .get(Uri.parse(releaseApiUrl))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final data = body['data'] ?? body['Data'];
      if (data is! Map) return null;
      return PosAndroidRelease.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('PosAppUpdateService.fetchLatest: $e');
      return null;
    }
  }

  /// Flutter `--split-per-abi` gán Android versionCode = pubspecBuild + abi*1000
  /// (armeabi-v7a=1, arm64-v8a=2, x86_64=3). Server có thể ghi 1049 hoặc 3049.
  static int toPubspecBuildNumber(int androidOrPubspecCode) {
    for (final abi in const [2, 1, 3]) {
      final n = androidOrPubspecCode - abi * 1000;
      if (n >= 100) return n;
    }
    return androidOrPubspecCode;
  }

  /// null = đã mới nhất / không kiểm tra được; ngược lại = có bản mới.
  static Future<PosAndroidRelease?> checkForUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final latest = await fetchLatest();
    if (latest == null || latest.versionCode <= 0 || latest.apkUrl.isEmpty) {
      return null;
    }
    final info = await currentPackage();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;
    final latestPub = toPubspecBuildNumber(latest.versionCode);
    final currentPub = toPubspecBuildNumber(currentCode);
    if (latest.versionCode > currentCode || latestPub > currentPub) {
      return latest;
    }
    return null;
  }

  /// Ưu tiên thư mục app (luôn ghi được); public Download chỉ khi có quyền.
  static Future<Directory> _apkSaveDir() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory('${ext.path}/Download');
        await dir.create(recursive: true);
        return dir;
      }
    } catch (_) {}
    try {
      final status = await Permission.storage.request();
      if (status.isGranted) {
        final publicDl = Directory('/storage/emulated/0/Download');
        if (await publicDl.exists()) return publicDl;
      }
    } catch (_) {}
    return getTemporaryDirectory();
  }

  static Future<bool> _looksLikeApk(File file) async {
    final raf = await file.open();
    try {
      final header = await raf.read(4);
      // ZIP local file header: PK\x03\x04
      return header.length >= 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4B &&
          header[2] == 0x03 &&
          header[3] == 0x04;
    } finally {
      await raf.close();
    }
  }

  static List<String> _candidateUrls(PosAndroidRelease release) {
    final seen = <String>{};
    final out = <String>[];
    void add(String? u) {
      final s = (u ?? '').trim();
      if (s.isEmpty || !seen.add(s)) return;
      out.add(s);
    }

    add(release.apkUrl);
    add(webDownloadUrl);
    // Cùng file qua domain còn lại nếu host khác.
    final base = getApiBaseUrl();
    if (base.contains('sboxhrm.com')) {
      add('https://sbox.sana.vn/api/app/pos-android-apk');
    } else {
      add('https://sboxhrm.com/api/app/pos-android-apk');
    }
    add('https://sbox.sana.vn/downloads/sbox-pos.apk');
    add('https://sboxhrm.com/downloads/sbox-pos.apk');
    return out;
  }

  static Future<void> _downloadWithDio(
    String url,
    String path, {
    void Function(double progress)? onProgress,
    int? apkBytes,
  }) async {
    await _dio.download(
      url,
      path,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        if (onProgress == null) return;
        if (total > 0) {
          onProgress(received / total);
        } else if (apkBytes != null && apkBytes > 0) {
          onProgress((received / apkBytes).clamp(0.0, 1.0));
        }
      },
    );
  }

  /// Fallback HttpClient (nhận SSL trust ISRG đã cài trong main).
  static Future<void> _downloadWithHttpClient(
    String url,
    String path, {
    void Function(double progress)? onProgress,
    int? apkBytes,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    client.idleTimeout = const Duration(minutes: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final res = await req.close().timeout(const Duration(minutes: 10));
      if (res.statusCode < 200 || res.statusCode >= 400) {
        throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
      }
      final sink = File(path).openWrite();
      var received = 0;
      final total = res.contentLength;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress == null) continue;
        if (total > 0) {
          onProgress(received / total);
        } else if (apkBytes != null && apkBytes > 0) {
          onProgress((received / apkBytes).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  /// Tải APK về thư mục app rồi mở trình cài đặt hệ thống.
  static Future<String?> downloadAndInstall(
    PosAndroidRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return 'Chỉ hỗ trợ Android.';
    if (release.apkUrl.isEmpty) return 'Thiếu URL APK.';

    try {
      final dir = await _apkSaveDir();
      final file = File('${dir.path}/sbox-pos-${release.versionCode}.apk');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      Object? lastError;
      var ok = false;
      for (final url in _candidateUrls(release)) {
        try {
          debugPrint('POS OTA download try: $url');
          try {
            await _downloadWithDio(
              url,
              file.path,
              onProgress: onProgress,
              apkBytes: release.apkBytes,
            );
          } catch (dioErr) {
            debugPrint('POS OTA dio fail: $dioErr — fallback HttpClient');
            if (await file.exists()) {
              try {
                await file.delete();
              } catch (_) {}
            }
            await _downloadWithHttpClient(
              url,
              file.path,
              onProgress: onProgress,
              apkBytes: release.apkBytes,
            );
          }
          if (!await file.exists()) {
            lastError = 'Không có file sau tải';
            continue;
          }
          final len = await file.length();
          if (len < 1024 * 100) {
            lastError = 'File quá nhỏ: $len byte';
            try {
              await file.delete();
            } catch (_) {}
            continue;
          }
          if (release.apkBytes != null &&
              release.apkBytes! > 1024 &&
              (len - release.apkBytes!).abs() > 64 * 1024) {
            lastError = 'Tải không đủ ($len / ${release.apkBytes} byte)';
            try {
              await file.delete();
            } catch (_) {}
            continue;
          }
          if (!await _looksLikeApk(file)) {
            lastError = 'File không phải APK (proxy/HTML)';
            try {
              await file.delete();
            } catch (_) {}
            continue;
          }
          ok = true;
          break;
        } catch (e) {
          lastError = e;
          debugPrint('POS OTA candidate fail $url: $e');
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {}
          }
        }
      }

      if (!ok) {
        return 'Lỗi tải APK: $lastError\nThử mở trình duyệt: $webDownloadUrl';
      }

      // Android 6: đảm bảo file đọc được bởi PackageInstaller.
      try {
        await Process.run('chmod', ['0644', file.path]);
      } catch (_) {}

      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        return result.message.isNotEmpty
            ? result.message
            : 'Không mở được trình cài đặt. Bật «Cài từ nguồn không xác định» cho SBOX POS.';
      }
      return null;
    } catch (e) {
      debugPrint('PosAppUpdateService.downloadAndInstall: $e');
      return 'Lỗi tải/cài APK: $e';
    }
  }
}
