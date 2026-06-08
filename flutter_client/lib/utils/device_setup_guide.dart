/// Hướng dẫn cấu hình máy chấm công ZKTeco kết nối ADMS cloud.
class DeviceSetupGuide {
  static const serverHost = '103.133.224.176';
  static const serverPort = '7070';
  static const menuPath = 'Thiết lập liên kết → Máy chủ đám mây';

  static const summary =
      'Trên máy ZKTeco: vào $menuPath, nhập Địa chỉ máy chủ: $serverHost, Port: $serverPort.';

  static const configureBeforeConnect =
      'Vui lòng vào $menuPath trên máy, nhập Địa chỉ máy chủ: $serverHost, Port: $serverPort, rồi thử lại.';

  static const emptyStateHint =
      'Cấu hình máy qua $menuPath\nĐịa chỉ máy chủ: $serverHost · Port: $serverPort\nSau đó máy sẽ tự xuất hiện tại đây.';
}
