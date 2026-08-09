// Chọn mDNS theo nền tảng — `multicast_dns` / `dart:io` không có trên web.
export 'zk_gateway_mdns_stub.dart'
    if (dart.library.io) 'zk_gateway_mdns_io.dart';
