import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

import '../models/zk_gateway.dart';

/// Service type khớp `mdns_service_add(..., "_sboxgw", "_tcp", ...)` trên ESP.
const _sboxService = '_sboxgw._tcp.local';

/// Hostname cố định (không gồm `.local`) khớp firmware `sboxadms`.
const _portalHostname = 'sboxadms.local';

/// Dò gateway qua Bonjour/mDNS — đường Safari dùng trên iPhone.
///
/// Quét PTR `_sboxgw._tcp` rồi lấy A/AAAA; đồng thời resolve `sboxadms.local`.
/// Việc mở multicast UDP kích hoạt hộp thoại **Mạng cục bộ** trên iOS 14+.
Future<List<ZkGatewayInfo>> discoverGatewaysViaMdns({
  Duration duration = const Duration(seconds: 4),
}) async {
  final ips = <String>{};
  MDnsClient? client;
  try {
    client = _newClient();
    await client.start();

    final queries = <Future<void>>[
      _collectServiceIps(client, _sboxService, ips),
      _collectHostIps(client, _portalHostname, ips),
    ];

    await Future.any([
      Future.wait(queries).catchError((_) => <void>[]),
      Future.delayed(duration),
    ]);
  } catch (e) {
    debugPrint('discoverGatewaysViaMdns: $e');
  } finally {
    client?.stop();
  }

  debugPrint('discoverGatewaysViaMdns: ips=${ips.toList()}');
  return [
    for (final ip in ips)
      ZkGatewayInfo(ip: ip, host: _portalHostname.replaceAll('.local', '')),
  ];
}

/// Resolve một hostname `.local` → danh sách IPv4 (và IPv6 nếu có).
Future<List<String>> resolveMdnsHost(
  String host, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final name = host.contains('.') ? host : '$host.local';
  final ips = <String>{};
  MDnsClient? client;
  try {
    client = _newClient();
    await client.start();
    await Future.any([
      _collectHostIps(client, name, ips),
      Future.delayed(timeout),
    ]);
  } catch (e) {
    debugPrint('resolveMdnsHost($name): $e');
  } finally {
    client?.stop();
  }
  return ips.toList();
}

MDnsClient _newClient() {
  return MDnsClient(rawDatagramSocketFactory: (
    dynamic host,
    int port, {
    bool reuseAddress = false,
    bool reusePort = false,
    int ttl = 1,
  }) {
    return RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: true,
      // reusePort gây lỗi trên một số iOS; tắt mặc định.
      reusePort: false,
      ttl: ttl,
    );
  });
}

Future<void> _collectServiceIps(
  MDnsClient client,
  String serviceType,
  Set<String> ips,
) async {
  try {
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(serviceType),
    )) {
      await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      )) {
        await _collectHostIps(client, srv.target, ips);
      }
    }
  } catch (e) {
    debugPrint('mdns service $serviceType: $e');
  }
}

Future<void> _collectHostIps(
  MDnsClient client,
  String host,
  Set<String> ips,
) async {
  final name = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
  try {
    await for (final IPAddressResourceRecord a
        in client.lookup<IPAddressResourceRecord>(
      ResourceRecordQuery.addressIPv4(name),
    )) {
      final ip = a.address.address;
      if (_usableIp(ip)) ips.add(ip);
    }
  } catch (_) {}
  try {
    await for (final IPAddressResourceRecord a
        in client.lookup<IPAddressResourceRecord>(
      ResourceRecordQuery.addressIPv6(name),
    )) {
      final ip = a.address.address;
      // HTTP client thường cần IPv4 trong LAN; vẫn giữ nếu không có IPv4.
      if (_usableIp(ip) && ips.isEmpty) ips.add(ip);
    }
  } catch (_) {}
}

bool _usableIp(String ip) {
  if (ip.isEmpty) return false;
  if (ip.startsWith('127.')) return false;
  if (ip.startsWith('169.254.')) return false;
  return true;
}
