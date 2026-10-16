import 'pos_scale_reader.dart';
import 'pos_scale_transport.dart';

class _Unsupported implements PosScaleTransport {
  @override
  bool get supported => false;
  @override
  bool get isWeb => false;
  @override
  String get unsupportedReason => 'Thiết bị này chưa hỗ trợ nối cân trực tiếp — dùng app Windows hoặc Chrome / Edge trên máy tính.';
  @override
  Future<List<String>> listPorts() async => const [];
  @override
  Future<({int? vendorId, int? productId})?> requestPort() async => null;
  @override
  Future<void> open(PosScaleDeviceSettings s, void Function(List<int> bytes) onData, void Function(String error) onError) async =>
      throw Exception(unsupportedReason);
  @override
  Future<void> write(List<int> bytes) async {}
  @override
  Future<void> close() async {}
}

PosScaleTransport createPosScaleTransport() => _Unsupported();
