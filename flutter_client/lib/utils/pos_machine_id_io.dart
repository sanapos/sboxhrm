import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Mã máy của bản Windows: `MachineGuid` trong registry — Windows sinh một lần lúc cài hệ điều hành,
/// giữ nguyên khi gỡ / cài lại app và khi xóa dữ liệu app. Dùng làm mã máy bền cho bán offline
/// (máy chủ cấp dải số hóa đơn theo mã này để kiểm soát; UUID lưu trong thiết lập app thì xóa được).
///
/// Trả null nếu không phải Windows hoặc không đọc được registry.
String? readWindowsMachineGuid() {
  if (!Platform.isWindows) return null;
  final subKey = r'SOFTWARE\Microsoft\Cryptography'.toNativeUtf16();
  final valueName = 'MachineGuid'.toNativeUtf16();
  // MachineGuid là chuỗi 36 ký tự + NUL → 128 byte là thừa đủ.
  const bufferBytes = 128;
  final data = calloc<Uint16>(bufferBytes ~/ 2);
  final size = calloc<Uint32>()..value = bufferBytes;
  try {
    final result = RegGetValue(
      HKEY_LOCAL_MACHINE,
      subKey,
      valueName,
      // App 32-bit trên Windows 64-bit bị chuyển hướng sang Wow6432Node (không có MachineGuid)
      // → đọc thẳng nhánh 64-bit cho mọi kiến trúc.
      RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY,
      nullptr,
      data.cast(),
      size,
    );
    if (result != ERROR_SUCCESS) return null;
    final guid = data.cast<Utf16>().toDartString().trim();
    // Chuỗi rỗng / rác thì coi như không đọc được, để bên gọi dùng đường dự phòng.
    return guid.length < 8 ? null : guid;
  } catch (e) {
    debugPrint('readWindowsMachineGuid: $e');
    return null;
  } finally {
    calloc.free(subKey);
    calloc.free(valueName);
    calloc.free(data);
    calloc.free(size);
  }
}
