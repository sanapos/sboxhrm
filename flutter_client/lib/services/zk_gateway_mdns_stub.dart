import '../models/zk_gateway.dart';

/// Web: không có mDNS socket — trả rỗng.
Future<List<ZkGatewayInfo>> discoverGatewaysViaMdns({
  Duration duration = const Duration(seconds: 4),
}) async =>
    const [];

/// Web: không resolve được `.local` qua Bonjour.
Future<List<String>> resolveMdnsHost(String host, {Duration timeout = const Duration(seconds: 3)}) async =>
    const [];
