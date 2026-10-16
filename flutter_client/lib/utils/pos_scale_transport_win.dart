import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'pos_scale_reader.dart';
import 'pos_scale_transport_android.dart';
import 'pos_scale_transport.dart';

/// Cân qua cổng COM trên Windows (RS232, hoặc USB-Serial hiện thành COMx).
/// Đọc trong isolate riêng: ReadFile chặn tới khi hết thời gian chờ, không làm đơ giao diện.
class _WinComTransport implements PosScaleTransport {
  Isolate? _isolate;
  SendPort? _control;
  ReceivePort? _rx;

  @override
  bool get supported => Platform.isWindows;
  @override
  bool get isWeb => false;
  @override
  String get kind => 'windows';
  @override
  String get unsupportedReason =>
      'Thiết bị này chưa hỗ trợ nối cân trực tiếp — dùng app Windows hoặc Chrome / Edge trên máy tính.';

  @override
  Future<List<String>> listPorts() async {
    if (!supported) return const [];
    try {
      final ports = await Isolate.run(_listComPorts);
      ports.sort((a, b) => (int.tryParse(a.substring(3)) ?? 0).compareTo(int.tryParse(b.substring(3)) ?? 0));
      return ports;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<({int? vendorId, int? productId})?> requestPort() async => null;

  @override
  Future<void> open(PosScaleDeviceSettings s, void Function(List<int> bytes) onData, void Function(String error) onError) async {
    await close();
    if (s.port.trim().isEmpty) throw Exception('Chưa chọn cổng COM của cân');
    final ports = await listPorts();
    if (!ports.any((p) => p.toUpperCase() == s.port.trim().toUpperCase())) {
      throw Exception('Không thấy ${s.port} — kiểm tra cáp cân / driver USB-Serial (cổng đang có: '
          '${ports.isEmpty ? 'không có' : ports.join(', ')})');
    }
    final rx = ReceivePort();
    final ready = Completer<String?>();
    rx.listen((msg) {
      if (msg is SendPort) {
        _control = msg;
      } else if (msg is TransferableTypedData) {
        onData(msg.materialize().asUint8List());
      } else if (msg is _Status) {
        if (!ready.isCompleted) {
          ready.complete(msg.error);
        } else if (msg.error != null) {
          onError(msg.error!);
        }
      }
    });
    _rx = rx;
    _isolate = await Isolate.spawn(
      _readLoop,
      _OpenArgs(rx.sendPort, s.port.trim(), s.baudRate, s.dataBits, s.parity, s.stopBits),
      debugName: 'pos-scale-com',
    );
    final err = await ready.future.timeout(const Duration(seconds: 5), onTimeout: () => 'Không mở được ${s.port}');
    if (err != null) {
      await close();
      throw Exception(err);
    }
  }

  @override
  Future<void> write(List<int> bytes) async => _control?.send(Uint8List.fromList(bytes));

  @override
  Future<void> close() async {
    _control?.send('close');
    _control = null;
    // Cho isolate đóng cổng gọn rồi mới kill (cổng COM bị giữ thì lần mở sau báo «đang bận»).
    final iso = _isolate;
    _isolate = null;
    if (iso != null) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      iso.kill(priority: Isolate.immediate);
    }
    _rx?.close();
    _rx = null;
  }
}

class _OpenArgs {
  const _OpenArgs(this.reply, this.port, this.baud, this.dataBits, this.parity, this.stopBits);
  final SendPort reply;
  final String port;
  final int baud;
  final int dataBits;
  final String parity;
  final int stopBits;
}

class _Status {
  const _Status(this.error);
  final String? error;
}

/// Các cổng COM đang có (HKLM\HARDWARE\DEVICEMAP\SERIALCOMM).
List<String> _listComPorts() {
  final out = <String>[];
  final hKey = calloc<HKEY>();
  final subKey = r'HARDWARE\DEVICEMAP\SERIALCOMM'.toNativeUtf16();
  try {
    if (RegOpenKeyEx(HKEY_LOCAL_MACHINE, subKey, 0, REG_SAM_FLAGS.KEY_READ, hKey) != WIN32_ERROR.ERROR_SUCCESS) {
      return out;
    }
    final name = wsalloc(256);
    final data = calloc<Uint8>(512);
    final nameLen = calloc<Uint32>();
    final dataLen = calloc<Uint32>();
    try {
      for (var i = 0; i < 256; i++) {
        nameLen.value = 256;
        dataLen.value = 512;
        final r = RegEnumValue(hKey.value, i, name, nameLen, nullptr, nullptr, data, dataLen);
        if (r != WIN32_ERROR.ERROR_SUCCESS) break;
        final v = data.cast<Utf16>().toDartString().trim();
        if (v.toUpperCase().startsWith('COM')) out.add(v);
      }
    } finally {
      free(name);
      free(data);
      free(nameLen);
      free(dataLen);
      RegCloseKey(hKey.value);
    }
  } finally {
    free(subKey);
    free(hKey);
  }
  return out;
}

Future<void> _readLoop(_OpenArgs a) async {
  final control = ReceivePort();
  a.reply.send(control.sendPort);
  // COM10 trở lên bắt buộc dạng \\.\COM10.
  final path = '\\\\.\\${a.port}'.toNativeUtf16();
  final handle = CreateFile(
    path,
    GENERIC_ACCESS_RIGHTS.GENERIC_READ | GENERIC_ACCESS_RIGHTS.GENERIC_WRITE,
    FILE_SHARE_MODE.FILE_SHARE_NONE,
    nullptr,
    FILE_CREATION_DISPOSITION.OPEN_EXISTING,
    FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_NORMAL,
    NULL,
  );
  // Lấy mã lỗi ngay sau CreateFile (lệnh khác chen vào sẽ ghi đè).
  final code = handle == INVALID_HANDLE_VALUE ? GetLastError() : 0;
  free(path);
  if (handle == INVALID_HANDLE_VALUE) {
    // Mã lỗi Win32 qua FFI không luôn giữ được → cổng có trong danh sách mà không mở được thường là đang bị dùng.
    a.reply.send(_Status(code == WIN32_ERROR.ERROR_FILE_NOT_FOUND
        ? 'Không thấy ${a.port} — kiểm tra cáp cân / driver USB-Serial'
        : 'Không mở được ${a.port} — cổng đang bị phần mềm khác dùng (phần mềm cân, máy in…) hoặc vừa rút cáp'));
    control.close();
    return;
  }

  final dcb = calloc<DCB>()..ref.DCBlength = sizeOf<DCB>();
  final timeouts = calloc<COMMTIMEOUTS>();
  try {
    GetCommState(handle, dcb);
    dcb.ref
      ..BaudRate = a.baud
      ..ByteSize = a.dataBits
      ..Parity = switch (a.parity) { 'odd' => 1, 'even' => 2, _ => 0 }
      ..StopBits = a.stopBits == 2 ? 2 : 0
      // fBinary=1, fParity theo cấu hình, DTR / RTS bật (nhiều cân lấy nguồn tín hiệu từ DTR).
      ..bitfield = 1 | (a.parity == 'none' ? 0 : 2) | (1 << 4) | (1 << 12);
    if (SetCommState(handle, dcb) == 0) {
      a.reply.send(_Status('Cổng ${a.port} không nhận tốc độ ${a.baud} baud'));
      CloseHandle(handle);
      control.close();
      return;
    }
    timeouts.ref
      ..ReadIntervalTimeout = 50
      ..ReadTotalTimeoutMultiplier = 0
      ..ReadTotalTimeoutConstant = 150
      ..WriteTotalTimeoutMultiplier = 0
      ..WriteTotalTimeoutConstant = 500;
    SetCommTimeouts(handle, timeouts);
    PurgeComm(handle, PURGE_COMM_FLAGS.PURGE_RXCLEAR | PURGE_COMM_FLAGS.PURGE_TXCLEAR);
  } finally {
    free(dcb);
    free(timeouts);
  }

  a.reply.send(const _Status(null));
  var running = true;
  final outbox = <Uint8List>[];
  control.listen((msg) {
    if (msg == 'close') running = false;
    if (msg is Uint8List) outbox.add(msg);
  });

  final buf = calloc<Uint8>(512);
  final read = calloc<Uint32>();
  final written = calloc<Uint32>();
  var failures = 0;
  try {
    while (running) {
      while (outbox.isNotEmpty) {
        final bytes = outbox.removeAt(0);
        final p = calloc<Uint8>(bytes.length);
        p.asTypedList(bytes.length).setAll(0, bytes);
        WriteFile(handle, p, bytes.length, written, nullptr);
        free(p);
      }
      read.value = 0;
      final ok = ReadFile(handle, buf, 512, read, nullptr);
      if (ok == 0) {
        // Rút cáp / cổng mất → báo lỗi, dừng.
        if (++failures >= 3) {
          a.reply.send(_Status('Mất kết nối cân ở ${a.port}'));
          break;
        }
      } else {
        failures = 0;
        if (read.value > 0) {
          a.reply.send(TransferableTypedData.fromList([Uint8List.fromList(buf.asTypedList(read.value))]));
        }
      }
      // Nhường vòng lặp sự kiện để nhận lệnh gửi / đóng.
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    free(buf);
    free(read);
    free(written);
    CloseHandle(handle);
    control.close();
  }
}

/// Bản máy (dart:ffi): Windows = cổng COM; Android = cáp USB-Serial qua kênh native.
PosScaleTransport createPosScaleTransport() =>
    Platform.isAndroid ? PosScaleAndroidUsbTransport() : _WinComTransport();
