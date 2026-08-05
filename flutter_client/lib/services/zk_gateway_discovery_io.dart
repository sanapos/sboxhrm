import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/zk_gateway.dart';

/// Dò gateway bằng quảng bá UDP. Chỉ dùng được trên nền tảng có `dart:io`
/// (Android, iOS, Windows, macOS, Linux).
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
    final targets = await _broadcastTargets();
    final deadline = DateTime.now().add(duration);

    // Gửi lặp lại vì UDP không bảo đảm tới đích.
    while (DateTime.now().isBefore(deadline)) {
      for (final target in targets) {
        try {
          sock.send(payload, target, port);
        } catch (_) {
          // Có giao diện mạng không cho broadcast, thử cái kế tiếp.
        }
      }
      await Future.delayed(const Duration(milliseconds: 700));
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

/// Broadcast toàn cục cộng broadcast riêng của từng subnet: Android thường
/// chặn 255.255.255.255 nhưng vẫn cho x.y.z.255 đi qua.
Future<List<InternetAddress>> _broadcastTargets() async {
  final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final itf in interfaces) {
      for (final addr in itf.addresses) {
        final parts = addr.address.split('.');
        if (parts.length != 4) continue;
        final candidate = InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
        if (!targets.any((t) => t.address == candidate.address)) {
          targets.add(candidate);
        }
      }
    }
  } catch (_) {
    // Không liệt kê được giao diện thì vẫn còn broadcast toàn cục.
  }
  return targets;
}
