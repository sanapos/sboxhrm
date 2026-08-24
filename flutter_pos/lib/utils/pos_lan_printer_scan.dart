import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'pos_thermal_printer_settings.dart';

/// Máy in LAN (cổng raw 9100 — Zywell / Xprinter / HPRT / ESC/POS).
class PosLanPrinterHit {
  const PosLanPrinterHit({
    required this.host,
    required this.port,
    this.brand = PosThermalPrinterBrand.generic,
    this.model,
  });

  final String host;
  final int port;
  final PosThermalPrinterBrand brand;
  final String? model;

  String get title {
    final m = (model ?? '').trim();
    if (m.isNotEmpty) return '$m · $host:$port';
    if (brand != PosThermalPrinterBrand.generic) {
      return '${brand.label} · $host:$port';
    }
    return 'Máy in LAN · $host:$port';
  }
}

/// Quét subnet Wi‑Fi/Ethernet nội bộ, mở TCP 9100 (và 9101).
class PosLanPrinterScan {
  PosLanPrinterScan._();

  static const ports = [9100, 9101];
  static const _connectTimeout = Duration(milliseconds: 280);
  static const _identifyTimeout = Duration(milliseconds: 350);
  static const _parallel = 32;

  /// GS I n — nhiều máy Zywell/Xprinter/HPRT trả model.
  static final _idCmd = Uint8List.fromList(const [0x1D, 0x49, 0x01]);

  static Future<List<InternetAddress>> localIpv4s() async {
    if (kIsWeb) return const [];
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final out = <InternetAddress>[];
      for (final iface in ifaces) {
        for (final a in iface.addresses) {
          if (_isPrivateLan(a)) out.add(a);
        }
      }
      return out;
    } catch (e) {
      debugPrint('PosLanPrinterScan.localIpv4s: $e');
      return const [];
    }
  }

  static bool _isPrivateLan(InternetAddress a) {
    if (a.type != InternetAddressType.IPv4) return false;
    final p = a.rawAddress;
    if (p.length != 4) return false;
    if (p[0] == 10) return true;
    if (p[0] == 192 && p[1] == 168) return true;
    if (p[0] == 172 && p[1] >= 16 && p[1] <= 31) return true;
    return false;
  }

  /// [onProgress]: done/total + hit vừa thấy (nếu có).
  static Future<List<PosLanPrinterHit>> scan({
    void Function(int done, int total, PosLanPrinterHit? hit)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (kIsWeb) return const [];
    final locals = await localIpv4s();
    if (locals.isEmpty) return const [];

    final skip = {for (final a in locals) a.address};
    final hosts = <String>{};
    for (final a in locals) {
      final p = a.rawAddress;
      if (p.length != 4) continue;
      final prefix = '${p[0]}.${p[1]}.${p[2]}';
      for (var i = 1; i <= 254; i++) {
        final h = '$prefix.$i';
        if (!skip.contains(h)) hosts.add(h);
      }
    }
    final list = hosts.toList()..sort();
    final total = list.length;
    var done = 0;
    final hits = <PosLanPrinterHit>[];
    final seen = <String>{};

    Future<PosLanPrinterHit?> probe(String host) async {
      if (isCancelled?.call() == true) return null;
      for (final port in ports) {
        if (isCancelled?.call() == true) return null;
        final hit = await _probeHost(host, port);
        if (hit != null) return hit;
      }
      return null;
    }

    var i = 0;
    while (i < list.length) {
      if (isCancelled?.call() == true) break;
      final chunk = list.skip(i).take(_parallel).toList();
      i += chunk.length;
      final found = await Future.wait(chunk.map(probe));
      for (final hit in found) {
        done++;
        if (hit != null && seen.add('${hit.host}:${hit.port}')) {
          hits.add(hit);
          onProgress?.call(done, total, hit);
        } else {
          onProgress?.call(done, total, null);
        }
      }
    }

    hits.sort((a, b) {
      final ba = a.brand == PosThermalPrinterBrand.generic ? 1 : 0;
      final bb = b.brand == PosThermalPrinterBrand.generic ? 1 : 0;
      if (ba != bb) return ba.compareTo(bb);
      return a.host.compareTo(b.host);
    });
    return hits;
  }

  static Future<PosLanPrinterHit?> _probeHost(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: _connectTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      var model = await _readId(socket);
      final brand = _guessBrand(model);
      return PosLanPrinterHit(
        host: host,
        port: port,
        brand: brand,
        model: model,
      );
    } catch (_) {
      return null;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
      socket?.destroy();
    }
  }

  static Future<String?> _readId(Socket socket) async {
    try {
      socket.add(_idCmd);
      await socket.flush();
    } catch (_) {
      return null;
    }
    final buf = BytesBuilder(copy: false);
    try {
      await for (final chunk in socket.timeout(
        _identifyTimeout,
        onTimeout: (sink) => sink.close(),
      )) {
        buf.add(chunk);
        if (buf.length >= 48) break;
      }
    } catch (_) {}
    final raw = buf.takeBytes();
    if (raw.isEmpty) return null;
    final s = String.fromCharCodes(raw.where((b) => b >= 32 && b < 127))
        .trim();
    return s.isEmpty ? null : s;
  }

  static PosThermalPrinterBrand _guessBrand(String? model) {
    final t = (model ?? '').toLowerCase();
    if (t.contains('xprinter') ||
        t.contains('xp-') ||
        t.contains('xp80') ||
        t.contains('xp58')) {
      return PosThermalPrinterBrand.xprinter;
    }
    if (t.contains('zywell') || t.contains('zp-') || t.contains('zw-')) {
      return PosThermalPrinterBrand.zywell;
    }
    if (t.contains('hprt') || t.contains('tp80') || t.contains('pos80')) {
      return PosThermalPrinterBrand.hprt;
    }
    if (t.contains('epson') || t.contains('tm-')) {
      return PosThermalPrinterBrand.epson;
    }
    if (t.contains('rongta') || t.contains('rp80')) {
      return PosThermalPrinterBrand.rp80;
    }
    return PosThermalPrinterBrand.generic;
  }
}
