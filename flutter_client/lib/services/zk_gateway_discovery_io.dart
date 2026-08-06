import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/zk_gateway.dart';

/// Dò gateway bằng UDP. Chỉ dùng được trên nền tảng có `dart:io`
/// (Android, iOS, Windows, macOS, Linux).
///
/// Hỏi theo hai đường song song vì không đường nào chạy được ở mọi nơi:
///
///  - **Quảng bá** (một gói tới `x.y.z.255`): nhanh, nhưng iOS 14 trở lên chặn
///    hẳn broadcast nếu app không có entitlement
///    `com.apple.developer.networking.multicast` — thứ phải xin Apple duyệt
///    riêng. Vì vậy trên iPhone đường này luôn im lặng.
///  - **Quét từng địa chỉ** (gói unicast tới `x.y.z.1..254`): tốn 254 gói nhỏ
///    nhưng là unicast nên iOS cho qua, chỉ cần quyền mạng nội bộ. Firmware trả
///    lời đúng địa chỉ đã hỏi nên không phải sửa gì phía mạch.
Future<List<ZkGatewayInfo>> discoverGateways({
  required Duration duration,
  required String probe,
  required int port,
}) async {
  RawDatagramSocket? socket;
  final found = <String, ZkGatewayInfo>{};

  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    final sock = socket;
    sock.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = sock.receive();
      if (packet == null) return;
      try {
        final decoded = jsonDecode(utf8.decode(packet.data));
        if (decoded is! Map) return;
        final json = decoded.cast<String, dynamic>();
        if (json['product'] != ZkGatewayInfo.productId) return;
        final info = ZkGatewayInfo.fromJson(
          json,
          fallbackIp: packet.address.address,
        );
        found[info.ip.isEmpty ? packet.address.address : info.ip] = info;
      } catch (_) {
        // Gói lạ trên cùng cổng, bỏ qua.
      }
    });

    final payload = utf8.encode(probe);
    final interfaces = await _localIPv4();
    final broadcast = _broadcastTargets(interfaces);
    final sweep = _sweepTargets(interfaces);
    final deadline = DateTime.now().add(duration);

    // Gửi lặp lại vì UDP không bảo đảm tới đích.
    while (DateTime.now().isBefore(deadline)) {
      for (final target in broadcast) {
        try {
          sock.send(payload, target, port);
        } catch (_) {
          // Có giao diện mạng không cho broadcast, thử cái kế tiếp.
        }
      }
      await _sweepOnce(sock, payload, sweep, port, deadline);
      if (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
  } on SocketException catch (e) {
    debugPrint('discoverGateways: $e');
  } finally {
    socket?.close();
  }

  final list = found.values.toList();
  list.sort((a, b) => a.displayName.compareTo(b.displayName));
  return list;
}

/// Địa chỉ IPv4 của máy trên các mạng thật (bỏ loopback và link-local 169.254,
/// vì hai loại đó không dẫn tới mạch nào).
Future<List<String>> _localIPv4() async {
  final out = <String>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final itf in interfaces) {
      for (final addr in itf.addresses) {
        if (addr.address.startsWith('169.254.')) continue;
        if (addr.address.split('.').length == 4) out.add(addr.address);
      }
    }
  } catch (_) {
    // Không liệt kê được thì chỉ còn trông vào broadcast toàn cục.
  }
  return out;
}

/// Broadcast toàn cục cộng broadcast riêng của từng subnet: Android thường
/// chặn 255.255.255.255 nhưng vẫn cho x.y.z.255 đi qua.
List<InternetAddress> _broadcastTargets(List<String> localIPv4) {
  final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
  for (final ip in localIPv4) {
    final p = ip.split('.');
    final candidate = InternetAddress('${p[0]}.${p[1]}.${p[2]}.255');
    if (!targets.any((t) => t.address == candidate.address)) {
      targets.add(candidate);
    }
  }
  return targets;
}

/// Toàn bộ địa chỉ trong cùng dải /24 với máy, trừ chính nó và hai địa chỉ
/// đầu/cuối. Chỉ quét /24: mạng gia đình và văn phòng nhỏ đều vậy, còn quét
/// rộng hơn thì quá lâu để chờ trong màn hình cài đặt.
List<InternetAddress> _sweepTargets(List<String> localIPv4) {
  final seen = <String>{};
  final targets = <InternetAddress>[];
  for (final ip in localIPv4) {
    final p = ip.split('.');
    final prefix = '${p[0]}.${p[1]}.${p[2]}';
    for (var host = 1; host <= 254; host++) {
      final candidate = '$prefix.$host';
      if (candidate == ip || !seen.add(candidate)) continue;
      targets.add(InternetAddress(candidate));
    }
  }
  return targets;
}

/// Rải gói theo từng cụm nhỏ. Bắn liền 254 gói dễ làm tràn bộ đệm gửi của
/// socket, lúc đó phần đuôi rơi mất và đúng mạch cần tìm có thể nằm ở đó.
Future<void> _sweepOnce(
  RawDatagramSocket sock,
  List<int> payload,
  List<InternetAddress> targets,
  int port,
  DateTime deadline,
) async {
  const batch = 32;
  for (var i = 0; i < targets.length; i += batch) {
    if (DateTime.now().isAfter(deadline)) return;
    final end = (i + batch).clamp(0, targets.length);
    for (var k = i; k < end; k++) {
      try {
        sock.send(payload, targets[k], port);
      } catch (_) {
        // Địa chỉ không gửi được thì bỏ qua, còn cả dải phía sau.
      }
    }
    await Future.delayed(const Duration(milliseconds: 12));
  }
}
