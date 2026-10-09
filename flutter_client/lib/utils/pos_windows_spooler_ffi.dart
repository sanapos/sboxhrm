import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Hàng đợi in Windows (winspool.drv). Chỉ gọi khi [isSupported] — Android / iOS không có winspool.
/// Mọi lệnh chạy trong isolate riêng: mở máy in mạng / máy đang treo có thể chặn vài giây.
class PosWindowsSpooler {
  PosWindowsSpooler._();

  static bool get isSupported => Platform.isWindows;

  /// Tên các máy in đã cài (máy cục bộ + máy chia sẻ qua mạng).
  static Future<List<String>> listPrinters() async {
    if (!isSupported) return const [];
    try {
      return await Isolate.run(_listPrinters);
    } catch (e) {
      debugPrint('PosWindowsSpooler.listPrinters: $e');
      return const [];
    }
  }

  static Future<String?> defaultPrinter() async {
    if (!isSupported) return null;
    try {
      return await Isolate.run(_defaultPrinter);
    } catch (e) {
      debugPrint('PosWindowsSpooler.defaultPrinter: $e');
      return null;
    }
  }

  /// Mở được máy in (còn cài trên Windows, spooler đang chạy).
  static Future<bool> canOpen(String printerName) async {
    if (!isSupported || printerName.trim().isEmpty) return false;
    try {
      return await Isolate.run(() => _canOpen(printerName));
    } catch (e) {
      debugPrint('PosWindowsSpooler.canOpen: $e');
      return false;
    }
  }

  /// Gửi byte ESC/POS thô. true = spooler đã nhận đủ byte (máy in sẽ in theo hàng đợi Windows).
  static Future<bool> writeRaw(String printerName, List<int> bytes, {String docName = 'SBOX POS'}) async {
    if (!isSupported || printerName.trim().isEmpty || bytes.isEmpty) return false;
    final data = Uint8List.fromList(bytes);
    try {
      return await Isolate.run(() => _writeRaw(printerName, data, docName));
    } catch (e) {
      debugPrint('PosWindowsSpooler.writeRaw: $e');
      return false;
    }
  }
}

List<String> _listPrinters() {
  const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
  final needed = calloc<Uint32>();
  final returned = calloc<Uint32>();
  try {
    EnumPrinters(flags, nullptr, 4, nullptr, 0, needed, returned);
    if (needed.value == 0) return const [];
    final buf = calloc<Uint8>(needed.value);
    try {
      if (EnumPrinters(flags, nullptr, 4, buf, needed.value, needed, returned) == 0) return const [];
      final infos = buf.cast<PRINTER_INFO_4>();
      final out = <String>[];
      for (var i = 0; i < returned.value; i++) {
        final name = infos[i].pPrinterName;
        if (name != nullptr) out.add(name.toDartString());
      }
      return out;
    } finally {
      calloc.free(buf);
    }
  } finally {
    calloc.free(needed);
    calloc.free(returned);
  }
}

String? _defaultPrinter() {
  final size = calloc<Uint32>()..value = 0;
  try {
    GetDefaultPrinter(nullptr, size);
    if (size.value == 0) return null;
    final buf = calloc<Uint16>(size.value).cast<Utf16>();
    try {
      if (GetDefaultPrinter(buf, size) == 0) return null;
      return buf.toDartString();
    } finally {
      calloc.free(buf);
    }
  } finally {
    calloc.free(size);
  }
}

bool _canOpen(String printerName) {
  final name = printerName.toNativeUtf16();
  final handle = calloc<IntPtr>();
  try {
    if (OpenPrinter(name, handle, nullptr) == 0) return false;
    ClosePrinter(handle.value);
    return true;
  } finally {
    calloc.free(name);
    calloc.free(handle);
  }
}

bool _writeRaw(String printerName, Uint8List data, String docName) {
  final name = printerName.toNativeUtf16();
  final handle = calloc<IntPtr>();
  final doc = calloc<DOC_INFO_1>();
  final docNamePtr = docName.toNativeUtf16();
  final rawType = 'RAW'.toNativeUtf16();
  final buf = calloc<Uint8>(data.length);
  final written = calloc<Uint32>();
  try {
    if (OpenPrinter(name, handle, nullptr) == 0) return false;
    final h = handle.value;
    try {
      doc.ref
        ..pDocName = docNamePtr
        ..pOutputFile = nullptr
        ..pDatatype = rawType;
      if (StartDocPrinter(h, 1, doc) == 0) return false;
      var ok = false;
      try {
        if (StartPagePrinter(h) == 0) return false;
        buf.asTypedList(data.length).setAll(0, data);
        ok = WritePrinter(h, buf, data.length, written) != 0 && written.value == data.length;
        EndPagePrinter(h);
      } finally {
        EndDocPrinter(h);
      }
      return ok;
    } finally {
      ClosePrinter(h);
    }
  } finally {
    calloc.free(name);
    calloc.free(handle);
    calloc.free(doc);
    calloc.free(docNamePtr);
    calloc.free(rawType);
    calloc.free(buf);
    calloc.free(written);
  }
}
