// Chọn cách dò tìm theo nền tảng lúc biên dịch.
//
// Bắt buộc phải tách như vậy: `dart:io` không tồn tại trên web, chỉ cần import
// là cả bản build web đứt, kể cả khi đã chặn bằng `kIsWeb` lúc chạy.
export 'zk_gateway_discovery_stub.dart'
    if (dart.library.io) 'zk_gateway_discovery_io.dart';
