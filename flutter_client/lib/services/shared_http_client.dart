import 'package:http/http.dart' as http;

import 'auth_retry_client.dart';
import 'reference_get_cache_client.dart';
import 'shared_http_client_env_stub.dart'
    if (dart.library.io) 'shared_http_client_env_io.dart';

/// Client HTTP giữ kết nối (keep-alive) cho toàn app, kèm cache ngắn hạn cho GET dữ liệu
/// tham chiếu ([ReferenceGetCacheClient]). Không bao giờ `close()`.
final ReferenceGetCacheClient _persistentClient =
    ReferenceGetCacheClient(http.Client());

/// Client HTTP dùng chung cho các lệnh gọi API.
///
/// Hàm top-level `http.get/post…` tạo client mới cho mỗi request → trên Android/iOS
/// mỗi lệnh phải bắt tay TCP + TLS lại từ đầu. Dùng chung một client để giữ kết nối.
///
/// Khi chạy `flutter test`, trả về `http.Client()` mỗi lần để test giả lập API bằng
/// `http.runWithClient` vẫn nhận đúng MockClient của zone hiện tại (không cache).
/// Gặp 401 vì token vừa hết hạn → [AuthRetryClient] làm mới rồi gửi lại 1 lần.
final AuthRetryClient _authRetryClient = AuthRetryClient(_persistentClient);

http.Client get sharedHttpClient =>
    isRunningFlutterTest ? http.Client() : _authRetryClient;

/// Xoá cache GET tham chiếu — gọi khi đăng xuất / đổi cửa hàng / nhận sự kiện realtime
/// báo dữ liệu danh mục thay đổi.
void clearSharedHttpCache() => _persistentClient.clear();
