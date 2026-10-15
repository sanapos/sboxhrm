import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.sboxhrm/file_saver');

/// Xóa bản ở thư mục Tải xuống / Ảnh (content:// của MediaStore hoặc đường dẫn tệp). Chỉ xóa được tệp do app tạo.
Future<bool> deletePublicCopy(String uriOrPath) async {
  try {
    if (uriOrPath.startsWith('content:')) {
      if (!Platform.isAndroid) return false;
      return await _channel.invokeMethod<bool>('deleteFile', {'uri': uriOrPath}) ?? false;
    }
    final f = File(uriOrPath);
    if (await f.exists()) {
      await f.delete();
      return true;
    }
    return false;
  } catch (e) {
    debugPrint('deletePublicCopy: $e');
    return false;
  }
}
