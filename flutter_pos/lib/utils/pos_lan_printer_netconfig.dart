import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pos_thermal_printer_settings.dart';

/// Dò máy in LAN bằng UDP broadcast (tới được máy in KHÁC lớp mạng IP nhưng cùng
/// mạng vật lý — vd. máy in còn IP nhà máy 192.168.123.100, Wi‑Fi cửa hàng 192.168.1.x)
/// và đặt IP tĩnh cho máy in qua mạng.
///
/// Chỉ dùng giao thức đã đối chiếu với mã nguồn / tài liệu hãng (không đoán):
/// - Xprinter: SDK Android 3.x `net.posprinter.esc.PosUdpNet` (searchNetDevice /
///   udpNetConfig) + `net.posprinter.model.UdpDevice` — jar trong
///   https://github.com/KickNext/pos_printers (android/libs/classes.jar).
///   UDP 9000, «XP0001FIND» / «XP0001FOUND» / «XP0001SAVE».
/// - Rongta: SDK RTPrinter `com.rt.printerlibrary.ipscan.IpScanner` / `IpUpdata` —
///   jar trong https://github.com/warrence/rongta-capacitor-thermal-printer
///   (android/libs/printer_library.jar). UDP 1460, «MP4200FIND/FOUND/SAVE».
///   Máy Zywell ZY80-Q2 thật cũng trả lời họ này; gói FOUND bắt được (64 byte) xác nhận
///   IP/mask/gw ở offset 19/23/27 như Xprinter và tên model ASCII (kết thúc 00) ở offset 34.
/// - Epson: ENPC UDP 3289 (Epson UB-E04 Technical Reference Guide,
///   https://files.support.epson.com/pdf/ube04_/ube04_trg.pdf). Gói dò lấy từ SANE
///   backend epson2.c (https://gitlab.com/sane-project/backends). Chỉ DÒ — layout gói
///   «Setup» đổi IP không có nguồn công khai, nên không cài; đổi IP Epson dùng
///   ARP + ping từ máy tính (SBOX Print Agent) hoặc EpsonNet Config.
/// Ghi chú nghiên cứu đầy đủ: docs/printers/lan-printer-ip-protocols.md.
enum PosLanNetProto {
  xprinter('Xprinter / tương thích', 9000),
  rongta('Rongta / tương thích', 1460),
  epson('Epson (ENPC)', 3289);

  const PosLanNetProto(this.label, this.udpPort);
  final String label;
  final int udpPort;

  /// Đổi IP qua mạng được (có gói SAVE đã xác minh).
  bool get canSetIp => this != PosLanNetProto.epson;

  PosThermalPrinterBrand get brand => switch (this) {
        PosLanNetProto.xprinter => PosThermalPrinterBrand.xprinter,
        PosLanNetProto.rongta => PosThermalPrinterBrand.rp80,
        PosLanNetProto.epson => PosThermalPrinterBrand.epson,
      };
}

/// Máy in trả lời gói dò UDP.
class PosLanNetDevice {
  const PosLanNetDevice({
    required this.proto,
    required this.ip,
    this.mac,
    this.mask,
    this.gateway,
    this.dhcp,
    this.model,
    this.keep17,
    this.keep31,
  });

  final PosLanNetProto proto;
  final String ip;

  /// 6 byte; gói SAVE chọn máy in theo MAC.
  final Uint8List? mac;
  final String? mask;
  final String? gateway;
  final bool? dhcp;
  final String? model;

  /// Byte FOUND 17..18 và 31..32 (SDK không đọc; 31..32 = 8C 23 = 9100 LE trên ZY80-Q2 — nhiều khả
  /// năng là cổng in). Gói SAVE lệch FOUND đúng 1 byte, nên gửi lại nguyên giá trị máy đang báo
  /// thay hằng SDK để không đổi nhầm cổng in. Đã thử thật: ZY80-Q2 .89 → .201 → .89, giữ 9100.
  final Uint8List? keep17;
  final Uint8List? keep31;

  String get macText => mac == null
      ? ''
      : mac!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();

  String get key => mac != null ? '${proto.name}/$macText' : '${proto.name}/$ip';

  bool get canSetIp => proto.canSetIp && mac != null && mac!.length == 6;

  /// Zywell dùng module chung giao thức Rongta (model «ZY80-Q2»…).
  PosThermalPrinterBrand get brand {
    final m = (model ?? '').toUpperCase();
    if (m.startsWith('ZY') || m.contains('ZYWELL')) return PosThermalPrinterBrand.zywell;
    if (m.startsWith('XP')) return PosThermalPrinterBrand.xprinter;
    return proto.brand;
  }

  String get title => model != null ? '$model · $ip' : '${proto.label} · $ip';
}

/// Dựng / đọc gói tin (thuần, có unit test).
class PosLanNetCodec {
  PosLanNetCodec._();

  static final xpFind = _ascii('XP0001FIND');
  static final rtFind = _ascii('MP4200FIND');

  /// SANE epson2.c: "EPSONP\x00\xff\x00\x00\x00\x00\x00\x00\x00" (15 byte, Probe).
  static final epsonProbe = Uint8List.fromList(
      [..._ascii('EPSONP'), 0x00, 0xFF, 0, 0, 0, 0, 0, 0, 0]);

  static Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);

  static bool _startsWith(Uint8List d, List<int> tag) {
    if (d.length < tag.length) return false;
    for (var i = 0; i < tag.length; i++) {
      if (d[i] != tag[i]) return false;
    }
    return true;
  }

  static String _ip(Uint8List d, int o) => '${d[o]}.${d[o + 1]}.${d[o + 2]}.${d[o + 3]}';

  static bool _isZero(Uint8List d, int o) => d[o] == 0 && d[o + 1] == 0 && d[o + 2] == 0 && d[o + 3] == 0;

  /// Chuỗi ASCII in được, kết thúc bằng 00 (tên model); null nếu rỗng / lẫn byte rác.
  static String? _cString(Uint8List d, int o) {
    final out = StringBuffer();
    for (var i = o; i < d.length && d[i] != 0; i++) {
      // Sau khi đổi IP, vùng này có thể còn rác bộ nhớ — chỉ nhận ký tự tên model.
      final c = d[i];
      final ok = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) ||
          c == 0x20 || c == 0x2D || c == 0x5F || c == 0x2E || c == 0x2F;
      if (!ok) return null;
      out.writeCharCode(d[i]);
    }
    final s = out.toString().trim();
    return s.length >= 2 ? s : null;
  }

  /// [sourceIp]: địa chỉ gửi gói (Rongta/Epson không có IP trong phần đọc được của SDK).
  static PosLanNetDevice? parse(Uint8List d, String sourceIp) {
    // UdpDevice(byte[]): MAC 11..16, IP 19, mask 23, gw 27, DHCP [33] == 1.
    if (_startsWith(d, _ascii('XP0001FOUND')) && d.length >= 34) {
      return PosLanNetDevice(
        proto: PosLanNetProto.xprinter,
        mac: Uint8List.fromList(d.sublist(11, 17)),
        ip: _ip(d, 19),
        mask: _ip(d, 23),
        gateway: _ip(d, 27),
        dhcp: d[33] == 1,
        keep17: Uint8List.fromList(d.sublist(17, 19)),
        keep31: Uint8List.fromList(d.sublist(31, 33)),
      );
    }
    // IpScanner: MAC 11..16, DHCP [33] != 0 (SDK lấy IP từ nguồn gói). IP/mask/gw 19/23/27
    // và model từ offset 34: theo gói thật của Zywell ZY80-Q2 (xem chú thích đầu file).
    if (_startsWith(d, _ascii('MP4200FOUND')) && d.length >= 34) {
      final ip = _ip(d, 19);
      return PosLanNetDevice(
        proto: PosLanNetProto.rongta,
        mac: Uint8List.fromList(d.sublist(11, 17)),
        ip: _isZero(d, 19) ? sourceIp : ip,
        mask: _isZero(d, 23) ? null : _ip(d, 23),
        gateway: _isZero(d, 27) ? null : _ip(d, 27),
        dhcp: d[33] != 0,
        model: _cString(d, 34),
        keep17: Uint8List.fromList(d.sublist(17, 19)),
        keep31: Uint8List.fromList(d.sublist(31, 33)),
      );
    }
    // ENPC: "EPSON" + loại gói; trả lời viết thường (gói dò của chính mình là 'P').
    if (_startsWith(d, _ascii('EPSON')) && d.length >= 6 && d[5] >= 0x61 && d[5] <= 0x7A) {
      return PosLanNetDevice(proto: PosLanNetProto.epson, ip: sourceIp);
    }
    return null;
  }

  /// Gói SAVE (33 byte) đặt IP tĩnh. Byte 16..17 / 30..31: giá trị máy đang báo ([keep17] / [keep31]
  /// từ FOUND) nếu có, không thì hằng số của SDK hãng.
  static Uint8List save(
    PosLanNetProto proto, {
    required Uint8List mac,
    required String ip,
    required String mask,
    required String gateway,
    Uint8List? keep17,
    Uint8List? keep31,
  }) {
    List<int> pick(Uint8List? k, List<int> sdk) => k != null && k.length == 2 ? k : sdk;
    if (mac.length != 6) throw ArgumentError('MAC phải 6 byte');
    final ipB = parseIpv4(ip), maskB = parseIpv4(mask), gwB = parseIpv4(gateway);
    if (ipB == null || maskB == null || gwB == null) {
      throw ArgumentError('IP / mask / gateway không hợp lệ');
    }
    final b = BytesBuilder();
    switch (proto) {
      case PosLanNetProto.xprinter:
        // udpNetConfig: tag + MAC + 22 00 + IP + mask + gw + 8C 17 + dhcp (00 = tĩnh).
        b
          ..add(_ascii('XP0001SAVE'))
          ..add(mac)
          ..add(pick(keep17, const [0x22, 0x00]))
          ..add(ipB)
          ..add(maskB)
          ..add(gwB)
          ..add(pick(keep31, const [0x8C, 0x17]))
          ..addByte(0x00);
      case PosLanNetProto.rongta:
        // IpUpdata: tag + MAC + 0F 00 + IP + mask + gw + 05 B4 + 00.
        b
          ..add(_ascii('MP4200SAVE'))
          ..add(mac)
          ..add(pick(keep17, const [0x0F, 0x00]))
          ..add(ipB)
          ..add(maskB)
          ..add(gwB)
          ..add(pick(keep31, const [0x05, 0xB4]))
          ..addByte(0x00);
      case PosLanNetProto.epson:
        throw UnsupportedError('Epson: không có gói đổi IP đã xác minh');
    }
    return b.toBytes();
  }
}

// —— IPv4 (thuần) ——

Uint8List? parseIpv4(String s) {
  final parts = s.trim().split('.');
  if (parts.length != 4) return null;
  final out = Uint8List(4);
  for (var i = 0; i < 4; i++) {
    final p = parts[i];
    if (p.isEmpty || p.length > 3 || !RegExp(r'^\d+$').hasMatch(p)) return null;
    final v = int.parse(p);
    if (v > 255) return null;
    out[i] = v;
  }
  return out;
}

int? _ipInt(String s) {
  final b = parseIpv4(s);
  if (b == null) return null;
  return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}

String _intIp(int v) => '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

String prefixToMask(int prefix) {
  final p = prefix.clamp(0, 32);
  final v = p == 0 ? 0 : (0xFFFFFFFF << (32 - p)) & 0xFFFFFFFF;
  return _intIp(v);
}

/// Mask hợp lệ (dãy bit 1 liền nhau), 8..30 bit.
bool isValidMask(String mask) {
  final m = _ipInt(mask);
  if (m == null) return false;
  final inv = (~m) & 0xFFFFFFFF;
  if ((inv & (inv + 1)) != 0) return false;
  final bits = 32 - inv.bitLength;
  return bits >= 8 && bits <= 30;
}

bool sameSubnet(String a, String b, String mask) {
  final x = _ipInt(a), y = _ipInt(b), m = _ipInt(mask);
  if (x == null || y == null || m == null) return false;
  return (x & m) == (y & m);
}

/// IP dùng được cho máy trong lớp mạng (không phải địa chỉ mạng / broadcast).
bool isUsableHost(String ip, String mask) {
  final x = _ipInt(ip), m = _ipInt(mask);
  if (x == null || m == null) return false;
  final host = x & ~m & 0xFFFFFFFF;
  return host != 0 && host != (~m & 0xFFFFFFFF);
}

/// Thứ tự thử IP trống trong lớp mạng của máy POS: .200–.250 rồi .100–.199
/// (tránh dải DHCP thường cấp ở đầu dải), bỏ IP máy POS / gateway / [avoid].
List<String> freeIpCandidates(String localIp, String mask, String gateway,
    {Set<String> avoid = const {}}) {
  final x = _ipInt(localIp), m = _ipInt(mask);
  if (x == null || m == null) return const [];
  final net = x & m;
  final hostMax = (~m & 0xFFFFFFFF) - 1;
  final order = <int>[
    for (var i = 200; i <= 250; i++) i,
    for (var i = 100; i < 200; i++) i,
  ];
  final out = <String>[];
  for (final h in order) {
    if (h < 1 || h > hostMax) continue;
    final ip = _intIp(net | h);
    if (ip == localIp || ip == gateway || avoid.contains(ip)) continue;
    out.add(ip);
  }
  return out;
}

/// Mạng của máy POS (IP + mask + gateway). Android đọc từ LinkProperties; nơi khác giả định /24 và gateway .1.
class PosLanLink {
  const PosLanLink({required this.ip, required this.mask, required this.gateway});
  final String ip;
  final String mask;
  final String gateway;
}

/// Dò / đổi IP qua UDP (dart:io).
class PosLanNetConfig {
  PosLanNetConfig._();

  static const _channel = MethodChannel('sbox/lan_printer_net');

  /// Android lọc gói broadcast khi không giữ WifiManager.MulticastLock.
  static Future<void> _multicastLock(bool on) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('multicastLock', {'on': on});
    } catch (e) {
      debugPrint('PosLanNetConfig.multicastLock: $e');
    }
  }

  static Future<List<PosLanLink>> localLinks(List<InternetAddress> locals) async {
    final out = <PosLanLink>[];
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final r = await _channel.invokeMethod<List<dynamic>>('links');
        for (final e in r ?? const []) {
          final m = Map<String, dynamic>.from(e as Map);
          final ip = '${m['ip'] ?? ''}';
          final prefix = (m['prefix'] as num?)?.toInt() ?? 24;
          if (parseIpv4(ip) == null) continue;
          final mask = prefixToMask(prefix);
          var gw = '${m['gateway'] ?? ''}';
          if (parseIpv4(gw) == null || !sameSubnet(gw, ip, mask)) gw = _guessGateway(ip, mask);
          out.add(PosLanLink(ip: ip, mask: mask, gateway: gw));
        }
      } catch (e) {
        debugPrint('PosLanNetConfig.links: $e');
      }
    }
    for (final a in locals) {
      if (out.any((l) => l.ip == a.address)) continue;
      const mask = '255.255.255.0';
      out.add(PosLanLink(ip: a.address, mask: mask, gateway: _guessGateway(a.address, mask)));
    }
    return out;
  }

  static String _guessGateway(String ip, String mask) =>
      _intIp((_ipInt(ip)! & _ipInt(mask)!) | 1);

  static Future<RawDatagramSocket> _bind() async {
    // Xprinter SDK bind cổng 9000 (máy in trả lời về cổng này); bận thì dùng cổng tạm.
    try {
      return await RawDatagramSocket.bind(InternetAddress.anyIPv4, 9000, reuseAddress: true);
    } catch (_) {
      return RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
  }

  static final _broadcast = InternetAddress('255.255.255.255');

  /// Gửi gói dò của cả 3 họ (nhiều lần — UDP có thể rơi), gom trả lời trong [timeout].
  static Future<List<PosLanNetDevice>> discover({
    Duration timeout = const Duration(milliseconds: 2500),
    void Function(PosLanNetDevice d)? onFound,
  }) async {
    if (kIsWeb) return const [];
    final found = <String, PosLanNetDevice>{};
    await _multicastLock(true);
    RawDatagramSocket? sock;
    try {
      sock = await _bind();
      sock.broadcastEnabled = true;
      final s = sock;
      final sub = s.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        Datagram? dg;
        while ((dg = s.receive()) != null) {
          final dev = PosLanNetCodec.parse(dg!.data, dg.address.address);
          if (dev == null) continue;
          if (found.containsKey(dev.key)) continue;
          found[dev.key] = dev;
          onFound?.call(dev);
        }
      });
      void sendAll() {
        try {
          s.send(PosLanNetCodec.xpFind, _broadcast, PosLanNetProto.xprinter.udpPort);
          s.send(PosLanNetCodec.rtFind, _broadcast, PosLanNetProto.rongta.udpPort);
          s.send(PosLanNetCodec.epsonProbe, _broadcast, PosLanNetProto.epson.udpPort);
        } catch (e) {
          debugPrint('PosLanNetConfig.send: $e');
        }
      }

      const rounds = 3;
      final step = Duration(milliseconds: timeout.inMilliseconds ~/ (rounds + 1));
      for (var i = 0; i < rounds; i++) {
        sendAll();
        await Future<void>.delayed(step);
      }
      await Future<void>.delayed(step);
      await sub.cancel();
    } catch (e) {
      debugPrint('PosLanNetConfig.discover: $e');
    } finally {
      sock?.close();
      await _multicastLock(false);
    }
    return found.values.toList();
  }

  /// Gửi gói SAVE (broadcast, chọn máy theo MAC) — 3 lần cho chắc, không có ACK chuẩn.
  static Future<void> sendStaticIp(PosLanNetDevice dev,
      {required String ip, required String mask, required String gateway}) async {
    final pkt = PosLanNetCodec.save(dev.proto,
        mac: dev.mac!, ip: ip, mask: mask, gateway: gateway, keep17: dev.keep17, keep31: dev.keep31);
    await _multicastLock(true);
    RawDatagramSocket? sock;
    try {
      sock = await _bind();
      sock.broadcastEnabled = true;
      for (var i = 0; i < 3; i++) {
        sock.send(pkt, _broadcast, dev.proto.udpPort);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      sock?.close();
      await _multicastLock(false);
    }
  }

  /// Chờ máy in lên IP mới: TCP 9100 mở được, hoặc dò thấy đúng MAC với IP mới.
  static Future<bool> waitForIp(PosLanNetDevice dev, String ip,
      {Duration timeout = const Duration(seconds: 20), bool Function()? isCancelled}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (isCancelled?.call() == true) return false;
      if (await tcpOpen(ip, 9100)) return true;
      final list = await discover(timeout: const Duration(milliseconds: 1500));
      if (list.any((d) => d.key == dev.key && d.ip == ip)) {
        // Thấy IP mới nhưng 9100 chưa mở (đang khởi động lại) — thử thêm.
        if (await tcpOpen(ip, 9100, timeout: const Duration(seconds: 2))) return true;
      }
    }
    return false;
  }

  static Future<bool> tcpOpen(String host, int port,
      {Duration timeout = const Duration(milliseconds: 800)}) async {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// IP đã có máy dùng? TCP tới vài cổng phổ biến (kết nối được hoặc bị từ chối
  /// ngay = có máy), thêm ping hệ điều hành nếu có. Không chắc 100% (máy chặn hết sẽ lọt).
  static Future<bool> isIpInUse(String ip) async {
    if (kIsWeb) return false;
    const ports = [9100, 80, 443, 515, 631, 22, 53, 8080, 554, 445, 62078];
    final tcp = await Future.wait(ports.map((p) => _tcpAlive(ip, p)));
    if (tcp.any((x) => x)) return true;
    return _ping(ip);
  }

  static Future<bool> _tcpAlive(String ip, int port) async {
    try {
      final s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 700));
      s.destroy();
      return true;
    } on SocketException catch (e) {
      // ECONNREFUSED: Linux/Android 111, macOS/iOS 61, Windows 10061 → máy có thật.
      final c = e.osError?.errorCode;
      return c == 111 || c == 61 || c == 10061;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _ping(String ip) async {
    try {
      final ProcessResult r;
      if (Platform.isWindows) {
        r = await Process.run('ping', ['-n', '1', '-w', '800', ip])
            .timeout(const Duration(seconds: 3));
        // Windows trả 0 cả khi «Destination host unreachable» — xem TTL=.
        return r.exitCode == 0 && '${r.stdout}'.toUpperCase().contains('TTL=');
      }
      r = await Process.run('ping', ['-c', '1', '-W', '1', ip])
          .timeout(const Duration(seconds: 3));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// IP trống đầu tiên trong lớp mạng [link] (kiểm tra lần lượt từng lô nhỏ).
  static Future<String?> suggestFreeIp(PosLanLink link,
      {Set<String> avoid = const {}, bool Function()? isCancelled}) async {
    final cands = freeIpCandidates(link.ip, link.mask, link.gateway, avoid: avoid);
    const batch = 6;
    for (var i = 0; i < cands.length && i < 60; i += batch) {
      if (isCancelled?.call() == true) return null;
      final chunk = cands.skip(i).take(batch).toList();
      final used = await Future.wait(chunk.map(isIpInUse));
      for (var j = 0; j < chunk.length; j++) {
        if (!used[j]) return chunk[j];
      }
    }
    return null;
  }
}
