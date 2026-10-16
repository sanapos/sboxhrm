import 'pos_scale_reader.dart';

/// Kết nối vật lý tới cân (cổng COM trên Windows / Web Serial trên Chrome, Edge).
abstract class PosScaleTransport {
  bool get supported;
  bool get isWeb;

  /// windows / android / web / none — câu hướng dẫn trong hộp thiết lập.
  String get kind;
  String get unsupportedReason;

  /// Windows: các cổng COM đang có. Web: danh sách mô tả cổng đã cấp quyền.
  Future<List<String>> listPorts();

  /// Web: hộp chọn cổng của trình duyệt (cần thao tác bấm). Windows: null.
  Future<({int? vendorId, int? productId})?> requestPort();

  Future<void> open(PosScaleDeviceSettings s, void Function(List<int> bytes) onData, void Function(String error) onError);
  Future<void> write(List<int> bytes);
  Future<void> close();
}
