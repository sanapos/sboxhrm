import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pos_scale_reader.dart';
import 'pos_scale_transport.dart';

/// Cân qua Web Serial (Chrome / Edge trên máy tính, trang https hoặc localhost).
/// Lần đầu phải bấm «Chọn cổng cân» (trình duyệt hỏi quyền); các lần sau tự mở cổng đã cấp quyền.
class _WebSerialTransport implements PosScaleTransport {
  _SerialPort? _port;
  _Reader? _reader;
  bool _closing = false;

  JSObject? get _serial {
    final nav = web.window.navigator as JSObject;
    return nav.has('serial') ? nav.getProperty<JSObject?>('serial'.toJS) : null;
  }

  @override
  bool get supported => _serial != null;
  @override
  bool get isWeb => true;
  @override
  String get kind => 'web';
  @override
  String get unsupportedReason =>
      'Trình duyệt này chưa hỗ trợ đọc cân (Web Serial) — dùng Chrome hoặc Edge trên máy tính, hoặc app Windows.';

  Future<List<_SerialPort>> _granted() async {
    final s = _serial;
    if (s == null) return const [];
    final arr = await s.callMethod<JSPromise<JSArray<JSObject>>>('getPorts'.toJS).toDart;
    return arr.toDart.map((o) => _SerialPort(o)).toList();
  }

  @override
  Future<List<String>> listPorts() async {
    final ports = await _granted();
    return [
      for (final p in ports)
        p.vendorId == null ? 'Cổng serial' : 'USB ${p.vendorId!.toRadixString(16).padLeft(4, '0')}:${(p.productId ?? 0).toRadixString(16).padLeft(4, '0')}',
    ];
  }

  @override
  Future<({int? vendorId, int? productId})?> requestPort() async {
    final s = _serial;
    if (s == null) return null;
    try {
      final o = await s.callMethod<JSPromise<JSObject>>('requestPort'.toJS).toDart;
      final p = _SerialPort(o);
      return (vendorId: p.vendorId, productId: p.productId);
    } catch (_) {
      return null; // người dùng bấm Hủy
    }
  }

  @override
  Future<void> open(PosScaleDeviceSettings s, void Function(List<int> bytes) onData, void Function(String error) onError) async {
    await close();
    final ports = await _granted();
    if (ports.isEmpty) throw Exception('Chưa cấp quyền cổng cân — bấm «Chọn cổng cân»');
    final port = ports.firstWhere(
      (p) => s.webUsbVendorId != null && p.vendorId == s.webUsbVendorId && p.productId == s.webUsbProductId,
      orElse: () => ports.first,
    );
    final opts = JSObject()
      ..setProperty('baudRate'.toJS, s.baudRate.toJS)
      ..setProperty('dataBits'.toJS, s.dataBits.toJS)
      ..setProperty('stopBits'.toJS, s.stopBits.toJS)
      ..setProperty('parity'.toJS, s.parity.toJS);
    try {
      await port.obj.callMethod<JSPromise<JSAny?>>('open'.toJS, opts).toDart;
    } catch (e) {
      throw Exception('Không mở được cổng cân (đang mở ở tab / phần mềm khác?)');
    }
    _port = port;
    _closing = false;
    final readable = port.obj.getProperty<JSObject?>('readable'.toJS);
    if (readable == null) throw Exception('Cổng cân không đọc được');
    final reader = _Reader(readable.callMethod<JSObject>('getReader'.toJS));
    _reader = reader;
    unawaited(() async {
      try {
        while (!_closing) {
          final r = await reader.obj.callMethod<JSPromise<JSObject>>('read'.toJS).toDart;
          if (r.getProperty<JSBoolean>('done'.toJS).toDart) break;
          final v = r.getProperty<JSUint8Array?>('value'.toJS);
          if (v != null) onData(v.toDart);
        }
      } catch (e) {
        if (!_closing) onError('Mất kết nối cân (rút cáp?)');
      }
    }());
  }

  @override
  Future<void> write(List<int> bytes) async {
    final w = _port?.obj.getProperty<JSObject?>('writable'.toJS);
    if (w == null) return;
    try {
      final writer = w.callMethod<JSObject>('getWriter'.toJS);
      await writer.callMethod<JSPromise<JSAny?>>('write'.toJS, Uint8List.fromList(bytes).toJS).toDart;
      writer.callMethod<JSAny?>('releaseLock'.toJS);
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    _closing = true;
    try {
      await _reader?.obj.callMethod<JSPromise<JSAny?>>('cancel'.toJS).toDart;
      _reader?.obj.callMethod<JSAny?>('releaseLock'.toJS);
    } catch (_) {}
    _reader = null;
    try {
      await _port?.obj.callMethod<JSPromise<JSAny?>>('close'.toJS).toDart;
    } catch (_) {}
    _port = null;
  }
}

class _SerialPort {
  _SerialPort(this.obj);
  final JSObject obj;
  JSObject? get _info => obj.callMethod<JSObject?>('getInfo'.toJS);
  int? get vendorId => _info?.getProperty<JSNumber?>('usbVendorId'.toJS)?.toDartInt;
  int? get productId => _info?.getProperty<JSNumber?>('usbProductId'.toJS)?.toDartInt;
}

class _Reader {
  _Reader(this.obj);
  final JSObject obj;
}

PosScaleTransport createPosScaleTransport() => _WebSerialTransport();
